from __future__ import annotations
import hashlib,importlib.util,json,os,shutil,subprocess,sys,time,uuid
from pathlib import Path
from spec import TASK,REPO,units
sys.path.insert(0,str(REPO/'engine/observation-player/1.0'))
from runtime import Player,CandidateError,InfrastructureError,load,write,sha,identity
spec=importlib.util.spec_from_file_location('public_snapshot_check',TASK/'input/tools/check_observation.py')
snapshot_check=importlib.util.module_from_spec(spec);spec.loader.exec_module(snapshot_check)
GENERATED={'.git','.vs','Binaries','Intermediate','Saved','DerivedDataCache','__pycache__'}
def clone(source,destination):
    source=Path(source).resolve()
    if not source.is_dir():raise CandidateError('PROJECT_ROOT_MISSING')
    for parent,dirs,files in os.walk(source):
        dirs[:]=[d for d in dirs if d not in GENERATED]
        for n in dirs+files:
            p=Path(parent)/n
            if p.is_symlink() or not p.resolve().is_relative_to(source):raise CandidateError('PROJECT_PATH_ESCAPE')
    shutil.copytree(source,destination,ignore=shutil.ignore_patterns(*GENERATED))
def compile_project(project,engine,log):
    targets=sorted((project.parent/'Source').rglob('*Editor.Target.cs'))
    preferred=[t for t in targets if t.name==project.stem+'Editor.Target.cs']
    if preferred:targets=preferred
    if len(targets)!=1:raise CandidateError('EDITOR_BUILD_TARGET_MISSING_OR_AMBIGUOUS')
    target=targets[0].name[:-len('.Target.cs')]
    with Path(log).open('w',encoding='utf-8') as out:
        try:r=subprocess.run([str(engine/'Engine/Build/BatchFiles/Build.bat'),target,'Win64','Development','-Project='+str(project),'-WaitMutex','-NoHotReloadFromIDE'],stdout=out,stderr=subprocess.STDOUT,timeout=900)
        except subprocess.TimeoutExpired as e:raise CandidateError('BUILD_TIMEOUT_900_SECONDS') from e
    return r.returncode
def inspect_image(path):
    r=subprocess.run(['pwsh','-NoProfile','-File',str(REPO/'engine/observation-player/1.0/Inspect-Image.ps1'),'-Path',str(path)],capture_output=True,text=True,encoding='utf-8',timeout=15)
    if r.returncode:raise InfrastructureError('IMAGE_DECODER_FAILED:'+r.stderr)
    return json.loads(r.stdout)
def select(s,kind,**attrs):
    targets=[t for t in s['targets'] if t['kind']==kind and t.get('visible') and t.get('interactable') and all(t.get(k)==v for k,v in attrs.items())]
    if not targets and kind=='inspect' and attrs.get('entity_id'):
        entities=[e for e in s['entities'] if e.get('id')==attrs['entity_id'] and e.get('cell') is not None]
        if len(entities)==1:
            targets=[t for t in s['targets'] if t['kind']=='board_cell' and t.get('cell')==entities[0]['cell'] and t.get('visible') and t.get('interactable')]
    if not targets:raise CandidateError('PUBLIC_TARGET_UNREACHABLE:'+kind+':'+str(attrs))
    # Repeated semantic controls (e.g. Restart on HUD and result panel) are valid.
    return max(targets,key=lambda t:t['rect'][2]*t['rect'][3])
class Case:
    def __init__(self,p,name):
        self.p=p;self.name=name;self.votes={};self.start_index=len(p.samples);self.start_action=len(p.actions);self.captures=[]
        p.case=name;p.set_case_budget(name,180 if name in ['lifecycle','seed'] else 65,80)
    def state(self):return self.p.state()
    def observe(self,n):return self.p.observe(n)
    def wait(self,f,n=5):return self.p.wait(f,n)
    def click(self,kind,**attrs):
        t=select(self.state(),kind,**attrs);r=t['rect'];self.p.rpc('click',x=r[0]+r[2]/2,y=r[1]+r[3]/2,button='Left',ms=55);return self.fresh_observation()
    def move(self,kind,**attrs):
        t=select(self.state(),kind,**attrs);r=t['rect'];self.p.rpc('move',x=r[0]+r[2]/2,y=r[1]+r[3]/2);return self.observe(.1)
    def fresh_observation(self):
        revision=self.state()['snapshot_id']
        return self.wait(lambda s:s['snapshot_id']>revision,.4)
    def key(self,k,ms=40):self.p.press(k,ms);return self.fresh_observation()
    def build(self,k,cell):self.click('build_'+k);return self.click('board_cell',cell=cell)
    def inspect(self,e):self.key('Escape');return self.click('inspect',entity_id=e['id'])
    def capture(self,label='after'):
        r=self.p.capture(self.name+'-'+label);self.captures.append(r['path']);return r
    def vote(self,id,ok,detail):
        old=self.votes.get(id);row={'verdict':'pass' if ok else 'fail','reason':'PUBLIC_REQUIREMENT_MET' if ok else 'PUBLIC_REQUIREMENT_VIOLATION','detail':detail,'attribution':'candidate'}
        if old and old['verdict']!='pass':return
        self.votes[id]=row
    def samples(self):return [r['state'] for r in self.p.samples[self.start_index:] if r['case']==self.name]
    def finish(self,error=None):
        if not self.captures:
            try:self.capture()
            except CandidateError:pass
        row={'case':self.name,'votes':self.votes,'error':str(error) if error else None,
             'captures':self.captures,'action_range':[self.start_action,len(self.p.actions)],'sample_range':[self.start_index,len(self.p.samples)],
             'session':self.p.root.name,'cleanup':'cleanup.json','input_actions':sum(a['operation'] in ['click','press','down','up','move','mouse_down','mouse_up'] for a in self.p.actions[self.start_action:])}
        write(self.p.root/'cases'/f'{self.name}.json',row);self.p.case_budget=None;return row
