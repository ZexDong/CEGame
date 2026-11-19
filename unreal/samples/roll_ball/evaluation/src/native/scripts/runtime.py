"""Normal-input collector. No candidate classes, object paths or write API."""
import json
import math
import hashlib
import queue
import subprocess
import threading
import time
import copy
from pathlib import Path
from schema import errors

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT.parent / 'input'
SCHEMA = json.loads((INPUT / 'contracts/game-state.schema.json').read_text(encoding='utf-8'))
CORE_SCHEMA=copy.deepcopy(SCHEMA)
# Presentation, round bookkeeping and fixed metadata errors fail their own
# contract checks, but do not discard otherwise usable movement observations.
CORE_SCHEMA['required']=['process_id','snapshot_id','monotonic_ms','provider_ready','first_frame','game_state']
CORE_SCHEMA['additionalProperties']=True
for key in ('schema_version','layout_id','start_cell','exit_cell','trap_cells','bridge_ready'):
    CORE_SCHEMA['properties'][key]={}
CORE_SCHEMA['allOf']=[]
CORE_SCHEMA['$defs']['game_state']['required']=['status','ball']
for key in ('hud','round_id','round_index','restart_count','trap_hits','input_enabled'):
    CORE_SCHEMA['$defs']['game_state']['properties'][key]={}

class InfrastructureError(RuntimeError): pass
class CandidateError(RuntimeError): pass
class ObservationUncertain(InfrastructureError): pass

def load(path):
    def reject(value): raise ValueError('NONFINITE_JSON')
    value = json.loads(Path(path).read_text(encoding='utf-8-sig'), parse_constant=reject)
    def finite(x):
        if isinstance(x, float) and not math.isfinite(x): raise ValueError('NONFINITE_JSON')
        if isinstance(x, dict):
            for v in x.values(): finite(v)
        if isinstance(x, list):
            for v in x: finite(v)
    finite(value)
    return value

