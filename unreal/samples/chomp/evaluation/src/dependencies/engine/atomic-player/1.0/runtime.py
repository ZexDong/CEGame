"""PID-bound normal input and atomic observation, with caller-owned schema.

No game names, candidate class names, fixture setters or scoring predicates.
"""
from __future__ import annotations
import contextlib, hashlib, json, os, queue, subprocess, threading, time
from pathlib import Path

VERSION='atomic-player-1.0.0'
GENERATED={'.git','.vs','Binaries','Intermediate','Saved','DerivedDataCache','__pycache__','.pytest_cache'}
class CandidateError(RuntimeError): pass
class InfrastructureError(RuntimeError): pass
def load(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'),parse_constant=lambda x:(_ for _ in ()).throw(ValueError('NONFINITE_JSON')))
def write(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def identity(root):
    root=Path(root).resolve();rows=[]
    if root.is_dir():
        for parent,dirs,files in os.walk(root):
            dirs[:]=sorted(d for d in dirs if d not in GENERATED)
            for name in dirs+files:
                p=Path(parent)/name
                if p.is_symlink() or not p.resolve().is_relative_to(root):raise CandidateError('PROJECT_PATH_ESCAPE')
            for name in sorted(files):
                p=Path(parent)/name;rows.append({'path':p.relative_to(root).as_posix(),'size':p.stat().st_size,'sha256':sha(p)})
    return {'sha256':hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'files':rows}

class Player:
    def __init__(self,repo,project,engine,root,observation_argument,seed_argument=None,extra_arguments=(),width=1280,height=720,watchdog=18000,userdir=None):
        self.repo=Path(repo).resolve();self.project=Path(project).resolve();self.engine=Path(engine).resolve();self.root=Path(root).resolve()
        self.root.mkdir(parents=True,exist_ok=False);self.path=self.root/'observation.json'
        self.userdir=Path(userdir).resolve() if userdir else self.root/'userdata'
        self.width=width;self.height=height;self.started=time.perf_counter();self.watchdog=watchdog
        self.extra=[f'-{observation_argument}={self.path}',*extra_arguments]
        if seed_argument:self.extra.append(seed_argument)
        self.pid=None;self.token=None;self.revision=0;self.latest=None;self.last_fresh=time.perf_counter();self.bad_since=None;self.error=None;self.starting=True
        self.samples=[];self.actions=[];self.held=set();self.case='startup';self.counter=0;self.closed=False
        self.lock=threading.RLock();self.rpc_lock=threading.RLock();self.stop_event=threading.Event();self.messages=queue.Queue()
        self.host=subprocess.Popen(['pwsh','-NoProfile','-File',str(Path(__file__).with_name('PlayerHost.ps1')),'-ExecutorPath',str(self.repo/'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1)
        def reader():
            with (self.root/'host.log').open('w',encoding='utf-8') as out:
                for line in self.host.stdout:
                    out.write(line);out.flush()
                    if line.startswith('@@'):
                        try:self.messages.put(json.loads(line[2:]))
                        except Exception:self.messages.put({'status':'host_protocol_error'})
        threading.Thread(target=reader,daemon=True).start()
        self.sampler=threading.Thread(target=self._sample,daemon=True);self.sampler.start()
    def _read(self):
        if not self.pid:return None
        now=time.perf_counter()
        if not self.path.exists():
            if self.latest and now-self.last_fresh>1 and not self.starting:raise CandidateError('OBSERVATION_MISSING')
            return self.latest
        try:s=load(self.path)
        except (OSError,ValueError) as e:
            if self.bad_since is None:self.bad_since=now
            if now-self.bad_since>1:raise CandidateError('OBSERVATION_MALFORMED') from e
            return self.latest
        self.bad_since=None
        if not isinstance(s,dict):raise CandidateError('OBSERVATION_NOT_OBJECT')
        if s.get('process_id')!=self.pid:return self.latest
        token=s.get('process_token');rev=s.get('snapshot_id')
        if not isinstance(token,str) or not token or type(rev)is not int or rev<1:raise CandidateError('OBSERVATION_IDENTITY')
        if token!=self.token:self.token=token;self.revision=0
        if rev<self.revision:raise CandidateError('OBSERVATION_SEQUENCE_REGRESSION')
        if rev>self.revision:
            self.latest=s;self.revision=rev;self.last_fresh=now
            self.samples.append({'time':now-self.started,'case':self.case,'state':s})
        elif now-self.last_fresh>1 and not self.starting:raise CandidateError('OBSERVATION_STALE')
        return self.latest
    def _sample(self):
        while not self.stop_event.wait(.008):
            try:
                with self.lock:self._read()
            except Exception as e:self.error=e
    def rpc(self,op,**args):
        with self.rpc_lock:
            if time.perf_counter()-self.started>self.watchdog and op not in ['up','stop']:raise InfrastructureError('SESSION_WATCHDOG')
            self.counter+=1;start=time.perf_counter()-self.started
            try:self.host.stdin.write(json.dumps({'op':op,**args})+'\n');self.host.stdin.flush()
            except OSError as e:raise InfrastructureError('HOST_PIPE_CLOSED') from e
            try:r=self.messages.get(timeout=150 if op=='start' else 30 if op=='stop' else 20)
            except queue.Empty as e:raise InfrastructureError('HOST_RPC_TIMEOUT:'+op) from e
            receipt={'operation':op,'case':self.case,'started':start,'ended':time.perf_counter()-self.started,'parameters':{k:v for k,v in args.items() if k not in ['project','engine','root','path','arguments']},'result':r}
            receipt['phase']=getattr(self,'action_phase','test')
            self.actions.append(receipt);write(self.root/f'receipts/{self.counter:05}-{op}.json',receipt)
            if r.get('status')!='ok':
                code=r.get('fault',{}).get('code',r.get('status','UNKNOWN'))
                if op=='stop' and code=='target_exited_before_stop' and r.get('result',{}).get('input_lease_released'):return r
                if code.lower() in ['start_window_timeout','start_process_exited','process_exited','target_process_exited','target_window_invalid']:raise CandidateError('CANDIDATE_RUNTIME:'+code)
                raise InfrastructureError('EXECUTOR:'+code)
            return r
    def start(self):
        r=self.rpc('start',project=str(self.project),engine=str(self.engine),root=str(self.root),width=self.width,height=self.height,arguments=[*self.extra,f'-UserDir={self.userdir}'])
        self.pid=r['result']['process_id'];self.last_fresh=time.perf_counter()
        self.wait(lambda s:s.get('first_frame') is True and s.get('snapshot_id',0)>12 and time.perf_counter()-self.last_fresh<.25,120,stable=.5,reason='FIRST_FRAME_UNAVAILABLE')
        self.starting=False
        return r
    def state(self):
        if self.error:raise self.error
        with self.lock:
            s=self._read()
            if s is None:raise CandidateError('OBSERVATION_NOT_READY')
            return s
    def wait(self,predicate,seconds=3,stable=0,reason='CONDITION_TIMEOUT'):
        end=time.perf_counter()+seconds;since=None
        while time.perf_counter()<end:
            try:s=self.state()
            except CandidateError as e:
                if str(e)!='OBSERVATION_NOT_READY':raise
                self.stop_event.wait(.008);continue
            if predicate(s):
                since=since if since is not None else time.perf_counter()
                if time.perf_counter()-since>=stable:return s
            else:since=None
            self.stop_event.wait(.008)
        raise CandidateError(reason)
    def observe(self,seconds):
        end=time.perf_counter()+seconds
        while time.perf_counter()<end:self.state();self.stop_event.wait(.008)
        return self.state()
    def press(self,key,ms=35):return self.rpc('press',key=key,ms=ms)
    def down(self,key):
        r=self.rpc('down',key=key);self.held.add(key);return r
    def up(self,key):
        try:return self.rpc('up',key=key)
        finally:self.held.discard(key)
    @contextlib.contextmanager
    def holding(self,key):
        self.down(key)
        try:yield
        finally:self.up(key)
    def click(self,rect,ms=35):
        x=rect['x']+rect['width']/2;y=rect['y']+rect['height']/2
        revision=self.state()['snapshot_id'];self.rpc('move',x=x,y=y)
        self.wait(lambda s:s['snapshot_id']>revision,1,reason='POINTER_MOVE_OBSERVATION_TIMEOUT')
        return self.rpc('click',x=x,y=y,button='Left',ms=ms)
    def capture(self,label,observation=True):
        path=self.root/f'captures/{label}.png';path.parent.mkdir(exist_ok=True)
        if path.exists():raise InfrastructureError('CAPTURE_LABEL_REUSE')
        before=self.state() if observation else None;r=self.rpc('capture',path=str(path),id=label)
        record={'path':path.relative_to(self.root).as_posix(),'sha256':sha(path),'before':before,'after':self.state() if observation else None,'pid':self.pid,'receipt':r}
        write(path.with_suffix('.json'),record);return record
    def reopen(self):
        old=self.pid;self.rpc('stop')
        with self.lock:
            self.pid=None;self.latest=None;self.revision=0;self.token=None;self.error=None;self.starting=True
            if self.path.exists():self.path.rename(self.root/f'observation-{old}.json')
        r=self.start();write(self.root/f'reopen-{old}.json',{'old_pid':old,'new_pid':self.pid,'new_process':old!=self.pid});return r
    def close(self):
        if self.closed:return
        self.closed=True;cleanup=None
        try:
            for key in list(self.held):self.up(key)
            if self.pid:cleanup=self.rpc('stop')
        finally:
            self.pid=None;self.stop_event.set();self.sampler.join(2);self.host.stdin.close()
            try:self.host.wait(timeout=20)
            except subprocess.TimeoutExpired:self.host.kill()
            with (self.root/'samples.jsonl').open('w',encoding='utf-8') as f:
                for s in self.samples:f.write(json.dumps(s,separators=(',',':'))+'\n')
            write(self.root/'actions.json',self.actions);write(self.root/'cleanup.json',cleanup)