def prepare_fixture(project_root,destination,mapping):
    clone(project_root,destination)
    mapping=load(mapping);expected=mapping['source_files']
    for name,digest in expected.items():
        p=Path(project_root)/name
        if not p.is_file() or hashlib.sha256(p.read_text(encoding='utf-8-sig').encode('utf-8')).hexdigest()!=digest:raise InfrastructureError('FIXTURE_MAPPING_SOURCE_IDENTITY_MISMATCH:'+name)
    for patch in mapping.get('assessment_source_patches',[]):
        path=(destination/patch['path']).resolve()
        if not path.is_relative_to(destination.resolve()):raise InfrastructureError('FIXTURE_PATCH_PATH_ESCAPE')
        text=path.read_text(encoding='utf-8-sig')
        if text.count(patch['before'])!=1:raise InfrastructureError('FIXTURE_PATCH_ANCHOR_MISMATCH')
        path.write_text(text.replace(patch['before'],patch['after']),encoding='utf-8')
    module=destination/mapping['module_path'];module.mkdir(parents=True,exist_ok=True)
    for name in ['StateFixture.h','StateFixture.cpp']:shutil.copy2(REPO/'engine/shared/state-fixture'/name,module/name)
    adapter=TASK/'evaluator'/mapping['adapter_source']
    if sha(adapter)!=mapping['adapter_sha256']:raise InfrastructureError('FIXTURE_MAPPING_ADAPTER_HASH')
    shutil.copy2(adapter,module/'EvaluationSetupMapping.cpp')
    return mapping
def setup(p,state,source_identity):
    directory=p.root/'userdata/private-fixture';directory.mkdir(parents=True,exist_ok=True)
    token=uuid.uuid4().hex+uuid.uuid4().hex
    write(directory/'authorization.json',{'nonce':token,'candidate_identity':source_identity})
    p.start()
    c=Case(p,'setup');before=c.state();c.capture('before')
    write(directory/'request.json',{'nonce':token,'sequence':1,'operation':'apply','semantic_state':state})
    deadline=time.perf_counter()+5
    while time.perf_counter()<deadline and not (directory/'receipt-1.json').exists():time.sleep(.02)
    if not (directory/'receipt-1.json').exists():raise InfrastructureError('FIXTURE_TRANSPORT_NO_RECEIPT')
    receipt=load(directory/'receipt-1.json')
    if not receipt.get('applied'):raise InfrastructureError('FIXTURE_SETUP_REJECTED:'+receipt.get('reason',''))
    after=c.wait(lambda s:s['phase']=='paused',3);c.observe(.15);c.capture('accepted')
    native=receipt['after']
    if native.get('coins')!=after['slots']['coins'] or native.get('phase')!=after['phase'] or before['round_id']!=after['round_id']:raise InfrastructureError('FIXTURE_NATIVE_PUBLIC_MISMATCH')
    if 'coins' in state and after['slots']['coins']!=state['coins']:raise InfrastructureError('FIXTURE_STATE_NOT_ESTABLISHED')
    if len(state.get('units',[]))+5!=len([e for e in after['entities'] if e['kind']!='feedback']):raise InfrastructureError('FIXTURE_ENTITY_NOT_ESTABLISHED')
    write(p.root/'setup-receipt.json',{'version':'1.0','before':before,'after':after,'native_receipt':receipt,'request':state,'candidate_identity':source_identity,'no_result_functions':True})
    c.finish();p.case_budget=None
    return after
