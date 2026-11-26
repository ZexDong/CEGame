"""Wait for D6's owned process and validate its complete three-round evidence.

The terminal may yield while this supervisor is running. Only d6-run.json after
child exit is a completion receipt; console output and partial files are not.
No game is launched, no score is published, and no request is retried here.
"""
import argparse
import subprocess
import sys
import time
from pathlib import Path

from runtime import ROOT, InfrastructureError, load, sha, write
from run_collector import say, stop_owned_process
from score import valid_raw, validate_evidence, aggregate_d6


def control_root(output):
    return output.with_name(output.name + '.supervisor')


def final_state(raw_path, output, returncode):
    if returncode != 0:
        return None, 'D6_PROCESS_EXIT_NONZERO'
    if not output.is_file():
        return None, 'D6_FINAL_REPORT_MISSING'
    try:
        data = load(output)
        if not isinstance(data, dict):
            return None, 'D6_FINAL_REPORT_MALFORMED'
        if data.get('status') != 'completed':
            return data, 'D6_FINAL_REPORT_INCOMPLETE'
        raw = load(raw_path)
        valid_raw(raw)
        validate_evidence(raw, raw_path.parent)
        # Reuse the canonical protocol validator, without publishing D1-D6 scores.
        aggregate_d6(data, raw, raw_path, raw_path.parent)
        return data, None
    except InfrastructureError as exc:
        return None, str(exc)
    except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError):
        return None, 'D6_FINAL_REPORT_MALFORMED'


def supervise(command, raw_path, output, timeout_seconds):
    raw_path = Path(raw_path).resolve()
    output = Path(output).resolve()
    controls = control_root(output)
    if output.exists() or controls.exists():
        raise InfrastructureError('D6_SUPERVISOR_REQUIRES_NEW_OUTPUT')
    if timeout_seconds <= 0:
        raise ValueError('Supervisor timeout must be positive')
    # Bind the input before spawning; existing candidate evidence is never edited.
    raw_sha256 = sha(raw_path)
    controls.mkdir(parents=True)
    receipt_path = controls / 'd6-run.json'
    started = time.monotonic()
    receipt = dict(schema_version='1.0.0', status='running', d6_exit_code=None,
                   fault=None, raw_sha256=raw_sha256, log='d6.log',
                   score_publication_allowed=False,
                   supervisor_sha256=sha(Path(__file__)))
    write(receipt_path, receipt)
    process = None
    problem = None
    try:
        with (controls / 'd6.log').open('wb') as log:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                stdout=log, stderr=subprocess.STDOUT,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            receipt['d6_pid'] = process.pid
            write(receipt_path, receipt)
            say('D6 running; waiting for all rounds and process exit.')
            receipt['d6_exit_code'] = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        problem = 'D6_SUPERVISOR_DEADLINE_EXCEEDED'
    except KeyboardInterrupt:
        problem = 'D6_SUPERVISOR_INTERRUPTED'
    except OSError as exc:
        problem = 'D6_SUPERVISOR_PROCESS_ERROR'
        receipt['exception_type'] = type(exc).__name__
    finally:
        if process is not None and process.poll() is None:
            try:
                stop_owned_process(process)
            except (OSError, subprocess.TimeoutExpired) as exc:
                receipt['termination_error'] = type(exc).__name__
        if process is not None:
            receipt['d6_exit_code'] = process.poll()
    data, report_problem = final_state(raw_path, output, receipt['d6_exit_code'])
    problem = problem or report_problem
    if data is not None:
        receipt.update(d6_status=data.get('status'), d6_fault=data.get('fault'))
    if output.is_file():
        receipt['d6_result_sha256'] = sha(output)
    if not raw_path.is_file() or sha(raw_path) != raw_sha256:
        problem = problem or 'D6_INPUT_CHANGED_DURING_RUN'
    receipt.update(status='evaluation_incomplete' if problem else 'completed',
                   fault=dict(domain='infrastructure', code=problem) if problem else None,
                   elapsed_seconds=round(time.monotonic() - started, 2))
    write(receipt_path, receipt)
    say(receipt['status'] + ': ' + str(receipt_path))
    return 2 if problem else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--base-url')
    parser.add_argument('--model')
    parser.add_argument('--key-env', default='OPENAI_API_KEY')
    args = parser.parse_args()
    raw_path = args.raw.resolve()
    valid_raw(load(raw_path))
    validate_evidence(load(raw_path), raw_path.parent)
    receipts = raw_path.parent / 'd6'
    if receipts.exists() and any(receipts.iterdir()):
        raise InfrastructureError('D6_RECEIPTS_ALREADY_EXIST')
    # Nine requests under the current contract, 180 s each, plus serialization,
    # parsing and final validation headroom. No early deadline based on round one.
    manifest = load(ROOT / 'd6/reference-manifest.json')
    timeout = 180 * manifest['rounds'] * len(manifest['states']) + 120
    command = [sys.executable, '-u', str(ROOT / 'scripts/d6.py'),
               '--raw', str(raw_path), '--output', str(args.output.resolve()),
               '--key-env', args.key_env]
    for flag, value in (('--base-url', args.base_url), ('--model', args.model)):
        if value is not None:
            command.extend([flag, value])
    return supervise(command, raw_path, args.output, timeout)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (InfrastructureError, OSError, ValueError) as exc:
        say(str(exc))
        raise SystemExit(2)
