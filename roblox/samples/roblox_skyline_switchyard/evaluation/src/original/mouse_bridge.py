"""Native pointer support for the user-run evaluator; no candidate API calls."""
import ctypes
from ctypes import wintypes
import math
import time
from local_bridge_support import USER32, INPUT, INPUT_MOUSE, MOUSEINPUT, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP

USER32.GetCursorPos.argtypes=[ctypes.POINTER(wintypes.POINT)]
USER32.GetCursorPos.restype=wintypes.BOOL
USER32.SetCursorPos.argtypes=[ctypes.c_int,ctypes.c_int]
USER32.SetCursorPos.restype=wintypes.BOOL
USER32.WindowFromPoint.argtypes=[wintypes.POINT]
USER32.WindowFromPoint.restype=wintypes.HWND
USER32.GetAncestor.argtypes=[wintypes.HWND,wintypes.UINT]
USER32.GetAncestor.restype=wintypes.HWND

def _bounds(window):
    if not USER32.IsWindow(window['hwnd']) or USER32.GetForegroundWindow()!=window['hwnd']:
        raise RuntimeError('QA Studio window no longer owns input')
    rect=wintypes.RECT()
    if not USER32.GetWindowRect(window['hwnd'],ctypes.byref(rect)): raise ctypes.WinError()
    return rect

def _move(window,x,y):
    bounds=_bounds(window)
    if not bounds.left+2 <= x < bounds.right-2 or not bounds.top+30 <= y < bounds.bottom-2:
        raise RuntimeError('Requested HUD pointer position is outside the QA Studio window')
    under=USER32.WindowFromPoint(wintypes.POINT(x,y))
    top=USER32.GetAncestor(under,2) if under else 0
    if top!=window['hwnd']: raise RuntimeError('Pointer target is covered by another window')
    if not USER32.SetCursorPos(x,y): raise ctypes.WinError()

def pointer_home(window):
    bounds=_bounds(window)
    _move(window,(bounds.left+bounds.right)//2,(bounds.top+bounds.bottom)//2)

def pointer_move(window,dx,dy):
    if not all(isinstance(v,(int,float)) and math.isfinite(v) and abs(v)<4096 for v in [dx,dy]):
        raise RuntimeError('Invalid HUD calibration displacement')
    position=wintypes.POINT()
    if not USER32.GetCursorPos(ctypes.byref(position)): raise ctypes.WinError()
    _move(window,position.x+round(dx),position.y+round(dy))

def mouse_click(window):
    position=wintypes.POINT()
    if not USER32.GetCursorPos(ctypes.byref(position)): raise ctypes.WinError()
    _move(window,position.x,position.y)
    def send(flag):
        event=INPUT(type=INPUT_MOUSE)
        event.union.mi=MOUSEINPUT(0,0,0,flag,0,None)
        if USER32.SendInput(1,ctypes.byref(event),ctypes.sizeof(INPUT))!=1: raise ctypes.WinError()
    send(MOUSEEVENTF_LEFTDOWN)
    try: time.sleep(.09)
    finally: send(MOUSEEVENTF_LEFTUP)
