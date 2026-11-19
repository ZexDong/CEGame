#!/usr/bin/env python3
"""Run the unchanged Deep Relay candidate through the unified local evaluator.

Roblox Luau performs discovery, path planning, observation, and judgment. This
desktop bridge only focuses Studio, executes requested Windows input, and copies
the resulting engine log records into immutable evidence files.
"""

from __future__ import annotations

import argparse
import ctypes
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
from urllib.parse import urlparse
from datetime import datetime, timezone
from pathlib import Path

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
    "command": "DEEP_RELAY_COMMAND ",
    "trace_anchor": "DEEP_RELAY_TRACE_ANCHOR ",
    "trace": "DEEP_RELAY_TRACE ",
    "checkpoint": "DEEP_RELAY_CHECKPOINT ",
    "ready": "DEEP_RELAY_EVAL_READY ",
    "done": "DEEP_RELAY_EVAL_DONE ",
    "observer": "DEEP_RELAY_OBSERVER ",
}
LAST_OUTPUT: Path | None = None


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


TRACE_ID_PATTERN = re.compile(r'"trace_id"\s*:\s*"(dr-trace-\d+)"')
TRACE_LITERAL_PATTERN = re.compile(r'"(dr-trace-\d+)"')
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
                elif kind == "trace_anchor" and payload.get("trace_id"):
                    trace_id = str(payload["trace_id"])
                    traces.setdefault(trace_id, {**payload, "record_format": "compact_trace_anchor"})
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
            if "DEEP_RELAY_EVAL_READY " in tail:
                return True
        except OSError:
            pass
        time.sleep(0.15)
    return False


def is_target_studio(current: dict, place_stem: str, target: dict) -> bool:
    return current.get("path", "").lower().endswith("robloxstudiobeta.exe") and (
        place_stem.lower() in current.get("title", "").lower()
        or (target.get("hwnd") and current.get("hwnd") == target.get("hwnd"))
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
    else:
        raise RuntimeError(f"Engine requested unsupported action {action!r}")
    return window


def generate_and_audit(task_root: Path) -> tuple[Path, Path, Path]:
    evaluation = task_root / "evaluation"
    formal_runner = evaluation / "generated" / "deep_relay_formal_runner.client.luau"
    reopen_runner = evaluation / "generated" / "deep_relay_reopen_runner.client.luau"
    for mode, runner in (("formal", formal_runner), ("reopen", reopen_runner)):
        subprocess.run(
            [sys.executable, str(evaluation / "generate_runtime.py"), "--runtime-dir", str(evaluation / "runtime"), "--output", str(runner), "--mode", mode],
            check=True,
        )
    audit = evaluation / "generated" / "policy_audit.json"
    subprocess.run(
        [
            sys.executable,
            str(evaluation / "static_policy_check.py"),
            str(formal_runner),
            str(reopen_runner),
            str(evaluation / "runtime" / "qa_observer.client.luau"),
            "--output",
            str(audit),
        ],
        check=True,
    )
    if not json.loads(audit.read_text(encoding="utf-8"))["passed"]:
        raise RuntimeError("Static evaluator policy audit failed")
    return formal_runner, reopen_runner, audit


def build_qa(task_root: Path, runner: Path, label: str) -> Path:
    project = task_root / "candidate" / "source" / "project"
    output = task_root / "qa" / f"DeepRelayCandidate_QA_{label}.rbxlx"
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
            str(task_root / "qa" / f"generated_{label}.project.json"),
            "-Rojo",
            str(task_root / "tools" / "rojo.exe"),
        ],
        cwd=task_root,
        check=True,
    )
    hashes_path = task_root / "audit" / "hashes.json"
    if hashes_path.exists():
        manifest = json.loads(hashes_path.read_text(encoding="utf-8"))
        relative = str(output.relative_to(task_root)).replace("\\", "/")
        manifest["files"] = [record for record in manifest.get("files", []) if record.get("file") != relative]
        manifest["files"].append({"file": relative, "sha256": sha256(output), "bytes": output.stat().st_size, "scope": "independent_qa_copy"})
        hashes_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return output


