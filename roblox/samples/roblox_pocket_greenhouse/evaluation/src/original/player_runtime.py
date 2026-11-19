#!/usr/bin/env python3
"""Run checkpoint-script.json in Roblox Studio with real OS mouse input.

Windows only.  A temporary copy of the place receives a read-only logging
bridge.  Gameplay actions are sent via the Windows input path; no internal
gameplay function is called.  The original rbxlx is never modified.
"""

from __future__ import annotations

import argparse
import csv
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import re
import shutil
import socket
import statistics
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
import urllib.error
import urllib.request
from urllib.parse import urlparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    from PIL import ImageChops, ImageGrab, ImageStat
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Pillow is required: python -m pip install pillow") from exc

from evaluate import eval_assertion, load_json, validate_snapshot

# Keep GetWindowRect, ImageGrab and SendInput in the same physical-pixel
# coordinate system on 125%/150% multi-monitor Windows desktops.
try:
    ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
except (AttributeError, OSError):
    try:
        ctypes.windll.user32.SetProcessDPIAware()
    except (AttributeError, OSError):
        pass


PREFIX = "__PG_SNAPSHOT__"
BG = (20, 43, 38)
VK_F5 = 0x74
VK_SHIFT = 0x10
VK_CONTROL = 0x11
VK_MENU = 0x12
VK_RETURN = 0x0D
VK_ESCAPE = 0x1B
VK_O = 0x4F
VK_V = 0x56
MOUSE_LEFTDOWN = 0x0002
MOUSE_LEFTUP = 0x0004
MOUSE_RIGHTDOWN = 0x0008
MOUSE_RIGHTUP = 0x0010
MOUSE_MOVE = 0x0001
MOUSE_ABSOLUTE = 0x8000
MOUSE_VIRTUALDESK = 0x4000
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008
SM_XVIRTUALSCREEN = 76
SM_YVIRTUALSCREEN = 77
SM_CXVIRTUALSCREEN = 78
SM_CYVIRTUALSCREEN = 79
SW_RESTORE = 9
SW_SHOW = 5
SW_MINIMIZE = 6
SW_MAXIMIZE = 3
WM_CLOSE = 0x0010
ASFW_ANY = 0xFFFFFFFF
HWND_TOPMOST = -1
HWND_NOTOPMOST = -2
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_SHOWWINDOW = 0x0040


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG), ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD), ("dwExtraInfo", wintypes.WPARAM),
    ]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD), ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD),
        # ctypes.wintypes does not expose ULONG_PTR on every bundled Python.
        ("dwExtraInfo", ctypes.c_size_t),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _anonymous_ = ("u",)
    _fields_ = [("type", wintypes.DWORD), ("u", INPUT_UNION)]


# Use the exact pointer-sized Win32 signatures from the proven evaluators.
USER32 = ctypes.windll.user32
USER32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
USER32.SendInput.restype = wintypes.UINT
USER32.IsWindow.argtypes = [wintypes.HWND]
USER32.IsWindow.restype = wintypes.BOOL
USER32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
USER32.ShowWindow.restype = wintypes.BOOL
USER32.BringWindowToTop.argtypes = [wintypes.HWND]
USER32.BringWindowToTop.restype = wintypes.BOOL
USER32.SetForegroundWindow.argtypes = [wintypes.HWND]
USER32.SetForegroundWindow.restype = wintypes.BOOL
USER32.GetForegroundWindow.restype = wintypes.HWND
USER32.AllowSetForegroundWindow.argtypes = [wintypes.DWORD]
USER32.AllowSetForegroundWindow.restype = wintypes.BOOL
USER32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.UINT]
USER32.SetWindowPos.restype = wintypes.BOOL
USER32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
USER32.GetWindowRect.restype = wintypes.BOOL


def send_mouse_input(flags: int, dx: int = 0, dy: int = 0) -> None:
    event = INPUT(type=0, mi=MOUSEINPUT(dx, dy, 0, flags, 0, 0))
    sent = ctypes.windll.user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT))
    if sent != 1:
        raise ctypes.WinError()


def send_keyboard_input(vk: int, flags: int) -> None:
    """Inject a virtual keyboard event through the same SendInput path as clicks."""
    event = INPUT(type=1, ki=KEYBDINPUT(vk, 0, flags, 0, 0))
    sent = ctypes.windll.user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT))
    if sent != 1:
        raise ctypes.WinError()


def send_scancode_input(vk: int, key_up: bool = False) -> None:
    """Send a hardware-style scan code for Qt shortcuts that ignore VK input."""
    scan = USER32.MapVirtualKeyW(vk, 0)
    if not scan:
        raise RuntimeError(f"Windows could not map virtual key {vk:#x} to a scan code")
    flags = KEYEVENTF_SCANCODE | (KEYEVENTF_KEYUP if key_up else 0)
    event = INPUT(type=1, ki=KEYBDINPUT(0, scan, flags, 0, 0))
    sent = USER32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT))
    if sent != 1:
        raise ctypes.WinError()


def move_mouse_absolute(x: int, y: int) -> tuple[int, int]:
    user32 = ctypes.windll.user32
    px = int(round(x))
    py = int(round(y))
    left = user32.GetSystemMetrics(SM_XVIRTUALSCREEN)
    top = user32.GetSystemMetrics(SM_YVIRTUALSCREEN)
    width = user32.GetSystemMetrics(SM_CXVIRTUALSCREEN)
    height = user32.GetSystemMetrics(SM_CYVIRTUALSCREEN)
    if width <= 1 or height <= 1:
        raise RuntimeError("Windows virtual desktop metrics are invalid")
    # SendInput absolute coordinates use the full virtual desktop range. This
    # is intentionally an injected/virtual mouse move, not SetCursorPos.
    command_x, command_y = px, py
    actual = wintypes.POINT()
    for _ in range(6):
        norm_x = round((command_x - left) * 65535 / (width - 1))
        norm_y = round((command_y - top) * 65535 / (height - 1))
        send_mouse_input(MOUSE_MOVE | MOUSE_ABSOLUTE | MOUSE_VIRTUALDESK, norm_x, norm_y)
        time.sleep(0.08)
        if not user32.GetCursorPos(ctypes.byref(actual)):
            raise ctypes.WinError()
        error_x, error_y = px - actual.x, py - actual.y
        if abs(error_x) <= 3 and abs(error_y) <= 3:
            return actual.x, actual.y
        if actual.x and command_x:
            command_x = int(round(command_x * px / actual.x))
        else:
            command_x += error_x
        if actual.y and command_y:
            command_y = int(round(command_y * py / actual.y))
        else:
            command_y += error_y
    print(
        f"  DPI cursor correction residual: target=({px},{py}) actual=({actual.x},{actual.y})",
        flush=True,
    )
    return actual.x, actual.y


