from __future__ import annotations

import hashlib
import json
import os
import socket
import subprocess
import sys
import time
import traceback
import ctypes
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Keep native pointer coordinates in the same pixels as Roblox's viewport.
ctypes.windll.user32.SetProcessDPIAware()

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
    mouse_drag,
    move_cursor_to_window_center,
)

ROOT = Path(__file__).resolve().parent
PREFIX = "SY_QA "
OWNED_PROCESSES = {}


def self_test() -> int:
    rules = json.loads((ROOT / "rules.json").read_text(encoding="utf-8"))
    required = [
        ROOT / "tools/rojo.exe",
        ROOT / "tools/luau-compile.exe",
        ROOT / "preflight.py",
        ROOT / "mouse_bridge.py",
        ROOT / "score_snapshot.py",
        ROOT / "candidate_sha256.json",
        ROOT / "input/SkylineSwitchyard-project.zip",
        ROOT / "candidate/project/default.project.json",
        ROOT / "candidate/SkylineSwitchyard.rbxlx",
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
    from preflight import verify_inputs
    verify_inputs()
    print("SELF-TEST PASS (evaluator files and input integrity; not a gameplay result)", flush=True)
    print("Python:", sys.executable, flush=True)
    print("Evaluator root:", ROOT, flush=True)
    count = sum(len(d.get("checks", [])) for d in rules["dimensions"].values())
    print(f"Automatic checks: {count}; weight: 90", flush=True)
    return 0


def hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(output: Path, fresh: bool = False) -> Path:
    import xml.etree.ElementTree as ET
    document = ET.parse(ROOT / "candidate/SkylineSwitchyard.rbxlx")
    def child(parent, cls, name):
        for item in parent.findall("Item"):
            if item.get("class") == cls and item.findtext("Properties/string[@name='Name']") == name:
                return item
        import uuid
        item=ET.SubElement(parent,"Item",{"class":cls,"referent":"RBX"+uuid.uuid4().hex.upper()})
        props=ET.SubElement(item,"Properties")
        ET.SubElement(props,"string",{"name":"Name"}).text=name
        return item
    def script(parent, cls, path):
        item=child(parent,cls,"SkylinePrivateQA")
        ET.SubElement(item.find("Properties"),"ProtectedString",{"name":"Source"}).text=path.read_text(encoding="utf-8")
    dm=document.getroot()
    script(child(dm,"ServerScriptService","ServerScriptService"),"Script",ROOT/"runtime/observer.server.luau")
    sp=child(child(dm,"StarterPlayer","StarterPlayer"),"StarterPlayerScripts","StarterPlayerScripts")
    script(sp,"LocalScript",ROOT/"runtime/trajectory.client.luau")
    if fresh:
        marker=child(child(dm,"ReplicatedStorage","ReplicatedStorage"),"BoolValue","SkylineSwitchyardFreshProbe")
        ET.SubElement(marker.find("Properties"),"bool",{"name":"Value"}).text="true"
    place=output/"SkylineFullPackageQA.rbxlx"
    document.write(place,encoding="utf-8",xml_declaration=True)
    return place



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


def studio_environment():
    """Inherit the operator-configured network environment for Studio."""
    return os.environ.copy()


def launch(place: Path):
    before = {window["hwnd"] for window in studio_windows()}
    launched_at = time.time()
    process = subprocess.Popen([str(find_studio()), "-task", "EditFile", "-localPlaceFile", str(place)], env=studio_environment())
    OWNED_PROCESSES[str(place.resolve())] = process
    chosen = choose_window(before, place.stem, 90)
    from local_bridge_support import USER32
    USER32.ShowWindow(chosen["hwnd"], 3)  # Maximize the owned QA window.
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
    if packet.get("kind") in {"pointer_home", "pointer_move", "mouse_click"}:
        from mouse_bridge import pointer_home, pointer_move, mouse_click
        if foreground_window().get("pid") != window.get("pid"):
            window = focus_live_studio(place.stem, 20)
        if packet["kind"] == "pointer_home":
            pointer_home(window)
        elif packet["kind"] == "pointer_move":
            pointer_move(window, packet["dx"], packet["dy"])
        else:
            mouse_click(window)
    elif packet.get("kind") == "camera":
        window = focus_live_studio(place.stem, 20)
        move_cursor_to_window_center(window)
        mouse_drag(int(packet["dx"]), int(packet["dy"]), 0.18)
    elif packet.get("kind") == "input":
        current = foreground_window()
        if current.get("pid") != window.get("pid"):
            window = focus_live_studio(place.stem, 20)
        send_key(VK[packet["key"]], packet["down"])
    elif packet.get("kind") == "check":
        checks[packet["id"]] = packet
        print(f'[{packet["id"]}] {packet["status"]}: {packet["detail"]}', flush=True)
    elif packet.get("kind") in {"error", "segment_error"}:
        print("Evaluator diagnostic:", packet.get("detail", ""), flush=True)
    return window


def collect(place, window, log, events, checks, timeout):
    offsets = {log: 0}
    start_event = len(events)
    chunks = {}
    deadline = time.time() + timeout
    finished = False
    incomplete = False
    started = time.monotonic()
    last_event = started
    last_progress = started
    ready = False
    while time.time() < deadline and not finished:
        prior_count = len(events)
        lines, offsets = read_new_log_lines([log], offsets)
        for line in lines:
            window = consume(line, events, checks, chunks, window, place)
        now = time.monotonic()
        if len(events) > prior_count:
            if any(e.get("kind") != "heartbeat" for e in events[prior_count:]):
                last_event = now
            for event in events[prior_count:]:
                if event.get("kind") == "ready":
                    ready = True
                    print("The client observer is ready.", flush=True)
            with (place.parent / "events.live.jsonl").open("a", encoding="utf-8") as stream:
                for event in events[prior_count:]:
                    stream.write(json.dumps(event, ensure_ascii=False) + "\n")
        if len(events) > prior_count and any(e.get("kind") == "check" for e in events[prior_count:]):
            # Preserve partial scoring even if Studio or the console is closed.
            from score_snapshot import write_partial
            write_partial(place.parent, checks)
        if now-last_progress >= 10:
            print(f"Progress: elapsed {int(now-started)} seconds; received {len(events)-start_event} events;{len(checks)} checks.", flush=True)
            last_progress = now
        if not ready and now-started >= 60:
            raise RuntimeError("Play startup timed out: no client ready within 60 seconds. No gameplay was scored. Inspect the Studio log; this does not establish a game failure.")
        if ready and now-last_event >= 45:
            raise RuntimeError("Evaluation stalled: no new event for 45 seconds. Live logs and existing observations were preserved.")
        for event in events[prior_count:]:
            if event.get("kind") == "done":
                finished = True
                incomplete = bool(event.get("incomplete"))
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
    if any(item.get("pid") == window.get("pid") for item in studio_windows()):
        process = OWNED_PROCESSES.get(str(place.resolve()))
        if process is None or process.pid != window.get("pid"):
            raise RuntimeError("Studio did not close and process ownership is unknown. The window was preserved.")
        if process.poll() is None:
            print("The temporary QA window did not close, possibly awaiting save. Ending the dedicated evaluator-owned process; source game files are unchanged.", flush=True)
            process.terminate()
            process.wait(timeout=15)


def wait_for_studio_closed(timeout=180):
    deadline = time.monotonic() + timeout
    previous = None
    next_notice = 0
    while True:
        windows = studio_windows()
        if not windows:
            return
        now = time.monotonic()
        summary = tuple((w.get("pid"), w.get("title", "")) for w in windows)
        if summary != previous or now >= next_notice:
            print("Waiting before launch: close these Studio windows. Evaluation resumes automatically afterward.", flush=True)
            for pid, title in summary:
                print(f"  PID {pid}: {title or '(untitled window)'}", flush=True)
            print(f"Remaining wait {max(0, int(deadline-now))} seconds; Ctrl+C cancels.", flush=True)
            previous = summary
            next_notice = now + 10
        if now >= deadline:
            raise RuntimeError("Prelaunch wait timed out with visible Studio windows. No evaluation or game score was produced.")
        time.sleep(0.5)


def main() -> int:
    from preflight import preflight
    if not preflight():
        return 2
    evidence = ROOT / "evidence" / datetime.now(timezone(timedelta(hours=8))).strftime("formal_%Y%m%d_%H%M%S")
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
        wait_for_studio_closed()
        print("[1/4] Building and launching the QA project...", flush=True)
        place = build(evidence)
        window, log = launch(place)
        logs.append(("studio_dynamic.log", log))
        process_ids.append(window.get("pid"))
        print("[2/4] Running 23 tests through real HUD clicks and keyboard input; leave input devices idle...", flush=True)
        finished, incomplete, window = collect(place, window, log, events, checks, 1200)
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
        finished, incomplete, window = collect(place, window, log, events, checks, 90)
        completed = finished and not incomplete
        if not completed:
            raise RuntimeError("The new-process observer did not finish")
        print("[4/4] Evaluation finished; writing evidence...", flush=True)
    except (Exception, KeyboardInterrupt) as exc:
        error = str(exc) or "Evaluation canceled"
        events.append({"kind": "runner_error", "error": error})
        traceback.print_exc()
    finally:
        if window is not None:
            for key in ("W", "A", "S", "D", "E", "R", "B", "C", "1", "2", "3", "SPACE", "ALT", "SHIFT"):
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
            "completed": completed,
            "assessment_complete": completed and not unresolved,
            "runner_error": error,
            "process_ids": process_ids,
            "automatic_score": automatic_total if completed and not unresolved else None,
            "confirmed_automatic_score": automatic_total if checks else None,
            "evaluation_status": "NOT_EVALUATED" if not checks else ("INCOMPLETE" if unresolved or not completed else "COMPLETE"),
            "automatic_score_maximum": rules["automatic_score_maximum"],
            "manual_visual_score_maximum": rules["manual_visual_score_maximum"],
            "dimensions": dimensions,
            "unresolved_checks": unresolved,
            "checks": checks,
            "candidate_hashes": {
                str(path.relative_to(ROOT / "candidate")): hash_file(path)
                for path in (ROOT / "candidate").rglob("*") if path.is_file()
            },
            "evaluator_revision": "skyline-switchyard-fullpackage-20261026-v1",
            "submission_kind": "USER_SUPPLIED_FULL_PACKAGE_20261026",
            "input_policy": {"real_hud_clicks": True, "real_keyboard": True,
                             "qa_candidate_remote_calls": 0, "qa_character_teleports": 0},
            "note": "Automatic score is out of 90. D6 visual quality is a separate 10-point manual review and is never inferred from runtime structure checks.",
        }
        (evidence / "score.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Evidence directory: {evidence}", flush=True)
        if checks:
            print(f"Confirmed-check subtotal: {automatic_total}/90; Unverified checks: {len(unresolved)}; Visual evidence review: Pending /10", flush=True)
            if unresolved or not completed:
                print("The full flow is unverified. There is no final score; automatic_score is null.", flush=True)
        else:
            print("No checks completed. Status is NOT_EVALUATED; no game score is available.", flush=True)
        if window and place and completed:
            print("The reopened window remains available for inspection. Stop Play and close Studio afterward.", flush=True)
    return 0 if completed and not unresolved else 1


if __name__ == "__main__":
    if "--preflight-only" in sys.argv[1:]:
        from preflight import preflight
        raise SystemExit(0 if preflight() else 2)
    if "--self-test" in sys.argv[1:]:
        raise SystemExit(self_test())
    raise SystemExit(main())

