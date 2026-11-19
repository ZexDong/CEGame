"""Narrow Windows-only bridge: real SendInput plus visible Studio window discovery."""
import ctypes, os, subprocess, time
from ctypes import wintypes
from pathlib import Path
U=ctypes.windll.user32; K=ctypes.windll.kernel32
VK={'W':0x57,'A':0x41,'S':0x53,'D':0x44,'E':0x45,'Q':0x51,'R':0x52,'SPACE':0x20,'ESC':0x1B,'SHIFT':0x10,'F5':0x74,'F6':0x75,'LBUTTON':0x01,'RBUTTON':0x02}
class KI(ctypes.Structure):_fields_=[('wVk',wintypes.WORD),('wScan',wintypes.WORD),('dwFlags',wintypes.DWORD),('time',wintypes.DWORD),('dwExtraInfo',ctypes.POINTER(ctypes.c_ulong))]
class MI(ctypes.Structure):_fields_=[('dx',wintypes.LONG),('dy',wintypes.LONG),('mouseData',wintypes.DWORD),('dwFlags',wintypes.DWORD),('time',wintypes.DWORD),('dwExtraInfo',ctypes.POINTER(ctypes.c_ulong))]
class IU(ctypes.Union):_fields_=[('ki',KI),('mi',MI)]
class IN(ctypes.Structure):_fields_=[('type',wintypes.DWORD),('u',IU)]
U.SendInput.argtypes=[wintypes.UINT,ctypes.POINTER(IN),ctypes.c_int]
def send_key(v,down):
 x=IN(type=1);x.u.ki=KI(v,0,0 if down else 2,0,None)
 if U.SendInput(1,ctypes.byref(x),ctypes.sizeof(IN))!=1:raise ctypes.WinError()
def input_state():
 """Return the real asynchronous state of every input this bridge can hold."""
 return {k:bool(U.GetAsyncKeyState(v)&0x8000) for k,v in VK.items() if k not in ('F5','F6')}
def terminate_owned_process(pid):
 """Terminate only a PID captured from this run's verified QA main window."""
 h=K.OpenProcess(0x0001,False,int(pid))
 if not h:return False
 try:return bool(K.TerminateProcess(h,3))
 finally:K.CloseHandle(h)
def tap(k,d=.18):
 send_key(VK[k],True)
 try:time.sleep(d)
 finally:send_key(VK[k],False)
 time.sleep(.2)
def hotkey(modifier,k):
 send_key(VK[modifier],True);time.sleep(.06);tap(k);send_key(VK[modifier],False);time.sleep(.2)
def stop_play():hotkey('SHIFT','F5')
def _mouse(flag,dx=0,dy=0):
 x=IN(type=0);x.u.mi=MI(dx,dy,0,flag,0,None)
 if U.SendInput(1,ctypes.byref(x),ctypes.sizeof(IN))!=1:raise ctypes.WinError()
def release_all_inputs():
 """Unconditionally release bridge-owned keys/buttons after focus or prompt changes."""
 before=input_state()
 for k in ('W','A','S','D','E','Q','R','SPACE','SHIFT','ESC'):
  send_key(VK[k],False)
 _mouse(16) # RMB up
 _mouse(4)  # LMB up
 time.sleep(.08)
 return {'before':before,'after':input_state()}
def mouse_drag(dx,dy,d=.28):
 """Hold RMB long enough for the Roblox viewport to lock, then turn in steps."""
 release_all_inputs()
 try:
  _mouse(8);time.sleep(.12)
  steps=10
  for _ in range(steps):
   _mouse(1,int(dx/steps),int(dy/steps));time.sleep(d/steps)
 finally:
  _mouse(16)
 time.sleep(.18)
def _path(pid):
 h=K.OpenProcess(0x1000,False,pid)
 if not h:return ''
 try:
  b=ctypes.create_unicode_buffer(32768);n=wintypes.DWORD(32768)
  return b.value if K.QueryFullProcessImageNameW(h,0,b,ctypes.byref(n)) else ''
 finally:K.CloseHandle(h)
def studio_windows():
 out=[]
 @ctypes.WINFUNCTYPE(ctypes.c_bool,wintypes.HWND,wintypes.LPARAM)
 def cb(h,_):
  if not U.IsWindowVisible(h):return True
  n=U.GetWindowTextLengthW(h);b=ctypes.create_unicode_buffer(n+1);U.GetWindowTextW(h,b,n+1);pid=wintypes.DWORD();U.GetWindowThreadProcessId(h,ctypes.byref(pid));p=_path(pid.value)
  if p.lower().endswith('robloxstudiobeta.exe'):out.append({'hwnd':int(h),'pid':pid.value,'title':b.value,'path':p})
  return True
 U.EnumWindows(cb,0);return out
