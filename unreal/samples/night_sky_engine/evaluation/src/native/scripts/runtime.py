"""Normal-input transport and fresh, schema-checked, read-only evidence."""
import hashlib
import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path
from PIL import Image, ImageStat
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
TASK = ROOT.parent
REPO = TASK.parents[1]
EXCLUDES = {'Binaries','Intermediate','Saved','DerivedDataCache','.vs','.idea','.git','__pycache__'}

def load(path):
    def invalid(value): raise ValueError('NONFINITE_JSON:'+value)
    return json.loads(Path(path).read_text(encoding='utf-8-sig'),parse_constant=invalid)

def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=True, indent=2, allow_nan=False)+'\n', encoding='utf-8')

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
        self.wait_seconds=0;self.small_rpcs=0;self.expired=False;self.processes=[];self.case=None
        self.start_rpcs=0;self.stop_rpcs=0
        calculated=(self.contract['build_timeout_seconds']+self.contract['preparation_budget_seconds']
            +self.contract['max_start_rpcs']*self.contract['start_rpc_timeout_seconds']
            +self.contract['max_stop_rpcs']*self.contract['stop_rpc_timeout_seconds']
            +self.contract['max_small_rpcs']*self.contract['small_rpc_timeout_seconds']
            +self.contract['local_wait_budget_seconds']+self.contract['cleanup_timeout_seconds'])
        if calculated!=self.contract['declared_serial_worst_case_seconds'] or self.contract['watchdog_seconds']<calculated+self.contract['headroom_seconds']:
            raise InfrastructureError('INVALID_WATCHDOG_BUDGET')
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
        if self.case:
            self.case['wait_seconds']+=seconds
            if self.case['wait_seconds']>self.case['contract']['max_wait_seconds']:
                raise InfrastructureError('CASE_WAIT_BUDGET_EXCEEDED')
    def rpc_timeout(self,op):
        self.check()
        if op in ('start','reopen'):
            self.start_rpcs+=1
            if self.start_rpcs>self.contract['max_start_rpcs']:raise InfrastructureError('START_COUNT_BUDGET_EXCEEDED')
            return self.contract['start_rpc_timeout_seconds']
        if op=='stop':
            self.stop_rpcs+=1
            if self.stop_rpcs>self.contract['max_stop_rpcs']:raise InfrastructureError('STOP_COUNT_BUDGET_EXCEEDED')
            return self.contract['stop_rpc_timeout_seconds']
        self.small_rpcs+=1
        if self.small_rpcs>self.contract['max_small_rpcs']:raise InfrastructureError('RPC_COUNT_BUDGET_EXCEEDED')
        return self.contract['small_rpc_timeout_seconds']
    def close(self): self.timer.cancel()
    def report(self):
        return {'elapsed_seconds':round(self.clock()-self.start,2),'reserved_local_wait_seconds':round(self.wait_seconds,2),
            'small_rpcs':self.small_rpcs,'watchdog_expired':self.expired,'contract':self.contract}

