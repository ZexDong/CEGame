#!/usr/bin/env python3
"""Windows input and Roblox Studio helpers for the Tide Lock evaluator.

The program launches a private QA place, sends normal Windows keyboard/mouse
input to Roblox Studio, tails the passive observer output from Studio logs, and
produces machine-readable evidence. It does not call candidate remotes or alter
gameplay state.
"""

from __future__ import annotations

import ctypes
import json
import math
import os
import shutil
import subprocess
import sys
import time
import traceback
import re
from ctypes import wintypes
from datetime import datetime, timezone
from pathlib import Path

USER32 = ctypes.windll.user32
KERNEL32 = ctypes.windll.kernel32
INPUT_MOUSE = 0
INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
SW_RESTORE = 9
SW_SHOW = 5
ASFW_ANY = 0xFFFFFFFF
VK = {
    "B": 0x42, "C": 0x43, "1": 0x31, "2": 0x32, "3": 0x33,
    "W": 0x57,
    "A": 0x41,
    "S": 0x53,
    "D": 0x44,
    "E": 0x45,
    "R": 0x52,
    "Z": 0x5A,
    "SPACE": 0x20,
    "F5": 0x74,
    "F6": 0x75,
    "F4": 0x73,
    "SHIFT": 0x10,
    "ALT": 0x12,
    "TAB": 0x09,
    "ESC": 0x1B,
}
EVIDENCE_PREFIX = "SIGNAL_CIRCUIT_EVIDENCE "
LAST_OUTPUT: Path | None = None

# ctypes otherwise assumes 32-bit integer arguments. HWND is pointer-sized, so
# omitting these prototypes can truncate valid 64-bit window handles and cause
# intermittent WinError 1400.
USER32.IsWindow.argtypes = [wintypes.HWND]
USER32.IsWindow.restype = wintypes.BOOL
USER32.IsWindowVisible.argtypes = [wintypes.HWND]
USER32.IsWindowVisible.restype = wintypes.BOOL
USER32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
USER32.ShowWindow.restype = wintypes.BOOL
USER32.BringWindowToTop.argtypes = [wintypes.HWND]
USER32.BringWindowToTop.restype = wintypes.BOOL
USER32.SetForegroundWindow.argtypes = [wintypes.HWND]
USER32.SetForegroundWindow.restype = wintypes.BOOL
USER32.GetForegroundWindow.restype = wintypes.HWND
USER32.SetActiveWindow.argtypes = [wintypes.HWND]
USER32.SetActiveWindow.restype = wintypes.HWND
USER32.SetFocus.argtypes = [wintypes.HWND]
USER32.SetFocus.restype = wintypes.HWND
USER32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
USER32.GetWindowRect.restype = wintypes.BOOL
USER32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
USER32.GetWindowTextLengthW.restype = ctypes.c_int
USER32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
USER32.GetWindowTextW.restype = ctypes.c_int
USER32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
USER32.GetWindowThreadProcessId.restype = wintypes.DWORD
USER32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
USER32.AttachThreadInput.restype = wintypes.BOOL
USER32.AllowSetForegroundWindow.argtypes = [wintypes.DWORD]
USER32.AllowSetForegroundWindow.restype = wintypes.BOOL
KERNEL32.GetCurrentThreadId.restype = wintypes.DWORD
KERNEL32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
KERNEL32.OpenProcess.restype = wintypes.HANDLE
KERNEL32.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.LPWSTR,
    ctypes.POINTER(wintypes.DWORD),
]
KERNEL32.QueryFullProcessImageNameW.restype = wintypes.BOOL
KERNEL32.CloseHandle.argtypes = [wintypes.HANDLE]
KERNEL32.CloseHandle.restype = wintypes.BOOL


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("union", INPUT_UNION)]


# INPUT is declared above, so install its exact SendInput signature now.
USER32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
USER32.SendInput.restype = wintypes.UINT


