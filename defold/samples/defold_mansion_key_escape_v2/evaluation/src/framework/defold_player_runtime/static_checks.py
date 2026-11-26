#!/usr/bin/env python3
"""Run the common Defold D1 checks in an evaluator-owned output directory."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from framework.defold_dashboard.dashboard_self_check import (
    validate_naming_tables,
    validate_snapshot,
)
from framework.defold_player_runtime.player import DashboardReader
from framework.defold_player_runtime.runtime_errors import candidate_runtime_error_line


def defold_build_tools():
    packages = os.environ.get("DEFOLD_PACKAGES")

    def tool(variable, pattern):
        explicit = os.environ.get(variable)
        if explicit and Path(explicit).is_file():
            return Path(explicit).resolve()
        matches = sorted(Path(packages).glob(pattern)) if packages and not explicit else []
        if len(matches) == 1 and matches[0].is_file():
            return matches[0].resolve()
        raise RuntimeError(f"Set {variable} to the installed tool, or select a unique match via DEFOLD_PACKAGES")

    return tool("DEFOLD_JAVA", "jdk*/bin/java"), tool("DEFOLD_BOB_JAR", "defold-*.jar")


HOST_ERROR_MARKERS = (
    "Vulkan is not supported on this device",
    "Could not install a graphics adapter",
)
SMOKE_STABILITY_SECONDS = 0.5


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def check(check_id: str, passed: bool, detail: str, evidence: str | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"id": check_id, "status": "pass" if passed else "fail", "detail": detail}
    if evidence is not None:
        result["evidence"] = evidence
    return result


def find_executable(bundle_output: Path) -> list[Path]:
    return sorted(
        path
        for path in bundle_output.glob("**/*.app/Contents/MacOS/*")
        if path.is_file() and os.access(path, os.X_OK)
    )


def terminate(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def first_candidate_runtime_error(runtime_text: str) -> str | None:
    """Return the first narrow Defold fatal line, ignoring generic ERROR noise."""
    for line in runtime_text.splitlines():
        fatal = candidate_runtime_error_line(line)
        if fatal is not None:
            return fatal
    return None


def wait_for_dashboard_stability(
    reader: DashboardReader,
    process: subprocess.Popen[str],
    tables: dict[str, Any],
    first_snapshot: dict[str, Any],
    seconds: float = SMOKE_STABILITY_SECONDS,
) -> dict[str, Any]:
    """Keep the first valid Dashboard alive briefly and validate later revisions."""
    latest = first_snapshot
    previous_revision = int(first_snapshot["revision"])
    line_number = 1
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        return_code = process.poll()
        if return_code is not None:
            raise RuntimeError(
                f"game exited with code {return_code} during Dashboard stability window"
            )
        for snapshot in reader.poll_updates():
            line_number += 1
            previous_revision = validate_snapshot(
                snapshot,
                line_number,
                previous_revision,
                tables,
            )
            latest = snapshot
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(0.03, remaining))
    return_code = process.poll()
    if return_code is not None:
        raise RuntimeError(
            f"game exited with code {return_code} during Dashboard stability window"
        )
    return latest


def run(project: Path, naming_path: Path, output: Path, smoke_timeout_s: float) -> dict[str, Any]:
    project = project.resolve()
    naming_path = naming_path.resolve()
    output = output.resolve()
    if output.exists():
        raise FileExistsError(f"evaluator output directory already exists: {output}")
    output.mkdir(parents=True)
    (output / "run").mkdir()
    candidate = output / "candidate"
    shutil.copytree(
        project,
        candidate,
        ignore=shutil.ignore_patterns(
            "build",
            ".internal",
            "log.txt",
            "dashboard.jsonl",
            "__pycache__",
        ),
    )

    checks: list[dict[str, Any]] = []
    project_file = project / "game.project"
    checks.append(check("D1_PROJECT_ENTRY", project_file.is_file(), str(project_file)))

    build_log = output / "build.log"
    java, jar = defold_build_tools()
    command = [
        str(java),
        "-cp",
        str(jar),
        "com.dynamo.bob.Bob",
        "--root",
        ".",
        "--platform",
        "arm64-macos",
        "--variant",
        "debug",
        "--archive",
        "--output",
        "build/default",
        "resolve",
        "distclean",
        "build",
        "bundle",
    ]
    completed = subprocess.run(
        command,
        cwd=candidate,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    build_log.write_text(completed.stdout, encoding="utf-8")
    checks.append(
        check(
            "D1_BOB_BUILD",
            completed.returncode == 0,
            f"Bob exit code {completed.returncode}",
            str(build_log),
        )
    )

    executables = find_executable(candidate / "build" / "default") if completed.returncode == 0 else []
    checks.append(
        check(
            "D1_BUNDLE_ENTRY",
            len(executables) == 1,
            f"found {len(executables)} macOS bundle executables",
        )
    )

    runtime_log = output / "runtime.log"
    dashboard_path = output / "run" / "dashboard.jsonl"
    smoke_passed = False
    smoke_detail = "bundle was not launchable"
    if len(executables) == 1:
        with runtime_log.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(
                [str(executables[0])],
                cwd=output / "run",
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
            )
            try:
                reader = DashboardReader(dashboard_path)
                snapshot = reader.wait_until(lambda _: True, smoke_timeout_s)
                tables = validate_naming_tables(json.loads(naming_path.read_text(encoding="utf-8")))
                validate_snapshot(snapshot, 1, -1, tables)
                snapshot = wait_for_dashboard_stability(reader, process, tables, snapshot)
                smoke_passed = True
                smoke_detail = f"dashboard revision {snapshot['revision']} phase {snapshot['phase']}"
            except (OSError, RuntimeError, SystemExit, json.JSONDecodeError) as exc:
                smoke_detail = str(exc)
            finally:
                terminate(process)
    infrastructure_error = None
    candidate_runtime_error = None
    if runtime_log.exists():
        runtime_text = runtime_log.read_text(encoding="utf-8", errors="replace")
        infrastructure_error = next((marker for marker in HOST_ERROR_MARKERS if marker in runtime_text), None)
        candidate_runtime_error = first_candidate_runtime_error(runtime_text)
    if candidate_runtime_error is not None:
        smoke_passed = False
        smoke_detail = f"candidate runtime error: {candidate_runtime_error}"
    runtime_check = check("D1_RUNTIME_DASHBOARD_SMOKE", smoke_passed, smoke_detail, str(runtime_log))
    if infrastructure_error is not None and not smoke_passed:
        runtime_check["status"] = "invalid"
        runtime_check["detail"] = f"host runtime error: {infrastructure_error}"
    checks.append(runtime_check)

    passed = sum(item["status"] == "pass" for item in checks)
    report = {
        "schema_version": 1,
        "project": str(project),
        "naming_tables": str(naming_path),
        "checks": checks,
        "evaluation_status": "infrastructure_invalid" if infrastructure_error and not smoke_passed else "valid",
        "d1_score": None if infrastructure_error and not smoke_passed else 10.0 * passed / len(checks),
        "d1_max": 10.0,
    }
    write_json(output / "d1-report.json", report)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--naming-tables", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--smoke-timeout", type=float, default=12.0)
    args = parser.parse_args()
    print(json.dumps(run(args.project, args.naming_tables, args.output, args.smoke_timeout), indent=2))


if __name__ == "__main__":
    main()
