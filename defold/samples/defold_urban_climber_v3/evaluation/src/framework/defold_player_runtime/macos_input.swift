import AppKit
import ApplicationServices
import Darwin
import Foundation

let keyCodes: [String: CGKeyCode] = [
    "UpArrow": 126,
    "DownArrow": 125,
    "LeftArrow": 123,
    "RightArrow": 124,
    "Space": 49,
    "Enter": 36,
    "Escape": 53,
    "W": 13,
    "A": 0,
    "S": 1,
    "D": 2,
    "R": 15,
    "Q": 12,
    "X": 7,
]

func fail(_ message: String, _ code: Int32 = 1) -> Never {
    fputs(message + "\n", stderr)
    exit(code)
}

func requireEventAccess() {
    guard CGPreflightPostEventAccess() else {
        fail("normal keyboard/mouse event access is unavailable", 2)
    }
    guard AXIsProcessTrusted() else {
        fail("accessibility hit-testing access is unavailable", 2)
    }
}

func activate(_ pid: pid_t) {
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        fail("no running application for pid \(pid)")
    }
    if app.isActive {
        return
    }
    guard app.activate(options: []) else {
        fail("could not activate application pid \(pid)")
    }
    usleep(120_000)
}

func requireFocus(_ pid: pid_t) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        fail("game lost foreground focus before input", 2)
    }
}

func ownsPoint(_ pid: pid_t, _ point: CGPoint) -> Bool {
    var element: AXUIElement?
    let status = AXUIElementCopyElementAtPosition(
        AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element
    )
    guard status == .success, let element else {
        fail("could not verify mouse destination (AX error \(status.rawValue))", 2)
    }
    var owner: pid_t = 0
    guard AXUIElementGetPid(element, &owner) == .success else {
        fail("could not identify mouse destination owner", 2)
    }
    return owner == pid
}

func exposedClickPoint(_ pid: pid_t, _ rect: CGRect) -> CGPoint {
    // Prefer the centre, then inspect interior points of the same public target.
    // AX hit-testing accounts for click-through windows; CGWindow bounds alone do not.
    for fractionY in [0.5, 0.25, 0.75] {
        for fractionX in [0.5, 0.25, 0.75] {
            let point = CGPoint(
                x: rect.minX + rect.width * fractionX,
                y: rect.minY + rect.height * fractionY
            )
            if ownsPoint(pid, point) { return point }
        }
    }
    fail("mouse target is obstructed: no verified game-owned click point", 2)
}

func eventSource() -> CGEventSource {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        fail("failed to create HID event source")
    }
    return source
}

func setKey(_ source: CGEventSource, _ keyCode: CGKeyCode, down: Bool) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
        fail("failed to create keyboard event")
    }
    event.post(tap: .cghidEventTap)
}

func windowBounds(_ pid: pid_t) -> CGRect {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let rows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        fail("could not enumerate windows")
    }
    var best: CGRect?
    for row in rows {
        guard
            let owner = row[kCGWindowOwnerPID as String] as? Int,
            owner == Int(pid),
            let layer = row[kCGWindowLayer as String] as? Int,
            layer == 0,
            let rawBoundsValue = row[kCGWindowBounds as String]
        else {
            continue
        }
        let rawBounds = rawBoundsValue as! NSDictionary
        guard let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else {
            continue
        }
        if best == nil || bounds.width * bounds.height > best!.width * best!.height {
            best = bounds
        }
    }
    guard let result = best else {
        fail("no visible layer-zero window for pid \(pid)")
    }
    return result
}

func postMouse(_ source: CGEventSource, type: CGEventType, point: CGPoint, button: CGMouseButton) {
    guard let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: button
    ) else {
        fail("failed to create mouse event")
    }
    event.post(tap: .cghidEventTap)
}

let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "--check" {
    requireEventAccess()
    print("macOS normal input and accessibility hit-testing access: available")
    exit(0)
}

if arguments.count == 2 && arguments[1] == "--keys" {
    for name in keyCodes.keys.sorted() {
        print(name)
    }
    exit(0)
}