def send_key(vk: int, is_down: bool) -> None:
    event = INPUT(type=INPUT_KEYBOARD)
    event.union.ki = KEYBDINPUT(vk, 0, 0 if is_down else KEYEVENTF_KEYUP, 0, None)
    sent = USER32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT))
    if sent != 1:
        raise ctypes.WinError()


def hold(name: str, duration: float) -> None:
    send_key(VK[name], True)
    time.sleep(duration)
    send_key(VK[name], False)
    time.sleep(0.15)


def tap(name: str, duration: float = 0.12) -> None:
    hold(name, duration)


def alt_tab() -> None:
    send_key(VK["ALT"], True)
    time.sleep(0.08)
    send_key(VK["TAB"], True)
    time.sleep(0.10)
    send_key(VK["TAB"], False)
    send_key(VK["ALT"], False)
    time.sleep(0.6)


def mouse_drag(dx: int, dy: int, duration: float = 0.35) -> None:
    down = INPUT(type=INPUT_MOUSE)
    down.union.mi = MOUSEINPUT(0, 0, 0, MOUSEEVENTF_RIGHTDOWN, 0, None)
    if USER32.SendInput(1, ctypes.byref(down), ctypes.sizeof(INPUT)) != 1:
        raise ctypes.WinError()
    steps = 10
    for index in range(steps):
        step_dx = dx // steps + (1 if index < abs(dx) % steps and dx > 0 else 0)
        step_dy = dy // steps + (1 if index < abs(dy) % steps and dy > 0 else 0)
        move = INPUT(type=INPUT_MOUSE)
        move.union.mi = MOUSEINPUT(step_dx, step_dy, 0, MOUSEEVENTF_MOVE, 0, None)
        USER32.SendInput(1, ctypes.byref(move), ctypes.sizeof(INPUT))
        time.sleep(duration / steps)
    up = INPUT(type=INPUT_MOUSE)
    up.union.mi = MOUSEINPUT(0, 0, 0, MOUSEEVENTF_RIGHTUP, 0, None)
    USER32.SendInput(1, ctypes.byref(up), ctypes.sizeof(INPUT))
    time.sleep(0.2)


def move_mouse_relative(dx: int, dy: int) -> None:
    event = INPUT(type=INPUT_MOUSE)
    event.union.mi = MOUSEINPUT(int(dx), int(dy), 0, MOUSEEVENTF_MOVE, 0, None)
    if USER32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT)) != 1:
        raise ctypes.WinError()
    time.sleep(0.12)


def click_left() -> None:
    down = INPUT(type=INPUT_MOUSE)
    down.union.mi = MOUSEINPUT(0, 0, 0, MOUSEEVENTF_LEFTDOWN, 0, None)
    up = INPUT(type=INPUT_MOUSE)
    up.union.mi = MOUSEINPUT(0, 0, 0, MOUSEEVENTF_LEFTUP, 0, None)
    if USER32.SendInput(1, ctypes.byref(down), ctypes.sizeof(INPUT)) != 1:
        raise ctypes.WinError()
    if USER32.SendInput(1, ctypes.byref(up), ctypes.sizeof(INPUT)) != 1:
        raise ctypes.WinError()
    time.sleep(0.18)


def move_cursor_to_window_center(window: dict) -> None:
    """Place the pointer inside the active 3D viewport before camera drag."""
    hwnd = window["hwnd"]
    if not USER32.IsWindow(hwnd):
        raise RuntimeError("Studio window changed before mouse input.")
    rect = wintypes.RECT()
    if not USER32.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise ctypes.WinError()
    # The middle of the Studio top-level window is safely inside the 3D view
    # for the default layout, unlike the pointer position left by the launcher.
    x = rect.left + (rect.right - rect.left) // 2
    y = rect.top + (rect.bottom - rect.top) * 55 // 100
    if not USER32.SetCursorPos(x, y):
        raise ctypes.WinError()
    time.sleep(0.25)


