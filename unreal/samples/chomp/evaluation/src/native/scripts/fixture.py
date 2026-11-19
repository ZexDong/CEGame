"""Authorized private setup transport; no gameplay outcomes or scoring writes."""
from common import *
import secrets,time,shutil,re

class Fixture:
    def __init__(self,player,source_identity):
        self.p=player;self.root=player.userdir/'private-fixture';self.root.mkdir(parents=True,exist_ok=True)
        self.nonce=secrets.token_hex(24);self.sequence=0;self.identity=source_identity
        write(self.root/'authorization.json',{'nonce':self.nonce,'candidate_identity':source_identity})
    def request(self,operation,state=None):
        self.sequence+=1;req={'nonce':self.nonce,'sequence':self.sequence,'operation':operation}
        if state is not None:req['semantic_state']=state
        temp=self.root/'request.tmp';write(temp,req);replace_deadline=time.perf_counter()+1
        while True:
            try:temp.replace(self.root/'request.json');break
            except PermissionError:
                if time.perf_counter()>=replace_deadline:raise InfrastructureError('FIXTURE_REQUEST_REPLACE_LOCK')
                time.sleep(.01)
        path=self.root/f'receipt-{self.sequence}.json';end=time.perf_counter()+5
        while time.perf_counter()<end:
            if path.exists():
                try:r=load(path)
                except (OSError,ValueError):continue
                if r.get('pid')!=self.p.pid or r.get('candidate_identity')!=self.identity:raise InfrastructureError('FIXTURE_IDENTITY_MISMATCH')
                if not r.get('applied'):raise InfrastructureError('FIXTURE_ADAPTER:'+r.get('reason','unknown'))
                dest=self.p.root/f'fixture/{self.p.case}-{self.sequence}.json';write(dest,r);return r
            self.p.observe(.02)
        raise InfrastructureError('FIXTURE_TRANSPORT_TIMEOUT')
    def setup(self,state):
        before=self.p.game();require(before['phase']=='paused','FIXTURE_REQUIRES_PAUSE')
        r=self.request('apply',state)
        self.p.wait_game(lambda s: s['phase']=='paused' and s['run_id']==before['run_id'],2,stable=.08)
        actual=self.p.game()
        # Every allowed semantic write is checked against independent public output.
        checks=[]
        for key in ['score','lives','extra_life_progress','capture_chain','active_seconds']:
            if key in state:checks.append((key,actual[key]==state[key]))
        for key in ['wave_index','wave_remaining_seconds','frightened_remaining_seconds','inactivity_remaining_seconds']:
            if key in state:
                if key=='wave_remaining_seconds' and state.get('wave_index')==7:checks.append((key,actual['timers'][key] is None))
                else:checks.append((key,abs(actual['timers'][key]-state[key])<1e-6))
        for key in ['ordinary_cells','energizer_cells']:
            if key in state:checks.append((key,{cell(c) for c in actual[key]}=={cell(c) for c in state[key]}))
        if 'player' in state:
            m=state['player'];progress=m.get('progress',0);x=m['x']+DIRS[m['direction']][0]*progress;y=m['y']+DIRS[m['direction']][1]*progress
            if x<-.5:x+=30
            if x>29.5:x-=30
            if y<-.5:y+=28
            if y>27.5:y-=28
            checks.append(('player',math.dist((actual['player']['position']['x'],actual['player']['position']['y']),(x,y))<.001 and actual['player']['heading']==NAMES[m['direction']]))
        for spec in state.get('ghosts',[]):
            a=ghost(actual,spec['id']);m=spec['motion'];expected=spec['state']
            if expected=='normal' and actual['timers']['frightened_remaining_seconds']>0:expected='frightened'
            progress=m.get('progress',0);x=m['x']+DIRS[m['direction']][0]*progress;y=m['y']+DIRS[m['direction']][1]*progress
            if x<-.5:x+=30
            if x>29.5:x-=30
            if y<-.5:y+=28
            if y>27.5:y-=28
            checks.append(('ghost:'+spec['id'],a['state']==expected and a['heading']==NAMES[m['direction']] and math.dist((x,y),(a['position']['x'],a['position']['y']))<.001))
        if 'fruit_remaining_seconds' in state:checks.append(('fruit',abs(actual['fruit']['remaining_seconds']-state['fruit_remaining_seconds'])<1e-6))
        if 'fruit_thresholds' in state:checks.append(('fruit_thresholds',actual['fruit']['spawned_thresholds']==state['fruit_thresholds']))
        write(self.p.root/f'fixture/{self.p.case}-acceptance.json',{'requested':state,'actual':actual,'checks':[{'field':k,'matched':v} for k,v in checks],'receipt_sequence':self.sequence,'run_id':before['run_id']})
        if not all(v for _,v in checks):raise InfrastructureError('FIXTURE_PUBLIC_STATE_MISMATCH:'+','.join(k for k,v in checks if not v))
        self.p.capture(self.p.case+'-setup');return actual

def stage_adapter(project,adapter,source_identity):
    spec=load(adapter);src=Path(adapter).parent/spec['source'];expected=spec.get('candidate_identity')
    if expected!=source_identity:raise InfrastructureError('ADAPTER_NOT_REVIEWED_FOR_CANDIDATE')
    if sha(src)!=spec['source_sha256']:raise InfrastructureError('ADAPTER_SOURCE_HASH_MISMATCH')
    module=spec['module'];module_path=Path(project)/'Source'/module
    if not module_path.is_dir():raise InfrastructureError('ADAPTER_MODULE_UNAVAILABLE')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*',module):raise InfrastructureError('ADAPTER_MODULE_UNSAFE')
    for name in ['StateFixture.cpp','StateFixture.h']:shutil.copy2(REPO/'engine/shared/state-fixture'/name,module_path/name)
    shutil.copy2(src,module_path/'PrivateSemanticFixture.cpp')
    return {'adapter':Path(adapter).name,'adapter_sha256':sha(adapter),'source_sha256':sha(src),'candidate_identity':source_identity,'transport':'ue-state-fixture-1.0.0','module':module}