def find_studio():
 xs=list((Path(os.environ['LOCALAPPDATA'])/'Roblox'/'Versions').glob('version-*/RobloxStudioBeta.exe'))
 if not xs:raise RuntimeError('Roblox Studio executable not found')
 return max(xs,key=lambda x:x.stat().st_mtime)
def choose_window(before,stem,timeout,pid=None):
 end=time.time()+timeout
 while time.time()<end:
  xs=[x for x in studio_windows() if x['hwnd'] not in before and (pid is None or x['pid']==pid)]
  # Prefer the opened place title when available. During authentication Studio
  # first exposes a login/main window whose title does not contain the rbxlx
  # stem, so exact ownership by the newly spawned PID is the safe fallback.
  titled=[x for x in xs if stem.lower() in x['title'].lower()]
  if titled:return titled[-1]
  if pid is not None and xs:return xs[-1]
  time.sleep(.25)
 raise RuntimeError('Studio visible window not discovered')
def focus_live_studio(target,timeout):
 stem=target if isinstance(target,str) else ''
 pid=None if isinstance(target,str) else target.get('pid')
 end=time.time()+timeout
 while time.time()<end:
  xs=[x for x in studio_windows() if (pid is not None and x['pid']==pid) or (stem and stem.lower() in x['title'].lower())]
  if xs:
   h=xs[-1]['hwnd'];U.ShowWindow(h,9);U.BringWindowToTop(h);U.SetForegroundWindow(h);time.sleep(.2);return xs[-1]
  time.sleep(.25)
 raise RuntimeError('QA Studio window no longer exists')
def refresh_window(w):
 """Resolve the current top-level HWND for the verified Studio PID."""
 xs=[x for x in studio_windows() if x['pid']==w.get('pid')]
 if not xs:raise RuntimeError('verified QA Studio PID has no visible window')
 return xs[-1]
def move_cursor_to_window_center(w):
 w=refresh_window(w)
 r=wintypes.RECT();U.GetWindowRect(w['hwnd'],ctypes.byref(r));U.SetCursorPos((r.left+r.right)//2,r.top+(r.bottom-r.top)*55//100);time.sleep(.15)
 return w
def focus_viewport(w):
 """Give the visible Play 3D viewport real foreground mouse focus before SendInput."""
 actual=0
 for attempt in range(1,4):
  release_all_inputs()
  w=refresh_window(w);U.ShowWindow(w['hwnd'],9);U.BringWindowToTop(w['hwnd']);U.SetForegroundWindow(w['hwnd']);time.sleep(.18)
  w=move_cursor_to_window_center(w)
  _mouse(2);time.sleep(.06);_mouse(4);time.sleep(.28)
  pid=wintypes.DWORD();U.GetWindowThreadProcessId(U.GetForegroundWindow(),ctypes.byref(pid));actual=pid.value
  if actual==w['pid']:
   release_all_inputs();return w
  # A notification, WebView, or another application can transiently take the
  # foreground between SetForegroundWindow and the viewport click. Never send
  # gameplay input to it; release everything and retry the verified QA PID.
  release_all_inputs();time.sleep(.35*attempt)
 raise RuntimeError(f'Studio 3D viewport did not retain foreground focus after 3 attempts (qa_pid={w["pid"]}, foreground_pid={actual})')
def find_session_log(folder,stem,started,timeout):
 end=time.time()+timeout
 while time.time()<end:
  # Several Studio instances can be active.  The newest log is not necessarily
  # this QA place, so bind the session to the local-place filename in its command line.
  xs=[]
  for x in folder.glob('*.log'):
   # An old headless Studio helper may keep touching its old log for hours.
   # Bind only to a log file created for this launcher invocation.
   if x.stat().st_ctime<started-5:continue
   try: head=x.open('rb').read(65536).decode('utf-8',errors='replace').lower()
   except OSError:continue
   if stem.lower() in head:xs.append(x)
  if xs:return max(xs,key=lambda x:x.stat().st_mtime)
  time.sleep(.3)
 raise RuntimeError('QA Studio session log for '+stem+' was not found')
def read_new_log_lines(paths,offsets):
 out=[]
 for p in paths:
  with p.open('rb') as f:f.seek(offsets.get(p,0));b=f.read();offsets[p]=f.tell()
  out+=b.decode('utf-8',errors='replace').splitlines()
 return out,offsets
