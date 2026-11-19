"""Deterministic window capture and OCR for dynamic D5 evidence (no VLM)."""

from __future__ import annotations

import ctypes
import re
import subprocess
from pathlib import Path


class EvidenceInfrastructureError(RuntimeError):
    pass


def window_id_for_pid(pid: int) -> int:
    core_graphics = ctypes.CDLL(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    )
    core_foundation = ctypes.CDLL(
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )
    core_graphics.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
    core_graphics.CGWindowListCopyWindowInfo.restype = ctypes.c_void_p
    core_foundation.CFArrayGetCount.argtypes = [ctypes.c_void_p]
    core_foundation.CFArrayGetCount.restype = ctypes.c_long
    core_foundation.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
    core_foundation.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
    core_foundation.CFDictionaryGetValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    core_foundation.CFDictionaryGetValue.restype = ctypes.c_void_p
    core_foundation.CFNumberGetValue.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    core_foundation.CFNumberGetValue.restype = ctypes.c_bool
    core_foundation.CFRelease.argtypes = [ctypes.c_void_p]

    owner_key = ctypes.c_void_p.in_dll(core_graphics, "kCGWindowOwnerPID")
    number_key = ctypes.c_void_p.in_dll(core_graphics, "kCGWindowNumber")
    layer_key = ctypes.c_void_p.in_dll(core_graphics, "kCGWindowLayer")

    def integer(dictionary: int, key: ctypes.c_void_p) -> int | None:
        value = core_foundation.CFDictionaryGetValue(dictionary, key)
        if not value:
            return None
        result = ctypes.c_int()
        if not core_foundation.CFNumberGetValue(value, 9, ctypes.byref(result)):
            return None
        return result.value

    rows = core_graphics.CGWindowListCopyWindowInfo(1 | 16, 0)
    if not rows:
        raise EvidenceInfrastructureError("CoreGraphics returned no window list")
    try:
        for index in range(core_foundation.CFArrayGetCount(rows)):
            row = core_foundation.CFArrayGetValueAtIndex(rows, index)
            if integer(row, owner_key) != pid or integer(row, layer_key) != 0:
                continue
            number = integer(row, number_key)
            if number is not None:
                return number
    finally:
        core_foundation.CFRelease(rows)
    raise EvidenceInfrastructureError(f"no visible layer-zero window for pid {pid}")


def capture_window(pid: int, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    window_id = window_id_for_pid(pid)
    completed = subprocess.run(
        ["/usr/sbin/screencapture", "-x", "-l", str(window_id), str(destination)],
        text=True,
        capture_output=True,
    )
    if completed.returncode or not destination.is_file() or destination.stat().st_size == 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "empty capture"
        raise EvidenceInfrastructureError(f"window capture failed: {detail}")
    return destination


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", "", value).casefold()


def ocr_image(path: Path, languages: str = "eng+chi_sim") -> dict[str, object]:
    lines: list[str] = []
    seen: set[str] = set()
    variants = ((6, 0), (11, 0), (11, 1), (11, 2))
    for page_segmentation_mode, thresholding_method in variants:
        command = [
            "/opt/homebrew/bin/tesseract",
            str(path),
            "stdout",
            "-l",
            languages,
            "--psm",
            str(page_segmentation_mode),
            "--dpi",
            "300",
            "-c",
            f"thresholding_method={thresholding_method}",
        ]
        completed = subprocess.run(
            command,
            text=True,
            capture_output=True,
        )
        if completed.returncode:
            raise EvidenceInfrastructureError(f"OCR failed: {completed.stderr.strip()}")
        for raw_line in completed.stdout.splitlines():
            line = raw_line.strip()
            normalized_line = normalize_text(line)
            if line and normalized_line not in seen:
                seen.add(normalized_line)
                lines.append(line)
    return {
        "lines": lines,
        "normalized": normalize_text(" ".join(lines)),
        "languages": languages,
        "page_segmentation_modes": [6, 11],
        "dpi": 300,
        "thresholding_methods": [0, 1, 2],
    }


def contains_any(ocr_result: dict[str, object], alternatives: list[str]) -> bool:
    text = str(ocr_result["normalized"])
    return any(normalize_text(value) in text for value in alternatives)
