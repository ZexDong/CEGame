#!/usr/bin/env python3
"""Run the unchanged Tide Lock candidate through the unified local evaluator.

Roblox Luau performs discovery, path planning, observation, and judgment. This
desktop bridge only focuses Studio, executes requested Windows input, and copies
the resulting engine log records into immutable evidence files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import socket
import shutil
import subprocess
import sys
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from PIL import ImageGrab

from local_bridge_support import (
    VK,
    choose_window,
    find_session_log,
    find_studio,
    focus,
    focus_live_studio,
    foreground_window,
    click_left,
    mouse_drag,
    move_mouse_relative,
    move_cursor_to_window_center,
    read_new_log_lines,
    send_key,
    studio_windows,
    tap,
)


PREFIXES = {
    "command": "TIDE_LOCK_COMMAND ",
    "trace": "TIDE_LOCK_TRACE ",
    "checkpoint": "TIDE_LOCK_CHECKPOINT ",
    "ready": "TIDE_LOCK_EVAL_READY ",
    "done": "TIDE_LOCK_EVAL_DONE ",
    "observer": "TIDE_LOCK_OBSERVER ",
}
LAST_OUTPUT: Path | None = None
ACTIVE_CAPTURE_DIR: Path | None = None
CAPTURE_FILES: list[Path] = []


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def parse_line(line: str) -> tuple[str, dict] | None:
    for kind, prefix in PREFIXES.items():
        marker = line.find(prefix)
        if marker < 0:
            continue
        payload = line[marker + len(prefix) :].strip()
        try:
            value = json.loads(payload)
        except json.JSONDecodeError:
            return None
        if isinstance(value, dict):
            return kind, value
    return None


TRACE_ID_PATTERN = re.compile(r'"trace_id"\s*:\s*"(tl-trace-\d+)"')
TRACE_LITERAL_PATTERN = re.compile(r'"(tl-trace-\d+)"')
ACTION_PATTERN = re.compile(r'"action"\s*:\s*"([^"]+)"')
OUTCOME_PATTERN = re.compile(r'"outcome"\s*:\s*"([^"]+)"')
CHECKPOINT_ID_PATTERN = re.compile(r'"checkpoint_id"\s*:\s*"([^"]+)"')
STATUS_PATTERN = re.compile(r'"status"\s*:\s*"(pass|fail|inconclusive|not_run)"')
DETAIL_PATTERN = re.compile(r'"detail"\s*:\s*"([^"]*)"')


def recover_engine_log(session_log: Path) -> tuple[dict[str, dict], dict[str, dict], dict[str, int]]:
    """Recover real records after Play, including Studio-truncated trace JSON.

    A truncated trace is retained as an auditable stub tied to the exact raw
    log line hash. Its ID is not inferred from an assertion and is never
    fabricated; it must literally occur in a SIGNAL_CIRCUIT_TRACE engine line.
    """
    traces: dict[str, dict] = {}
    checkpoints: dict[str, dict] = {}
    counts: dict[str, int] = {}
    with session_log.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, 1):
            parsed = parse_line(line)
            if parsed:
                kind, payload = parsed
                counts[kind] = counts.get(kind, 0) + 1
                if kind == "trace" and payload.get("trace_id"):
                    traces[str(payload["trace_id"])] = payload
                elif kind == "checkpoint" and payload.get("checkpoint_id"):
                    checkpoints[str(payload["checkpoint_id"])] = {
                        "status": payload.get("status", "inconclusive"),
                        "detail": payload.get("detail", ""),
                        "trace_ids": payload.get("trace_ids", []),
                    }
                continue
            marker = line.find(PREFIXES["trace"])
            if marker >= 0:
                raw = line[marker + len(PREFIXES["trace"]) :].rstrip("\r\n")
                match = TRACE_ID_PATTERN.search(raw)
                if not match:
                    continue
                trace_id = match.group(1)
                action = ACTION_PATTERN.search(raw)
                outcome = OUTCOME_PATTERN.search(raw)
                traces[trace_id] = {
                    "trace_id": trace_id,
                    "action": action.group(1) if action else "unavailable_in_truncated_line",
                    "outcome": outcome.group(1) if outcome else "unavailable_in_truncated_line",
                    "raw_log_line_number": line_number,
                    "raw_log_line_sha256": hashlib.sha256(line.encode("utf-8", errors="replace")).hexdigest().upper(),
                    "record_format": "studio_truncated_json_stub",
                }
                counts["trace_stub"] = counts.get("trace_stub", 0) + 1
                continue

            # Checkpoint JSON can also be cut off by a long trace list. Recover
            # only fields literally present before Studio's truncation point.
            marker = line.find(PREFIXES["checkpoint"])
            if marker < 0:
                continue
            raw = line[marker + len(PREFIXES["checkpoint"]) :].rstrip("\r\n")
            checkpoint_id = CHECKPOINT_ID_PATTERN.search(raw)
            status = STATUS_PATTERN.search(raw)
            if not checkpoint_id or not status:
                continue
            detail = DETAIL_PATTERN.search(raw)
            trace_ids = list(dict.fromkeys(TRACE_LITERAL_PATTERN.findall(raw)))
            checkpoints[checkpoint_id.group(1)] = {
                "status": status.group(1),
                "detail": detail.group(1) if detail else "recovered from Studio-truncated checkpoint line",
                "trace_ids": trace_ids,
                "raw_log_line_number": line_number,
                "raw_log_line_sha256": hashlib.sha256(line.encode("utf-8", errors="replace")).hexdigest().upper(),
                "record_format": "studio_truncated_json_stub",
            }
            counts["checkpoint_stub"] = counts.get("checkpoint_stub", 0) + 1
    return traces, checkpoints, counts


def wait_for_place_open_success(session_log: Path, place_stem: str, timeout: float = 120) -> None:
    deadline = time.time() + timeout
    last_text = ""
    while time.time() < deadline:
        try:
            last_text = session_log.read_text(encoding="utf-8", errors="replace")
        except OSError:
            time.sleep(0.25)
            continue
        lowered = last_text.lower()
        owns_place = place_stem.lower() in lowered
        succeeded = (
            "state: openplacesuccess" in lowered
            or ("workflow: openplace" in lowered and "workflowresult: success" in lowered)
        )
        if owns_place and succeeded:
            return
        time.sleep(0.25)
    raise RuntimeError(f"Studio did not report OpenPlaceSuccess for {place_stem} within {timeout:.0f}s")


def wait_for_eval_client_ready(session_log: Path, timeout: float = 20) -> bool:
    """Wait until the Play Client (not merely the local server) runs QA code."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with session_log.open("rb") as handle:
                handle.seek(max(0, session_log.stat().st_size - 2_000_000))
                tail = handle.read().decode("utf-8", errors="replace")
            if "TIDE_LOCK_EVAL_READY " in tail:
                return True
        except OSError:
            pass
        time.sleep(0.15)
    return False