class SnapshotFeed:
    def __init__(self) -> None:
        self.latest: dict | None = None
        self.serial = 0
        self.error: str | None = None
        self.viewport_size: tuple[float, float] | None = None
        self.viewport_source: str | None = None
        self.engine_mouse: tuple[float, float] | None = None
        self.mouse_serial = 0
        self.client_channel = False
        self.gui_inset = (0.0, 0.0)
        self.ignore_gui_inset = False
        self._lock = threading.Lock()
        self._stop = threading.Event()

    def update(self, value: dict) -> None:
        channel = value.pop("_evaluator_channel", None)
        engine_mouse = value.pop("_evaluator_mouse", None)
        client_viewport = value.pop("_evaluator_viewport_size", None)
        gui_inset = value.pop("_evaluator_gui_inset", None)
        ignore_gui_inset = value.pop("_evaluator_ignore_gui_inset", False)
        if channel != "client" and self.client_channel:
            return
        if channel == "client":
            self.client_channel = True
        self.set_viewport_size(client_viewport)
        if (isinstance(gui_inset, list) and len(gui_inset) == 2
                and all(isinstance(n, (int, float)) for n in gui_inset)):
            with self._lock:
                self.gui_inset = (float(gui_inset[0]), float(gui_inset[1]))
                self.ignore_gui_inset = bool(ignore_gui_inset)
        if channel == "client" and "phase" not in value:
            # Coordinate-only telemetry must not replace the full dashboard
            # snapshot received independently over server HTTP.
            with self._lock:
                if (isinstance(engine_mouse, list) and len(engine_mouse) == 2
                        and all(isinstance(n, (int, float)) for n in engine_mouse)):
                    self.engine_mouse = (float(engine_mouse[0]), float(engine_mouse[1]))
                    self.mouse_serial += 1
            return
        # GUI controls are children of the 82%-sized card. Their declared
        # UDim2 scale is known from the candidate and AbsoluteSize comes from
        # the actual client. This yields the client viewport even though the
        # evaluator bridge itself runs on the server (whose camera is 1x1).
        factors = {
            "start_button": (0.82 * 0.30, 0.82 * 0.11),
            "plot_1": (0.82 * 0.25, 0.82 * 0.34),
            "plot_2": (0.82 * 0.25, 0.82 * 0.34),
            "plot_3": (0.82 * 0.25, 0.82 * 0.34),
            "plant_sunberry_button": (0.82 * 0.20, 0.82 * 0.10),
            "plant_moonleaf_button": (0.82 * 0.20, 0.82 * 0.10),
            "water_button": (0.82 * 0.13, 0.82 * 0.10),
            "harvest_button": (0.82 * 0.13, 0.82 * 0.10),
            "end_day_button": (0.82 * 0.16, 0.82 * 0.10),
            "deliver_button": (0.82 * 0.16, 0.82 * 0.10),
            "restart_button": (0.82 * 0.16, 0.82 * 0.10),
        }
        widths: list[float] = []
        heights: list[float] = []
        for target in value.get("targets", []):
            if not isinstance(target, dict) or target.get("kind") not in factors:
                continue
            rect = target.get("rect")
            if not isinstance(rect, list) or len(rect) != 4 or rect[2] <= 0 or rect[3] <= 0:
                continue
            fx, fy = factors[target["kind"]]
            widths.append(float(rect[2]) / fx)
            heights.append(float(rect[3]) / fy)
        inferred = None
        if widths and heights:
            inferred = (statistics.median(widths), statistics.median(heights))
        with self._lock:
            self.latest = value
            self.serial += 1
            if (isinstance(engine_mouse, list) and len(engine_mouse) == 2
                    and all(isinstance(n, (int, float)) for n in engine_mouse)):
                self.engine_mouse = (float(engine_mouse[0]), float(engine_mouse[1]))
                self.mouse_serial += 1
            if inferred is not None:
                self.viewport_size = inferred
                self.viewport_source = "GUI AbsoluteSize"

    def set_viewport_size(self, value: object) -> None:
        if (isinstance(value, list) and len(value) == 2
                and all(isinstance(n, (int, float)) and n >= 64 for n in value)):
            with self._lock:
                self.viewport_size = (float(value[0]), float(value[1]))
                self.viewport_source = "client camera"

    def get(self) -> tuple[int, dict | None]:
        with self._lock:
            return self.serial, json.loads(json.dumps(self.latest)) if self.latest is not None else None

    def stop(self) -> None:
        self._stop.set()

    def tail(self, path: Path, start_at_end: bool = False) -> None:
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                if start_at_end:
                    handle.seek(0, 2)
                while not self._stop.is_set():
                    line = handle.readline()
                    if not line:
                        time.sleep(0.05)
                        continue
                    at = line.find(PREFIX)
                    if at >= 0:
                        payload = line[at + len(PREFIX):].strip()
                        # Roblox log decoration may follow the JSON; decode only one value.
                        try:
                            value, _ = json.JSONDecoder().raw_decode(payload)
                            self.update(value)
                        except json.JSONDecodeError:
                            pass
        except Exception as exc:  # pragma: no cover
            self.error = str(exc)


class LocalSnapshotServer:
    def __init__(self, feed: SnapshotFeed, host: str = "127.0.0.1", port: int = 8765) -> None:
        self.feed = feed
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                if self.path != "/snapshot":
                    self.send_error(404)
                    return
                try:
                    size = int(self.headers.get("Content-Length", "0"))
                    if size <= 0 or size > 1_000_000:
                        raise ValueError("invalid content length")
                    payload = json.loads(self.rfile.read(size).decode("utf-8"))
                    if not isinstance(payload, dict):
                        raise ValueError("snapshot must be an object")
                    outer.feed.set_viewport_size(payload.pop("_evaluator_viewport_size", None))
                    outer.feed.update(payload)
                    self.send_response(204)
                    self.end_headers()
                except Exception as exc:
                    outer.feed.error = str(exc)
                    self.send_error(400, str(exc))

            def log_message(self, format: str, *args) -> None:
                return

        self.httpd = ThreadingHTTPServer((host, port), Handler)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.started = False

    def start(self) -> None:
        self.thread.start()
        self.started = True

    def close(self) -> None:
        if not self.started:
            self.httpd.server_close()
            return
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=2)


def find_studio() -> Path:
    base = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "Versions"
    choices = list(base.glob("*/RobloxStudioBeta.exe"))
    if not choices:
        raise FileNotFoundError("RobloxStudioBeta.exe not found")
    # Always use the newest installed Studio. Selecting a hard-coded older
    # version can create a separate authentication profile and repeatedly ask
    # the user to sign in after the normal launcher has already been updated.
    return max(choices, key=lambda p: p.stat().st_mtime)


def preflight_roblox_auth_routes() -> None:
    """Stop before Studio can delete cookies when auth routes are unreachable."""
    checks = [
        ("OAuth metadata", "https://apis.roblox.com/oauth/.well-known/openid-configuration", True),
        ("moderation status", "https://usermoderation.roblox.com/v1/not-approved", False),
    ]
    failures: list[str] = []
    for label, url, require_success in checks:
        request = urllib.request.Request(url, headers={"User-Agent": "RobloxStudio/0.735 preflight"})
        try:
            with urllib.request.urlopen(request, timeout=8) as response:
                status = int(response.status)
                if require_success and not 200 <= status < 300:
                    failures.append(f"{label}: HTTP {status}")
        except urllib.error.HTTPError as exc:
            # The moderation endpoint normally rejects an anonymous request;
            # any prompt HTTP response proves DNS/TLS/routing are working.
            if require_success or exc.code >= 500:
                failures.append(f"{label}: HTTP {exc.code}")
        except Exception as exc:
            failures.append(f"{label}: {exc}")
    if failures:
        raise RuntimeError(
            "Roblox authentication network preflight failed; Studio was not opened, "
            "so saved login cookies were preserved. Make browser and Studio use the "
            "same VPN/TUN route, then retry. " + "; ".join(failures)
        )


def studio_environment():
    """Inherit the operator-configured network environment for Studio."""
    return os.environ.copy()


