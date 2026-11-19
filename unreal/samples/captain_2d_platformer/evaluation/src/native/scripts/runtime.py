"""Normal-input transport and fresh, schema-checked, read-only evidence."""
import hashlib
import json
import os
import queue
import subprocess
import threading
import time
import tempfile
from pathlib import Path
from PIL import Image, ImageStat
from schema import errors as schema_errors

ROOT = Path(__file__).resolve().parents[1]
TASK = ROOT.parent
REPO = TASK.parents[1]
EXCLUDES = {'Binaries','Intermediate','Saved','DerivedDataCache','.vs','.idea','.git','__pycache__'}

def load(path):
    def invalid(value): raise ValueError('NONFINITE_JSON:'+value)
    def pairs(rows):
        result={}
        for k,v in rows:
            if k in result:raise ValueError('DUPLICATE_JSON_KEY:'+k)
            result[k]=v
        return result
    return json.loads(Path(path).read_text(encoding='utf-8-sig'),parse_constant=invalid,object_pairs_hook=pairs)

def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    body=json.dumps(data, ensure_ascii=True, indent=2,allow_nan=False)+'\n'
    # A reader must see either the previous checkpoint or the complete new one.
    handle,temporary=tempfile.mkstemp(prefix=path.name+'.',suffix='.tmp',dir=path.parent)
    try:
        with os.fdopen(handle,'w',encoding='utf-8') as stream:stream.write(body)
        os.replace(temporary,path)
    finally:
        if os.path.exists(temporary):os.unlink(temporary)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def inside(root, relative):
    root = Path(root).resolve()
    p = (root / relative).resolve()
    if not p.is_relative_to(root):
        raise InfrastructureError('EVIDENCE_PATH_ESCAPE')
    return p

def identity(root):
    rows=[]
    if root.is_dir():
        for directory, dirs, files in os.walk(root, followlinks=False):
            if any((Path(directory)/d).is_symlink() or not (Path(directory)/d).resolve().is_relative_to(root.resolve()) for d in dirs):
                raise CandidateError('CANDIDATE_PATH_ESCAPE')
            dirs[:] = sorted(d for d in dirs if d not in EXCLUDES)
            for name in sorted(files):
                p=Path(directory)/name
                if p.is_symlink() or not p.resolve().is_relative_to(root.resolve()):
                    raise CandidateError('CANDIDATE_PATH_ESCAPE')
                rows.append({'path':p.relative_to(root).as_posix(),'size':p.stat().st_size,'sha256':sha(p)})
    rows.sort(key=lambda r:r['path'])
    digest=hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    return {'sha256':digest,'files':rows}

class CandidateError(Exception):
    pass

class InfrastructureError(Exception):
    pass

class Budget:
    """Hard bounds on every blocking operation, plus an independent process watchdog."""
    def __init__(self, contract=None, clock=time.monotonic):
        self.contract=contract or load(ROOT/'contracts/budget.json');self.clock=clock;self.start=clock()
        self.wait_seconds=0;self.small_rpcs=0;self.captures=0;self.expired=False;self.processes=[]
        self.timer=threading.Timer(self.contract['watchdog_seconds'],self.expire);self.timer.daemon=True
    def arm(self): self.timer.start()
    def expire(self):
        self.expired=True
        for p in self.processes:
            if p.poll() is None:
                subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True,timeout=15)
    def check(self):
        if self.expired or self.clock()-self.start>=self.contract['watchdog_seconds']:
            raise InfrastructureError('SESSION_WATCHDOG_EXCEEDED')
    def reserve_wait(self,seconds):
        self.check();self.wait_seconds+=seconds
        if self.wait_seconds>self.contract['local_wait_budget_seconds']:raise InfrastructureError('LOCAL_WAIT_BUDGET_EXCEEDED')
    def rpc_timeout(self,op):
        self.check()
        if op in ('start','reopen'):return self.contract['start_rpc_timeout_seconds']
        if op=='stop':return self.contract['stop_rpc_timeout_seconds']
        self.small_rpcs+=1
        if self.small_rpcs>self.contract['max_small_rpcs']:raise InfrastructureError('RPC_COUNT_BUDGET_EXCEEDED')
        if op=='capture':
            self.captures+=1
            if self.captures>self.contract['max_captures']:raise InfrastructureError('CAPTURE_COUNT_BUDGET_EXCEEDED')
            return self.contract['capture_rpc_timeout_seconds']
        return self.contract['small_rpc_timeout_seconds']
    def close(self): self.timer.cancel()
    def report(self):
        return {'elapsed_seconds':round(self.clock()-self.start,2),'reserved_local_wait_seconds':round(self.wait_seconds,2),
            'small_rpcs':self.small_rpcs,'captures':self.captures,'watchdog_expired':self.expired,'contract':self.contract}

