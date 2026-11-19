// Native task evaluator: ordinary foreground OS events, PID/AX guarded.
// Derived from the existing private desktop transport; no game-state APIs.
import AppKit
import ApplicationServices
import Foundation
import Carbon

let originalInput = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
var inputSelected = false
func useGameKeyboard() throws {
    let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
    guard TISSelectInputSource(ascii) == noErr else { try fail("ASCII_INPUT_SOURCE_UNAVAILABLE") }
    inputSelected = true
}

enum NativeFault: Error { case code(String) }
func fail(_ value: String) throws -> Never { throw NativeFault.code(value) }
func sessionLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String:Any] else { return true }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}
let keys: [String: CGKeyCode] = ["A":0,"D":2,"E":14,"Q":12,"R":15,"Z":6,"Space":49,
    "Enter":36,"Escape":53,"W":13,"S":1,"X":7,"C":8,
    "Up":126,"Down":125,"Left":123,"Right":124,"RightShift":60]

func window(_ pid: Int32) throws -> [String: Any] {
    let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let windows = rows.compactMap { row -> (UInt32, CGRect)? in
        guard (row[kCGWindowOwnerPID as String] as? Int)==Int(pid),
              (row[kCGWindowLayer as String] as? Int)==0,
              let id=row[kCGWindowNumber as String] as? UInt32,
              let raw=row[kCGWindowBounds as String] as? NSDictionary,
              let rect=CGRect(dictionaryRepresentation: raw as CFDictionary), rect.width>200, rect.height>100 else { return nil }
        return (id,rect)
    }.sorted { $0.1.width*$0.1.height > $1.1.width*$1.1.height }
    guard let selected=windows.first else { try fail("WINDOW_NOT_FOUND") }
    return ["window_id":selected.0,"x":Double(selected.1.minX),"y":Double(selected.1.minY),
            "width":Double(selected.1.width),"height":Double(selected.1.height),"pid":pid]
}
func focus(_ pid: Int32, _ activate: Bool) throws {
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.002))
    guard !sessionLocked() else { try fail("MACOS_SESSION_LOCKED") }
    guard CGPreflightPostEventAccess(), AXIsProcessTrusted() else { try fail("ACCESSIBILITY_PERMISSION_REQUIRED") }
    guard let app=NSRunningApplication(processIdentifier:pid), !app.isTerminated else { try fail("PROCESS_EXITED") }
    if activate && !app.isActive {
        guard app.activate(options:[]) else { try fail("ACTIVATION_FAILED") }
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else { try fail("FOREGROUND_LOST") }
    if activate {
        try useGameKeyboard()
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.2))
    }
}
var held = Set<String>()
var heldOwners = [String:Int32]()
func key(_ name: String, _ down: Bool, _ pid: Int32? = nil) throws {
    guard let code=keys[name] else { try fail("KEY_NOT_SUPPORTED") }
    guard let source=CGEventSource(stateID:.hidSystemState),
          let event=CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:down) else { try fail("INPUT_EVENT_FAILED") }
    // The requested controls have no Command/Option/Control chord. Never inherit a user's hotkey.
    var flags: CGEventFlags = ["Up","Down","Left","Right"].contains(name) ? [.maskSecondaryFn,.maskNumericPad] : []
    if (name=="RightShift" && down) || (name != "RightShift" && held.contains("RightShift")) { flags.insert(.maskShift) }
    event.flags = flags
    guard let owner = pid ?? heldOwners[name] else { try fail("KEY_OWNER_MISSING") }
    event.setIntegerValueField(.keyboardEventAutorepeat, value:0)
    if down { try focus(owner, false) }
    event.postToPid(owner)
    if down { held.insert(name);heldOwners[name]=owner }
    else { held.remove(name);heldOwners.removeValue(forKey:name) }
}
func operate(_ request: [String: Any]) throws -> [String: Any] {
    let op=request["op"] as? String ?? ""
    if op=="check" { return ["ok":true,"accessibility":AXIsProcessTrusted(),"input":CGPreflightPostEventAccess(),"screen_recording":CGPreflightScreenCaptureAccess(),"session_locked":sessionLocked(),
        "foreground_pid":Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1),
        "foreground_app":NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"] }
    if op=="release" {
        for name in request["keys"] as? [String] ?? [] { try key(name,false) }
        return ["ok":true]
    }
    guard let pid=request["pid"] as? Int32 else { try fail("PID_REQUIRED") }
    if op=="window" { return ["ok":true].merging(try window(pid)) { _,new in new } }
    if op=="close" {
        guard let app=NSRunningApplication(processIdentifier:pid), app.terminate() else { try fail("TARGET_CLOSE_FAILED") }
        return ["ok":true]
    }
    try focus(pid,request["activate"] as? Bool ?? false)
    if op=="focus" { return ["ok":true] }
    if op=="key" {
        guard let name=request["key"] as? String, let down=request["down"] as? Bool else { try fail("KEY_ARGUMENTS_REQUIRED") }
        try key(name,down,pid)
    } else if op=="click" || op=="drag" {
        let bounds=try window(pid)
        guard let x=request["x"] as? Double, let y=request["y"] as? Double,
              let width=request["width"] as? Double, let height=request["height"] as? Double,
              let wx=bounds["x"] as? Double, let wy=bounds["y"] as? Double,
              let ww=bounds["width"] as? Double, let wh=bounds["height"] as? Double,
              x>=0,y>=0,x<width,y<height,width>0,height>0 else { try fail("CLIENT_GEOMETRY_UNVERIFIED") }
        let content = NSWindow.contentRect(forFrameRect:CGRect(x:0,y:0,width:ww,height:wh),
                                          styleMask:[.titled,.closable,.miniaturizable,.resizable])
        let clientH=Double(content.height)
        guard clientH>0, wh-clientH>=0, wh-clientH<100 else { try fail("CLIENT_GEOMETRY_UNVERIFIED") }
        // v3 targets already include viewport/letterbox offsets in the full client.
        func point(_ lx:Double,_ ly:Double)->CGPoint {
            CGPoint(x:wx+lx/width*ww,
                    y:wy+(wh-clientH)+(1-ly/height)*clientH)
        }
        func verify(_ at:CGPoint) throws {
            try focus(pid,false)
            var element:AXUIElement?
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(at.x),Float(at.y),&element) == .success,
                  let target=element else { try fail("MOUSE_TARGET_UNVERIFIED") }
            var owner:pid_t=0
            guard AXUIElementGetPid(target,&owner) == .success,owner==pid else { try fail("MOUSE_TARGET_OBSTRUCTED") }
        }
        let source=CGEventSource(stateID:.hidSystemState)
        func send(_ type:CGEventType,_ at:CGPoint) throws {
            guard let event=CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:at,mouseButton:.left) else { try fail("MOUSE_EVENT_FAILED") }
            event.flags=[];event.post(tap:.cghidEventTap)
        }
        let from=point(x,y)
        try verify(from)
        try send(.mouseMoved,from);usleep(50_000)
        try verify(from)
        try send(.leftMouseDown,from)
        var last=from
        defer { try? send(.leftMouseUp,last) }
        if op=="drag" {
            guard let ex=request["end_x"] as? Double,let ey=request["end_y"] as? Double,
                  ex>=0,ey>=0,ex<width,ey<height else { try fail("DRAG_END_INVALID") }
            let seconds=request["seconds"] as? Double ?? 0.4
            guard seconds>=0.05,seconds<=5 else { try fail("DRAG_DURATION_INVALID") }
            let target=point(ex,ey),steps=max(4,Int(seconds*60))
            for i in 1...steps {
                last=CGPoint(x:from.x+(target.x-from.x)*Double(i)/Double(steps),
                             y:from.y+(target.y-from.y)*Double(i)/Double(steps))
                try verify(last)
                try send(.leftMouseDragged,last)
                usleep(UInt32(seconds/Double(steps)*1_000_000))
            }
        } else { usleep(80_000) }
    } else { try fail("UNKNOWN_OPERATION") }
    return ["ok":true]
}
while let line=readLine() {
    autoreleasepool {
        let reply:[String:Any]
        do {
            guard let data=line.data(using:.utf8),let request=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { try fail("REQUEST_INVALID") }
            reply=try operate(request)
        } catch {
            let message:String
            if case NativeFault.code(let code)=error { message=code } else { message=String(describing:error) }
            reply=["ok":false,"error":message]
        }
        let data=try! JSONSerialization.data(withJSONObject:reply,options:[.sortedKeys])
        FileHandle.standardOutput.write(data);FileHandle.standardOutput.write(Data([10]))
    }
}
for name in Array(held) { try? key(name,false) }
if inputSelected { TISSelectInputSource(originalInput) }
