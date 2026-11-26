"""Portable sample-local orchestration of the frozen D1-D5 runtime."""
import argparse
import json
import os
import shutil
import platform
import subprocess
import sys
from pathlib import Path

from framework.defold_player_runtime.score_reports import infrastructure_invalid_report, expected_checks


def read(path):
    return json.loads(path.read_text())


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def call(command, env, output=None, label=None):
    result = subprocess.run([str(v) for v in command], text=True, capture_output=True, env=env)
    if output is not None:
        write(output / "logs" / (label + ".json"),
              {"returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    return result


def validate_package(evaluation, env):
    runtime = evaluation / "src/framework/defold_player_runtime"
    required = ["rules.json", "coverage.json",
                "baseline-applicability.json", "required-player-capabilities.json", "requirements.txt",
                "src/framework/defold_dashboard/dashboard_self_check.py"]
    required += ["src/framework/defold_player_runtime/" + name for name in (
        "__init__.py", "checkpoint_runner.py", "player.py", "expressions.py", "evidence.py",
        "static_checks.py", "score_reports.py", "runtime_errors.py", "macos_input.sh", "macos_input.swift")]
    missing = [name for name in required if not (evaluation / name).is_file()]
    if missing:
        raise ValueError("Missing packaged evaluator files: " + ", ".join(missing))
    naming = evaluation.parent / "input/naming-tables.json"
    check = call([sys.executable, runtime / "checkpoint_runner.py", "--script",
                  evaluation / "rules.json", "--naming-tables", naming,
                  "--validate-only"], env)
    if check.returncode:
        raise ValueError("Checkpoint validation failed: " + check.stdout + check.stderr)
    expected = expected_checks(read(evaluation / "rules.json"))
    return {"package_valid": True, "sample_id": read(evaluation.parent / "sample.json")["sample_id"],
            "checkpoint_count": len(expected), "engine_run": False,
            "complete_six_dimension_evaluator": False}


def host_check(runtime, env, output):
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("This evaluator requires the configured native host platform")
    from framework.defold_player_runtime.static_checks import defold_build_tools
    defold_build_tools()
    tesseract = env.get("TESSERACT_EXE") or shutil.which("tesseract")
    if not tesseract or not shutil.which("swiftc") or not shutil.which("screencapture"):
        raise RuntimeError("Install Tesseract and the native capture/input backend tools")
    languages = call([tesseract, "--list-langs"], env, output, "ocr-languages")
    if languages.returncode or not {"eng"} <= set(languages.stdout.splitlines()):
        raise RuntimeError("Required OCR language data is unavailable; see logs/ocr-languages.json")
    result = call(["/bin/sh", runtime / "macos_input.sh", "--check"], env, output, "input-preflight")
    if result.returncode:
        raise RuntimeError("Normal input/Accessibility permission unavailable: " + result.stdout + result.stderr)


def main(evaluation, argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-only", action="store_true",
                        help="Check bundled dependencies and task script without launching the engine")
    args = parser.parse_args(argv)
    evaluation = evaluation.resolve()
    env = dict(os.environ, PYTHONPATH=str(evaluation / "src"), PYTHONDONTWRITEBYTECODE="1")
    if args.validate_only:
        try:
            print(json.dumps(validate_package(evaluation, env)))
            return 0
        except (OSError, ValueError, KeyError) as error:
            print(json.dumps({"package_valid": False, "reason": str(error)}))
            return 2
    if args.project is None or args.output is None:
        parser.error("--project and --output are required unless --validate-only is used")
    if not args.project.is_absolute() or not args.output.is_absolute():
        parser.error("--project and --output must be absolute paths")
    project, output = args.project.resolve(), args.output.resolve()
    if not project.is_dir() or output.exists():
        parser.error("project must exist and output must be a new directory")
    sample = evaluation.parent
    if project == output or project in output.parents or output in project.parents:
        parser.error("project and output must not overlap")
    if sample == output or sample in output.parents or output in sample.parents:
        parser.error("output must be outside the distributed sample")
    output.mkdir(parents=True)
    runtime = evaluation / "src/framework/defold_player_runtime"
    script, naming = evaluation / "rules.json", evaluation.parent / "input/naming-tables.json"
    status, reason, code = "infrastructure_invalid", "Evaluation did not finish.", 2
    try:
        validate_package(evaluation, env)
        host_check(runtime, env, output)
        static = call([sys.executable, runtime / "static_checks.py", "--project", project,
                       "--naming-tables", naming, "--output", output / "d1"], env, output, "d1")
        d1_path = output / "d1/d1-report.json"
        if static.returncode or not d1_path.is_file():
            raise RuntimeError("D1 runner failed; see logs/d1.json")
        d1 = read(d1_path)
        if d1.get("evaluation_status") != "valid":
            raise RuntimeError("D1 host/runtime failure; see d1/d1-report.json")
        build_check = next(c for c in d1["checks"] if c["id"] == "D1_BOB_BUILD")
        executables = sorted(p for p in (output / "d1/candidate/build/default").glob("**/*.app/Contents/MacOS/*")
                             if p.is_file() and os.access(p, os.X_OK))
        if build_check["status"] != "pass" or len(executables) != 1:
            status, reason, code = "incomplete", "Candidate build failed; D1 evidence retained, dynamic checks not run.", 3
            report = infrastructure_invalid_report(reason)
            report["evaluation_status"] = status
            report["dimensions"]["D1"] = {"score": d1["d1_score"], "max": 10.0, "source": "static D1 report"}
            write(output / "score.json", report)
        else:
            # The runtime invokes its driver directly; invoke the bundled script
            # through sh so ZIP extraction need not preserve executable mode.
            driver = output / "input-driver.sh"
            import shlex
            driver.write_text("#!/bin/sh\nexec /bin/sh " + shlex.quote(str(runtime / "macos_input.sh")) + ' "$@"\n')
            driver.chmod(0o755)
            checkpoint = call([sys.executable, runtime / "checkpoint_runner.py", "--script", script,
                               "--naming-tables", naming, "--executable", executables[0],
                               "--input-driver", driver, "--output", output / "checkpoint"],
                              env, output, "checkpoint")
            evidence = output / "checkpoint/checkpoint-report.json"
            if not evidence.is_file() or read(evidence).get("evaluation_status") != "valid":
                raise RuntimeError("Checkpoint execution failed; see logs/checkpoint.json")
            if checkpoint.returncode:
                raise RuntimeError("Checkpoint runner exited unsuccessfully; see logs/checkpoint.json")
            score = call([sys.executable, runtime / "score_reports.py", "--d1-report", d1_path,
                          "--checkpoint-report", evidence, "--script", script,
                          "--output", output / "score.json"], env, output, "score")
            if score.returncode or read(output / "score.json").get("evaluation_status") != "valid":
                raise RuntimeError("Functional scoring failed; see logs/score.json")
            status, reason, code = "valid", "D1-D5 evaluation completed; D6 is separate.", 0
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        status, reason, code = "infrastructure_invalid", str(error), 2
        write(output / "error.json", {"evaluation_status": status, "reason": reason})
        # Keep a malformed/invalid combiner report for diagnosis, but never expose
        # it as a valid score just because the subprocess returned zero.
        if (output / "score.json").exists():
            (output / "score.json").rename(output / "score-rejected.json")
        write(output / "score.json", infrastructure_invalid_report(reason))
    print(json.dumps({"report": str(output / "score.json"), "evaluation_status": status,
                      "reason": reason}))
    return code
