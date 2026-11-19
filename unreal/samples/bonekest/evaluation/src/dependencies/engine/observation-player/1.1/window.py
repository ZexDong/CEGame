"""Ordinary host window operations, bound to a launched process ID only."""
import ctypes,time
from ctypes import wintypes as W

class WindowHost:
    def __init__(self,pid):
        self.pid=pid;self.u=ctypes.WinDLL('user32',use_last_error=True)
        # The executor captures physical client pixels. Without per-monitor
        # awareness Windows virtualizes these coordinates at the desktop DPI.
        self.u.SetThreadDpiAwarenessContext.argtypes=[ctypes.c_void_p]
        self.u.SetThreadDpiAwarenessContext.restype=ctypes.c_void_p
        if not self.u.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4)):
            raise OSError(ctypes.get_last_error(),'SetThreadDpiAwarenessContext')
        self.u.GetForegroundWindow.restype=W.HWND
        self.u.SetForegroundWindow.argtypes=[W.HWND]
        self.u.ShowWindow.argtypes=[W.HWND,ctypes.c_int]
        self.u.GetClientRect.argtypes=[W.HWND,ctypes.POINTER(W.RECT)]
        self.u.GetWindowRect.argtypes=[W.HWND,ctypes.POINTER(W.RECT)]
        self.u.GetWindowThreadProcessId.argtypes=[W.HWND,ctypes.POINTER(W.DWORD)]
        self.u.SetWindowPos.argtypes=[W.HWND,W.HWND,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,W.UINT]
        self.u.IsWindowVisible.argtypes=[W.HWND]
        self.hwnd=self.find()
    def find(self):
        windows=[];callback=ctypes.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
        @callback
        def visit(hwnd,_):
            pid=W.DWORD();self.u.GetWindowThreadProcessId(hwnd,ctypes.byref(pid))
            if pid.value==self.pid and self.u.IsWindowVisible(hwnd):
                r=W.RECT();self.u.GetClientRect(hwnd,ctypes.byref(r))
                if r.right-r.left>=320 and r.bottom-r.top>=200:windows.append(((r.right-r.left)*(r.bottom-r.top),hwnd))
            return True
        self.u.EnumWindows(visit,0)
        if not windows:
            from runtime import CandidateError
            raise CandidateError('CANDIDATE_BOUND_CLIENT_NOT_FOUND')
        return max(windows)[1]
    def resize(self,width,height):
        c=W.RECT();r=W.RECT();self.u.GetClientRect(self.hwnd,ctypes.byref(c));self.u.GetWindowRect(self.hwnd,ctypes.byref(r))
        ok=self.u.SetWindowPos(self.hwnd,None,0,0,width+r.right-r.left-c.right,height+r.bottom-r.top-c.bottom,0x0004|0x0010)
        if not ok:raise OSError(ctypes.get_last_error(),'SetWindowPos')
        end=time.perf_counter()+2
        while True:
            self.u.GetClientRect(self.hwnd,ctypes.byref(c))
            if [c.right,c.bottom]==[width,height]:break
            if time.perf_counter()>=end:raise RuntimeError('HOST_PHYSICAL_CLIENT_SIZE_NOT_ESTABLISHED')
            time.sleep(.02)
        return {'process_id':self.pid,'requested':[width,height],'actual':[c.right,c.bottom],'coordinate_units':'physical_pixels','dpi_awareness':'per_monitor_v2','operation':'ordinary_window_resize'}
    def minimize(self):
        # A short-lived ordinary host window provides a real foreground target
        # even on an otherwise empty evaluation desktop. It never handles game
        # input, reads another application, or sends synthetic focus messages.
        self.u.CreateWindowExW.argtypes=[W.DWORD,W.LPCWSTR,W.LPCWSTR,W.DWORD,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,W.HWND,W.HMENU,W.HINSTANCE,W.LPVOID]
        self.u.CreateWindowExW.restype=W.HWND
        self.focus_probe=self.u.CreateWindowExW(0,'STATIC','Evaluation focus probe',0x10CF0000,0,0,320,120,None,None,None,None)
        if not self.focus_probe:raise OSError(ctypes.get_last_error(),'Create focus probe')
        self.activate(self.focus_probe)
        end=time.perf_counter()+1
        while self.u.GetForegroundWindow()==self.hwnd and time.perf_counter()<end:time.sleep(.02)
        focused=self.u.GetForegroundWindow()==self.hwnd
        if focused:raise RuntimeError('HOST_FOCUS_TRANSFER_NOT_CONFIRMED')
        return {'process_id':self.pid,'operation':'ordinary_focus_transfer_to_host_probe','focused':focused}
    def restore(self):
        if getattr(self,'focus_probe',None):
            self.u.DestroyWindow.argtypes=[W.HWND];self.u.DestroyWindow(self.focus_probe);self.focus_probe=None
        self.u.ShowWindow(self.hwnd,9);self.activate(self.hwnd)
        return {'process_id':self.pid,'operation':'ordinary_window_restore','focused':self.u.GetForegroundWindow()==self.hwnd}
    def activate(self,hwnd):
        self.u.AttachThreadInput.argtypes=[W.DWORD,W.DWORD,W.BOOL]
        self.u.BringWindowToTop.argtypes=[W.HWND]
        current=ctypes.WinDLL('kernel32').GetCurrentThreadId();pid=W.DWORD();threads=set()
        for window in [self.u.GetForegroundWindow(),hwnd]:
            if window:
                thread=self.u.GetWindowThreadProcessId(window,ctypes.byref(pid))
                if thread and thread!=current:threads.add(thread)
        attached=[]
        try:
            for thread in threads:
                if self.u.AttachThreadInput(current,thread,True):attached.append(thread)
            self.u.BringWindowToTop(hwnd);self.u.SetForegroundWindow(hwnd)
        finally:
            for thread in attached:self.u.AttachThreadInput(current,thread,False)
