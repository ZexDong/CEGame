"""Wait for the collector process and its final report; never infer exit from UE.

This supervisor does not score, retry a candidate, or change collector verdicts.
Its log and receipt live in a sibling directory so the collector gets an empty
run root. Redirected child output cannot be lost when a terminal tool yields.
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

from runtime import ROOT, InfrastructureError, load, sha, write


def control_root(output):
    return output.with_name(output.name + '.supervisor')


def say(message):
    try:
        print(message, flush=True)
    except (OSError, ValueError):
        pass


def final_state(output, returncode):
    """A checkpoint is not completion, even if the game process has exited."""
    path = output / 'raw-evaluation.json'
    if not path.is_file():
        return None, 'COLLECTOR_FINAL_REPORT_MISSING'
    try:
        raw = load(path)
    except (OSError, ValueError):
        return None, 'COLLECTOR_FINAL_REPORT_MALFORMED'
    if not isinstance(raw, dict):
        return None, 'COLLECTOR_FINAL_REPORT_MALFORMED'
    if raw.get('run_id') != output.name:
        return raw, 'COLLECTOR_RUN_ID_MISMATCH'
    if raw.get('status') == 'running':
        return raw, 'COLLECTOR_EXITED_WITH_RUNNING_CHECKPOINT'
    if returncode != 0:
        return raw, 'COLLECTOR_EXIT_NONZERO'
    if raw.get('status') != 'collected' or raw.get('fault') is not None:
        return raw, 'COLLECTOR_FINAL_REPORT_INVALID'
    if raw.get('cleanup_confirmed') is not True:
        return raw, 'COLLECTOR_CLEANUP_UNVERIFIED'
    return raw, None


def stop_owned_process(process):
    if process.poll() is not None:
        return
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
    else:
        process.kill()
    process.wait(timeout=15)


def supervise(command, output, timeout_seconds):
    output = Path(output).resolve()
    controls = control_root(output)
    # Never overwrite a prior run or attach to an unrelated process.
    if output.exists() or controls.exists():
        raise InfrastructureError('SUPERVISOR_REQUIRES_NEW_RUN_ROOT')
    if timeout_seconds <= 0:
        raise ValueError('Supervisor timeout must be positive')
    controls.mkdir(parents=True)
    output.mkdir()
    receipt_path = controls / 'collector-run.json'
    started = time.monotonic()
    receipt = dict(schema_version='1.0.0', run_id=output.name, status='running',
                   collector_exit_code=None, cleanup_confirmed=False,
                   log='collector.log', supervisor_sha256=sha(Path(__file__)))
    write(receipt_path, receipt)
    process = None
    problem = None
    try:
        with (controls / 'collector.log').open('wb') as log:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                stdout=log, stderr=subprocess.STDOUT,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            receipt['collector_pid'] = process.pid
            write(receipt_path, receipt)
            say('Collector running; waiting for process completion: ' + output.name)
            # The same Popen instance owns the wait. No search by process name,
            # CPU usage, target PID, first file appearance, or terminal output.
            receipt['collector_exit_code'] = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        problem = 'SUPERVISOR_DEADLINE_EXCEEDED'
    except KeyboardInterrupt:
        problem = 'SUPERVISOR_INTERRUPTED'
    except OSError as exc:
        problem = 'SUPERVISOR_PROCESS_ERROR'
        receipt['exception_type'] = type(exc).__name__
    finally:
        if process is not None and process.poll() is None:
            try:
                stop_owned_process(process)
            except (OSError, subprocess.TimeoutExpired) as exc:
                receipt['termination_error'] = type(exc).__name__
        if process is not None:
            receipt['collector_exit_code'] = process.poll()
    raw, report_problem = final_state(output, receipt['collector_exit_code'])
    problem = problem or report_problem
    if raw is not None:
        receipt.update(raw_status=raw.get('status'), collector_fault=raw.get('fault'),
                       candidate_identity_sha256=raw.get('candidate_identity_sha256'))
    path = output / 'raw-evaluation.json'
    if path.is_file():
        receipt['raw_sha256'] = sha(path)
    receipt.update(status='evaluation_incomplete' if problem else 'collected',
                   fault=dict(domain='infrastructure', code=problem) if problem else None,
                   cleanup_confirmed=not problem,
                   elapsed_seconds=round(time.monotonic() - started, 2))
    write(receipt_path, receipt)
    say(receipt['status'] + ': ' + str(receipt_path))
    return 2 if problem else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pwsh', default='pwsh')
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    output = args.output.resolve()
    for path in (output, control_root(output)):
        if path.is_relative_to(candidate) or candidate.is_relative_to(path):
            raise InfrastructureError('RUN_CANDIDATE_ROOT_OVERLAP')
    budget = load(ROOT / 'contracts/budget.json')
    # The outer wait includes the collector watchdog AND its cleanup/report time.
    timeout = budget['watchdog_seconds'] + budget['stop_rpc_timeout_seconds'] + 60
    command = [sys.executable, '-u', str(ROOT / 'scripts/evaluate.py'),
               '--candidate', str(candidate), '--engine', str(args.engine.resolve()),
               '--output', str(output), '--pwsh', args.pwsh]
    return supervise(command, output, timeout)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (InfrastructureError, OSError, ValueError) as exc:
        say(str(exc))
        raise SystemExit(2)