def code_identity():
    paths=[ROOT/'scripts'/p for p in ('runtime.py','evaluate.py','atomic.py','coverage_cases.py',
                                    'coverage_assertions.py','coverage_gate.py','source_review.py','PlayerHost.ps1')]
    paths += [ROOT/'catalog/boundary-coverage.json']
    paths += [ROOT/'contracts/budget.json',ROOT/'contracts/scoring-contract.json',ROOT/'catalog/trajectories.json',TASK/'input/contracts/duel-state.schema.json']
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
    if code in CANDIDATE_CODES or code.startswith('STATE_'):
        return 'candidate'
    # Other shared-executor faults identify host input, window capture, or protocol failures.
    # Retain the complete typed receipt as positive attribution evidence, never infer from prose.
    return 'infrastructure'

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
            for line in self.process.stdout:
                if line.startswith('@@'):
                    try:self.responses.put(json.loads(line[2:]))
                    except ValueError:self.responses.put({'status':'host_exception','fault':{'code':'HOST_PROTOCOL_INVALID'}})
            self.responses.put(None)
        threading.Thread(target=consume,daemon=True).start()
        self.serial=0
        self.session=None
        self.case=None;self.action_count=0

    def begin_case(self,contract):
        self.action_count=0
        self.case={'contract':contract,'started':time.monotonic(),'wait_seconds':0}
        if self.budget:self.budget.case=self.case

    def end_case(self):
        result={'actions':self.action_count,'elapsed_seconds':round(time.monotonic()-self.case['started'],3),
                'reserved_wait_seconds':self.case['wait_seconds']} if self.case else {}
        self.case=None
        if self.budget:self.budget.case=None
        return result

    def call(self,op,**kw):
        if self.case and op in ('press','down'):
            if self.action_count>=self.case['contract']['max_actions']:
                raise InfrastructureError('CASE_ACTION_CONTRACT_EXCEEDED')
            if time.monotonic()-self.case['started']>self.case['contract']['max_serial_seconds']:
                raise InfrastructureError('CASE_SERIAL_CONTRACT_EXCEEDED')
            self.action_count+=1
        timeout=self.budget.rpc_timeout(op) if self.budget else (85 if op in ('start','reopen') else 20)
        self.serial+=1
        message={'op':op,**kw}
        try:
            self.process.stdin.write(json.dumps(message)+'\n'); self.process.stdin.flush()
            receipt=self.responses.get(timeout=timeout)
        except (queue.Empty,BrokenPipeError):
            raise InfrastructureError('PLAYER_HOST_RPC_TIMEOUT') from None
        if receipt is None: raise InfrastructureError('PLAYER_HOST_EXITED')
        receipt_path=f'receipts/{self.serial:04}-{op}.json'
        write(self.root/receipt_path,receipt)
        if op=='stop':self.session=None
        kind=classify(receipt)
        if kind!='ok':
            code=(receipt.get('fault') or {}).get('code',receipt.get('status'))
            raise (CandidateError if kind=='candidate' else InfrastructureError)(str(code)+':'+receipt_path)
        if op in ('press','down','up') and receipt.get('input_dispatched') is not True:
            raise InfrastructureError('INPUT_RECEIPT_NOT_DISPATCHED:'+receipt_path)
        if op in ('start','reopen'): self.session=receipt['result']
        return receipt

    def capture(self,name,expected_size=(1280,720)):
        def context():
            for _ in range(4):
                try:return load(self.root/'state/duel-state.json')
                except (OSError,ValueError):time.sleep(.005)
            return None
        before=context()
        path=self.root/'captures'/f'{name}.png'
        receipt=self.call('capture',path=str(path),id=name)
        with Image.open(path) as im:
            if expected_size and im.size!=expected_size: raise InfrastructureError('CAPTURE_VIEWPORT_MISMATCH')
            width,height=im.size
            stat=ImageStat.Stat(im.convert('RGB'))
            visible=max(stat.mean)>3 and max(stat.stddev)>2
        after=context()
        write(self.root/'captures'/f'{name}.context.json',{'before':before,'after':after,'receipt_sha256':sha(self.root/f'receipts/{self.serial:04}-capture.json')})
        return {'path':f'captures/{name}.png','sha256':sha(path),'visible':visible,'width':width,'height':height,
            'context':f'captures/{name}.context.json'}

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try: self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.process.kill()
                raise InfrastructureError('PLAYER_HOST_CLEANUP_TIMEOUT')

class Observer:
    def __init__(self,root,session,budget=None):
        self.budget=budget
        self.root=Path(root)
        self.validator=Draft202012Validator(load(TASK/'input/contracts/duel-state.schema.json'))
        self.bind(session)
        self.errors=[]
        self.samples=[]
        self.transient_reads=0

    def bind(self,session):
        self.pid=session['process_id']; self.token=session['process_token']
        self.last_id=-1;self.last_clock=-1;self.last_seen=time.monotonic();self.last=None

    def read(self):
        if self.budget:self.budget.check()
        path=self.root/'state/duel-state.json'
        try:
            if path.stat().st_size>1048576: raise ValueError('oversize')
            if time.time()-path.stat().st_mtime>2: raise ValueError('stale')
            s=load(path)
            errors=list(self.validator.iter_errors(s))
            if errors:
                code='schema:'+'.'.join(map(str,errors[0].absolute_path))
                if code not in self.errors: self.errors.append(code)
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
                except (KeyError,TypeError,ValueError,AttributeError):
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
