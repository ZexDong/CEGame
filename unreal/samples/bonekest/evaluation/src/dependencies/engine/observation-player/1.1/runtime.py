"""Versioned normal-input player, independent of game and candidate architecture.

The only observation is a public, read-only atomic JSON snapshot. No engine reflection, candidate object names or game-specific commands.
"""
from __future__ import annotations
import contextlib
import hashlib
import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path

VERSION = '1.1.1-bounded-observation'
GENERATED = {'.git','.vs','Binaries','Intermediate','Saved','DerivedDataCache','__pycache__'}
INPUT_OPERATIONS={'press','down','up','mouse_down','mouse_up','click','move','drag','mouse_chord'}

def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'),parse_constant=lambda s:(_ for _ in ()).throw(ValueError('NONFINITE_JSON')))

def write(path, value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def identity(root):
    root=Path(root).resolve();rows=[]
    if root.is_dir():
        for parent,dirs,files in os.walk(root):
            dirs[:]=sorted(d for d in dirs if d not in GENERATED)
            for name in dirs+files:
                p=Path(parent)/name
                if p.is_symlink() or not p.resolve().is_relative_to(root):raise CandidateError('CANDIDATE_PATH_ESCAPE')
            for name in sorted(files):
                p=Path(parent)/name;rows.append({'path':p.relative_to(root).as_posix(),'size':p.stat().st_size,'sha256':sha(p)})
    rows.sort(key=lambda x:x['path'])
    return {'sha256':hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'files':rows}

class CandidateError(RuntimeError): pass
class InfrastructureError(RuntimeError): pass

def completed_exit_cleanup(receipt,expected_exit=False):
    """A dead candidate is distinct from a failed host cleanup operation."""
    result=receipt.get('result') or {};code=(receipt.get('fault') or {}).get('code')
    if code!='target_exited_before_stop':return None
    if not (result.get('process_exited') and result.get('job_handle_closed') and result.get('input_lease_released') and result.get('input_cleanup',{}).get('all_released') and result.get('job_active_process_count_after_wait')==0):return None
    return {'status':'ok','result':result,'expected_player_quit':expected_exit,'unexpected_candidate_exit':not expected_exit,'original_executor_status':receipt['status'],'original_fault_code':code}

class Dashboard:
    """Atomic snapshot transport. Every record is bound to the launched PID."""
    def __init__(self,path):self.path=Path(path);self.expected_pid=None;self.starting=True;self.reset()
    def reset(self):self.latest=None;self.revision=0;self.records=[];self.record_times=[];self.bad_since=None;self.starting=True
    def read(self):
        if not self.path.exists():
            if self.latest and not self.starting and time.perf_counter()-self.record_times[-1]>1:raise CandidateError('OBSERVATION_MISSING')
            return self.latest
        now=time.perf_counter()
        try:
            s=load(self.path); modified=self.path.stat().st_mtime
        except (PermissionError,OSError,json.JSONDecodeError) as error:
            if self.bad_since is None:self.bad_since=now
            if now-self.bad_since>1:raise CandidateError('OBSERVATION_IO_OR_MALFORMED') from error
            return self.latest
        self.bad_since=None
        if not isinstance(s,dict):raise CandidateError('OBSERVATION_NOT_OBJECT')
        if self.expected_pid is None or s.get('process_id')!=self.expected_pid:return None
        rev=s.get('snapshot_id')
        if type(rev) is not int or rev<1:raise CandidateError('OBSERVATION_SEQUENCE')
        if time.time()-modified>1:
            if self.starting:return None
            raise CandidateError('OBSERVATION_STALE')
        if self.latest and s.get('session_id')!=self.latest.get('session_id'):raise CandidateError('OBSERVATION_SESSION_CHANGED')
        if rev<self.revision:raise CandidateError('OBSERVATION_SEQUENCE_REGRESSION')
        if rev>self.revision:
            self.latest=s;self.revision=rev;self.records.append(s);self.record_times.append(now)
        return self.latest

class Player:
    def __init__(self,repo,project,engine,root,width=1280,height=720,pwsh='pwsh',serial_limit=18000):
        self.repo=Path(repo).resolve();self.project=Path(project).resolve();self.engine=Path(engine).resolve();self.root=Path(root).resolve()
        self.root.mkdir(parents=True,exist_ok=False)
        self.width,self.height=width,height;self.dashboard_path=self.root/'observation.json';self.stream=Dashboard(self.dashboard_path)
        self.process_id=None;self.process_token=None;self.actions=[];self.samples=[];self.held=set();self.number=0;self.case='bootstrap';self.fault=None;self.sample_cursor=0;self.expected_exit=False
        self.start_time=time.perf_counter();self.serial_limit=serial_limit;self.lock=threading.RLock();self.stop_event=threading.Event()
        self.rpc_lock=threading.RLock()
        write(self.root/'clock.json',{'clock':'QPC/perf_counter','origin_seconds':self.start_time,'resolution_seconds':time.get_clock_info('perf_counter').resolution})
        self.process=subprocess.Popen([pwsh,'-NoProfile','-File',str(Path(__file__).with_name('PlayerHost.ps1')),'-ExecutorPath',str(self.repo/'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1)
        self.messages=queue.Queue()
        def reader():
            for line in self.process.stdout:
                if line.startswith('@@'):
                    try:self.messages.put(json.loads(line[2:]))
                    except Exception as e:self.messages.put({'status':'transport_error','error':str(e)})
        threading.Thread(target=reader,daemon=True).start()
        self.sampler=threading.Thread(target=self._sample,daemon=True);self.sampler.start()
    def _sample(self):
        while not self.stop_event.wait(.02):
            try:
                with self.lock:
                    if not self.process_id:continue
                    s=self.stream.read()
                    added=False
                    # Retain every complete public record. Sampling only the
                    # latest record loses one-frame projectile/impact events.
                    for i in range(self.sample_cursor,len(self.stream.records)):
                        self.record_sample({'time':self.stream.record_times[i]-self.start_time,'pid':self.process_id,'case':self.case,'state':self.stream.records[i],'timestamp_kind':'external_read_batch'})
                        added=True
                    self.sample_cursor=len(self.stream.records)
                    if self.sample_cursor>2000:
                        self.stream.records=self.stream.records[-1000:];self.stream.record_times=self.stream.record_times[-1000:];self.sample_cursor=1000
                    if s and not added:self.record_sample({'time':time.perf_counter()-self.start_time,'pid':self.process_id,'case':self.case,'state':s,'timestamp_kind':'unchanged_observation'})
            except Exception as e:self.fault=e
    def record_sample(self,row):
        if row['timestamp_kind']=='unchanged_observation':return
        self.samples.append(row)
        if len(self.samples)>3000:del self.samples[:1000]
        with (self.root/'samples-stream.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(row,separators=(',',':'))+'\n')
    def rpc(self,op,**args):
        with self.rpc_lock:return self._rpc(op,**args)
    def set_case_budget(self,name,seconds,actions):
        self.case_budget={'name':name,'deadline':time.perf_counter()+seconds,'max_actions':actions,'action_start':len(self.actions)}
    def check_case_budget(self,operation=None):
        budget=getattr(self,'case_budget',None)
        if not budget or operation in ['up','mouse_up','stop','acknowledge_focus_release']:return
        if time.perf_counter()>budget['deadline']:raise InfrastructureError('CASE_SERIAL_BUDGET:'+budget['name'])
        used=sum(r['operation'] in INPUT_OPERATIONS for r in self.actions[budget['action_start']:])
        if operation in INPUT_OPERATIONS and used>=budget['max_actions']:raise InfrastructureError('CASE_INPUT_BUDGET:'+budget['name'])
    def _rpc(self,op,**args):
        self.check_case_budget(op)
        if time.perf_counter()-self.start_time>self.serial_limit:raise InfrastructureError('SESSION_WATCHDOG')
        self.number+=1;start=time.perf_counter()-self.start_time
        self.process.stdin.write(json.dumps({'op':op,**args})+'\n');self.process.stdin.flush()
        try:r=self.messages.get(timeout=150 if op in ['start','reopen'] else 25 if op=='stop' else 15)
        except queue.Empty as e:raise InfrastructureError('PLAYER_RPC_TIMEOUT:'+op) from e
        receipt={'operation':op,'parameters':{k:v for k,v in args.items() if k not in ['project','engine','root','dashboard','userdir','path']},'started':start,'ended':time.perf_counter()-self.start_time,'case':self.case,'result':r}
        self.actions.append(receipt);write(self.root/f'receipts/{self.number:05}-{op}.json',receipt)
        if r.get('status')!='ok':
            code=r.get('fault',{}).get('code',r.get('status','UNKNOWN'))
            normalized=completed_exit_cleanup(r,self.expected_exit) if op=='stop' else None
            if normalized:
                # Preserve abnormal candidate exit while recognizing the
                # independently confirmed process/input cleanup success.
                write(self.root/f'exit-cleanup-{self.number:05}.json',normalized);return normalized
            if code in ['PROCESS_EXITED','TARGET_PROCESS_EXITED','TARGET_WINDOW_INVALID','start_window_timeout','start_process_exited','START_WINDOW_TIMEOUT']:
                raise CandidateError('CANDIDATE_RUNTIME:'+code)
            raise InfrastructureError('EXECUTOR:'+code)
        return r
    def start(self,require_dashboard=True):
        self.expected_exit=False
        started=time.perf_counter()
        while True:
            try:
                r=self.rpc('start',project=str(self.project),engine=str(self.engine),root=str(self.root),dashboard=str(self.dashboard_path),userdir=str(self.root/'userdata'),width=self.width,height=self.height)
                break
            except InfrastructureError as e:
                if str(e)!='EXECUTOR:active_input_session_exists' or time.perf_counter()-started>=6:raise
                # The executor refused before launching any game. Preserve every
                # failure receipt and wait briefly; never remove or bypass its lock.
                self.stop_event.wait(.5)
        self.process_id=r['result']['process_id'];self.process_token=r['result'].get('process_token');self.stream.expected_pid=self.process_id
        from window import WindowHost
        placement=WindowHost(self.process_id).restore()
        write(self.root/f'window-start-{self.process_id}.json',placement)
        if require_dashboard:self.wait(lambda s:bool(s) and s.get('snapshot_id',0)>1,30,stable=2)
        self.stream.starting=False
        return r
    def state(self):
        self.check_case_budget()
        if self.fault:raise self.fault
        with self.lock:
            s=self.stream.read()
            if s is None:raise CandidateError('DASHBOARD_NO_COMPLETE_RECORD')
            return s
    def wait(self,predicate,seconds=3,stable=0,reason='CONDITION_TIMEOUT'):
        started=time.perf_counter();since=None
        while time.perf_counter()-started<=seconds:
            try:s=self.state()
            except CandidateError as e:
                if str(e)!='DASHBOARD_NO_COMPLETE_RECORD':raise
                self.stop_event.wait(.02);continue
            if predicate(s):
                if since is None:since=time.perf_counter()
                if time.perf_counter()-since>=stable:return s
            else:since=None
            self.stop_event.wait(.02)
        raise CandidateError(reason)
    def observe(self,seconds):
        end=time.perf_counter()+seconds
        while time.perf_counter()<end:self.state();self.stop_event.wait(min(.02,max(0,end-time.perf_counter())))
        return self.state()
    def target(self,kind):
        items=[x for x in self.state()['targets'] if x.get('kind')==kind and x.get('visible') is True and x.get('interactable') is True]
        if len(items)!=1:raise CandidateError('VISIBLE_TARGET_UNAVAILABLE:'+kind)
        r=items[0].get('rect')
        if not isinstance(r,list) or len(r)!=4 or r[2]<=0 or r[3]<=0:raise CandidateError('TARGET_RECT_INVALID')
        return items[0]
    def click_target(self,kind):
        r=self.target(kind)['rect'];return self.rpc('click',x=r[0]+r[2]/2,y=r[1]+r[3]/2,button='Left',ms=100)
    def click_entity(self,entity,button='Left'):
        r=entity.get('rect')
        if not r:raise CandidateError('ENTITY_NOT_VISIBLE')
        return self.rpc('click',x=r[0]+r[2]/2,y=r[1]+r[3]/2,button=button,ms=25)
    def press(self,key,ms=40):return self.rpc('press',key=key,ms=ms)
    def hold(self,keys,seconds):
        with self.holding(keys):self.observe(seconds)
    @contextlib.contextmanager
    def holding(self,keys):
        try:
            for key in keys:self.rpc('down',key=key);self.held.add(key)
            yield
        finally:
            for key in list(self.held):self.rpc('up',key=key);self.held.discard(key)
    def capture(self,label,require_dashboard=True):
        before=self.state() if require_dashboard else None;path=self.root/f'captures/{label}.png';path.parent.mkdir(exist_ok=True)
        if path.exists():raise InfrastructureError('CAPTURE_REUSE_WITHOUT_IDENTITY')
        started=time.perf_counter()
        while True:
            try:result=self.rpc('capture',path=str(path),id=label);break
            except InfrastructureError as e:
                if str(e)!='EXECUTOR:client_capture_environment_unavailable' or time.perf_counter()-started>3:raise
                from window import WindowHost
                write(self.root/f'capture-recovery-{self.number:05}.json',WindowHost(self.process_id).restore())
                if require_dashboard:self.observe(.1)
                else:self.stop_event.wait(.1)
        after=self.state() if require_dashboard else None
        record={'path':path.relative_to(self.root).as_posix(),'sha256':sha(path),'before':before,'after':after,'pid':self.process_id,'receipt':result,'time':time.perf_counter()-self.start_time}
        write(path.with_suffix('.json'),record);return record
    def reopen(self):
        with self.lock:
            oldpid=self.process_id;stopped=self.rpc('stop');self.process_id=None;self.stream.expected_pid=None
            if stopped.get('unexpected_candidate_exit'):raise CandidateError('CANDIDATE_EXITED_BEFORE_REOPEN')
            if self.dashboard_path.exists():self.dashboard_path.rename(self.root/f'dashboard-process-{oldpid}.jsonl')
            self.stream.reset();self.sample_cursor=0;self.fault=None
        r=self.start()
        write(self.root/f'reopen-{oldpid}.json',{'old_pid':oldpid,'new_pid':self.process_id,'normal_stop':True,'new_process':oldpid!=self.process_id})
        return r
    @contextlib.contextmanager
    def clip(self,label,seconds=30,fps=8):
        stop=threading.Event();frames=[];fault=[];deadline=time.perf_counter()+seconds
        def record():
            index=0
            while not stop.is_set() and time.perf_counter()<deadline:
                started=time.perf_counter()
                try:
                    frames.append(self.capture(f'clip-{label}-{index:04}'));index+=1
                except Exception as error:fault.append(error);return
                stop.wait(max(0,1/fps-(time.perf_counter()-started)))
        thread=threading.Thread(target=record,daemon=True);thread.start()
        try:yield frames
        finally:
            stop.set();thread.join(timeout=20)
            if thread.is_alive():raise InfrastructureError('CLIP_CLEANUP_TIMEOUT')
            write(self.root/f'clip-{label}.json',{'frames':frames,'fps_requested':fps,'maximum_seconds':seconds,'fault':str(fault[0]) if fault else None})
            if fault:raise fault[0]
    def close(self):
        cleanup=None;release_errors=[]
        try:
            for key in list(self.held):
                try:self.rpc('up',key=key)
                except Exception as error:release_errors.append({'key':key,'error':str(error)})
                finally:self.held.discard(key)
            if self.process_id:cleanup=self.rpc('stop')
        finally:
            self.process_id=None;self.stop_event.set();self.sampler.join(timeout=2)
            self.process.stdin.close()
            try:self.process.wait(timeout=20)
            except subprocess.TimeoutExpired:self.process.kill();raise InfrastructureError('PLAYER_HOST_CLEANUP')
            with (self.root/'samples.jsonl').open('w',encoding='utf-8') as f:
                for row in self.samples:f.write(json.dumps(row,separators=(',',':'))+'\n')
            write(self.root/'actions.json',self.actions);write(self.root/'cleanup.json',cleanup)
            if release_errors:write(self.root/'cleanup-release-errors.json',release_errors)
        return cleanup