def process_path(pid: int) -> str:
    handle = KERNEL32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return ""
    try:
        size = wintypes.DWORD(32768)
        buffer = ctypes.create_unicode_buffer(size.value)
        if KERNEL32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            return buffer.value
        return ""
    finally:
        KERNEL32.CloseHandle(handle)


def studio_windows() -> list[dict]:
    result: list[dict] = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    def callback(hwnd, _):
        if not USER32.IsWindowVisible(hwnd):
            return True
        length = USER32.GetWindowTextLengthW(hwnd)
        title = ctypes.create_unicode_buffer(length + 1)
        USER32.GetWindowTextW(hwnd, title, length + 1)
        pid = wintypes.DWORD()
        USER32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        path = process_path(pid.value)
        if path.lower().endswith("robloxstudiobeta.exe"):
            result.append({"hwnd": int(hwnd), "pid": int(pid.value), "title": title.value, "path": path})
        return True

    USER32.EnumWindows(callback, 0)
    return result


def find_studio() -> Path:
    local = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "Versions"
    candidates = list(local.glob("version-*/RobloxStudioBeta.exe"))
    if not candidates:
        raise RuntimeError("RobloxStudioBeta.exe was not found. Install or update Roblox Studio.")

    # A Studio self-update can create the new version while leaving the old
    # executable newer by directory metadata or still running as an updater.
    # Select the executable's numeric ProductVersion/FileVersion, not mtime.
    def version_key(item: Path) -> tuple[int, ...]:
        try:
            command = [
                str(Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"),
                "-NoProfile", "-Command",
                f"(Get-Item -LiteralPath '{str(item).replace(chr(39), chr(39) * 2)}').VersionInfo.FileVersion",
            ]
            value = subprocess.run(command, capture_output=True, text=True, timeout=8, check=True).stdout
            numbers = tuple(int(part) for part in re.findall(r"\d+", value))
            if numbers:
                return numbers
        except Exception:
            pass
        return (0, int(item.stat().st_mtime))

    return max(candidates, key=version_key)


def click_title_bar(hwnd: int) -> None:
    rect = wintypes.RECT()
    if not USER32.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise ctypes.WinError()
    x = rect.left + max(120, min(480, (rect.right - rect.left) // 3))
    y = rect.top + 15
    previous = wintypes.POINT()
    USER32.GetCursorPos(ctypes.byref(previous))
    USER32.SetCursorPos(x, y)
    down = INPUT(type=INPUT_MOUSE)
    down.union.mi = MOUSEINPUT(0, 0, 0, 0x0002, 0, None)
    up = INPUT(type=INPUT_MOUSE)
    up.union.mi = MOUSEINPUT(0, 0, 0, 0x0004, 0, None)
    USER32.SendInput(1, ctypes.byref(down), ctypes.sizeof(INPUT))
    USER32.SendInput(1, ctypes.byref(up), ctypes.sizeof(INPUT))
    time.sleep(0.35)
    USER32.SetCursorPos(previous.x, previous.y)


def focus(window: dict) -> None:
    hwnd = window["hwnd"]
    if not USER32.IsWindow(hwnd):
        raise RuntimeError("The Roblox Studio window changed during loading; locate it again.")
    USER32.ShowWindow(hwnd, SW_RESTORE)
    USER32.ShowWindow(hwnd, SW_SHOW)
    USER32.AllowSetForegroundWindow(ASFW_ANY)
    USER32.BringWindowToTop(hwnd)
    USER32.SetForegroundWindow(hwnd)
    time.sleep(0.35)
    if USER32.GetForegroundWindow() == hwnd:
        return

    current_thread = KERNEL32.GetCurrentThreadId()
    target_thread = USER32.GetWindowThreadProcessId(hwnd, None)
    foreground = USER32.GetForegroundWindow()
    foreground_thread = USER32.GetWindowThreadProcessId(foreground, None) if foreground else 0
    attached_target = bool(target_thread and USER32.AttachThreadInput(current_thread, target_thread, True))
    attached_foreground = bool(
        foreground_thread
        and foreground_thread != target_thread
        and USER32.AttachThreadInput(current_thread, foreground_thread, True)
    )
    try:
        USER32.BringWindowToTop(hwnd)
        USER32.SetActiveWindow(hwnd)
        USER32.SetFocus(hwnd)
        USER32.SetForegroundWindow(hwnd)
    finally:
        if attached_foreground:
            USER32.AttachThreadInput(current_thread, foreground_thread, False)
        if attached_target:
            USER32.AttachThreadInput(current_thread, target_thread, False)
    time.sleep(0.35)
    if USER32.GetForegroundWindow() == hwnd:
        return

    click_title_bar(hwnd)
    if USER32.GetForegroundWindow() == hwnd:
        return

    # Windows deliberately restricts background applications from stealing
    # focus. Alt+Tab is an ordinary user input and is therefore the most
    # faithful fallback for this evaluator. Cycle only through the bounded set
    # of currently visible top-level windows.
    visible_count = 0

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    def count_visible(candidate, _):
        nonlocal visible_count
        if USER32.IsWindowVisible(candidate) and USER32.GetWindowTextLengthW(candidate) > 0:
            visible_count += 1
        return True

    USER32.EnumWindows(count_visible, 0)
    for _ in range(max(3, min(visible_count + 2, 20))):
        alt_tab()
        if USER32.GetForegroundWindow() == hwnd:
            return

    active = USER32.GetForegroundWindow()
    raise RuntimeError(
        f"Cannot focus Roblox Studio automatically (target window={hwnd}, current foreground={active})."
        "Windows rejected SetForegroundWindow and Alt+Tab."
    )


def find_session_log(log_dir: Path, place_stem: str, launched_at: float, timeout: float) -> Path:
    deadline = time.time() + timeout
    while time.time() < deadline:
        candidates = []
        for path in log_dir.glob("*Studio*_last.log"):
            if not path.is_file() or path.stat().st_ctime < launched_at - 3:
                continue
            try:
                with path.open("r", encoding="utf-8", errors="replace") as handle:
                    if place_stem.lower() in handle.read().lower():
                        candidates.append(path)
            except OSError:
                continue
        if candidates:
            return max(candidates, key=lambda item: item.stat().st_ctime)
        time.sleep(0.5)
    raise RuntimeError("No Studio log was found for the newly opened QA project.")


def read_new_log_lines(log_paths: list[Path], offsets: dict[Path, int]) -> tuple[list[str], dict[Path, int]]:
    lines: list[str] = []
    for path in log_paths:
        if not path.is_file():
            continue
        start = offsets.get(path, 0)
        size = path.stat().st_size
        if size < start:
            start = 0
        if size > start:
            # Tail byte offsets in binary mode. Text-mode offsets are opaque
            # cookies and become unreliable when UTF-8 HUD text is appended;
            # that previously duplicated a few input commands and skipped some
            # assertion lines. Leave an incomplete final line for the next poll.
            with path.open("rb") as handle:
                handle.seek(start)
                payload = handle.read()
            newline = payload.rfind(b"\n")
            if newline >= 0:
                complete = payload[: newline + 1]
                lines.extend(complete.decode("utf-8", errors="replace").splitlines(keepends=True))
                offsets[path] = start + newline + 1
            else:
                offsets[path] = start
        else:
            offsets.setdefault(path, start)
    return lines, offsets


def parse_records(lines: list[str]) -> list[dict]:
    records = []
    for line in lines:
        marker = line.find(EVIDENCE_PREFIX)
        if marker < 0:
            continue
        payload = line[marker + len(EVIDENCE_PREFIX) :].strip()
        try:
            value = json.loads(payload)
            if isinstance(value, dict):
                records.append(value)
        except json.JSONDecodeError:
            continue
    return records


def wait_for_record(log_paths: list[Path], offsets: dict[Path, int], records: list[dict], kind: str, timeout: float) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        new_lines, offsets = read_new_log_lines(log_paths, offsets)
        records.extend(parse_records(new_lines))
        if any(record.get("kind") == kind for record in records):
            return
        time.sleep(0.25)
    raise RuntimeError(f"Timeout waiting for observer event {kind} .")


def collect_for(log_paths: list[Path], offsets: dict[Path, int], records: list[dict], seconds: float) -> None:
    deadline = time.time() + seconds
    while time.time() < deadline:
        new_lines, offsets = read_new_log_lines(log_paths, offsets)
        records.extend(parse_records(new_lines))
        time.sleep(0.2)


def distance(left: dict, right: dict) -> float:
    return math.sqrt(sum((float(right[key]) - float(left[key])) ** 2 for key in ("x", "y", "z")))


def choose_window(before: set[int], place_stem: str, timeout: float) -> dict:
    deadline = time.time() + timeout
    last: list[dict] = []
    stable_hwnd = None
    stable_since = 0.0
    while time.time() < deadline:
        last = studio_windows()
        new = [item for item in last if item["hwnd"] not in before]
        exact_new = [item for item in new if place_stem.lower() in item["title"].lower()]
        exact_any = [item for item in last if place_stem.lower() in item["title"].lower()]
        candidates = exact_new or exact_any or new
        if candidates:
            candidate = candidates[-1]
            if candidate["hwnd"] != stable_hwnd:
                stable_hwnd = candidate["hwnd"]
                stable_since = time.time()
            elif time.time() - stable_since >= 1.5 and USER32.IsWindow(stable_hwnd):
                return candidate
        time.sleep(0.25)
    raise RuntimeError(f"No Studio window was found for {place_stem} ; currently visible Studio window count:{len(last)}.")


def refresh_window(window: dict, place_stem: str, timeout: float = 15) -> dict:
    if USER32.IsWindow(window["hwnd"]):
        return window
    return choose_window(set(), place_stem, timeout)


def foreground_window() -> dict:
    """Read the input-owning window live; never rely on a cached HWND."""
    hwnd = USER32.GetForegroundWindow()
    if not hwnd or not USER32.IsWindow(hwnd):
        return {"hwnd": 0, "pid": 0, "title": "", "path": ""}
    length = USER32.GetWindowTextLengthW(hwnd)
    title = ctypes.create_unicode_buffer(max(1, length + 1))
    USER32.GetWindowTextW(hwnd, title, len(title))
    pid = wintypes.DWORD()
    USER32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return {
        "hwnd": int(hwnd),
        "pid": int(pid.value),
        "title": title.value,
        "path": process_path(pid.value),
    }


def is_studio_foreground(window: dict, place_stem: str) -> bool:
    return (
        window.get("path", "").lower().endswith("robloxstudiobeta.exe")
        and place_stem.lower() in window.get("title", "").lower()
    )


def is_any_studio_window(window: dict) -> bool:
    return window.get("path", "").lower().endswith("robloxstudiobeta.exe")


def focus_live_studio(place_stem: str, timeout: float = 30) -> dict:
    """Find a fresh Studio HWND on every attempt, then verify it owns input."""
    deadline = time.time() + timeout
    last = foreground_window()
    while time.time() < deadline:
        last = foreground_window()
        if is_studio_foreground(last, place_stem):
            time.sleep(0.8)
            verified = foreground_window()
            if is_studio_foreground(verified, place_stem):
                return verified

        # Never reuse a handle captured during loading. Roblox can replace its
        # top-level window at any moment, so enumerate again on every pass and
        # validate immediately before each operation.
        candidates = [
            item
            for item in studio_windows()
            if place_stem.lower() in item.get("title", "").lower()
        ]
        # Startup notices (including lighting migration and read-only alerts)
        # are separate Studio-owned foreground windows. Only dismiss one when
        # the uniquely named place window is already present, so Escape cannot
        # affect another application or another evaluation run.
        if candidates and is_any_studio_window(last) and not is_studio_foreground(last, place_stem):
            tap("ESC", 0.08)
            time.sleep(0.5)
        for candidate in candidates:
            hwnd = candidate["hwnd"]
            if not USER32.IsWindow(hwnd):
                continue
            USER32.ShowWindow(hwnd, SW_RESTORE)
            if not USER32.IsWindow(hwnd):
                continue
            USER32.AllowSetForegroundWindow(ASFW_ANY)
            USER32.BringWindowToTop(hwnd)
            USER32.SetForegroundWindow(hwnd)
            time.sleep(0.4)
            verified = foreground_window()
            if is_studio_foreground(verified, place_stem):
                return verified

            # A synthetic Alt press grants this process foreground activation
            # rights without cycling unpredictably through unrelated windows.
            send_key(VK["ALT"], True)
            send_key(VK["ALT"], False)
            if USER32.IsWindow(hwnd):
                USER32.SetForegroundWindow(hwnd)
            time.sleep(0.4)
            verified = foreground_window()
            if is_studio_foreground(verified, place_stem):
                return verified
        time.sleep(0.25)
    raise RuntimeError(
        "Could not switch input to Roblox Studio. "
        f"Last foreground process: {last.get('path') or 'unknown'}; "
        f"title: {last.get('title')!r}."
    )


def main() -> int:
    global LAST_OUTPUT
    task_root = Path(__file__).resolve().parents[1]
    source_place = task_root / "candidates" / "candidate_001" / "qa" / "CrystalRelayCandidate_QA.rbxlx"
    if not source_place.exists():
        raise RuntimeError(f"QA project does not exist:{source_place}")

    run_id = datetime.now().strftime("local_smoke_%Y%m%d_%H%M%S")
    output = task_root / "candidates" / "candidate_001" / "evidence" / run_id
    output.mkdir(parents=True, exist_ok=False)
    LAST_OUTPUT = output
    # A previously open Studio instance locks a local place and makes the next
    # instance read-only. Use a unique, auditable copy for every evaluation.
    place = output / f"CrystalRelayCandidate_QA_{run_id}.rbxlx"
    shutil.copy2(source_place, place)
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    actions: list[dict] = []
    started = datetime.now(timezone.utc)

    print("[1/5] Opening the Roblox Studio QA project......", flush=True)
    studio = find_studio()
    before = {item["hwnd"] for item in studio_windows()}
    launched_at = time.time()
    subprocess.Popen(
        [str(studio), "-task", "EditFile", "-localPlaceFile", str(place)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    window = choose_window(before, place.stem, 60)
    session_log = find_session_log(log_dir, place.stem, launched_at, 30)
    log_paths = [session_log]
    offsets = {session_log: session_log.stat().st_size}
    # Do not touch the HWND returned while Studio was loading. Roblox may have
    # replaced it already. Discover and verify the live foreground process.
    window = focus_live_studio(place.stem, 30)

    print("[2/5] Entering Play with F5; leave the keyboard and mouse idle......", flush=True)
    tap("F5")
    actions.append({"type": "tap_key", "key": "F5"})
    wait_for_record(log_paths, offsets, records, "observer_ready", 40)
    wait_for_record(log_paths, offsets, records, "sample", 30)
    collect_for(log_paths, offsets, records, 0.5)

    baseline_samples = [item for item in records if item.get("kind") == "sample"]
    if not baseline_samples:
        raise RuntimeError("The observer started but produced no character-state samples.")
    baseline = baseline_samples[-1]

    print("[3/5] Sending W, Space, and mouse-look input......", flush=True)
    window = focus_live_studio(place.stem, 20)
    hold("W", 0.8)
    actions.append({"type": "hold_key", "key": "W", "duration_s": 0.8})
    collect_for(log_paths, offsets, records, 0.7)
    after_w_index = len(records)
    tap("SPACE", 0.10)
    actions.append({"type": "tap_key", "key": "Space", "duration_s": 0.10})
    collect_for(log_paths, offsets, records, 0.8)
    # Reconfirm the live Studio window and put the pointer inside its 3D
    # viewport. A right-drag over Explorer or a Studio dock does not rotate the
    # Roblox camera even though the mouse events themselves are valid.
    window = focus_live_studio(place.stem, 20)
    move_cursor_to_window_center(window)
    collect_for(log_paths, offsets, records, 0.4)
    before_mouse_samples = [item for item in records if item.get("kind") == "sample"]
    before_mouse = before_mouse_samples[-1]
    mouse_drag(140, -15)
    actions.append({"type": "mouse_drag", "dx": 140, "dy": -15})
    collect_for(log_paths, offsets, records, 0.8)

    samples = [item for item in records if item.get("kind") == "sample"]
    input_began = [item for item in records if item.get("kind") == "input_began"]
    moved = max((distance(baseline["position"], item["position"]) for item in samples), default=0.0)
    jumped = any(
        float(item.get("velocity", {}).get("y", 0)) > 2 or item.get("floor_material") == "Air"
        for item in records[after_w_index:]
        if item.get("kind") == "sample"
    )
    camera_delta = max(
        (distance(before_mouse["camera_look"], item["camera_look"]) for item in samples), default=0.0
    )
    assertions = {
        "observer_ready": any(item.get("kind") == "observer_ready" for item in records),
        "virtual_w_received": any(item.get("key") == "W" for item in input_began),
        "virtual_space_received": any(item.get("key") == "Space" for item in input_began),
        "w_moved_character": moved > 1.0,
        "space_produced_jump": jumped,
        "mouse_changed_camera": camera_delta > 0.02,
    }

    print("[4/5] Stopping Play and organizing evidence......", flush=True)
    window = focus_live_studio(place.stem, 20)
    tap("F6")
    actions.append({"type": "tap_key", "key": "F6"})
    collect_for(log_paths, offsets, records, 1.0)

    report = {
        "schema_version": "1.0",
        "run_id": run_id,
        "started_at_utc": started.isoformat(),
        "finished_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_place": str(source_place),
        "runtime_place": str(place),
        "studio": str(studio),
        "studio_pid": window["pid"],
        "studio_log": str(session_log),
        "input_backend": "Windows SendInput",
        "policy": {
            "only_virtual_input": True,
            "teleports": 0,
            "direct_business_calls": 0,
            "direct_state_mutations": 0,
        },
        "actions": actions,
        "measurements": {
            "maximum_position_delta_studs": moved,
            "camera_look_delta": camera_delta,
            "observer_record_count": len(records),
        },
        "assertions": assertions,
        "passed": all(assertions.values()),
        "screenshots": [],
    }
    (output / "runtime_records.jsonl").write_text(
        "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in records), encoding="utf-8"
    )
    (output / "smoke_evidence.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    print("[5/5] Local evaluation smoke check:" + ("PASSED" if report["passed"] else "FAILED"), flush=True)
    for name, passed in assertions.items():
        print(f"  {'PASS' if passed else 'FAIL'}  {name}", flush=True)
    print(f"Evidence directory:{output}", flush=True)
    return 0 if report["passed"] else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        diagnostic = traceback.format_exc()
        if LAST_OUTPUT is not None:
            (LAST_OUTPUT / "bridge_error.txt").write_text(diagnostic, encoding="utf-8")
        print(f"\nLocal bridge failed:{error}", file=sys.stderr, flush=True)
        if LAST_OUTPUT is not None:
            print(f"Diagnostic file:{LAST_OUTPUT / 'bridge_error.txt'}", file=sys.stderr, flush=True)
        print("Keep this window open and retain the final diagnostic lines. Do not include credentials.", file=sys.stderr, flush=True)
        raise SystemExit(1)