def code_identity():
    paths=[ROOT/'scripts'/p for p in ('runtime.py','evaluate.py','PlayerHost.ps1','schema.py')]
    paths += [ROOT/'contracts/budget.json',TASK/'input/contracts/game-state.schema.json']
    paths += sorted((REPO/'engine/unreal-5.7.4/executor').rglob('*.psm1'))
    paths += sorted((REPO/'engine/unreal-5.7.4/executor').rglob('*.cs'))
    rows=[{'path':p.relative_to(REPO).as_posix(),'sha256':sha(p)} for p in paths]
    return {'files':rows,'sha256':hashlib.sha256(json.dumps(rows,sort_keys=True).encode()).hexdigest()}

CANDIDATE_CODES = {'PROJECT_FILE_INVALID','PROCESS_EXITED_DURING_START','WINDOW_DISCOVERY_TIMEOUT',
    'FIRST_FRAME_TIMEOUT','STATE_READY_TIMEOUT','STATE_FILE_UNAVAILABLE','PROCESS_EXITED',
    'PROCESS_NOT_RUNNING','WINDOW_INVALID','WINDOW_NOT_FOUND','TARGET_PROCESS_EXITED',
    'STOP_GRACE_TIMEOUT','STOP_WINDOW_INVALID','TARGET_EXITED_BEFORE_STOP','WAIT_CONDITION_TIMEOUT',
    'FIRST_FRAME_NOT_OBSERVED','STARTUP_STATE_TIMEOUT','FIRST_FRAME_STATE_TIMEOUT'}

INFRASTRUCTURE_CODES = {'STATE_PATH_CONFLICT','STATE_PATH_INVALID','STATE_PATH_OUTSIDE_RUN_ROOT',
    'STATE_PATH_REQUIRED','STATE_PATH_UNSAFE','STATE_PROCESS_TOKEN_CONFLICT','STATE_PROCESS_TOKEN_INVALID'}

def classify(receipt):
    if receipt.get('status') == 'ok': return 'ok'
    fault=receipt.get('fault') or {}
    code=fault.get('code','').upper()
    if code in INFRASTRUCTURE_CODES:return 'infrastructure'
    # A destroyed candidate window is also reported through the input watchdog
    # when it disappears while a key is held. Preserve that typed cause rather
    # than treating the wrapper as a host failure. Focus loss and input-release
    # failures remain infrastructure faults.
    details=fault.get('details')
    if (code=='INPUT_WATCHDOG_FAULT_LATCHED' and isinstance(details,dict)
        and details.get('watchdog_faulted') is True
        and details.get('watchdog_fault_code')=='WINDOW_INVALID'
        and details.get('native_error')==0):
        return 'candidate'
    if code in CANDIDATE_CODES or code.startswith('STATE_'):
        return 'candidate'
    # Other shared-executor faults identify host input, window capture, or protocol failures.
    # Retain the complete typed receipt as positive attribution evidence, never infer from prose.
    return 'infrastructure'

def cleanup_verified(receipt):
    if not isinstance(receipt,dict):return False
    result=receipt.get('result')
    if not isinstance(result,dict):return False
    # This receipt proves the old session is gone; successful Reopen creates a
    # new session and must never be cleared using evidence about the old one.
    if receipt.get('operation')=='Reopen':
        if receipt.get('status')=='ok' or result.get('termination_reason')!='old_session_stop_failed':return False
        result=result.get('stop_result')
        if not isinstance(result,dict):return False
    return (result.get('process_exited') is True and type(result.get('job_active_process_count_after_wait')) is int
        and result['job_active_process_count_after_wait']==0
        and result.get('job_handle_closed') is True and result.get('input_lease_released') is True)

