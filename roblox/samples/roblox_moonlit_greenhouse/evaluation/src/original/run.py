from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time
import traceback
from datetime import datetime
from pathlib import Path

from local_bridge_support import (
    VK,
    choose_window,
    find_studio,
    focus_live_studio,
    foreground_window,
    read_new_log_lines,
    send_key,
    studio_windows,
    tap,
)

ROOT = Path(__file__).resolve().parent
PREFIX = "MG26_QA "
KEY_DOWN_AT = {}
REVISION = "moonlit-greenhouse-20261026-v3.1-physical-input-natural-final"


def self_test() -> int:
    rules = json.loads((ROOT / "rules.json").read_text(encoding="utf-8"))
    required = [
        ROOT / "tools/rojo.exe",
        ROOT / "source/MoonlitGreenhouse/default.project.json",
        ROOT / "runtime/observer.server.luau",
        ROOT / "runtime/trajectory.client.luau",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    automatic_total = sum(
        check["weight"]
        for dimension in rules["dimensions"].values()
        for check in dimension.get("checks", [])
    )
    if missing or automatic_total != 90:
        print("SELF-TEST FAILED", flush=True)
        for path in missing:
            print("Missing:", path, flush=True)
        print("Automatic weight:", automatic_total, flush=True)
        return 2
    print("SELF-TEST PASS", flush=True)
    print("Evaluator revision:", REVISION, flush=True)
    print("Python:", sys.executable, flush=True)
    print("Evaluator root:", ROOT, flush=True)
    print("Automatic checks: 21; weight: 90", flush=True)
    return 0


def hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(output: Path, fresh: bool = False) -> Path:
    from evaluate import build as build_candidate_qa
    return build_candidate_qa(output, fresh)


def open_log(place: Path, launched_at: float) -> Path:
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox/logs"
    deadline = time.time() + 180
    while time.time() < deadline:
        candidates = sorted(log_dir.glob("*Studio*_last.log"), key=lambda p: p.stat().st_ctime, reverse=True)
        for path in candidates:
            if path.stat().st_ctime < launched_at - 3:
                continue
            content = path.read_text(encoding="utf-8", errors="replace").lower()
            if place.stem.lower() in content and "openplacesuccess" in content:
                return path
        time.sleep(0.25)
    raise RuntimeError("Studio did not report OpenPlaceSuccess")


def launch(place: Path):
    before = {window["hwnd"] for window in studio_windows()}
    launched_at = time.time()
    subprocess.Popen([str(find_studio()), "-task", "EditFile", "-localPlaceFile", str(place)], env=os.environ.copy())
    choose_window(before, place.stem, 90)
    log = open_log(place, launched_at)
    window = focus_live_studio(place.stem, 30)
    tap("F5")
    return window, log


def consume(line, events, checks, chunks, window, place):
    marker = line.find(PREFIX)
    if marker < 0:
        return window
    try:
        packet = json.loads(line[marker + len(PREFIX):].strip())
    except json.JSONDecodeError:
        return window
    if packet.get("kind") == "chunk":
        entry = chunks.setdefault(packet["packet"], {})
        entry[packet["part"]] = packet["data"]
        if len(entry) != packet["total"]:
            return window
        try:
            packet = json.loads("".join(entry[index] for index in range(1, packet["total"] + 1)))
        except (KeyError, json.JSONDecodeError):
            return window
    events.append(packet)
    if packet.get("kind") == "await_input":
        key = packet.get("key")
        if key not in ("E", "R"):
            raise RuntimeError("Unsupported private input request")
        current = foreground_window()
        if current.get("pid") != window.get("pid") or place.stem.lower() not in current.get("title", "").lower():
            window = focus_live_studio(place.stem, 20)
        tap(key, 0.08)
    elif packet.get("kind") == "input":
        current = foreground_window()
        if current.get("pid") != window.get("pid"):
            window = focus_live_studio(place.stem, 20)
        key = packet["key"]
        if not packet["down"]:
            remaining = 0.22 - (time.monotonic() - KEY_DOWN_AT.get(key, 0))
            if remaining > 0:
                time.sleep(remaining)
        send_key(VK[key], packet["down"])
        if packet["down"]:
            KEY_DOWN_AT[key] = time.monotonic()
    elif packet.get("kind") == "check":
        checks[packet["id"]] = packet
        print(f'[{packet["id"]}] {packet["status"]}: {packet["detail"]}', flush=True)
    elif packet.get("kind") in {"error", "segment_error"}:
        print("Evaluator diagnostic:", packet.get("detail", ""), flush=True)
    elif packet.get("kind") in {"server_boot", "client_boot", "ready", "server_status", "client_readiness", "visual_checkpoint", "physical_input_pass", "preview_observation"}:
        print("Stage diagnostic:", json.dumps(packet, ensure_ascii=False), flush=True)
    return window


def collect(place, window, log, events, checks, timeout):
    offsets = {log: 0}
    chunks = {}
    stage_start = len(events)
    deadline = time.time() + timeout
    finished = False
    incomplete = False
    while time.time() < deadline and not finished:
        lines, offsets = read_new_log_lines([log], offsets)
        for line in lines:
            window = consume(line, events, checks, chunks, window, place)
        stage_done = next((event for event in events[stage_start:] if event.get("kind") == "done"), None)
        if stage_done is not None:
            finished = True
            incomplete = bool(stage_done.get("incomplete"))
        time.sleep(0.015)
    return finished, incomplete, window


def stop_and_close_owned(place: Path, window):
    window = focus_live_studio(place.stem, 20)
    send_key(VK["SHIFT"], True)
    try:
        tap("F5")
    finally:
        send_key(VK["SHIFT"], False)
    time.sleep(1)
    send_key(VK["ALT"], True)
    try:
        tap("F4")
    finally:
        send_key(VK["ALT"], False)
    deadline = time.time() + 12
    while any(item.get("pid") == window.get("pid") for item in studio_windows()) and time.time() < deadline:
        time.sleep(0.2)
    remaining = [item for item in studio_windows() if item.get("pid") == window.get("pid")]
    if remaining:
        owned = any(
            place.stem.lower() in item.get("title", "").lower()
            and item.get("path", "").lower().endswith("robloxstudiobeta.exe")
            for item in remaining
        )
        if not owned:
            raise RuntimeError("The remaining Studio process is not uniquely attributable to this evaluator")
        subprocess.run(
            ["taskkill", "/PID", str(window["pid"]), "/T", "/F"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(1)
    if any(item.get("pid") == window.get("pid") for item in studio_windows()):
        raise RuntimeError("The evaluator-owned first Studio window did not close")


def main() -> int:
    print("Evaluator revision:", REVISION, flush=True)
    evidence = ROOT / "evidence" / datetime.now().strftime("formal_%Y%m%d_%H%M%S")
    evidence.mkdir(parents=True, exist_ok=False)
    events = []
    checks = {}
    logs = []
    process_ids = []
    completed = False
    incomplete = False
    error = None
    place = None
    window = None
    try:
        compile_results = []
        for script in sorted((ROOT / "source/MoonlitGreenhouse").rglob("*.luau")):
            result = subprocess.run([str(ROOT / "tools/luau-compile.exe"), "--null", str(script)], capture_output=True, encoding="utf-8", errors="replace")
            compile_results.append({"file": str(script.relative_to(ROOT / "source/MoonlitGreenhouse")), "exit_code": result.returncode, "stderr": result.stderr})
        (evidence / "compile.json").write_text(json.dumps(compile_results, ensure_ascii=False, indent=2), encoding="utf-8")
        if any(item["exit_code"] for item in compile_results):
            raise RuntimeError("Candidate Luau compilation failed; see compile.json")
        if studio_windows():
            raise RuntimeError("Close all Roblox Studio windows, then rerun the command.")
        print("[1/4] Building and launching the QA project...", flush=True)
        place = build(evidence)
        window, log = launch(place)
        logs.append(("studio_dynamic.log", log))
        process_ids.append(window.get("pid"))
        print("[2/4] Running gameplay and boundary tests; leave the keyboard and mouse idle...", flush=True)
        finished, incomplete, window = collect(place, window, log, events, checks, 900)
        if not finished or incomplete:
            raise RuntimeError("The first observer session did not finish")
        stop_and_close_owned(place, window)

        print("[3/4] Verifying a clean reopen in a new Studio process...", flush=True)
        fresh_dir = evidence / "fresh"
        fresh_dir.mkdir()
        place = build(fresh_dir, fresh=True)
        window, log = launch(place)
        logs.append(("studio_fresh.log", log))
        process_ids.append(window.get("pid"))
        if process_ids[0] == process_ids[1]:
            raise RuntimeError("The reopen check did not obtain a different PID")
        fresh_event_start = len(events)
        finished, incomplete, window = collect(place, window, log, events, checks, 240)
        fresh_check = any(packet.get("kind")=="check" and packet.get("id")=="D4_REOPEN" for packet in events[fresh_event_start:])
        completed = finished and not incomplete and fresh_check
        if not completed:
            packets = events[fresh_event_start:]
            kinds = sorted({packet.get("kind", "unknown") for packet in packets})
            raise RuntimeError("The new process did not complete client/character readiness and D4_REOPEN; phase events:" + ", ".join(kinds))
        print("[4/4] Evaluation finished; writing evidence...", flush=True)
    except Exception as exc:
        error = str(exc)
        events.append({"kind": "runner_error", "error": error})
        traceback.print_exc()
    finally:
        for key in ("W", "A", "S", "D", "E", "R", "SHIFT"):
            send_key(VK[key], False)
        for name, source in logs:
            try:
                (evidence / name).write_text(source.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
            except OSError:
                pass
        (evidence / "events.json").write_text(json.dumps(events, ensure_ascii=False, indent=2), encoding="utf-8")
        rules = json.loads((ROOT / "rules.json").read_text(encoding="utf-8"))
        dimensions = {}
        unresolved = []
        automatic_total = 0
        for dimension, spec in rules["dimensions"].items():
            if spec.get("manual"):
                dimensions[dimension] = {"status": "MANUAL_REVIEW_REQUIRED", "maximum": spec["maximum_score"]}
                continue
            earned = 0
            unknown = 0
            for item in spec["checks"]:
                result = checks.get(item["id"])
                if result and result.get("status") == "PASS":
                    earned += item["weight"]
                elif not result or result.get("status") == "INCONCLUSIVE_EVALUATOR":
                    unknown += item["weight"]
                    unresolved.append(item["id"])
            dimensions[dimension] = {"confirmed": earned, "unresolved": unknown, "maximum": spec["maximum_score"]}
            automatic_total += earned
        payload = {
            "schema_version": 1,
            "benchmark_id": rules["benchmark_id"],
            "completed": completed and not unresolved,
            "runtime_finished": completed,
            "runner_error": error,
            "process_ids": process_ids,
            "automatic_score": automatic_total,
            "automatic_score_maximum": rules["automatic_score_maximum"],
            "manual_visual_score_maximum": rules["manual_visual_score_maximum"],
            "dimensions": dimensions,
            "unresolved_checks": unresolved,
            "checks": checks,
            "candidate_hashes": {
                str(path.relative_to(ROOT / "source/MoonlitGreenhouse")): hash_file(path)
                for path in (ROOT / "source/MoonlitGreenhouse").rglob("*") if path.is_file()
            },
            "evaluator_revision": REVISION,
            "note": "Automatic score is out of 90; pending items are not product failures. Physical E keys drive original prompts, physical R verifies terminal reset. Earlier bed setup uses QA placement; final route uses natural Humanoid walking. D6 requires separate visual review.",
        }
        (evidence / "score.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Evidence directory: {evidence}", flush=True)
        print(f"Confirmed passed-check score: {automatic_total}/90; Unresolved checks: {len(unresolved)}; Visual evidence review: Pending /10", flush=True)
        if unresolved or not completed:
            print("Evaluation is incomplete. The passed-check subtotal is not final; unresolved checks are not product failures.", flush=True)
        if window and place and completed:
            print("The reopened window remains available for inspection. Stop Play and close Studio afterward.", flush=True)
    return 0 if completed and not unresolved else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        raise SystemExit(self_test())
    if "--preflight-only" in sys.argv[1:]:
        from evaluate import prepare
        prepare()
        print("PREFLIGHT PASS. Studio was not opened; dynamic score is pending.")
        raise SystemExit(0)
    raise SystemExit(main())