def assert_no_existing_studio() -> None:
    # A recently closed Studio can leave a windowless helper process alive for
    # several seconds. It cannot contaminate the next Play run and must not be
    # treated as an open editor. Only block on a real visible titled window.
    deadline = time.time() + 8
    windows: list[dict] = []
    while time.time() < deadline:
        windows = [
            item for item in studio_windows()
            if str(item.get("title", "")).strip()
            and "deeprelaycandidate_qa_" not in str(item.get("title", "")).lower()
        ]
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
    """Windowless helpers are ignored and never force-terminated."""
    return


def clear_stale_evaluator_studio() -> None:
    """Terminate only stale evaluator-owned Deep Relay QA windows."""
    targets = [
        item for item in studio_windows()
        if "deeprelaycandidate_qa_" in str(item.get("title", "")).lower()
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
    # Closing an evaluator-owned window is process lifecycle control, not a
    # gameplay input. Do not require foreground focus merely to close it.
    current_matches = [
        item for item in studio_windows()
        if int(item.get("hwnd", 0)) == int(window.get("hwnd", 0))
        and item.get("path", "").lower().endswith("robloxstudiobeta.exe")
        and place_stem.lower() in str(item.get("title", "")).lower()
    ]
    if not current_matches:
        return
    window = current_matches[0]
    target_pid = int(window.get("pid", 0))
    WM_CLOSE = 0x0010
    ctypes.windll.user32.PostMessageW(int(window["hwnd"]), WM_CLOSE, 0, 0)
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


def open_studio_place(place: Path) -> tuple[dict, Path, float]:
    """Open and bind a QA place, allowing one pre-Play startup-level retry."""
    failures: list[str] = []
    for attempt in (1, 2):
        clear_stale_evaluator_studio()
        clear_windowless_studio_helpers()
        assert_no_existing_studio()
        studio = find_studio()
        print(f"Studio executable:{studio}", flush=True)
        before = {item["hwnd"] for item in studio_windows()}
        log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
        log_baseline = {path: path.stat().st_size for path in log_dir.glob("*Studio*_last.log") if path.is_file()}
        launched_at = time.time()
        subprocess.Popen(
            [str(studio), "-task", "EditFile", "-localPlaceFile", str(place)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=studio_environment(),
        )
        window: dict | None = None
        try:
            window = choose_window(before, place.stem, 75)
            session_log = find_session_log(log_dir, place.stem, launched_at, 45, log_baseline)
            wait_for_place_open_success(session_log, place.stem, 120)
            return window, session_log, launched_at
        except Exception as error:
            failures.append(f"attempt {attempt}: {error}")
            if window is not None:
                try:
                    close_studio(place.stem, window)
                except Exception as close_error:
                    failures.append(f"attempt {attempt} cleanup: {close_error}")
            if attempt == 1:
                print("The QA place is not bound to the target log and Play has not started. Another Studio task may occupy the single-instance channel; wait and retry once.", flush=True)
                time.sleep(15)
    raise RuntimeError("QA Place startup failed before Play: " + " | ".join(failures))


def run_open_smoke(task_root: Path, qa_source: Path) -> Path:
    """Open the QA copy without Play/input and preserve OpenPlaceSuccess evidence."""
    global LAST_OUTPUT
    output = task_root / "audit" / "studio_open_smoke"
    output.mkdir(parents=True, exist_ok=True)
    previous_error = output / "bridge_error.txt"
    if previous_error.exists():
        invalid_dir = task_root / "audit" / "invalid_debug"
        invalid_dir.mkdir(parents=True, exist_ok=True)
        archived = invalid_dir / datetime.now().strftime("smoke_%Y%m%d_%H%M%S_bridge_error.txt")
        shutil.move(str(previous_error), str(archived))
    LAST_OUTPUT = output
    window, session_log, launched_at = open_studio_place(qa_source)
    copied = output / "studio_open_smoke.log"
    shutil.copy2(session_log, copied)
    static_path = task_root / "audit" / "static_results.json"
    static = json.loads(static_path.read_text(encoding="utf-8"))
    static["checkpoints"]["d1.studio_open_smoke"] = {
        "status": "pass",
        "detail": "The unchanged delivered place reached OpenPlaceSuccess without entering Play mode or receiving player input.",
        "evidence": [{"file": str(copied.relative_to(task_root)), "sha256": sha256(copied)}],
        "trace_ids": [],
    }
    static_path.write_text(json.dumps(static, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    close_studio(qa_source.stem, window)
    print(f"Studio open smoke PASS; log: {copied}", flush=True)
    return copied


def run_candidate(
    task_root: Path,
    qa_source: Path,
    runner: Path,
    audit: Path,
    timeout: float,
    run_kind: str,
) -> Path:
    global LAST_OUTPUT
    candidate_id = "DeepRelayCandidate"
    original_place = task_root / "candidate" / "original" / "DeepRelayCandidate.rbxlx"
    project_zip = task_root / "candidate" / "original" / "DeepRelayCandidate_project.zip"
    if not original_place.exists() or not project_zip.exists():
        raise RuntimeError(f"{candidate_id} submission is incomplete")

    if run_kind == "formal" and (task_root / "evidence" / "FORMAL_COMPLETE.lock").exists():
        raise RuntimeError("A completed formal evidence lock exists; refusing to execute a second valid formal trajectory.")
    batch_id = datetime.now().strftime(f"{run_kind}_%Y%m%d_%H%M%S")
    output = task_root / "evidence" / batch_id
    output.mkdir(parents=True, exist_ok=False)
    LAST_OUTPUT = output
    runtime_place = output / f"DeepRelayCandidate_QA_{batch_id}.rbxlx"
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
        "formal_valid": run_kind in {"formal", "reopen"},
        "window_validation": "live HWND and RobloxStudioBeta.exe foreground check before every input",
        "play_client_ready_required": True,
    }

    window, session_log, launched_at = open_studio_place(runtime_place)
    offsets = {session_log: session_log.stat().st_size}
    log_paths = [session_log]
    window = focus_live_studio(runtime_place.stem, 60)

    label = "primary formal" if run_kind == "formal" else ("formal Reopen" if run_kind == "reopen" else "discarded diagnostic")
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
    window = ensure_focus(runtime_place.stem, window)
    move_cursor_to_window_center(window)
    click_left()
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
            elif kind == "trace_anchor":
                trace_id = str(payload.get("trace_id", ""))
                if trace_id:
                    traces.setdefault(trace_id, {**payload, "record_format": "compact_trace_anchor"})
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
    emitted_unresolved = [
        checkpoint_id for checkpoint_id, record in checkpoints.items()
        if record.get("status") in {"inconclusive", "not_run"}
    ]
    metadata["formal_valid"] = (
        run_kind in {"formal", "reopen"} and completed and not emitted_unresolved
    )
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
        "schema_version": "deep-relay-dynamic-v1",
        "metadata": metadata,
        "policy": {
            "only_virtual_input": True,
            "static_audit_passed": policy_audit["passed"],
            "teleports": 0,
            "direct_business_calls": 0,
            "direct_state_mutations": 0,
            "screenshots_used_for_control_or_scoring": False,
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
        "runner_status": "completed" if completed else "aborted",
        "host_fault": None if completed else "formal runner did not complete",
        "engine_done": done_payload,
        "summary": {
            "executable": completed and checkpoints.get("d4.start_to_play", {}).get("status") == "pass",
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
    print(f"Evidence directory:{output}", flush=True)
    close_studio(runtime_place.stem, window)
    return output


def merge_formal_sessions(task_root: Path, formal_dir: Path, reopen_dir: Path) -> Path:
    """Merge the separate clean-process Reopen evidence into the formal result."""
    formal_path = formal_dir / "evidence.json"
    reopen_path = reopen_dir / "evidence.json"
    formal = json.loads(formal_path.read_text(encoding="utf-8"))
    reopened = json.loads(reopen_path.read_text(encoding="utf-8"))
    reopen_checkpoint = reopened.get("checkpoints", {}).get("d4.reopen_clean_session")
    if not isinstance(reopen_checkpoint, dict):
        raise RuntimeError("Clean Reopen session did not produce d4.reopen_clean_session evidence")

    formal_traces_path = formal_dir / "trace_index.json"
    reopen_traces_path = reopen_dir / "trace_index.json"
    formal_traces = json.loads(formal_traces_path.read_text(encoding="utf-8"))
    reopen_traces = json.loads(reopen_traces_path.read_text(encoding="utf-8"))
    renamed: dict[str, dict] = {}
    for trace_id, payload in reopen_traces.items():
        new_id = f"reopen/{trace_id}"
        new_payload = dict(payload)
        new_payload["trace_id"] = new_id
        renamed[new_id] = new_payload
    formal_traces.update(renamed)
    reopen_checkpoint = dict(reopen_checkpoint)
    reopen_checkpoint["trace_ids"] = [f"reopen/{value}" for value in reopen_checkpoint.get("trace_ids", [])]
    formal["checkpoints"]["d4.reopen_clean_session"] = reopen_checkpoint
    formal["trace_index"] = sorted(formal_traces)

    evidence_faults: list[str] = []
    for checkpoint_id, record in formal["checkpoints"].items():
        status = record.get("status")
        trace_ids = record.get("trace_ids", [])
        if status in {"pass", "fail"} and not trace_ids:
            evidence_faults.append(f"{checkpoint_id}: PASS/FAIL without trace ids")
            continue
        missing = [trace_id for trace_id in trace_ids if trace_id not in formal_traces]
        if missing:
            evidence_faults.append(f"{checkpoint_id}: missing trace records {missing}")
        full = [trace_id for trace_id in trace_ids if trace_id in formal_traces and formal_traces[trace_id].get("record_format") not in {"compact_trace_anchor", "studio_truncated_json_stub"}]
        if status in {"pass", "fail"} and not full:
            evidence_faults.append(f"{checkpoint_id}: no complete engine-state trace")
    formal["evidence_contract_faults"] = evidence_faults
    formal["runner_status"] = "completed" if formal.get("runner_status") == "completed" and reopened.get("runner_status") == "completed" and not evidence_faults else "aborted"
    formal["host_fault"] = None if formal["runner_status"] == "completed" else ("evidence contract did not close" if evidence_faults else "formal or Reopen runner did not complete")
    required_dynamic = {
        checkpoint_id
        for dimension in json.loads((task_root / "evaluation" / "rules.json").read_text(encoding="utf-8"))["dimensions"]
        if dimension["id"] in {"D2", "D3", "D4", "D5"}
        for checkpoint_id in dimension["checkpoints"]
    }
    formal["metadata"]["formal_valid"] = (
        formal["runner_status"] == "completed"
        and required_dynamic.issubset(formal["checkpoints"])
        and all(formal["checkpoints"][checkpoint_id].get("status") in {"pass", "fail"} for checkpoint_id in required_dynamic)
    )
    formal.setdefault("summary", {})["solved"] = (
        formal.get("checkpoints", {}).get("d4.complete_success_flow", {}).get("status") == "pass"
        and reopen_checkpoint.get("status") == "pass"
    )

    reopen_log = reopen_dir / "studio_session.log"
    copied_reopen_log = formal_dir / "studio_reopen_session.log"
    shutil.copy2(reopen_log, copied_reopen_log)
    formal["metadata"]["reopen_session"] = {
        "evidence_file": str(reopen_path.relative_to(task_root)).replace("\\", "/"),
        "evidence_sha256": sha256(reopen_path),
        "studio_log_file": copied_reopen_log.name,
        "studio_log_sha256": sha256(copied_reopen_log),
        "separate_process_boundary": True,
    }
    formal_traces_path.write_text(json.dumps(formal_traces, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    formal["trace_file_sha256"] = sha256(formal_traces_path)
    formal_path.write_text(json.dumps(formal, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    score_path = formal_dir / "score.json"
    subprocess.run(
        [
            sys.executable, str(task_root / "evaluation" / "score_evidence.py"),
            "--rules", str(task_root / "evaluation" / "rules.json"),
            "--static", str(task_root / "audit" / "static_results.json"),
            "--dynamic", str(formal_path),
            "--output", str(score_path),
            "--allow-incomplete",
        ],
        check=True,
    )
    score = json.loads(score_path.read_text(encoding="utf-8"))
    budget = json.loads((task_root / "evaluation" / "runtime" / "budget_plan.json").read_text(encoding="utf-8"))
    run_stats = {
        "schema_version": "deep-relay-evaluator-run-stats-v1",
        "formal_started_at_utc": formal.get("metadata", {}).get("started_at_utc"),
        "formal_finished_at_utc": formal.get("metadata", {}).get("finished_at_utc"),
        "reopen_started_at_utc": reopened.get("metadata", {}).get("started_at_utc"),
        "reopen_finished_at_utc": reopened.get("metadata", {}).get("finished_at_utc"),
        "dynamic_trajectory_count": 2,
        "declared_dynamic_trajectory_steps": sum(item["declared_dynamic_trajectory_steps"] for item in budget["sessions"]),
        "runner_input_command_count": int(formal.get("input_command_count", 0)) + int(reopened.get("input_command_count", 0)),
        "budget_plan": "evaluation/runtime/budget_plan.json",
        "generation_token_usage": {"status": "unavailable", "value": None, "reason": "Generation-only provider usage was not supplied with the candidate handoff."},
        "generation_trajectory_steps": {"status": "unavailable", "value": None, "reason": "No normalized generation-only action-observation log was supplied."},
        "evaluator_token_usage": {"status": "not_applicable", "value": 0, "reason": "D1-D5 evaluator is deterministic Python/Luau and does not call a model."}
    }
    (formal_dir / "evaluator_run_stats.json").write_text(json.dumps(run_stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    report_lines = [
        "# Deep Relay Final Automated Evaluation Report",
        "",
        f"- Official score: {score.get('official_score')}",
        f"- D1–D5 provisional subtotal: {score.get('provisional_subtotal')} / 90",
        f"- Executable: {score.get('executable')}",
        f"- Solved: {score.get('solved')}",
        f"- D6: {'unavailable (no independent reference image set)' if score.get('official_score') is None else 'available'}",
        "",
        "## Checkpoints",
        "",
    ]
    for dimension in score.get("breakdown", []):
        report_lines.append(f"### {dimension.get('dimension')} — {dimension.get('score')} / {dimension.get('possible')}")
        report_lines.append("")
        for item in dimension.get("checkpoints", []):
            report_lines.append(f"- {item.get('id')}: {str(item.get('status', '')).upper()} — {item.get('detail', '')}")
        report_lines.append("")
    if score.get("problems"):
        report_lines.extend(["## Evaluator problems", "", *[f"- {item}" for item in score["problems"]], ""])
    (formal_dir / "final_evaluation_report.md").write_text("\n".join(report_lines), encoding="utf-8")

    final_hashes = []
    for path in sorted(formal_dir.rglob("*")):
        if path.is_file() and path.name != "formal_output_hashes.json":
            final_hashes.append({"file": str(path.relative_to(formal_dir)).replace("\\", "/"), "sha256": sha256(path), "bytes": path.stat().st_size})
    (formal_dir / "formal_output_hashes.json").write_text(json.dumps({"schema_version": "deep-relay-formal-output-hashes-v1", "files": final_hashes}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    non_visual_unresolved = [item for item in score.get("unresolved", []) if item != "D6 visual evaluation not available"]
    formal_valid_without_d6 = score.get("runner_valid") is True and not non_visual_unresolved and not score.get("problems")
    if not formal_valid_without_d6:
        (formal_dir / "INVALID_FORMAL_RUN.txt").write_text(
            "This run is invalid for candidate scoring because D1-D5 adjudication or evaluator execution is incomplete.\n"
            + "unresolved=" + json.dumps(non_visual_unresolved, ensure_ascii=False) + "\n"
            + "problems=" + json.dumps(score.get("problems", []), ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        raise RuntimeError("Formal D1-D5 adjudication is incomplete; no formal lock was written. Inspect INVALID_FORMAL_RUN.txt and controller evidence before retrying.")
    lock = task_root / "evidence" / "FORMAL_COMPLETE.lock"
    lock.write_text(f"formal_evidence={formal_dir.name}\nscore_sha256={sha256(score_path)}\n", encoding="utf-8")
    return score_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--open-smoke", action="store_true")
    parser.add_argument("--run-kind", choices=("debug", "formal", "reopen"), default="debug")
    args = parser.parse_args()
    task_root = Path(__file__).resolve().parents[1]
    formal_runner, reopen_runner, audit = generate_and_audit(task_root)
    formal_qa = build_qa(task_root, formal_runner, "Formal")
    reopen_qa = build_qa(task_root, reopen_runner, "Reopen")
    runner = reopen_runner if args.run_kind == "reopen" else formal_runner
    qa = reopen_qa if args.run_kind == "reopen" else formal_qa
    print(f"DeepRelayCandidate formal QA build: {formal_qa}")
    print(f"DeepRelayCandidate Reopen QA build: {reopen_qa}")
    if args.build_only:
        return 0
    if args.open_smoke:
        run_open_smoke(task_root, task_root / "candidate" / "original" / "DeepRelayCandidate.rbxlx")
        return 0
    if args.run_kind == "formal":
        static_path = task_root / "audit" / "static_results.json"
        if not static_path.is_file():
            raise RuntimeError("Run evaluation/static_audit.py before the formal dynamic evaluation.")
        static = json.loads(static_path.read_text(encoding="utf-8"))
        if static.get("checkpoints", {}).get("d1.studio_open_smoke", {}).get("status") != "pass":
            run_open_smoke(task_root, task_root / "candidate" / "original" / "DeepRelayCandidate.rbxlx")
        formal_dir = run_candidate(task_root, formal_qa, formal_runner, audit, args.timeout, "formal")
        reopen_dir = run_candidate(task_root, reopen_qa, reopen_runner, audit, 150, "reopen")
        score_path = merge_formal_sessions(task_root, formal_dir, reopen_dir)
        print(f"Merged score:{score_path}", flush=True)
    else:
        run_candidate(task_root, qa, runner, audit, args.timeout, args.run_kind)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        diagnostic = traceback.format_exc()
        if LAST_OUTPUT is not None:
            (LAST_OUTPUT / "bridge_error.txt").write_text(diagnostic, encoding="utf-8")
            try:
                if (LAST_OUTPUT.parent.name == "evidence" or LAST_OUTPUT.parent.parent.name == "evidence"):
                    (LAST_OUTPUT / "INVALID_EVALUATOR_RUN.txt").write_text(
                        "Environment, host, or controller execution failed. This directory is invalid for candidate scoring.\n",
                        encoding="utf-8",
                    )
            except OSError:
                pass
        print(f"Evaluator stopped:{error}", file=sys.stderr, flush=True)
        if LAST_OUTPUT is not None:
            print(f"Diagnostic file:{LAST_OUTPUT / 'bridge_error.txt'}", file=sys.stderr, flush=True)
        raise SystemExit(1)