def clear_headless_studio_processes() -> None:
    """Refuse visible Studio sessions, then remove stale headless launchers."""
    user32 = ctypes.windll.user32
    visible: list[str] = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd: int, _: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length <= 0:
            return True
        buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buffer, length + 1)
        if buffer.value.replace(" ", "") == "RobloxStudio" or "Roblox Studio" in buffer.value:
            visible.append(buffer.value)
        return True

    cb = callback_type(callback)
    user32.EnumWindows(cb, 0)
    if visible:
        raise RuntimeError("close visible Roblox Studio windows before evaluation (" + ", ".join(visible) + ")")
    # Roblox frequently leaves an invisible singleton alive after its window
    # closes. A fresh launch then hands the request to that stale process and
    # subprocess.pid no longer owns the editor HWND. With all visible Studio
    # sessions already rejected above, these exact-name processes are stale.
    listing = subprocess.run(
        ["tasklist.exe", "/FI", "IMAGENAME eq RobloxStudioBeta.exe", "/FO", "CSV", "/NH"],
        capture_output=True, text=True, errors="replace", check=False,
    )
    stale_pids: list[int] = []
    for row in csv.reader(listing.stdout.splitlines()):
        if len(row) >= 2 and row[0].lower() == "robloxstudiobeta.exe":
            try:
                stale_pids.append(int(row[1]))
            except ValueError:
                pass
    for pid in stale_pids:
        print(f"Closing stale background Roblox Studio PID {pid}...", flush=True)
        subprocess.run(
            ["taskkill.exe", "/PID", str(pid), "/T", "/F"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
    if stale_pids:
        time.sleep(1.5)


def inject_bridge(source: Path, destination: Path, bridge_text: str, client_bridge_text: str) -> None:
    tree = ET.parse(source)
    root = tree.getroot()
    service = None
    for item in root.findall("Item"):
        if item.attrib.get("class") != "ServerScriptService":
            continue
        props = item.find("Properties")
        if props is not None and any(n.attrib.get("name") == "Name" and n.text == "ServerScriptService" for n in props):
            service = item
            break
    if service is None:
        # Some valid compact place exports omit empty services entirely.  Add
        # the evaluator-only server container to the instrumented copy; the
        # delivered candidate remains byte-for-byte unchanged.
        service = ET.SubElement(
            root,
            "Item",
            {"class": "ServerScriptService", "referent": "PG_SERVER_SCRIPT_SERVICE"},
        )
        service_props = ET.SubElement(service, "Properties")
        ET.SubElement(service_props, "string", {"name": "Name"}).text = "ServerScriptService"
    http_service = next((item for item in root.findall("Item") if item.attrib.get("class") == "HttpService"), None)
    if http_service is None:
        http_service = ET.SubElement(root, "Item", {"class": "HttpService", "referent": "PG_HTTP_SERVICE"})
        http_props = ET.SubElement(http_service, "Properties")
        ET.SubElement(http_props, "string", {"name": "Name"}).text = "HttpService"
        ET.SubElement(http_props, "bool", {"name": "HttpEnabled"}).text = "true"
    else:
        http_props = http_service.find("Properties")
        enabled = None if http_props is None else next((n for n in http_props if n.attrib.get("name") == "HttpEnabled"), None)
        if http_props is None:
            http_props = ET.SubElement(http_service, "Properties")
        if enabled is None:
            enabled = ET.SubElement(http_props, "bool", {"name": "HttpEnabled"})
        enabled.text = "true"
    script = ET.SubElement(service, "Item", {"class": "Script", "referent": "PG_EVALUATOR_BRIDGE"})
    props = ET.SubElement(script, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = "PocketGreenhouseEvaluatorBridge"
    ET.SubElement(props, "bool", {"name": "Disabled"}).text = "false"
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = bridge_text
    player_scripts = None
    for item in root.iter("Item"):
        if item.attrib.get("class") != "StarterPlayerScripts":
            continue
        item_props = item.find("Properties")
        if item_props is not None and any(n.attrib.get("name") == "Name" and n.text == "StarterPlayerScripts" for n in item_props):
            player_scripts = item
            break
    if player_scripts is None:
        # A compact project may keep its game LocalScript in StarterGui and
        # omits StarterPlayer/StarterPlayerScripts.  A LocalScript parented to
        # StarterGui is copied to PlayerGui and runs in the same client
        # context, which is sufficient for this read-only bridge.
        for item in root.findall("Item"):
            if item.attrib.get("class") != "StarterGui":
                continue
            item_props = item.find("Properties")
            if item_props is not None and any(
                n.attrib.get("name") == "Name" and n.text == "StarterGui" for n in item_props
            ):
                player_scripts = item
                break
    if player_scripts is None:
        raise RuntimeError("neither StarterPlayerScripts nor StarterGui was found in rbxlx")
    local_script = ET.SubElement(player_scripts, "Item", {"class": "LocalScript", "referent": "PG_EVALUATOR_CLIENT_BRIDGE"})
    local_props = ET.SubElement(local_script, "Properties")
    ET.SubElement(local_props, "string", {"name": "Name"}).text = "PocketGreenhouseEvaluatorClientBridge"
    ET.SubElement(local_props, "bool", {"name": "Disabled"}).text = "false"
    ET.SubElement(local_props, "ProtectedString", {"name": "Source"}).text = client_bridge_text
    tree.write(destination, encoding="utf-8", xml_declaration=False)


def newest_log_after(started: float, timeout: float = 30) -> Path:
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        logs = [p for p in log_dir.glob("*Studio*.log") if p.stat().st_mtime >= started - 2]
        if logs:
            return max(logs, key=lambda p: p.stat().st_mtime)
        time.sleep(0.25)
    raise TimeoutError("Roblox Studio log file did not appear")


def newest_studio_log() -> Path:
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
    logs = list(log_dir.glob("*Studio*.log"))
    if not logs:
        raise FileNotFoundError(f"no Roblox Studio log found in {log_dir}")
    return max(logs, key=lambda p: p.stat().st_mtime)


def log_for_place(place: Path, started: float, timeout: float = 120) -> Path:
    """Find the exact Studio log that opened this unique QA pathname."""
    log_dir = Path(os.environ["LOCALAPPDATA"]) / "Roblox" / "logs"
    needle = str(place).replace("\\", "/").lower()
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        logs = sorted(log_dir.glob("*Studio*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
        for log in logs:
            if log.stat().st_mtime < started - 2:
                continue
            try:
                text = log.read_text(encoding="utf-8", errors="replace").replace("\\", "/").lower()
            except OSError:
                continue
            if needle in text:
                return log
        time.sleep(0.20)
    raise TimeoutError(f"no Studio log claimed unique QA place {place.name!r}")


def wait_unique_place_open(log: Path, place: Path, timeout: float = 120) -> None:
    """Require OpenPlaceSuccess after this run's unique pathname."""
    needle = str(place).replace("\\", "/").lower()
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            text = log.read_text(encoding="utf-8", errors="replace").replace("\\", "/").lower()
            # The unique pathname may be repeated in telemetry after success;
            # anchor to its first appearance (command/open start), not last.
            at = text.find(needle)
            if at >= 0 and text.find("openplacesuccess", at) >= 0:
                return
        except OSError:
            pass
        time.sleep(0.15)
    raise TimeoutError(f"Studio did not finish opening unique QA place {place.name!r}")


def log_process_id(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"Constructing UIThreadNotifier for process '([0-9]+)'", text)
    if not match:
        raise RuntimeError(f"cannot bind Studio process id from log {log.name}")
    return int(match.group(1))


def wait_log_contains(path: Path, marker: str, timeout: float = 120) -> None:
    end = time.monotonic() + timeout
    position = 0
    while time.monotonic() < end:
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                handle.seek(position)
                chunk = handle.read()
                position = handle.tell()
            if marker in chunk:
                return
        except OSError:
            pass
        time.sleep(0.1)
    raise TimeoutError(f"Studio did not report {marker!r} within {timeout:.0f}s")


def wait_log_contains_since(path: Path, marker: str, position: int, timeout: float) -> bool:
    """Wait for a marker appended after *position*; never accept an old run."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                handle.seek(position)
                chunk = handle.read()
            if marker in chunk:
                return True
        except OSError:
            pass
        time.sleep(0.10)
    return False


def window_pid(hwnd: int) -> int:
    pid = wintypes.DWORD()
    ctypes.windll.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return int(pid.value)


def running_studio_pids() -> set[int]:
    """Return RobloxStudioBeta PIDs without relying on localized window titles."""
    listing = subprocess.run(
        ["tasklist.exe", "/FI", "IMAGENAME eq RobloxStudioBeta.exe", "/FO", "CSV", "/NH"],
        capture_output=True, text=True, errors="replace", check=False,
    )
    result: set[int] = set()
    for row in csv.reader(listing.stdout.splitlines()):
        if len(row) >= 2 and row[0].lower() == "robloxstudiobeta.exe":
            try:
                result.add(int(row[1]))
            except ValueError:
                pass
    return result


def process_start_filetime(pid: int) -> int:
    """Return process creation FILETIME; unknown processes sort last."""
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.windll.kernel32
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.GetProcessTimes.argtypes = [
        wintypes.HANDLE, ctypes.POINTER(wintypes.FILETIME), ctypes.POINTER(wintypes.FILETIME),
        ctypes.POINTER(wintypes.FILETIME), ctypes.POINTER(wintypes.FILETIME),
    ]
    kernel32.GetProcessTimes.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return (1 << 63) - 1
    try:
        created = wintypes.FILETIME()
        exited = wintypes.FILETIME()
        kernel = wintypes.FILETIME()
        user = wintypes.FILETIME()
        if not kernel32.GetProcessTimes(
            handle, ctypes.byref(created), ctypes.byref(exited),
            ctypes.byref(kernel), ctypes.byref(user),
        ):
            return (1 << 63) - 1
        return (int(created.dwHighDateTime) << 32) | int(created.dwLowDateTime)
    finally:
        kernel32.CloseHandle(handle)


def studio_windows() -> list[int]:
    """Return visible Studio windows, oldest process then largest window.

    Roblox's home shell can have a localized or temporarily empty title. Use
    the owning RobloxStudioBeta process as the primary identity instead of
    treating the title text as an authentication/window-state signal.
    """
    user32 = ctypes.windll.user32
    pids = running_studio_pids()
    found: list[tuple[int, int, int]] = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd: int, _: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        owner_pid = window_pid(hwnd)
        length = user32.GetWindowTextLengthW(hwnd)
        title = ctypes.create_unicode_buffer(length + 1)
        if length:
            user32.GetWindowTextW(hwnd, title, length + 1)
        # Qt/Chromium Studio shells frequently expose an empty title and
        # MainWindowHandle=0 to the process API. Accept process ownership;
        # title matching remains a safe fallback when tasklist is localized.
        title_match = "roblox studio" in title.value.lower() or title.value.replace(" ", "").lower() == "robloxstudio"
        if owner_pid not in pids and not title_match:
            return True
        rect = wintypes.RECT()
        if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
            return True
        width = max(0, rect.right - rect.left)
        height = max(0, rect.bottom - rect.top)
        # Ignore stale Qt helper handles and dialogs.
        if width < 800 or height < 500:
            return True
        pid = window_pid(hwnd)
        found.append((process_start_filetime(pid), -(width * height), int(hwnd)))
        return True

    user32.EnumWindows(callback_type(callback), 0)
    found.sort()
    return [hwnd for _, _, hwnd in found]


def wait_studio_windows(timeout: float = 12) -> list[int]:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        found = studio_windows()
        if found:
            return found
        time.sleep(0.25)
    return []


def find_studio_via_alt_tab(max_steps: int = 12) -> int | None:
    """Find an existing Studio window through the real Alt-Tab surface.

    Some Studio Home shells do not expose a normal EnumWindows top-level HWND,
    even while Windows can foreground them through Alt-Tab. Cycle only through
    existing windows and accept a foreground window owned by RobloxStudioBeta.
    """
    user32 = ctypes.windll.user32
    studio_pids = running_studio_pids()
    for step in range(1, max_steps + 1):
        key_combo(VK_MENU, 0x09)  # Alt+Tab
        time.sleep(0.45)
        hwnd = user32.GetForegroundWindow()
        pid = window_pid(hwnd) if hwnd else 0
        if hwnd and pid in studio_pids:
            rect = wintypes.RECT()
            if user32.GetWindowRect(hwnd, ctypes.byref(rect)):
                width = max(0, rect.right - rect.left)
                height = max(0, rect.bottom - rect.top)
                if width >= 800 and height >= 500:
                    print(f"Found existing Studio through Alt-Tab: PID={pid}, HWND={hwnd}, step={step}.", flush=True)
                    return int(hwnd)
    return None


def window_for_pid(pid: int, timeout: float = 30) -> int:
    user32 = ctypes.windll.user32
    found: list[tuple[int, int]] = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd: int, _: int) -> bool:
        proc_id = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(proc_id))
        if proc_id.value != pid or not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        title = ctypes.create_unicode_buffer(length + 1)
        if length:
            user32.GetWindowTextW(hwnd, title, length + 1)
        if "Roblox Studio" not in title.value and title.value.replace(" ", "") != "RobloxStudio":
            return True
        rect = wintypes.RECT()
        if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
            return True
        width = max(0, rect.right - rect.left)
        height = max(0, rect.bottom - rect.top)
        if width < 900 or height < 600:
            return True
        # A Studio process exposes helper/tool HWNDs as well as its editor.
        # Bind to the largest real editor, never to the first enumerated HWND.
        found.append((width * height, int(hwnd)))
        return True

    cb = callback_type(callback)
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        found.clear()
        user32.EnumWindows(cb, 0)
        if found:
            found.sort(reverse=True)
            return found[0][1]
        time.sleep(0.25)
    raise TimeoutError("Roblox Studio window did not appear")


def any_studio_window(timeout: float = 30) -> int:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        found = studio_windows()
        if found:
            return found[0]
        time.sleep(0.25)
    raise TimeoutError("no visible Roblox Studio window found")


def focus(hwnd: int) -> int:
    if not USER32.IsWindow(hwnd):
        raise RuntimeError("Studio window handle is no longer valid")
    target_pid = window_pid(hwnd)
    USER32.ShowWindow(hwnd, SW_RESTORE)
    USER32.ShowWindow(hwnd, SW_SHOW)
    flags = SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW
    for _ in range(4):
        # This is the same foreground grant/topmost pulse used by the earlier
        # Dockline/DeepRelay controller. The topmost state is removed
        # immediately; it only makes Windows accept the activation request.
        USER32.AllowSetForegroundWindow(ASFW_ANY)
        USER32.SetWindowPos(hwnd, wintypes.HWND(HWND_TOPMOST), 0, 0, 0, 0, flags)
        USER32.BringWindowToTop(hwnd)
        USER32.SetForegroundWindow(hwnd)
        time.sleep(0.12)
        USER32.SetWindowPos(hwnd, wintypes.HWND(HWND_NOTOPMOST), 0, 0, 0, 0, flags)
        # A synthetic Alt press grants foreground activation rights on builds
        # that reject the first SetForegroundWindow request.
        send_keyboard_input(VK_MENU, 0)
        time.sleep(0.08)
        send_keyboard_input(VK_MENU, KEYEVENTF_KEYUP)
        USER32.SetForegroundWindow(hwnd)
        time.sleep(0.45)
        foreground_now = USER32.GetForegroundWindow()
        if foreground_now == hwnd:
            return int(hwnd)

    # Studio exposes multiple top-level/helper windows in one process. PID
    # equality is insufficient: F5 sent while a helper owns focus is silently
    # discarded. Attach the input queues and activate the exact editor HWND,
    # matching the proven Dockline controller.
    current_thread = ctypes.windll.kernel32.GetCurrentThreadId()
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
        return int(hwnd)

    # Final exact-HWND fallback: a real SendInput click on the editor title
    # bar, not on an arbitrary center panel or another same-PID helper.
    rect = wintypes.RECT()
    if USER32.GetWindowRect(hwnd, ctypes.byref(rect)):
        click_screen(rect.left + max(120, min(480, (rect.right - rect.left) // 3)), rect.top + 15)
        if USER32.GetForegroundWindow() == hwnd:
            return int(hwnd)
    foreground = USER32.GetForegroundWindow()
    if foreground and window_pid(foreground) == target_pid:
        live_rect = wintypes.RECT()
        if USER32.GetWindowRect(foreground, ctypes.byref(live_rect)):
            width = live_rect.right - live_rect.left
            height = live_rect.bottom - live_rect.top
            title_len = USER32.GetWindowTextLengthW(foreground)
            live_title = ctypes.create_unicode_buffer(title_len + 1)
            if title_len:
                USER32.GetWindowTextW(foreground, live_title, title_len + 1)
            escaped_title = live_title.value.encode("unicode_escape").decode("ascii")
            print(
                f"    same-PID foreground HWND={foreground} size={width}x{height} "
                f"title_unicode={escaped_title!r}",
                flush=True,
            )
            if width >= 800 and height >= 500:
                print(
                    f"    Studio replaced editor HWND {hwnd} -> {foreground}; using live same-PID editor.",
                    flush=True,
                )
                return int(foreground)
            # A small same-process modal is covering the editor. Escape is a
            # non-affirming dismissal (it never accepts publish/login/save),
            # then retry activation of the already bound editor HWND.
            key_press(VK_ESCAPE)
            time.sleep(0.5)
            USER32.BringWindowToTop(hwnd)
            USER32.SetForegroundWindow(hwnd)
            time.sleep(0.5)
            if USER32.GetForegroundWindow() == hwnd:
                print("    dismissed same-PID modal with Escape.", flush=True)
                return int(hwnd)
    length = USER32.GetWindowTextLengthW(foreground) if foreground else 0
    buffer = ctypes.create_unicode_buffer(length + 1)
    if foreground and length:
        USER32.GetWindowTextW(foreground, buffer, length + 1)
    raise RuntimeError(
        f"cannot focus the exact bound Roblox Studio HWND {hwnd}; "
        f"foreground PID={window_pid(foreground) if foreground else 0}, title={buffer.value!r}"
    )


def start_play_verified(log: Path, preferred_hwnd: int | None = None) -> int:
    """Start Play with real input and require Studio's own PlaySolo receipt."""
    user32 = ctypes.windll.user32
    position = log.stat().st_size
    for round_no in range(1, 4):
        if preferred_hwnd is not None:
            # The caller bound this HWND through unique path -> log -> PID ->
            # largest editor window.  Never fall back to unrelated Studio
            # windows: doing so only creates fake input attempts.
            candidates = [preferred_hwnd] if user32.IsWindow(preferred_hwnd) else []
        else:
            candidates = studio_windows()
        if not candidates:
            time.sleep(1)
            continue
        for index, hwnd in enumerate(candidates, 1):
            pid = window_pid(hwnd)
            rect = wintypes.RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            print(f"  Play attempt {round_no}.{index}: HWND={hwnd} PID={pid} size={rect.right-rect.left}x{rect.bottom-rect.top}", flush=True)
            try:
                hwnd = focus(hwnd)
                preferred_hwnd = hwnd
            except RuntimeError as exc:
                print(f"    focus rejected: {exc}", flush=True)
                continue
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            # Click inside the editor first so an address/file field cannot own
            # keyboard focus, then deliver the physical F5 key event.
            click_screen((rect.left + rect.right) // 2, (rect.top + rect.bottom) // 2)
            if round_no == 1:
                print("    sending F5 as virtual-key SendInput", flush=True)
                key_press(VK_F5)
            else:
                # Recent Qt Studio shells intermittently discard VK-only F5
                # events. A scan-code SendInput is still genuine virtual
                # keyboard input and matches a physical function key.
                print("    sending F5 as scan-code SendInput", flush=True)
                send_scancode_input(VK_F5)
                time.sleep(0.08)
                send_scancode_input(VK_F5, key_up=True)
                time.sleep(0.12)
            if wait_log_contains_since(log, "initiatePlaySolo", position, timeout=4):
                print("  Studio log confirmed PlaySolo started.", flush=True)
                return hwnd
            if round_no == 1 and click_studio_play_button(hwnd):
                if wait_log_contains_since(log, "initiatePlaySolo", position, timeout=12):
                    print("  Studio log confirmed PlaySolo started from toolbar click.", flush=True)
                    return hwnd
        time.sleep(1)
    raise RuntimeError("the exact Studio editor for this QA place did not acknowledge F5/PlaySolo")


def dpi_scale(hwnd: int) -> float:
    try:
        dpi = ctypes.windll.user32.GetDpiForWindow(hwnd)
        if dpi:
            return float(dpi) / 96.0
    except (AttributeError, OSError):
        pass
    return 1.0


def key_press(vk: int, shift: bool = False) -> None:
    if shift:
        send_keyboard_input(VK_SHIFT, 0)
        time.sleep(0.05)
    send_keyboard_input(vk, 0)
    time.sleep(0.06)
    send_keyboard_input(vk, KEYEVENTF_KEYUP)
    if shift:
        time.sleep(0.05)
        send_keyboard_input(VK_SHIFT, KEYEVENTF_KEYUP)
    time.sleep(0.06)


def key_combo(modifier: int, key: int) -> None:
    send_keyboard_input(modifier, 0)
    time.sleep(0.05)
    send_keyboard_input(key, 0)
    time.sleep(0.06)
    send_keyboard_input(key, KEYEVENTF_KEYUP)
    time.sleep(0.05)
    send_keyboard_input(modifier, KEYEVENTF_KEYUP)
    time.sleep(0.08)


def open_place_dialog(path: Path) -> None:
    """Open Studio's native place picker using virtual SendInput keys."""
    # Some Home-shell builds ignore Ctrl+O until the File menu has focus.
    # Alt+F, O opens the picker without creating another Studio process.
    key_combo(VK_MENU, ord("F"))
    time.sleep(0.35)
    key_press(ord("O"))
    time.sleep(1.0)
    subprocess.run(["clip.exe"], input=str(path), text=True, check=True)
    key_combo(VK_CONTROL, ord("A"))
    key_combo(VK_CONTROL, VK_V)
    time.sleep(0.25)
    key_press(VK_RETURN)


def click_screen(x: int, y: int) -> None:
    actual_x, actual_y = move_mouse_absolute(int(x), int(y))
    print(f"  cursor verified at ({actual_x},{actual_y})", flush=True)
    send_mouse_input(MOUSE_LEFTDOWN)
    time.sleep(0.12)
    send_mouse_input(MOUSE_LEFTUP)
    time.sleep(0.15)


def right_click_screen(x: int, y: int) -> None:
    """Focus a Roblox viewport without activating a candidate GUI button."""
    actual_x, actual_y = move_mouse_absolute(int(x), int(y))
    print(f"  viewport focus cursor verified at ({actual_x},{actual_y})", flush=True)
    send_mouse_input(MOUSE_RIGHTDOWN)
    time.sleep(0.10)
    send_mouse_input(MOUSE_RIGHTUP)
    time.sleep(0.20)


def move_mouse_relative(dx: int, dy: int) -> None:
    """Send a genuine relative mouse-motion packet through SendInput."""
    send_mouse_input(MOUSE_MOVE, int(dx), int(dy))
    time.sleep(0.12)


def click_studio_play_button(hwnd: int) -> bool:
    """Locate Studio Play with UI Automation, then click it via SendInput."""
    helper = Path(__file__).resolve().with_name("find_studio_play_button.ps1")
    result = subprocess.run(
        ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
         "-File", str(helper), "-Hwnd", str(int(hwnd))],
        capture_output=True, text=True, errors="replace", check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        print(f"  UI Automation could not locate Studio Play button (exit={result.returncode}).", flush=True)
        return False
    try:
        button = json.loads(result.stdout.strip().splitlines()[-1])
        x = float(button["left"]) + float(button["width"]) / 2
        y = float(button["top"]) + float(button["height"]) / 2
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"  Invalid UI Automation Play result: {exc}", flush=True)
        return False
    print(f"  Clicking Studio Play button {button.get('name')!r} at ({x:.0f},{y:.0f}) via SendInput.", flush=True)
    focus(hwnd)
    click_screen(round(x), round(y))
    return True


def locate_viewport(hwnd: int) -> tuple[int, int, int, int]:
    """Find the game viewport from its deterministic dark-green background."""
    rect = wintypes.RECT()
    if not ctypes.windll.user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise RuntimeError("cannot read Studio window rectangle")
    window_box = (rect.left, rect.top, rect.right, rect.bottom)
    image = ImageGrab.grab(bbox=window_box, all_screens=True).convert("RGB")
    width, height = image.size
    pix = image.load()
    matches: set[tuple[int, int]] = set()
    for y in range(0, height, 3):
        for x in range(0, width, 3):
            r, g, b = pix[x, y]
            if abs(r - BG[0]) <= 2 and abs(g - BG[1]) <= 2 and abs(b - BG[2]) <= 2:
                matches.add((x // 3, y // 3))
    if len(matches) < 500:
        raise RuntimeError("cannot locate Pocket Greenhouse viewport; keep Studio visible and unobscured")
    # Do not combine unrelated dark-green pixels from Studio chrome or an
    # exposed background application. The full-screen game background forms
    # one large connected component around the centered card.
    remaining = set(matches)
    best: tuple[int, int, int, int, int] | None = None
    while remaining:
        seed = remaining.pop()
        stack = [seed]
        min_x = max_x = seed[0]
        min_y = max_y = seed[1]
        count = 0
        while stack:
            gx, gy = stack.pop()
            count += 1
            min_x, max_x = min(min_x, gx), max(max_x, gx)
            min_y, max_y = min(min_y, gy), max(max_y, gy)
            for neighbor in ((gx - 1, gy), (gx + 1, gy), (gx, gy - 1), (gx, gy + 1)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
        candidate = (count, min_x, min_y, max_x, max_y)
        if best is None or candidate[0] > best[0]:
            best = candidate
    if best is None or best[0] < 200:
        raise RuntimeError("Pocket Greenhouse viewport background is fragmented or obscured")
    _, min_x, min_y, max_x, max_y = best
    return (
        rect.left + min_x * 3,
        rect.top + min_y * 3,
        rect.left + (max_x + 1) * 3,
        rect.top + (max_y + 1) * 3,
    )


def screenshot_viewport(viewport: tuple[int, int, int, int]):
    return ImageGrab.grab(bbox=viewport, all_screens=True).convert("RGB")


def changed(before, after) -> bool:
    if before.size != after.size:
        return True
    stat = ImageStat.Stat(ImageChops.difference(before, after))
    return sum(stat.mean) / 3.0 >= 0.35


class Runtime:
    def __init__(self, studio: Path, place: Path, naming: dict, evidence_dir: Path) -> None:
        self.studio = studio
        self.place = place
        self.naming = naming
        self.evidence_dir = evidence_dir
        self.process: subprocess.Popen | None = None
        self.hwnd: int | None = None
        self.feed = SnapshotFeed()
        self.snapshot_server = LocalSnapshotServer(self.feed)
        self.viewport: tuple[int, int, int, int] | None = None
        self.owns_process = False
        self.controller_hwnd = ctypes.windll.user32.GetForegroundWindow()
        self.log: Path | None = None
        self.bound_pid: int | None = None
        self.engine_map: tuple[float, float, float, float] | None = None

    def hide_controller(self) -> None:
        if self.controller_hwnd and self.controller_hwnd != self.hwnd and ctypes.windll.user32.IsWindow(self.controller_hwnd):
            ctypes.windll.user32.ShowWindow(self.controller_hwnd, SW_MINIMIZE)
            time.sleep(0.5)

    def restore_controller(self) -> None:
        if self.controller_hwnd and ctypes.windll.user32.IsWindow(self.controller_hwnd):
            ctypes.windll.user32.ShowWindow(self.controller_hwnd, SW_RESTORE)

    def launch(self) -> None:
        started = time.time()
        self.process = subprocess.Popen([
            str(self.studio), "-newInstance", "-task", "EditFile",
            "-localPlaceFile", str(self.place)
        ])
        self.owns_process = True
        self.hwnd = window_for_pid(self.process.pid)
        log = newest_log_after(started)
        self.log = log
        self.feed = SnapshotFeed()
        threading.Thread(target=self.feed.tail, args=(log,), daemon=True).start()
        time.sleep(3)
        self.hwnd = start_play_verified(log, self.hwnd)
        self.wait_snapshot(45, require_ready=True)
        time.sleep(1)
        rect = wintypes.RECT()
        USER32.GetWindowRect(self.hwnd, ctypes.byref(rect))
        self.viewport = (rect.left, rect.top, rect.right, rect.bottom)

    def launch_via_open_dialog(self, instrumented_place: Path) -> None:
        """Open QA copy through Roblox's proven EditFile handoff path."""
        self.snapshot_server.start()
        print(f"Opening instrumented place via Roblox EditFile handoff: {instrumented_place}", flush=True)
        clear_headless_studio_processes()
        open_started = time.time()
        self.process = subprocess.Popen([
            str(self.studio), "-task", "EditFile", "-localPlaceFile", str(instrumented_place)
        ], env=studio_environment())
        self.owns_process = True
        log = log_for_place(instrumented_place, open_started, timeout=120)
        self.log = log
        threading.Thread(target=self.feed.tail, args=(log, True), daemon=True).start()
        print("Waiting for Roblox Studio to finish loading the place...", flush=True)
        wait_unique_place_open(log, instrumented_place, timeout=120)
        print("Place loaded. Starting Play and waiting for the local dashboard channel...", flush=True)
        # Bind exact unique path -> log -> PID -> window.
        bound_pid = log_process_id(log)
        self.bound_pid = bound_pid
        self.hwnd = window_for_pid(bound_pid, timeout=30)
        print(f"Bound unique QA place to Studio PID={bound_pid} HWND={self.hwnd}.", flush=True)
        self.hide_controller()
        ctypes.windll.user32.ShowWindow(self.hwnd, SW_MAXIMIZE)
        time.sleep(1.5)
        # Give the editor UI a moment after OpenPlaceSuccess, then require a
        # PlaySolo acknowledgement before waiting for the HTTP bridge.
        time.sleep(2)
        self.hwnd = start_play_verified(log, self.hwnd)
        self.wait_snapshot(45, require_ready=True)
        self.wait_client_channel(15)
        print("Dashboard connected. Locating the game viewport and starting real input...", flush=True)
        time.sleep(1)
        foreground = USER32.GetForegroundWindow()
        if foreground and window_pid(foreground) == bound_pid:
            self.hwnd = int(foreground)
            print(f"Rebound post-Play Studio HWND={self.hwnd} for PID={bound_pid}.", flush=True)
        # Keep using the HWND bound to this run's unique place/log/PID.  A
        # different Studio editor may still exist behind a save prompt; using
        # any_studio_window() here could silently redirect all gameplay input.
        if not ctypes.windll.user32.IsWindow(self.hwnd):
            raise RuntimeError("the Studio window bound to the unique QA place disappeared")
        ctypes.windll.user32.ShowWindow(self.hwnd, SW_MAXIMIZE)
        time.sleep(1)
        self.hwnd = focus(self.hwnd)
        rect = wintypes.RECT()
        USER32.GetWindowRect(self.hwnd, ctypes.byref(rect))
        self.viewport = (rect.left, rect.top, rect.right, rect.bottom)
        self.activate_play_viewport()
        self.calibrate_engine_coordinates()

    def stop_play(self) -> None:
        if self.hwnd:
            self.hwnd = focus(self.hwnd)
            key_press(VK_F5, shift=True)
            time.sleep(2)

    def close(self, keep_window: bool = False) -> None:
        self.feed.stop()
        self.snapshot_server.close()
        if keep_window:
            self.restore_controller()
            return
        if self.hwnd:
            try:
                self.stop_play()
            except Exception as exc:
                print(f"Studio stop shortcut skipped during cleanup: {exc}", flush=True)
        if self.owns_process and self.process and self.process.poll() is None:
            # Give Studio a normal close first so authentication/cookie state
            # can be flushed. Force termination is only a final fallback.
            if self.hwnd:
                ctypes.windll.user32.PostMessageW(self.hwnd, WM_CLOSE, 0, 0)
            try:
                self.process.wait(12)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try: self.process.wait(5)
                except subprocess.TimeoutExpired: self.process.kill()
        self.restore_controller()

    def reopen_game(self) -> None:
        self.stop_play()
        if self.feed:
            self.feed.latest = None
        if self.log is None:
            raise RuntimeError("cannot restart Play: Studio log is unknown")
        self.hwnd = start_play_verified(self.log, self.hwnd)
        self.wait_snapshot(45, require_ready=True)
        self.wait_client_channel(15)
        time.sleep(1)
        foreground = USER32.GetForegroundWindow()
        if self.bound_pid and foreground and window_pid(foreground) == self.bound_pid:
            self.hwnd = int(foreground)
        elif self.bound_pid:
            self.hwnd = window_for_pid(self.bound_pid, timeout=30)
        rect = wintypes.RECT()
        USER32.GetWindowRect(self.hwnd, ctypes.byref(rect))
        self.viewport = (rect.left, rect.top, rect.right, rect.bottom)
        self.activate_play_viewport()
        self.calibrate_engine_coordinates()

    def wait_snapshot(self, timeout: float, require_ready: bool = False) -> dict:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            _, snap = self.feed.get() if self.feed else (0, None)
            if snap is not None:
                errors = validate_snapshot(snap, self.naming)
                if not errors and (not require_ready or snap.get("phase") != "not_ready"):
                    return snap
            time.sleep(0.05)
        requirement = "ready client dashboard" if require_ready else "valid dashboard"
        phase = None
        if self.feed:
            _, latest = self.feed.get()
            phase = latest.get("phase") if latest else None
        raise TimeoutError(
            f"no {requirement} snapshot (last phase={phase!r}; "
            f"feed error={self.feed.error if self.feed else 'no feed'})"
        )

    def snapshot(self) -> dict:
        _, snap = self.feed.get()
        if snap is None:
            raise RuntimeError("dashboard snapshot unavailable")
        return snap

    def wait_client_channel(self, timeout: float) -> None:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if self.feed.client_channel and self.feed.engine_mouse is not None:
                print("Client engine coordinate channel connected.", flush=True)
                return
            time.sleep(0.05)
        raise TimeoutError("client engine coordinate channel did not appear in Studio log")

    def wait_engine_mouse(self, after_serial: int, timeout: float = 2.0) -> tuple[float, float]:
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if self.feed.mouse_serial > after_serial and self.feed.engine_mouse is not None:
                return self.feed.engine_mouse
            time.sleep(0.02)
        raise TimeoutError("Roblox client did not report mouse coordinates")

    def activate_play_viewport(self, timeout: float = 5.0) -> None:
        """Give embedded PlayClient focus using the proven non-action right click."""
        self.hwnd = focus(self.hwnd)
        rect = wintypes.RECT()
        if not USER32.GetWindowRect(self.hwnd, ctypes.byref(rect)):
            raise RuntimeError("cannot read Studio editor bounds")
        # This is the same top-level-window 50%/55% point used by the earlier
        # successful evaluators. Right click grants viewport focus but Roblox
        # TextButtons only activate on left click, so candidate state is safe.
        safe_x = rect.left + (rect.right - rect.left) // 2
        safe_y = rect.top + (rect.bottom - rect.top) * 55 // 100
        serial = self.feed.mouse_serial
        right_click_screen(safe_x, safe_y)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            mouse = self.feed.engine_mouse
            if self.feed.mouse_serial > serial and mouse is not None and mouse[0] >= 0 and mouse[1] >= 0:
                print(f"Play viewport focused; client mouse={mouse}.", flush=True)
                return
            time.sleep(0.05)
        raise RuntimeError(
            f"Play viewport did not acquire mouse focus (last client mouse={self.feed.engine_mouse})"
        )

    def calibrate_engine_coordinates(self) -> None:
        """Derive desktop-to-engine mapping from two real in-viewport moves."""
        rect = wintypes.RECT()
        if not USER32.GetWindowRect(self.hwnd, ctypes.byref(rect)):
            raise RuntimeError("cannot read Studio window for engine calibration")
        cx = (rect.left + rect.right) // 2
        cy = rect.top + (rect.bottom - rect.top) * 55 // 100
        probes = [(cx - 140, cy - 90), (cx + 140, cy + 90)]
        pairs: list[tuple[float, float, float, float]] = []
        for sx, sy in probes:
            serial = self.feed.mouse_serial
            before_mouse = self.feed.engine_mouse
            actual_x, actual_y = move_mouse_absolute(sx, sy)
            # Roblox Studio's embedded client refreshes GetMouseLocation on a
            # button event, not on raw pointer movement alone. A right click
            # is non-mutating for the candidate GUI and supplies that event.
            # Also emit relative motion: Roblox updates GetMouseLocation from
            # InputChanged, while absolute packets may only move Windows' OS
            # cursor and leave the embedded client value stale.
            move_mouse_relative(1, 1)
            send_mouse_input(MOUSE_RIGHTDOWN)
            time.sleep(0.05)
            send_mouse_input(MOUSE_RIGHTUP)
            deadline = time.monotonic() + 2.0
            updated = None
            while time.monotonic() < deadline:
                current = self.feed.engine_mouse
                if self.feed.mouse_serial > serial and current is not None and current != before_mouse:
                    updated = current
                    break
                time.sleep(0.02)
            if updated is None:
                raise TimeoutError(f"Roblox client mouse did not refresh at calibration point {(sx, sy)}")
            ex, ey = updated
            pairs.append((actual_x, actual_y, ex, ey))
        p1, p2 = pairs
        if abs(p2[2] - p1[2]) < 20 or abs(p2[3] - p1[3]) < 20:
            raise RuntimeError(f"engine mouse calibration did not move enough after viewport focus: {pairs}")
        scale_x = (p2[0] - p1[0]) / (p2[2] - p1[2])
        scale_y = (p2[1] - p1[1]) / (p2[3] - p1[3])
        if not (0.5 <= scale_x <= 3.0 and 0.5 <= scale_y <= 3.0):
            raise RuntimeError(f"invalid engine mouse calibration scale: {pairs}")
        offset_x = p1[0] - p1[2] * scale_x
        offset_y = p1[1] - p1[3] * scale_y
        self.engine_map = (scale_x, scale_y, offset_x, offset_y)
        print(f"Engine mouse calibrated: desktop=engine*({scale_x:.4f},{scale_y:.4f})+({offset_x:.1f},{offset_y:.1f})", flush=True)

    def click_target(self, kind: str, retry_if_no_change: bool = False) -> None:
        live_hwnd = focus(self.hwnd)
        if live_hwnd != self.hwnd:
            self.hwnd = live_hwnd
            rect = wintypes.RECT()
            USER32.GetWindowRect(self.hwnd, ctypes.byref(rect))
            self.viewport = (rect.left, rect.top, rect.right, rect.bottom)
            self.activate_play_viewport()
            self.calibrate_engine_coordinates()
        snap = self.snapshot()
        before_revision = snap.get("revision")
        target = next((t for t in snap["targets"] if t["kind"] == kind), None)
        if not target or not target["visible"] or not target["interactable"]:
            raise RuntimeError(f"target {kind!r} is not visible/interactable")
        if self.viewport is None:
            self.hwnd = any_studio_window(timeout=30)
            rect = wintypes.RECT()
            USER32.GetWindowRect(self.hwnd, ctypes.byref(rect))
            self.viewport = (rect.left, rect.top, rect.right, rect.bottom)
        x, y, w, h = target["rect"]
        if self.engine_map is None:
            self.calibrate_engine_coordinates()
        scale_x, scale_y, offset_x, offset_y = self.engine_map
        engine_x, engine_y = x + w / 2, y + h / 2
        inset_x, inset_y = self.feed.gui_inset if self.feed.ignore_gui_inset else (0.0, 0.0)
        hit_x, hit_y = engine_x + inset_x, engine_y + inset_y
        screen_x = offset_x + hit_x * scale_x
        screen_y = offset_y + hit_y * scale_y
        observed = None
        for _ in range(3):
            serial = self.feed.mouse_serial
            before_mouse = self.feed.engine_mouse
            move_mouse_absolute(screen_x, screen_y)
            # Refresh the engine coordinate without invoking a TextButton.
            move_mouse_relative(1, 1)
            send_mouse_input(MOUSE_RIGHTDOWN)
            time.sleep(0.05)
            send_mouse_input(MOUSE_RIGHTUP)
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline:
                current_mouse = self.feed.engine_mouse
                if (current_mouse is not None and
                    ((self.feed.mouse_serial > serial and current_mouse != before_mouse) or
                     (abs(current_mouse[0] - hit_x) <= 2 and abs(current_mouse[1] - hit_y) <= 2))):
                    observed = current_mouse
                    break
                time.sleep(0.02)
            if observed is None:
                # Coordinate telemetry is advisory after a valid calibration.
                # Keep the previously computed mapping and let the game's
                # revision/state provide the authoritative click evidence.
                print(f"  client mouse telemetry stale while aligning {kind!r}; using calibrated mapping", flush=True)
                observed = before_mouse
                break
            error_x = hit_x - observed[0]
            error_y = hit_y - observed[1]
            if abs(error_x) <= 2 and abs(error_y) <= 2:
                break
            screen_x += error_x * scale_x
            screen_y += error_y * scale_y
        if observed is None:
            observed = self.feed.engine_mouse
        print(f"CLICK {kind}: gui=({engine_x:.1f},{engine_y:.1f}) hit=({hit_x:.1f},{hit_y:.1f}) client_mouse={observed} screen=({screen_x:.0f},{screen_y:.0f}) revision={before_revision}", flush=True)
        click_screen(screen_x, screen_y)
        # The candidate mirrors client state through a RemoteEvent and the
        # server then performs an HTTP POST. On this Studio build that round
        # trip can take ~2 seconds. Advancing after 0.75s caused every action
        # to be credited to the following click and retries could double-apply
        # End Day. Send exactly one click and wait for the mirror to settle.
        deadline = time.monotonic() + 6.0
        current = snap
        while time.monotonic() < deadline:
            current = self.snapshot()
            if current.get("revision") != before_revision:
                break
            time.sleep(0.05)
        if current.get("revision") != before_revision:
            print(f"  accepted: revision {before_revision} -> {current.get('revision')}", flush=True)
        else:
            print(f"  no revision change after one click (expected for invalid/no-op actions)", flush=True)
            if retry_if_no_change:
                refreshed = self.snapshot()
                refreshed_target = next(
                    (t for t in refreshed["targets"] if t["kind"] == kind), None
                )
                if (refreshed.get("revision") == before_revision and
                    refreshed_target and refreshed_target["visible"] and
                    refreshed_target["interactable"]):
                    print(f"  required state change missing; realigning and retrying {kind!r} once", flush=True)
                    # Recalibrate once because Studio DPI/window geometry can drift
                    # during a long trajectory. The recursive call cannot retry.
                    self.calibrate_engine_coordinates()
                    self.click_target(kind, retry_if_no_change=False)


def execute(script: dict, naming: dict, runtime: Runtime, trace_path: Path) -> None:
    saved_snapshots: dict[str, dict] = {}
    saved_images: dict[str, object] = {}
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    initial = runtime.snapshot()
    if initial.get("phase") == "not_ready":
        raise RuntimeError(
            "client dashboard is not ready; aborting invalid controller run before any candidate input"
        )
    with trace_path.open("w", encoding="utf-8") as trace:
        for traj in script["trajectories"]:
            if traj["clean_start"] == "restart":
                snap = runtime.snapshot()
                restart = next((t for t in snap["targets"] if t["kind"] == "restart_button"), None)
                if restart and restart["visible"] and restart["interactable"]:
                    runtime.click_target("restart_button")
            for index, step in enumerate(traj["steps"]):
                evidence = "runtime snapshot"
                try:
                    if runtime.snapshot().get("phase") == "not_ready":
                        raise RuntimeError("client dashboard became not_ready during trajectory")
                    action = step.get("do")
                    if action == "start":
                        pass
                    elif action == "click":
                        runtime.click_target(
                            step["target"]["kind"],
                            retry_if_no_change=bool(step.get("retry_once_if_no_change", False)),
                        )
                    elif action == "restart":
                        runtime.click_target("restart_button")
                    elif action == "reopen":
                        runtime.reopen_game()
                    elif action == "wait_until":
                        end = time.monotonic() + float(step.get("timeout_s", 10))
                        while True:
                            snap = runtime.snapshot()
                            if eval_assertion(step["cond"], snap, saved_snapshots, {}):
                                break
                            if time.monotonic() >= end:
                                raise TimeoutError(f"condition timed out: {step['cond']}")
                            time.sleep(0.05)
                    elif action == "capture":
                        name = step.get("save_as", f"{traj['id']}_{index}")
                        image = screenshot_viewport(runtime.viewport)
                        image.save(runtime.evidence_dir / f"{name}.png")
                        evidence = f"screenshot: {name}.png"
                    elif action == "snapshot":
                        name = step["save_as"]
                        saved_snapshots[name] = runtime.snapshot()
                        saved_images[name] = screenshot_viewport(runtime.viewport)
                    elif action is not None:
                        raise NotImplementedError(f"action {action!r} is not implemented by this click-only adapter")
                    snap = runtime.snapshot()
                    visual_changes = {name: changed(img, screenshot_viewport(runtime.viewport)) for name, img in saved_images.items()}
                    row = {"trajectory": traj["id"], "step": index, "snapshot": snap,
                           "visual_changes": visual_changes, "evidence": evidence}
                except Exception as exc:
                    try:
                        error_snapshot = runtime.snapshot()
                    except Exception:
                        error_snapshot = None
                    row = {"trajectory": traj["id"], "step": index, "snapshot": error_snapshot,
                           "runtime_error": str(exc), "evidence": f"runtime error: {exc}"}
                trace.write(json.dumps(row, ensure_ascii=False) + "\n")
                trace.flush()


def main() -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--trace", type=Path, default=here / "evidence" / "runtime-trace.jsonl")
    parser.add_argument("--studio", type=Path)
    args = parser.parse_args()
    if sys.platform != "win32":
        raise SystemExit("player_runtime.py requires Windows")
    script = load_json(here / "checkpoint-script.json")
    naming = load_json(here / "naming-tables.json")
    evidence = args.trace.resolve().parent
    evidence.mkdir(parents=True, exist_ok=True)
    # A unique path forces a reused Studio session to load the freshly
    # injected QA copy instead of retaining an older in-memory document that
    # happened to use the same filename.
    run_stamp = f"{time.strftime('%Y%m%d_%H%M%S')}_{os.getpid()}"
    instrumented = evidence / f"PocketGreenhouse.instrumented.{run_stamp}.rbxlx"
    inject_bridge(
        args.game.resolve(), instrumented,
        (here / "roblox_snapshot_bridge.lua").read_text(encoding="utf-8"),
        (here / "roblox_client_snapshot_bridge.lua").read_text(encoding="utf-8"),
    )
    runtime = Runtime((args.studio or find_studio()).resolve(), instrumented, naming, evidence)
    succeeded = False
    # Keep the interactive desktop awake for the full trajectory run.
    ctypes.windll.kernel32.SetThreadExecutionState(0x80000000 | 0x00000001 | 0x00000002)
    try:
        runtime.launch_via_open_dialog(instrumented)
        execute(script, naming, runtime, args.trace.resolve())
        succeeded = True
    except Exception as exc:
        runtime.restore_controller()
        print(f"PLAYER RUNTIME ERROR: {exc}", file=sys.stderr)
        return 2
    finally:
        # Never leave an evaluator-owned editor visible after a failed startup
        # or controller run. Keeping it open makes the next invocation reject
        # the stale QA document as an unrelated visible Studio window.
        runtime.close(keep_window=False)
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
    print(args.trace.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
