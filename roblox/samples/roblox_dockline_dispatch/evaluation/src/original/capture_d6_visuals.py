#!/usr/bin/env python3
"""Capture read-only candidate visuals for D6; never used by D1-D5."""

from __future__ import annotations

import ctypes
import hashlib
import json
import shutil
import time
from ctypes import wintypes
from datetime import datetime, timezone
from pathlib import Path

from PIL import ImageGrab

from local_bridge_support import focus_live_studio, hold, mouse_drag, move_cursor_to_window_center, tap
from local_complete_eval import close_studio, open_studio_place


USER32 = ctypes.windll.user32


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def capture(window: dict, path: Path) -> None:
    rect = wintypes.RECT()
    if not USER32.GetWindowRect(window["hwnd"], ctypes.byref(rect)):
        raise ctypes.WinError()
    image = ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom), all_screens=True)
    image.save(path)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    source = root / "candidate" / "original" / "DocklineDispatchCandidate.rbxlx"
    output = root / "visual_review"
    output.mkdir(parents=True, exist_ok=True)
    place = output / "DocklineDispatchCandidate_D6_Capture.rbxlx"
    shutil.copy2(source, place)
    window = None
    records = []
    try:
        window, _, _ = open_studio_place(place)
        window = focus_live_studio(place.stem, 30)
        tap("F5")
        time.sleep(12)
        window = focus_live_studio(place.stem, 30)
        first = output / "candidate_view_01_spawn.png"
        capture(window, first)
        records.append(first)

        move_cursor_to_window_center(window)
        mouse_drag(210, -20, 0.5)
        hold("W", 1.6)
        time.sleep(2)
        window = focus_live_studio(place.stem, 30)
        second = output / "candidate_view_02_floor.png"
        capture(window, second)
        records.append(second)

        move_cursor_to_window_center(window)
        mouse_drag(-330, 15, 0.6)
        hold("W", 1.2)
        time.sleep(2)
        window = focus_live_studio(place.stem, 30)
        third = output / "candidate_view_03_workstations.png"
        capture(window, third)
        records.append(third)
    finally:
        if window is not None:
            close_studio(place.stem, window)

    manifest = {
        "schema_version": "dockline-d6-capture-v1",
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "candidate_place_sha256": sha256(source),
        "capture_only": True,
        "used_for_d1_d5": False,
        "images": [
            {"file": str(path.relative_to(root)), "sha256": sha256(path)} for path in records
        ],
    }
    (output / "capture_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