class Player:
    def __init__(self, pwsh, root, budget=None):
        self.budget=budget
        self.root=Path(root).resolve()
        for d in ('state','captures','receipts','states','logs'):
            (self.root/d).mkdir(parents=True,exist_ok=True)
        self.process=subprocess.Popen([str(pwsh),'-NoProfile','-File',str(ROOT/'scripts/PlayerHost.ps1'),
            '-ExecutorPath',str(REPO/'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1')],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',
            creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        self.responses=queue.Queue()
        if self.budget:self.budget.processes.append(self.process)
        def consume():
            try:
                with (self.root/'logs/player-host.log').open('w',encoding='utf-8') as log:
                    for line in self.process.stdout:
                        log.write(line);log.flush()
                        if line.startswith('@@'):
                            try:self.responses.put(json.loads(line[2:]))
                            except ValueError:self.responses.put({'status':'host_exception','fault':{'code':'HOST_PROTOCOL_INVALID'}})
            except (OSError,UnicodeError) as e:
                self.responses.put({'status':'host_exception','fault':{'code':'HOST_OUTPUT_READ_FAILED'},'exception_type':type(e).__name__})
            finally:
                self.process.stdout.close()
                self.responses.put(None)
        self.reader=threading.Thread(target=consume,daemon=True)
        self.reader.start()
        self.serial=0
        self.session=None
        self.last_receipt=None
        self.last_cleanup_receipt=None
        self.had_session=False

    def call(self,op,**kw):
        if op=='stop' and self.session is None and cleanup_verified(self.last_cleanup_receipt):
            return self.last_cleanup_receipt
        timeout=self.budget.rpc_timeout(op) if self.budget else (85 if op in ('start','reopen') else 20)
        self.serial+=1
        message={'op':op,**kw}
        try:
            self.process.stdin.write(json.dumps(message)+'\n'); self.process.stdin.flush()
            receipt=self.responses.get(timeout=timeout)
        except (queue.Empty,OSError,ValueError) as e:
            write(self.root/f'receipts/{self.serial:04}-{op}.json',dict(status='host_exception',
                fault=dict(domain='infrastructure',code='PLAYER_HOST_RPC_TIMEOUT'),exception_type=type(e).__name__))
            raise InfrastructureError('PLAYER_HOST_RPC_TIMEOUT') from None
        if receipt is None:
            receipt=dict(status='host_exception',fault=dict(code='PLAYER_HOST_EXITED'))
        if not isinstance(receipt,dict):
            receipt=dict(status='host_exception',fault=dict(code='HOST_PROTOCOL_INVALID'))
        receipt_path=f'receipts/{self.serial:04}-{op}.json'
        write(self.root/receipt_path,receipt)
        self.last_receipt=receipt
        if op in ('stop','reopen') and cleanup_verified(receipt):
            self.session=None;self.last_cleanup_receipt=receipt
        kind=classify(receipt)
        if kind!='ok':
            code=(receipt.get('fault') or {}).get('code',receipt.get('status'))
            raise (CandidateError if kind=='candidate' else InfrastructureError)(str(code)+':'+receipt_path)
        if op in ('start','reopen'):
            result=receipt.get('result')
            if not isinstance(result,dict) or not all(k in result for k in ('process_id','process_token','session')):
                raise InfrastructureError('PLAYER_SESSION_PROTOCOL_INVALID:'+receipt_path)
            self.session=result;self.had_session=True;self.last_cleanup_receipt=None
        return receipt

    def capture(self,name,expected_size=(1280,720)):
        def context():
            for _ in range(4):
                try:return load(self.root/'state/game-state.json')
                except (OSError,ValueError):time.sleep(.005)
            return None
        before=context()
        path=self.root/'captures'/f'{name}.png'
        receipt=self.call('capture',path=str(path),id=name)
        with Image.open(path) as im:
            if expected_size and im.size!=expected_size: raise CandidateError('CANDIDATE_VIEWPORT_MISMATCH')
            width,height=im.size
            stat=ImageStat.Stat(im.convert('RGB'))
            visible=max(stat.mean)>3 and max(stat.stddev)>2
        after=context()
        write(self.root/'captures'/f'{name}.context.json',{'before':before,'after':after,'receipt_sha256':sha(self.root/f'receipts/{self.serial:04}-capture.json')})
        return {'path':f'captures/{name}.png','sha256':sha(path),'visible':visible,'width':width,'height':height,
            'context':f'captures/{name}.context.json'}

    def close(self):
        try:self.process.stdin.close()
        except (OSError,ValueError):pass
        if self.process.poll() is None:
            try: self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
                raise InfrastructureError('PLAYER_HOST_CLEANUP_TIMEOUT')
        self.reader.join(timeout=2)
        if self.reader.is_alive():raise InfrastructureError('PLAYER_HOST_OUTPUT_NOT_CLOSED')
        if self.process.returncode!=0:raise InfrastructureError('PLAYER_HOST_EXIT_NONZERO')

class Observer:
    def __init__(self,root,session,budget=None):
        self.budget=budget
        self.root=Path(root)
        self.schema=load(TASK/'input/contracts/game-state.schema.json')
        self.bind(session)
        self.errors=[]
        self.samples=[]
        self.transient_reads=0

    def bind(self,session):
        self.pid=session['process_id']; self.token=session['process_token']
        self.last_id=-1;self.last_clock=-1;self.last_seen=time.monotonic();self.last=None

    def read(self):
        if self.budget:self.budget.check()
        path=self.root/'state/game-state.json'
        try:
            if path.stat().st_size>1048576: raise ValueError('oversize')
            if time.time()-path.stat().st_mtime>2: raise ValueError('stale')
            s=load(path)
            if not isinstance(s,dict):raise ValueError('invalid_envelope')
            errors=schema_errors(s,self.schema)
            if errors:
                code='schema:'+str(errors[0])
                if code not in self.errors: self.errors.append(code)
            if errors and any(not x.startswith('.game_state') and not x.startswith(': allOf') for x in errors):
                raise ValueError('invalid_envelope')
            # Isolate malformed gameplay fields; valid independent fields remain observable.
            for k,t in (('process_id',int),('process_token',str),('snapshot_id',int),('monotonic_ms',(int,float))):
                if not isinstance(s.get(k),t) or isinstance(s.get(k),bool): raise ValueError('envelope:'+k)
            if s['process_id']!=self.pid or s['process_token']!=self.token: raise ValueError('identity')
            if s['snapshot_id']<self.last_id or s['monotonic_ms']<self.last_clock: raise ValueError('regression')
            if s['snapshot_id']==self.last_id:
                if time.monotonic()-self.last_seen>2: raise ValueError('stalled')
                return None
            if s['monotonic_ms']<=self.last_clock: raise ValueError('nonincreasing_clock')
            self.last_id=s['snapshot_id']; self.last_clock=s['monotonic_ms'];self.last_seen=time.monotonic();self.last=s
            self.samples.append(s)
            return s
        except (OSError,ValueError,KeyError,TypeError) as e:
            # Atomic file replacement can briefly cause sharing/not-found errors on Windows.
            # A healthy new snapshot within the published two-second freshness deadline is sufficient.
            if isinstance(e,OSError) or isinstance(e,json.JSONDecodeError):
                self.transient_reads+=1
                if time.monotonic()-self.last_seen<=2:return None
            code=str(e) if not isinstance(e,OSError) else type(e).__name__
            if not self.errors or self.errors[-1]!=code: self.errors.append(code)
            return None

    def wait(self,name,predicate,timeout,stable=1):
        if self.budget:self.budget.reserve_wait(timeout)
        start=time.monotonic();seq=[];matched=0;found=None
        while time.monotonic()-start<timeout:
            s=self.read()
            if s:
                seq.append(s)
                try:
                    passed=s.get('provider_ready') is True and isinstance(s.get('game_state'),dict) and predicate(s['game_state'])
                except (KeyError,TypeError,ValueError,IndexError,AttributeError):
                    passed=False
                if passed:
                    matched+=1
                    if matched>=stable: found=s;break
                else: matched=0
            time.sleep(.025)
        write(self.root/'states'/f'{name}.json',{'samples':seq,'matched':found is not None,'timeout_seconds':timeout,'errors':list(self.errors)})
        return found

    def window(self,name,seconds):
        if self.budget:self.budget.reserve_wait(seconds)
        start=time.monotonic();seq=[]
        while time.monotonic()-start<seconds:
            s=self.read()
            if s: seq.append(s)
            time.sleep(.025)
        write(self.root/'states'/f'{name}.json',{'samples':seq,'window_seconds':seconds,'errors':list(self.errors)})
        return seq