def is_target_studio(current: dict, place_stem: str, target: dict) -> bool:
    return current.get("path", "").lower().endswith("robloxstudiobeta.exe") and (
        place_stem.lower() in current.get("title", "").lower()
        or (target.get("pid") and current.get("pid") == target.get("pid"))
    )


def ensure_focus(place_stem: str, target: dict) -> dict:
    current = foreground_window()
    if is_target_studio(current, place_stem, target):
        return current
    try:
        focus(target)
        current = foreground_window()
        if is_target_studio(current, place_stem, target):
            return current
    except Exception:
        pass
    exact = [item for item in studio_windows() if place_stem.lower() in item.get("title", "").lower()]
    if exact:
        focus(exact[-1])
        return exact[-1]
    return focus_live_studio(place_stem, 25)


def execute_command(command: dict, place_stem: str, window: dict) -> dict:
    window = ensure_focus(place_stem, window)
    action = command.get("action")
    if action in {"key_down", "key_up"}:
        key_name = str(command.get("key", "")).upper()
        if key_name not in VK:
            raise RuntimeError(f"Engine requested unsupported key {key_name!r}")
        send_key(VK[key_name], action == "key_down")
    elif action == "mouse_drag":
        move_cursor_to_window_center(window)
        mouse_drag(int(command.get("dx", 0)), int(command.get("dy", 0)))
    elif action == "mouse_center":
        move_cursor_to_window_center(window)
    elif action == "mouse_move_relative":
        move_mouse_relative(int(command.get("dx", 0)), int(command.get("dy", 0)))
    elif action == "mouse_left_click":
        click_left()
    elif action == "capture_screenshot":
        if ACTIVE_CAPTURE_DIR is None:
            raise RuntimeError("Screenshot requested without an active evidence directory")
        label = re.sub(r"[^A-Za-z0-9_.-]+", "_", str(command.get("label", "capture"))).strip("._") or "capture"
        sequence = int(command.get("sequence", len(CAPTURE_FILES) + 1))
        destination = ACTIVE_CAPTURE_DIR / f"{sequence:03d}_{label}.png"
        time.sleep(0.25)
        ImageGrab.grab(window=int(window["hwnd"])).save(destination, "PNG")
        CAPTURE_FILES.append(destination)
        print(f"[{place_stem}] D6 capture: {destination.name}", flush=True)
    else:
        raise RuntimeError(f"Engine requested unsupported action {action!r}")
    return window