def write(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    # Keep evidence bytes stable across Windows checkout settings.
    path.write_bytes((json.dumps(value, ensure_ascii=False, allow_nan=False, indent=2)+'\n').encode('utf-8'))

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def vec(v): return tuple(v[k] for k in ('x','y','z'))
def norm(v): return math.sqrt(sum(x*x for x in v))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def cell(s): return tuple(s['game_state']['ball']['grid_cell'][k] for k in ('x','y'))
def position(s): return vec(s['game_state']['ball']['world_position'])
def velocity(s): return vec(s['game_state']['ball']['linear_velocity'])

def interval_verdict(lower, upper, allowed_min, allowed_max):
    """Only fail an interval wholly outside the public limit; ambiguous is review."""
    if upper < allowed_min or lower > allowed_max: return 'fail'
    if lower >= allowed_min and upper <= allowed_max: return 'pass'
    return 'review'

class Player:
    def __init__(self, pwsh, tools, engine, project, root):
        self.root=Path(root).resolve(); self.root.mkdir(parents=True, exist_ok=False)
        self.engine=str(engine); self.project=str(project)
        self.state_path=self.root/'game-state.json'; self.receipts=[]; self.samples=[]
        self.latest=None; self.last_id=0; self.last_received=0; self.errors=[]; self.held=set(); self.pid=None
        self.lock=threading.Lock(); self.done=threading.Event(); self.replies=queue.Queue()
        self.log=(self.root/'bridge.log').open('w',encoding='utf-8')
        self.proc=subprocess.Popen([str(pwsh),'-NoProfile','-File',str(ROOT/'scripts/bridge.ps1'),'-ToolsRoot',str(tools)],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.log,text=True,encoding='utf-8',creationflags=0x08000000)
        def replies():
            for line in self.proc.stdout:
                try: self.replies.put(json.loads(line))
                except ValueError: self.replies.put({'status':'bridge_error','error':'Non-JSON stdout'})
        threading.Thread(target=replies,daemon=True).start()
        self.sampler=threading.Thread(target=self._sample,daemon=True); self.sampler.start()
    def rpc(self, op, **args):
        started=time.monotonic()
        self.proc.stdin.write(json.dumps(dict(op=op,**args))+'\n'); self.proc.stdin.flush()
        try: result=self.replies.get(timeout=150 if op=='start' else 45)
        except queue.Empty: raise InfrastructureError('PUBLIC_EXECUTOR_RPC_TIMEOUT')
        rec=dict(operation=op,started=started,ended=time.monotonic(),result=result)
        if 'key' in args: rec['key']=args['key']
        self.receipts.append(rec)
        if result.get('status')!='ok':
            code=str((result.get('fault') or {}).get('code',result.get('error','unknown')))
            cleanup=result.get('result') or {}
            if op=='stop' and code=='target_exited_before_stop' and cleanup.get('process_exited') and cleanup.get('job_handle_closed') and cleanup.get('input_lease_released') and (cleanup.get('input_cleanup') or {}).get('all_released'):
                return cleanup
            # A candidate that never produced its first frame can leave the
            # public executor waiting for its normal grace period. Attribute
            # that bounded stop timeout to the candidate launch outcome so a
            # cleanup symptom does not turn every independent case into an
            # infrastructure fault. Input leases are still released by the
            # bridge finally block.
            if op=='stop' and code.lower()=='stop_grace_timeout':
                raise CandidateError('CANDIDATE_STOP_TIMEOUT')
            # Public executor labels process/window failures as environment faults;
            # the task layer attributes them by direct cause, never that label alone.
            candidate_codes=('process_exited','window_discovery_timeout','process_not_running','window_not_found','window_invalid','target_process_exited')
            if any(c in code.lower() for c in candidate_codes): raise CandidateError(code)
            raise InfrastructureError('PUBLIC_EXECUTOR:'+code)
        return result.get('result')
    def _sample(self):
        while not self.done.wait(.012):
            try:
                s=load(self.state_path); now=time.monotonic()
                with self.lock:
                    if s.get('snapshot_id')==self.last_id: continue
                    issue=errors(s,SCHEMA)
                    if self.pid and s.get('process_id')!=self.pid: issue.append('PROCESS_ID')
                    if s.get('snapshot_id',0)<self.last_id: issue.append('NONMONOTONIC_ID')
                    # A provider may publish one transient schema-invalid
                    # bootstrap snapshot (game_state=null while
                    # provider_ready=true) before its first valid frame. Do
                    # not poison an otherwise healthy run; only record errors
                    # after a valid sample has been observed or when the
                    # condition persists across subsequent snapshots.
                    transient_bootstrap = (issue == [': allOf'] and
                        self.latest is None and s.get('first_frame') is False)
                    if issue and not transient_bootstrap:
                        self.errors.append(dict(time=now,errors=issue))
                    if errors(s,CORE_SCHEMA) or (self.pid and s.get('process_id')!=self.pid) or s.get('snapshot_id',0)<self.last_id:continue
                    if self.latest and s['monotonic_ms']<self.latest['monotonic_ms']:
                        self.errors.append(dict(time=now,errors=['NONMONOTONIC_TIME'])); continue
                    self.latest=s; self.last_id=s['snapshot_id']; self.last_received=now
                    self.samples.append(dict(received=now,snapshot=s))
            except FileNotFoundError: pass
            except (ValueError, OSError, TypeError) as exc:
                self.errors.append(dict(time=time.monotonic(),errors=[type(exc).__name__]))
    def start(self, gameplay=True):
        result=self.rpc('start',project=self.project,engine=self.engine,root=str(self.root),state=str(self.state_path))
        self.pid=result['process_id']
        self.window=result
        self.wait(lambda s:s['first_frame'], 60, 'FIRST_FRAME_MISSING', consecutive=5)
        if gameplay: self.wait(lambda s:s['provider_ready'],3,'GAMEPLAY_PROVIDER_MISSING')
        return self.read(gameplay)
    def read(self, gameplay=True):
        with self.lock:
            if self.latest is None or time.monotonic()-self.last_received>2: raise CandidateError('STATE_MISSING_OR_STALE')
            if gameplay and not self.latest['provider_ready']: raise CandidateError('GAMEPLAY_PROVIDER_MISSING')
            return self.latest
    def wait(self, predicate, timeout, reason, consecutive=1):
        end=time.monotonic()+timeout; previous=None; matched=0
        while time.monotonic()<end:
            try:
                s=self.read(False)
                if s['snapshot_id']!=previous:
                    previous=s['snapshot_id']; matched=matched+1 if predicate(s) else 0
                    if matched>=consecutive: return s
            except CandidateError: pass
            time.sleep(.016)
        raise CandidateError(reason)
    def keys(self, desired):
        desired=set(desired)
        for k in sorted(self.held-desired): self.rpc('up',key=k); self.held.remove(k)
        for k in sorted(desired-self.held): self.rpc('down',key=k); self.held.add(k)
    def press(self,key):
        self.keys([key]); self.observe(.075); self.keys([])
    def observe(self,seconds):
        end=time.monotonic()+seconds
        while time.monotonic()<end: time.sleep(min(.016,max(0,end-time.monotonic())))
        return self.read(False)
    def capture(self,name):
        before=self.read(False); path=self.root/(name+'.png')
        result=self.rpc('capture',path=str(path)); after=self.read(False)
        data=dict(path=path.name,sha256=sha(path),before=before,after=after,receipt_index=len(self.receipts)-1)
        write(self.root/(name+'.json'),data)
        return data
    def close(self):
        fault=None; fault_candidate=False
        try:
            if self.pid:
                try: self.keys([])
                except CandidateError: pass
                self.rpc('stop')
        except CandidateError as exc: fault=str(exc); fault_candidate=True
        except InfrastructureError as exc: fault=str(exc)
        finally:
            self.done.set(); self.sampler.join(timeout=2)
            self.proc.stdin.close()
            try:self.proc.wait(timeout=20)
            except subprocess.TimeoutExpired:self.proc.kill();fault='BRIDGE_CLEANUP_TIMEOUT'
            self.log.close()
            write(self.root/'receipts.json',self.receipts)
            write(self.root/'samples.json',self.samples)
            write(self.root/'observation-errors.json',self.errors)
        if fault:
            if fault_candidate: raise CandidateError(fault)
            raise InfrastructureError(fault)
