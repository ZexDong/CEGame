"""Windows SendInput bridge for Relay Foundry QA. No candidate state is altered."""
from __future__ import annotations
import argparse, json, os, re, shutil, socket, subprocess, sys, time, traceback
from pathlib import Path
from datetime import datetime, timezone
from bridge_support import VK, find_studio, studio_windows, choose_window, focus_live_studio, find_session_log, read_new_log_lines, tap, stop_play, send_key, mouse_drag, move_cursor_to_window_center, focus_viewport, terminate_owned_process, release_all_inputs, input_state

PREFIX={"command":"RFP_RUNNER_COMMAND ","check":"RFP_RUNNER_CHECK ","done":"RFP_RUNNER_DONE ","observer":"RFP_OBSERVER "}
def parse(line):
 for k,p in PREFIX.items():
  i=line.find(p)
  if i>=0:
   try:return k,json.loads(line[i+len(p):])
   except json.JSONDecodeError:return None
 return None
def sha(p):
 import hashlib; return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def studio_environment():
    """Inherit the operator-configured network environment for Studio."""
    return os.environ.copy()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--qa',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--timeout',type=float,default=3600);ap.add_argument('--debug',action='store_true');ap.add_argument('--startup-smoke',action='store_true');a=ap.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 try:
  if [x for x in studio_windows() if x.get('title','').strip()]:raise RuntimeError('Visible Roblox Studio window exists; refusing to interfere with user Studio.')
  before={x['hwnd'] for x in studio_windows()};started=time.time();studio=find_studio();child_env=studio_environment();print('STATUS: launching isolated QA Studio...',flush=True);studio_process=subprocess.Popen([str(studio),'-task','EditFile','-localPlaceFile',str(a.qa.resolve())],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,env=child_env)
  print('STATUS: waiting at most 45 seconds for a visible QA Studio window...',flush=True)
  try:win=choose_window(before,a.qa.stem,45,pid=studio_process.pid)
  except RuntimeError:
   (out/'STARTUP_RETRYABLE.txt').write_text('Studio created no visible QA main window. No Play or gameplay input occurred.\n',encoding='utf-8')
   raise
  qa_pid=win['pid'];(out/'owned_qa_pid.txt').write_text(str(qa_pid)+'\n',encoding='ascii');print('STATUS: waiting at most 45 seconds for the QA Studio session log...',flush=True);log=find_session_log(Path(os.environ['LOCALAPPDATA'])/'Roblox'/'logs',a.qa.stem,started,45);off={log:0}
  def wait_log_marker(markers,seconds):
   nonlocal off
   end=time.time()+seconds
   while time.time()<end:
    lines,off=read_new_log_lines([log],off)
    if any(any(marker in line for marker in markers) for line in lines):return True
    time.sleep(.08)
   return False
  print('STATUS: waiting up to 180 seconds for login (if required) and OpenPlaceSuccess; no Play input will be sent yet...',flush=True)
  if not wait_log_marker(('State: OpenPlaceSuccess','OpenPlaceSuccess tasks.'),180):raise RuntimeError('QA place did not reach OpenPlaceSuccess after the login/open wait; no Play input was sent.')
  print('STATUS: QA place open; focusing the 3D viewport and starting PlayClient...',flush=True);win=focus_live_studio(win,30);tap('ESC');win=focus_viewport(win);time.sleep(.7);tap('F5');print('STATUS: waiting at most 45 seconds for PlayClient and the passive observer...',flush=True)
  observer_ready=False;ready_data={};startup_targets={};pending=[];saw_playserver=False;saw_playclient=False
  def wait_ready(seconds):
   nonlocal off,observer_ready,ready_data,startup_targets,pending,saw_playserver,saw_playclient
   ready_deadline=time.time()+seconds
   while time.time()<ready_deadline and not observer_ready:
    lines,off=read_new_log_lines([log],off)
    for line in lines:
     if 'StudioGameStateType_PlayServer' in line:saw_playserver=True
     if 'StudioGameStateType_PlayClient' in line:saw_playclient=True
     item=parse(line)
     if item:
      if item[0] in ('command','check','done'):pending.append(item)
      if item[0]=='observer' and item[1].get('kind')=='target':startup_targets[item[1]['key']]=item[1]['record']
      if item[0]=='observer' and item[1].get('kind')=='ready':
       # Do not break this batch: runner checks/commands commonly follow ready
       # in the same file read, whose offset has already advanced to the end.
       observer_ready=True;ready_data=dict(item[1]);ready_data['targets']={**startup_targets,**(item[1].get('targets') or {})}
    time.sleep(.08)
  def wait_stopped(seconds):
   nonlocal off
   stopped_deadline=time.time()+seconds
   while time.time()<stopped_deadline:
    lines,off=read_new_log_lines([log],off)
    if any(('StudioGameStateType_Edit' in line or 'NetworkClient:Destroy' in line or 'Close DataModel' in line) for line in lines):return True
    time.sleep(.08)
   return False
  wait_ready(45)
  if not observer_ready:
   if not saw_playclient:
    print('STATUS: first F5 produced no PlayClient; refocusing and sending one startup-level F5 retry.',flush=True)
    win=focus_live_studio(win,20);tap('ESC');win=focus_viewport(win);time.sleep(.5);tap('F5');pending=[];wait_ready(45)
   else:
    print('STATUS: PlayClient data model existed but never connected; requesting one full Studio startup retry.',flush=True)
  if not observer_ready:
   (out/'STARTUP_RETRYABLE.txt').write_text('No observer/LocalScript readiness. No gameplay checkpoint ran.\n',encoding='utf-8')
   if 'qa_pid' in locals():terminate_owned_process(qa_pid)
   raise RuntimeError('PlayClient did not reach observer readiness; request a fresh Studio startup. This is not a candidate failure.')
  if a.startup_smoke:
   print('STARTUP_SMOKE_PASS: OpenPlaceSuccess, PlayClient, observer ready, and semantic targets confirmed.',flush=True)
   (out/'STARTUP_SMOKE_PASS.txt').write_text('No gameplay scoring occurred.\n',encoding='utf-8');stop_play();wait_stopped(15);shutil.copy2(log,out/'studio_session.log');terminate_owned_process(qa_pid);return
  win=focus_live_studio(win,20);win=focus_viewport(win)
  print(f'STATUS: PlayClient observer ready and 3D viewport focused; beginning formal trajectory ({a.timeout:.0f} second hard limit).',flush=True);deadline=time.time()+a.timeout;events=[];checks={};done=None;targets=ready_data.get('targets') or {};latest_sample=None;visible_prompts=set()
  def record(kind,data):
   nonlocal latest_sample,targets,done,visible_prompts
   events.append({'kind':kind,'at':datetime.now(timezone.utc).isoformat(),**data})
   if kind=='observer':
    if data.get('kind')=='ready':targets={**targets,**(data.get('targets') or {})}
    elif data.get('kind')=='target':targets[data['key']]=data['record']
    elif data.get('kind')=='sample':latest_sample=data
    elif data.get('kind')=='prompt':
     prompt_key=(data.get('key'),data.get('keyboard'))
     if data.get('visible'):visible_prompts.add(prompt_key)
     else:visible_prompts.discard(prompt_key)
   elif kind=='check':
    checks[data['id']]={'status':data['status'],'detail':data['detail']}
    (out/'progress.json').write_text(json.dumps({'checks':checks},ensure_ascii=False,indent=2),encoding='utf-8')
    print('CHECKPOINT: {} = {} — {}'.format(data['id'],data['status'].upper(),data['detail']),flush=True)
   elif kind=='done':done=data
  def drain(seconds=.0):
   nonlocal off,pending
   end=time.time()+seconds
   while True:
    lines,off=read_new_log_lines([log],off)
    for line in lines:
     item=parse(line)
     if item:
      # A new gameplay command can arrive while this function is blocked in a
      # previous navigation. Preserve it for the main dispatcher; never mark a
      # command as observed without actually executing its real input.
      if item[0]=='command':pending.append(item)
      else:record(*item)
    if time.time()>=end:return
    time.sleep(.04)
  def navigate_use(data,win):
   tag=data['tag'];target_record=targets.get(tag)
   if not target_record: raise RuntimeError('observer did not provide unique semantic target '+tag)
   target=target_record.get('position',target_record);size=target_record.get('size',{'x':0,'z':0})
   # Long cross-map routes need enough time to traverse at normal character
   # speed. Collision recovery below handles walls/station geometry without
   # using any world-coordinate route.
   release_report=release_all_inputs();record('input_diagnostic',{'stage':'navigation_start','tag':tag,**release_report})
   until=time.time()+75;arrived=False;stagnant=0;escape_side='A';input_silent=0;approach=None
   while time.time()<until:
    drain(.28)
    s=latest_sample
    if not s or not s.get('camera'):continue
    px,pz=s['p']['x'],s['p']['z']
    if data.get('key') and approach is None:
     # Prompts live at the part centre, but large solid parts cannot be entered.
     # Approach the shorter semantic face, derived from live size and current
     # relative side, so the prompt is reachable without absolute coordinates.
     hx=float(size.get('x',0))/2;hz=float(size.get('z',0))/2;clearance=.8
     if hz<=hx:
      sign=1 if pz>=target['z'] else -1;approach={'x':target['x'],'z':target['z']+sign*(hz+clearance)}
     else:
      sign=1 if px>=target['x'] else -1;approach={'x':target['x']+sign*(hx+clearance),'z':target['z']}
     record('input_diagnostic',{'stage':'prompt_approach_selected','tag':tag,'axis':'z' if hz<=hx else 'x','clearance':clearance})
    nav=approach or target;dx,dz=nav['x']-px,nav['z']-pz
    if data.get('key'):
     # Reach the selected semantic face before pressing the prompt key.  Merely
     # entering the outer edge of MaxActivationDistance proved too marginal:
     # the character could be 9.2 studs from a 10-stud prompt and E would still
     # occasionally be rejected.  The face point is derived from live size and
     # relative position, so this remains layout-independent.  A 2.75-stud
     # tolerance accounts for the HumanoidRootPart/capsule being unable to sit
     # at the 0.8-stud face clearance itself.
     dist=(dx*dx+dz*dz)**.5;arrival_limit=float(data.get('approach_tolerance',2.75))
    elif data.get('surface_distance'):
     gx=max(abs(dx)-float(size.get('x',0))/2,0);gz=max(abs(dz)-float(size.get('z',0))/2,0);dist=(gx*gx+gz*gz)**.5
     arrival_limit=float(data.get('arrival_distance',.8))
    else:dist=(dx*dx+dz*dz)**.5;arrival_limit=float(data.get('arrival_distance',7.5))
    prompt_ready=(tag,data.get('key')) in visible_prompts if data.get('key') else True
    if dist<=arrival_limit and prompt_ready:arrived=True;break
    math=__import__('math');length=max((dx*dx+dz*dz)**.5,.001);ux,uz=dx/length,dz/length
    # Express the desired world direction in the live camera basis. Roblox
    # movement accepts simultaneous forward/back and strafe keys, so semantic
    # navigation must not depend on RMB camera rotation succeeding.
    cx,cz=s['camera']['x'],s['camera']['z'];cl=max((cx*cx+cz*cz)**.5,.001);cx,cz=cx/cl,cz/cl
    forward=ux*cx+uz*cz;right=ux*(-cz)+uz*cx
    win=focus_live_studio(win,10);win=focus_viewport(win)
    primary='W' if forward>=0 else 'S';lateral='D' if right>=0 else 'A'
    keys=[primary]
    if abs(right)>.22:keys.append(lateral)
    before=(px,pz)
    # Full 0.65-second strides are useful across the map but overshoot a
    # prompt-face target when only a few studs remain. Scale the real key hold
    # by the remaining gap so the controller converges instead of oscillating
    # across the semantic face.
    walk_seconds=min(.65,max(.12,(dist-arrival_limit)/18.0))
    try:
      for key in keys:send_key(VK[key],True)
      time.sleep(walk_seconds)
    finally:
     for key in keys:send_key(VK[key],False)
    drain(.45)
    after=latest_sample.get('p') if latest_sample else None
    moved=((after['x']-before[0])**2+(after['z']-before[1])**2)**.5 if after else 0
    stagnant=stagnant+1 if moved<.35 else 0
    if stagnant>=2:
     # Jump plus alternating strafe provides a real-input wall/corner escape.
     win=focus_live_studio(win,10);win=focus_viewport(win)
     tap('SPACE')
     try:
      send_key(VK[escape_side],True);send_key(VK['S'],True);time.sleep(.85)
     finally:
      send_key(VK[escape_side],False);send_key(VK['S'],False)
     escape_side='D' if escape_side=='A' else 'A';stagnant=0;drain(.5)
   if arrived:
    win=focus_live_studio(win,10);win=focus_viewport(win)
    if data.get('key'):
     observed=('RFP_EventSerial','RFP_FeedbackText','RFP_CorePhase','RFP_ChargeMode','RFP_StabilizeMode','RFP_EncodeMode','RFP_DeliveredCount','RFP_Powered','RFP_Completed')
     def signature():
      state=(latest_sample or {}).get('state') or {};return tuple(state.get(k) for k in observed)
     before_signature=signature();accepted=False
     for attempt in range(1,4):
      # Candidate prompts require a 0.1-second hold. A 0.24-second OS hold can
      # cross the shortest Windows repeat threshold and fire the same prompt
      # twice (Processed.Charge immediately followed by WrongPhase). PromptShown
      # now proves proximity, so 0.16 seconds is sufficient and single-fire.
      tap(data['key'],.16);drain(1.0)
      after_signature=signature()
      if after_signature!=before_signature:
       accepted=True;break
      if attempt<3:
       record('input_diagnostic',{'stage':'prompt_input_retry','tag':tag,'key':data['key'],'attempt':attempt+1})
       win=focus_live_studio(win,10);win=focus_viewport(win)
     record('input_diagnostic',{'stage':'prompt_input_result','tag':tag,'key':data['key'],'accepted_by_public_state':accepted})
    elif data.get('surface_distance'):
     try:send_key(VK['W'],True);time.sleep(.3)
     finally:send_key(VK['W'],False)
    drain(.8)
   release_report=release_all_inputs();record('input_diagnostic',{'stage':'navigation_end','tag':tag,'arrived':arrived,**release_report})
   print('STATUS: semantic navigation {} ({}).'.format('arrived and interacted' if arrived else 'timed out',tag),flush=True)
  # A debug run proves the Windows closed loop itself.  Do not depend on a
  # Studio-log command hand-off that is deliberately absent from formal scoring.
  if a.debug:
   print('STATUS: debug controller received RFP_CoreDock target; waiting for first player sample.',flush=True)
   # Discard only the runner's initial CoreDock command because this debug
   # branch executes that first probe directly. Commands emitted while the
   # probe is running (notably the follow-up Stabilize route) must remain queued.
   pending=[]
   # The public ProximityPrompt declares a 10-stud activation range; leave a
   # conservative 0.5-stud tolerance rather than requiring the part centre.
   navigate_use({'tag':'RFP_CoreDock','key':'E','arrival_distance':9.5},win)
   release_report=release_all_inputs();record('input_diagnostic',{'stage':'after_core_dock','tag':'RFP_CoreDock',**release_report})
  while time.time()<deadline and done is None:
   lines,off=read_new_log_lines([log],off)
   parsed=[x for x in (parse(line) for line in lines) if x]
   if pending: parsed=pending+parsed;pending=[]
   for v in parsed:
    kind,data=v;record(kind,data)
    if kind=='command':
     if a.debug and data.get('tag')=='RFP_CoreDock':
      record('input_diagnostic',{'stage':'duplicate_debug_command_ignored','tag':'RFP_CoreDock','seq':data.get('seq')})
      continue
     win=focus_live_studio(win,20);win=focus_viewport(win);act=data['action']
     if act=='tap':tap(data['key'])
     elif act in ('navigate_use','navigate'): navigate_use(data,win)
     elif act=='turn_walk':
      move_cursor_to_window_center(win);mouse_drag(int(max(-420,min(420,data['yaw']*170))),0,.28);send_key(VK['W'],True);time.sleep(float(data['seconds']));send_key(VK['W'],False)
     elif act=='turn':
      move_cursor_to_window_center(win);mouse_drag(int(max(-140,min(140,data['yaw']*55))),0,.20)
     elif act=='walk':
      move_cursor_to_window_center(win);send_key(VK['W'],True);time.sleep(float(data['seconds']));send_key(VK['W'],False)
     else:raise RuntimeError('unsupported engine command '+act)
   time.sleep(.02)
  release_all_inputs()
  stop_play();wait_stopped(15);shutil.copy2(log,out/'studio_session.log');(out/'engine_events.jsonl').write_text(''.join(json.dumps(x,ensure_ascii=False)+'\n' for x in events),encoding='utf-8')
  static_path=Path(__file__).parent.parent/'results'/'static_audit.json'
  static_checks=json.loads(static_path.read_text(encoding='utf-8')).get('checks',{}) if static_path.exists() else {}
  # This marker was established before F5/player input in the current launcher,
  # so it is the D1 engine-open smoke rather than a D2-D5 gameplay observation.
  static_checks={**static_checks,'engine_open_smoke':{'status':'pass','detail':'QA build reached Studio OpenPlaceSuccess before Play input.'}}
  evidence={'runner_status':'completed' if done and done.get('status')=='completed' else 'aborted','host_fault':None if done and done.get('status')=='completed' else 'incomplete PlayClient trajectory','candidate_qa_sha256':sha(a.qa),'static_checks':static_checks,'checks':checks,'input_backend':'Windows SendInput','policy':{'teleports':0,'direct_state_mutations':0,'business_calls':0,'screenshots_or_llm_for_play_scoring':False,'absolute_coordinates':0}}
  evidencePath=out/'evidence.json';evidencePath.write_text(json.dumps(evidence,ensure_ascii=False,indent=2),encoding='utf-8')
  if a.debug:
   (out/'INVALID_DEBUG_RUN.txt').write_text('Controller diagnostic only. This run is excluded from any candidate score.\n',encoding='utf-8')
   print('DEBUG RESULT: excluded from formal scoring; inspect evidence.json.',flush=True)
  else:
   subprocess.run([sys.executable,str(Path(__file__).with_name('score_evidence.py')),'--evidence',str(evidencePath),'--output',str(out/'score.json')],check=True)
   scored=json.loads((out/'score.json').read_text(encoding='utf-8'))
   if scored.get('score_status')=='invalid_controller_run':raise RuntimeError('scoring rejected this trajectory as an invalid controller run')
  if evidence['runner_status']!='completed':raise RuntimeError(evidence['host_fault'])
  # The QA Studio belongs to this invocation (PID captured from its verified
  # new main window). Close only that exact process after all evidence is safe.
  terminate_owned_process(qa_pid)
 except Exception:
  # Only clean up the exact process handle created by this evaluator. Never
  # enumerate or terminate unrelated user/helper Studio processes.
  try:
   if 'studio_process' in locals() and studio_process.poll() is None:studio_process.terminate()
  except Exception:pass
  try:
   if 'qa_pid' in locals():terminate_owned_process(qa_pid)
  except Exception:pass
  try:
   if 'log' in locals() and Path(log).exists():shutil.copy2(log,out/'studio_session.log')
  except Exception:pass
  (out/'bridge_error.txt').write_text(traceback.format_exc(),encoding='utf-8');raise
if __name__=='__main__':main()