guard arguments.count >= 5, let rawPid = Int32(arguments[1]) else {
    fail(
        "usage: macos_input --check | --keys | PID key KEY press | PID key KEY hold SECONDS | " +
        "PID dual_hold KEY1 KEY2 SECONDS | " +
        "PID click LEFT BOTTOM WIDTH HEIGHT VIEW_WIDTH VIEW_HEIGHT",
        64
    )
}

let pid = pid_t(rawPid)
let command = arguments[2]
requireEventAccess()
activate(pid)
requireFocus(pid)
let source = eventSource()

if command == "key" {
    let keyName = arguments[3]
    let mode = arguments[4]
    guard let keyCode = keyCodes[keyName] else {
        fail("unknown key \(keyName)", 64)
    }
    if mode == "press" {
        setKey(source, keyCode, down: true)
        // Keep a tap down across several 60 Hz frames so continuous movement
        // games cannot receive press and release in the same update tick.
        usleep(80_000)
        setKey(source, keyCode, down: false)
    } else if mode == "hold" {
        guard arguments.count == 6, let seconds = Double(arguments[5]), seconds >= 0 else {
            fail("hold requires a non-negative duration", 64)
        }
        setKey(source, keyCode, down: true)
        usleep(useconds_t(seconds * 1_000_000))
        setKey(source, keyCode, down: false)
    } else {
        fail("key mode must be press or hold", 64)
    }
} else if command == "dual_hold" {
    guard
        arguments.count == 6,
        let firstCode = keyCodes[arguments[3]],
        let secondCode = keyCodes[arguments[4]],
        firstCode != secondCode,
        let seconds = Double(arguments[5]),
        seconds >= 0
    else {
        fail("dual_hold requires two distinct known keys and a non-negative duration", 64)
    }
    setKey(source, firstCode, down: true)
    setKey(source, secondCode, down: true)
    usleep(useconds_t(seconds * 1_000_000))
    setKey(source, secondCode, down: false)
    setKey(source, firstCode, down: false)
} else if command == "click" {
    guard
        arguments.count == 9,
        let localX = Double(arguments[3]),
        let localY = Double(arguments[4]),
        let width = Double(arguments[5]),
        let height = Double(arguments[6]),
        let viewWidth = Double(arguments[7]),
        let viewHeight = Double(arguments[8]),
        [localX, localY, width, height, viewWidth, viewHeight].allSatisfy({ $0.isFinite }),
        width > 0,
        height > 0,
        viewWidth > 0,
        viewHeight > 0,
        localX >= 0,
        localX + width <= viewWidth,
        localY >= 0,
        localY + height <= viewHeight
    else {
        fail("click requires a positive target rectangle inside the game view", 64)
    }
    let bounds = windowBounds(pid)
    // Defold preserves the configured game-view aspect ratio in its content area.  CGWindow
    // bounds include the title bar at the top, while the content and game origin share the
    // frame's bottom edge.  Width therefore gives the stable view-to-window scale without
    // guessing a title-bar height or assuming a 1:1 Retina scale.
    let scale = bounds.width / viewWidth
    guard viewHeight * scale <= bounds.height + 2 else {
        fail("game-view aspect ratio does not fit the current window")
    }
    let targetRect = CGRect(
        x: bounds.minX + localX * scale,
        y: bounds.maxY - (localY + height) * scale,
        width: width * scale,
        height: height * scale
    )
    let globalPoint = exposedClickPoint(pid, targetRect)
    postMouse(source, type: .mouseMoved, point: globalPoint, button: .left)
    usleep(20_000)
    requireFocus(pid)
    guard ownsPoint(pid, globalPoint) else {
        fail("mouse target became obstructed before press", 2)
    }
    postMouse(source, type: .leftMouseDown, point: globalPoint, button: .left)
    usleep(35_000)
    postMouse(source, type: .leftMouseUp, point: globalPoint, button: .left)
    // Exit buttons may terminate the process immediately on release.
    if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
        requireFocus(pid)
    }
} else {
    fail("command must be key, dual_hold, or click", 64)
}