def generate_and_audit(task_root: Path) -> tuple[Path, Path]:
    evaluation = task_root / "evaluation"
    runner = evaluation / "generated" / "tide_lock_formal_runner.client.luau"
    subprocess.run(
        [sys.executable, str(evaluation / "generate_runtime.py"), "--runtime-dir", str(evaluation / "runtime"), "--output", str(runner)],
        check=True,
    )
    audit = evaluation / "generated" / "policy_audit.json"
    subprocess.run(
        [
            sys.executable,
            str(evaluation / "static_policy_check.py"),
            str(runner),
            str(evaluation / "runtime" / "qa_observer.client.luau"),
			str(evaluation / "runtime" / "reopen_runner.client.luau"),
            "--output",
            str(audit),
        ],
        check=True,
    )
    if not json.loads(audit.read_text(encoding="utf-8"))["passed"]:
        raise RuntimeError("Static evaluator policy audit failed")
    return runner, audit


def build_qa(task_root: Path, runner: Path) -> Path:
    project = task_root / "candidate" / "original" / "TideLockCandidate" / "project"
    output = task_root / "qa" / "TideLockCandidate_QA.rbxlx"
    subprocess.run(
        [
            str(Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"),
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(task_root / "evaluation" / "build_qa_place.ps1"),
            "-ProjectDirectory",
            str(project),
            "-OutputPlace",
            str(output),
            "-FormalRunnerSource",
            str(runner),
            "-ObserverSource",
            str(task_root / "evaluation" / "runtime" / "qa_observer.client.luau"),
            "-GeneratedProject",
            str(task_root / "qa" / "generated.project.json"),
            "-Rojo",
            str(Path(os.environ.get('ROJO_EXE') or shutil.which('rojo') or 'rojo')),
        ],
        cwd=task_root,
        check=True,
    )
    return output


def assert_no_existing_studio() -> None:
    # A recently closed Studio can leave a windowless helper process alive for
    # several seconds. It cannot contaminate the next Play run and must not be
    # treated as an open editor. Only block on a real visible titled window.
    deadline = time.time() + 8
    windows: list[dict] = []
    while time.time() < deadline:
        windows = [item for item in studio_windows() if str(item.get("title", "")).strip()]
        if not windows:
            return
        time.sleep(0.4)
    details = "; ".join(
        f"PID={item.get('pid')} title={item.get('title')!r}" for item in windows
    )
    raise RuntimeError(
        "A Roblox Studio window is still visible:" + details
        + ". Close the window and retry."
    )


def clear_windowless_studio_helpers() -> None:
    """Stop stale Studio processes that retain WebView2/plugin file locks."""
    script = "Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | " \
        "Where-Object { $_.MainWindowHandle -eq 0 } | Stop-Process -Force -ErrorAction SilentlyContinue"
    powershell = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
    subprocess.run(
        [str(powershell), "-NoProfile", "-Command", script],
        check=False, capture_output=True, text=True,
    )
    time.sleep(1.5)


def clear_stale_evaluator_studio() -> None:
    """Terminate only stale Studio windows opened on Tide Lock QA copies."""
    targets = [
        item for item in studio_windows()
        if "tidelockcandidate_qa" in str(item.get("title", "")).lower()
    ]
    for item in targets:
        pid = int(item.get("pid", 0))
        if pid > 0:
            subprocess.run(
                ["taskkill.exe", "/PID", str(pid), "/T", "/F"],
                check=False, capture_output=True, text=True,
            )
    if targets:
        time.sleep(2)


def studio_environment():
    """Inherit the operator-configured network environment for Studio."""
    return os.environ.copy()


def release_all_keys() -> None:
    for key in ("W", "A", "S", "D", "E", "R", "SPACE"):
        send_key(VK[key], False)


def close_studio(place_stem: str, window: dict) -> None:
    window = ensure_focus(place_stem, window)
    target_pid = int(window.get("pid", 0))
    send_key(VK["ALT"], True)
    tap("F4", 0.08)
    send_key(VK["ALT"], False)
    # Closing is asynchronous. Do not let the next phase mistake the instance
    # we just closed for an unrelated user-owned Studio window.
    deadline = time.time() + 8
    while time.time() < deadline:
        remaining = [
            item for item in studio_windows()
            if (target_pid and int(item.get("pid", 0)) == target_pid)
            or place_stem.lower() in str(item.get("title", "")).lower()
        ]
        if not remaining:
            time.sleep(1.0)
            return
        time.sleep(0.25)
    # The QA instance is evaluator-owned: it was selected by its exact place
    # title and PID above.  A modal Studio shutdown occasionally ignores Alt-F4,
    # so terminate only that PID tree rather than leaving a false host failure.
    if target_pid > 0:
        terminated = subprocess.run(
            ["taskkill.exe", "/PID", str(target_pid), "/T", "/F"],
            check=False, capture_output=True, text=True,
        )
        time.sleep(1.5)
        if terminated.returncode == 0 and not any(
            int(item.get("pid", 0)) == target_pid for item in studio_windows()
        ):
            print(f"Studio QA window closed by evaluator-owned PID cleanup: {target_pid}.", flush=True)
            return
    raise RuntimeError(
        f"Studio window for {place_stem} did not close after controlled shutdown; "
        f"target PID was {target_pid}."
    )


def run_open_smoke(task_root: Path, qa_source: Path) -> Path:
    """Open the QA copy without Play/input and preserve OpenPlaceSuccess evidence."""
    global LAST_OUTPUT
    output = task_root / "audit" / "studio_open_smoke"
    output.mkdir(parents=True, exist_ok=True)
    LAST_OUTPUT = output
    clear_windowless_studio_helpers()
    assert_no_existing_studio()
    studio = find_studio()
    before = {item["hwnd"] for item in studio_windows()}
    launched_at = time.time()
    subprocess.Popen(
        [str(studio), "-task", "EditFile", "-localPlaceFile", str(qa_source)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=studio_environment(),
    )
    window = choose_window(before, qa_source.stem, 75)
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
    session_log = find_session_log(log_dir, qa_source.stem, launched_at, 45)
    wait_for_place_open_success(session_log, qa_source.stem, 120)
    copied = output / "studio_open_smoke.log"
    shutil.copy2(session_log, copied)
    static_path = task_root / "audit" / "static_results.json"
    static = json.loads(static_path.read_text(encoding="utf-8"))
    static["checkpoints"]["d1.studio_open_smoke"] = {
        "status": "pass",
        "detail": "Independent QA place reached OpenPlaceSuccess without entering Play mode.",
        "evidence": [{"file": str(copied.relative_to(task_root)), "sha256": sha256(copied)}],
        "trace_ids": [],
    }
    static_path.write_text(json.dumps(static, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    close_studio(qa_source.stem, window)
    print(f"Studio open smoke PASS; log: {copied}", flush=True)
    return copied


def run_reopen_probe(task_root: Path, output: Path) -> dict:
    """Fresh Studio Play session used only to prove clean initial state."""
    reopen_runner = task_root / "evaluation" / "runtime" / "reopen_runner.client.luau"
    qa_source = build_qa(task_root, reopen_runner)
    runtime_place = output / "TideLockCandidate_QA_reopen.rbxlx"
    shutil.copy2(qa_source, runtime_place)
    clear_stale_evaluator_studio()
    clear_windowless_studio_helpers()
    assert_no_existing_studio()
    studio = find_studio()
    before = {item["hwnd"] for item in studio_windows()}
    launched_at = time.time()
    subprocess.Popen([str(studio), "-task", "EditFile", "-localPlaceFile", str(runtime_place)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=studio_environment())
    window = choose_window(before, runtime_place.stem, 75)
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
    session_log = find_session_log(log_dir, runtime_place.stem, launched_at, 45)
    wait_for_place_open_success(session_log, runtime_place.stem, 120)
    offsets = {session_log: session_log.stat().st_size}
    window = focus_live_studio(runtime_place.stem, 60)
    print("[TideLockCandidate] Starting an independent clean-session Reopen check (no gameplay input)......", flush=True)
    tap("F5")
    if not wait_for_eval_client_ready(session_log, 25):
        raise RuntimeError("Reopen Play Client did not start; no Reopen verdict was produced")
    traces, checkpoints, events, done = {}, {}, [], False
    deadline = time.time() + 40
    while time.time() < deadline and not done:
        lines, offsets = read_new_log_lines([session_log], offsets)
        for line in lines:
            parsed = parse_line(line)
            if not parsed:
                continue
            kind, payload = parsed
            events.append({"kind": kind, **payload, "bridge_received_at_utc": datetime.now(timezone.utc).isoformat()})
            if kind == "trace" and payload.get("trace_id"):
                traces[str(payload["trace_id"])] = payload
            elif kind == "checkpoint" and payload.get("checkpoint_id"):
                checkpoints[str(payload["checkpoint_id"])] = {"status": payload.get("status", "inconclusive"), "detail": payload.get("detail", ""), "trace_ids": payload.get("trace_ids", [])}
                print(f"[TideLockCandidate] {payload.get('checkpoint_id')}: {str(payload.get('status')).upper()}", flush=True)
            elif kind == "done":
                done = payload.get("status") == "completed"
        time.sleep(0.02)
    window = ensure_focus(runtime_place.stem, window)
    tap("F6")
    time.sleep(1)
    close_studio(runtime_place.stem, window)
    copied = output / "reopen_studio_session.log"
    shutil.copy2(session_log, copied)
    event_file = output / "reopen_engine_events.jsonl"
    event_file.write_text("".join(json.dumps(item, ensure_ascii=False) + "\n" for item in events), encoding="utf-8")
    if not done or "d4.reopen_clean_session" not in checkpoints:
        raise RuntimeError("Reopen runner did not produce its required checkpoint")
    return {"checkpoints": checkpoints, "traces": traces, "log": copied.name, "log_sha256": sha256(copied), "events": event_file.name, "events_sha256": sha256(event_file), "qa_place_sha256": sha256(runtime_place)}


def run_candidate(
    task_root: Path,
    qa_source: Path,
    runner: Path,
    audit: Path,
    timeout: float,
    run_kind: str,
) -> Path:
    global LAST_OUTPUT, ACTIVE_CAPTURE_DIR, CAPTURE_FILES
    candidate_id = "TideLockCandidate"
    original_place = task_root / "candidate" / "original" / "TideLockCandidate" / "TideLockCandidate.rbxlx"
    project_zip = task_root / "candidate" / "TideLockCandidate.zip"
    if not original_place.exists() or not project_zip.exists():
        raise RuntimeError(f"{candidate_id} submission is incomplete")

    if run_kind == "formal" and list((task_root / "evidence").glob("formal_*")):
        raise RuntimeError("A formal evidence directory already exists; refusing to execute a second formal trajectory.")
    batch_id = datetime.now().strftime(f"{run_kind}_%Y%m%d_%H%M%S")
    output = task_root / "evidence" / batch_id
    output.mkdir(parents=True, exist_ok=False)
    LAST_OUTPUT = output
    ACTIVE_CAPTURE_DIR = output / "visual_states"
    ACTIVE_CAPTURE_DIR.mkdir(parents=True, exist_ok=False)
    CAPTURE_FILES = []
    runtime_place = output / f"TideLockCandidate_QA_{batch_id}.rbxlx"
    shutil.copy2(qa_source, runtime_place)

    policy_audit = json.loads(audit.read_text(encoding="utf-8"))
    metadata = {
        "run_id": f"{candidate_id}_{batch_id}",
        "candidate_id": candidate_id,
        "candidate_place_sha256": sha256(original_place),
        "candidate_project_zip_sha256": sha256(project_zip),
        "qa_place_sha256": sha256(runtime_place),
        "evaluator_sha256": sha256(runner),
        "policy_audit_sha256": sha256(audit),
        "input_backend": "Windows SendInput actuator",
        "judgment_backend": "Roblox Luau live engine state",
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "run_kind": run_kind,
        "formal_valid": run_kind == "formal",
    }

    clear_stale_evaluator_studio()
    clear_windowless_studio_helpers()
    assert_no_existing_studio()
    studio = find_studio()
    before = {item["hwnd"] for item in studio_windows()}
    launched_at = time.time()
    subprocess.Popen(
        [str(studio), "-task", "EditFile", "-localPlaceFile", str(runtime_place)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=studio_environment(),
    )
    window = choose_window(before, runtime_place.stem, 75)
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
    session_log = find_session_log(log_dir, runtime_place.stem, launched_at, 45)
    wait_for_place_open_success(session_log, runtime_place.stem, 120)
    offsets = {session_log: session_log.stat().st_size}
    log_paths = [session_log]
    window = focus_live_studio(runtime_place.stem, 60)

    label = "formal" if run_kind == "formal" else ("supplemental review" if run_kind == "supplemental" else "discarded diagnostic")
    print(f"[{candidate_id}] Studio opened; starting{label} Play trajectory......", flush=True)
    tap("F5")
    if not wait_for_eval_client_ready(session_log, 20):
        # Occasionally Studio creates only the local PlayServer data model and
        # never creates PlayClient. No candidate input or assertion has run, so
        # this is a startup retry rather than a second evaluation trajectory.
        print(f"[{candidate_id}] Play Client did not start; stopping and retrying once......", flush=True)
        window = ensure_focus(runtime_place.stem, window)
        tap("F6")
        time.sleep(2)
        window = ensure_focus(runtime_place.stem, window)
        tap("F5")
        if not wait_for_eval_client_ready(session_log, 25):
            window = ensure_focus(runtime_place.stem, window)
            tap("F6")
            raise RuntimeError(
                "Studio twice started PlayServer without PlayClient; no formal trajectory was executed. "
                "Close Studio and retry after it has fully exited."
            )
    events: list[dict] = []
    traces: dict[str, dict] = {}
    checkpoints: dict[str, dict] = {}
    commands: list[dict] = []
    command_sequences: set[int] = set()
    completed = False
    done_payload: dict = {}
    deadline = time.time() + timeout
    while time.time() < deadline and not completed:
        lines, offsets = read_new_log_lines(log_paths, offsets)
        for line in lines:
            parsed = parse_line(line)
            if not parsed:
                continue
            kind, payload = parsed
            received = datetime.now(timezone.utc).isoformat()
            event = {"kind": kind, **payload, "bridge_received_at_utc": received}
            events.append(event)
            if kind == "command":
                sequence = int(payload.get("sequence", -1))
                if sequence in command_sequences:
                    continue
                command_sequences.add(sequence)
                window = execute_command(payload, runtime_place.stem, window)
                commands.append(payload)
            elif kind == "trace":
                trace_id = str(payload.get("trace_id", ""))
                if trace_id:
                    traces[trace_id] = payload
            elif kind == "checkpoint":
                checkpoint_id = str(payload.get("checkpoint_id", ""))
                if checkpoint_id:
                    checkpoints[checkpoint_id] = {
                        "status": payload.get("status", "inconclusive"),
                        "detail": payload.get("detail", ""),
                        "trace_ids": payload.get("trace_ids", []),
                    }
                    print(f"[{candidate_id}] {checkpoint_id}: {str(payload.get('status', '')).upper()}", flush=True)
            elif kind == "done":
                done_payload = payload
                completed = payload.get("status") == "completed"
                if not completed:
                    raise RuntimeError(f"Engine suite aborted: {payload.get('detail', '')}")
        time.sleep(0.012)

    release_all_keys()
    try:
        window = ensure_focus(runtime_place.stem, window)
        tap("F6")
    finally:
        time.sleep(1)

    metadata["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    recovered_traces, recovered_checkpoints, recovered_counts = recover_engine_log(session_log)
    traces.update(recovered_traces)
    checkpoints.update(recovered_checkpoints)
    raw_log_copy = output / "studio_session.log"
    with session_log.open("rb") as source, raw_log_copy.open("wb") as destination:
        shutil.copyfileobj(source, destination, 1024 * 1024)
    metadata["studio_log_file"] = raw_log_copy.name
    metadata["studio_log_sha256"] = sha256(raw_log_copy)
    event_file = output / "engine_events.jsonl"
    event_file.write_text(
        "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in events),
        encoding="utf-8",
    )
    trace_file = output / "trace_index.json"
    trace_file.write_text(json.dumps(traces, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    dynamic = {
        "schema_version": "tide-lock-dynamic-v1",
        "metadata": metadata,
        "policy": {
            "only_virtual_input": True,
            "static_audit_passed": policy_audit["passed"],
            "teleports": 0,
            "direct_business_calls": 0,
            "direct_state_mutations": 0,
            "screenshots_used_for_control_or_scoring": run_kind == "supplemental",
            "llm_used_for_control_or_scoring": False,
            "candidate_source_used_for_routing_or_scoring": False,
            "absolute_candidate_coordinates": 0,
        },
        "checkpoints": checkpoints,
        "trace_index": sorted(traces),
        "trace_file": trace_file.name,
        "trace_file_sha256": sha256(trace_file),
        "engine_event_file": event_file.name,
        "engine_event_file_sha256": sha256(event_file),
        "recovered_engine_record_counts": recovered_counts,
        "input_command_count": len(commands),
        "visual_captures": [
            {"file": str(path.relative_to(output)), "sha256": sha256(path)} for path in CAPTURE_FILES
        ],
        "runner_status": "completed" if completed else "aborted",
        "host_fault": None if completed else "formal runner did not complete",
        "engine_done": done_payload,
        "summary": {
            "executable": completed,
            "solved": checkpoints.get("d4.complete_success_flow", {}).get("status") == "pass",
        },
    }
    evidence = output / "evidence.json"
    evidence.write_text(json.dumps(dynamic, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if run_kind == "debug":
        (output / "INVALID_DEBUG_RUN.txt").write_text(
            "This run is invalid for candidate scoring. It was executed only to debug the unified controller.\n",
            encoding="utf-8",
        )
    close_studio(runtime_place.stem, window)
    if run_kind == "formal":
        reopen = run_reopen_probe(task_root, output)
        dynamic = json.loads(evidence.read_text(encoding="utf-8"))
        dynamic["checkpoints"].update(reopen["checkpoints"])
        active_ok = dynamic["checkpoints"].get("aux.active_r_clean", {}).get("status") == "pass"
        reopen_ok = dynamic["checkpoints"].get("d4.reopen_clean_session", {}).get("status") == "pass"
        reopen_trace_ids = dynamic["checkpoints"].get("d4.reopen_clean_session", {}).get("trace_ids", [])
        dynamic["checkpoints"]["d2.restart_and_reopen_content"] = {
            "status": "pass" if active_ok and reopen_ok else "fail",
            "detail": "R reset and independent fresh Studio session must both begin clean.",
            "trace_ids": dynamic["checkpoints"].get("aux.active_r_clean", {}).get("trace_ids", []) + reopen_trace_ids,
        }
        dynamic["reopen_evidence"] = reopen
        dynamic["trace_index"] = sorted(set(dynamic.get("trace_index", [])) | set(reopen["traces"]))
        evidence.write_text(json.dumps(dynamic, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Evidence directory:{output}", flush=True)
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--open-smoke", action="store_true")
    parser.add_argument("--run-kind", choices=("debug", "formal", "supplemental"), default="debug")
    args = parser.parse_args()
    task_root = Path(__file__).resolve().parents[1]
    runner, audit = generate_and_audit(task_root)
    qa = build_qa(task_root, runner)
    print(f"TideLockCandidate QA build: {qa}")
    if args.build_only:
        return 0
    if args.open_smoke:
        run_open_smoke(task_root, qa)
        return 0
    output = run_candidate(task_root, qa, runner, audit, args.timeout, args.run_kind)
    if args.run_kind == "formal":
        score = output / "score.json"
        subprocess.run([sys.executable, str(task_root / "evaluation" / "score_evidence.py"), "--rules", str(task_root / "evaluation" / "rules.json"), "--static", str(task_root / "audit" / "static_results.json"), "--dynamic", str(output / "evidence.json"), "--output", str(score), "--allow-incomplete"], check=True)
        print(f"Formal score file:{score}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        diagnostic = traceback.format_exc()
        if LAST_OUTPUT is not None:
            (LAST_OUTPUT / "bridge_error.txt").write_text(diagnostic, encoding="utf-8")
        print(f"Evaluator stopped:{error}", file=sys.stderr, flush=True)
        if LAST_OUTPUT is not None:
            print(f"Diagnostic file:{LAST_OUTPUT / 'bridge_error.txt'}", file=sys.stderr, flush=True)
        raise SystemExit(1)
