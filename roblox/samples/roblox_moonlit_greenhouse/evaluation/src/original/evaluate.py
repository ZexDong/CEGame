from __future__ import annotations
import hashlib,json,os,shutil,subprocess,sys,time
from datetime import datetime
from pathlib import Path

ROOT=Path(__file__).resolve().parent
CANDIDATE=ROOT/'source/MoonlitGreenhouse'
TOOLS=ROOT/'tools'
PREFIX='MG26_QA '
REVISION='moonlit-greenhouse-20261026-v3.1-physical-input-natural-final'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
def call(argv,log):
    r=subprocess.run([str(a) for a in argv],capture_output=True,text=True,encoding='utf-8',errors='replace')
    log.write_text(r.stdout+r.stderr,encoding='utf-8')
    print(log.name,r.returncode,flush=True)
    if r.returncode: raise RuntimeError(log.read_text(encoding='utf-8'))
    return r.stdout

def prepare():
    TOOLS.mkdir(exist_ok=True)
    previous=ROOT.parent/'MoonlitGreenhouse_GamesBuild_Evaluation_20261023/tools'
    for n in ('rojo.exe','luau.exe','luau-compile.exe'):
        if not (TOOLS/n).is_file(): shutil.copy2(previous/n,TOOLS/n)
    evidence=ROOT/'evidence'/datetime.now().strftime('preflight_%Y%m%d_%H%M%S')
    evidence.mkdir(parents=True)
    scripts=sorted((CANDIDATE/'src').rglob('*.luau'))+sorted((ROOT/'runtime').rglob('*.luau'))
    for i,p in enumerate(scripts): call([TOOLS/'luau-compile.exe','--null',p],evidence/f'compile_{i}.log')
    rebuilt=evidence/'MoonlitGreenhouse_Rebuilt.rbxlx'
    call([TOOLS/'rojo.exe','build',CANDIDATE/'default.project.json','-o',rebuilt],evidence/'build.log')
    supplied=Path(ROOT/'input/MoonlitGreenhouse.rbxlx')
    shutil.copy2(supplied,ROOT/'MoonlitGreenhouse.rbxlx')
    originalzip=supplied.with_name('MoonlitGreenhouse_Source.zip')
    hashes={'source_zip_sha256':sha(originalzip),'supplied_place_sha256':sha(supplied),'rebuilt_place_sha256':sha(rebuilt),'byte_identical':supplied.read_bytes()==rebuilt.read_bytes(),'sources':{str(p.relative_to(CANDIDATE)):sha(p) for p in sorted((CANDIDATE/'src').rglob('*.luau'))}}
    write(evidence/'candidate_identity.json',hashes)
    # Candidate behavior is checked in Studio through the published interfaces.
    # Compile and build use the submitted project without private source-layout assumptions.
    build(ROOT/'qa_main',False);build(ROOT/'qa_fresh',True)
    write(ROOT/'preflight.json',{'revision':REVISION,'status':'PASS','candidate_identity':hashes,'evidence':str(evidence),'runtime_score':'PENDING_STUDIO','physical_input':'PENDING','manual_visual':'PENDING'})
    print('PREFLIGHT PASS; byte-identical source/place:',hashes['byte_identical'],flush=True)
    return evidence

def build(out,fresh=False):
    out.mkdir(exist_ok=True,parents=True)
    project=json.loads((CANDIDATE/'default.project.json').read_text(encoding='utf-8'))
    def resolve(v):
        if isinstance(v,dict):
            for k,x in v.items():
                if k=='$path':v[k]=str((CANDIDATE/x).resolve())
                else:resolve(x)
    resolve(project)
    project['name']='MoonlitGreenhouse_20261026_QA_'+('Fresh' if fresh else 'Main')
    t=project['tree'];t['ServerScriptService']['PrivateQA']={'$path':str(ROOT/'runtime/observer.server.luau')}
    t['StarterPlayer']['StarterPlayerScripts']['PrivateQA']={'$path':str(ROOT/'runtime/trajectory.client.luau')}
    if fresh:t['ReplicatedStorage']['MoonlitGreenhouseFreshProbe']={'$className':'BoolValue','$properties':{'Value':True}}
    pp=out/'qa.project.json';write(pp,project)
    place=out/(project['name']+'.rbxlx')
    call([TOOLS/'rojo.exe','build',pp,'-o',place],out/'build.log')
    return place

def studio_exe():
    return max((Path(os.environ['LOCALAPPDATA'])/'Roblox/Versions').glob('*/RobloxStudioBeta.exe'),key=lambda p:p.stat().st_mtime)

def launch(fresh=False):
    place=ROOT/('qa_fresh' if fresh else 'qa_main')/('MoonlitGreenhouse_20261026_QA_'+('Fresh' if fresh else 'Main')+'.rbxlx')
    p=subprocess.Popen([str(studio_exe()),'-task','EditFile','-localPlaceFile',str(place)])
    record={'pid':p.pid,'place':str(place),'started_at':time.time(),'fresh':fresh}
    write(ROOT/('launch_fresh.json' if fresh else 'launch_main.json'),record)
    print(json.dumps(record),flush=True)

def read_packets():
    packets=[];chunks={};logs=[]
    for fresh in (False,True):
        f=ROOT/('launch_fresh.json' if fresh else 'launch_main.json')
        if not f.exists():continue
        launch=json.loads(f.read_text(encoding='utf-8'));stem=Path(launch['place']).stem
        candidates=[]
        for log in (Path(os.environ['LOCALAPPDATA'])/'Roblox/logs').glob('*Studio*_last.log'):
            if log.stat().st_mtime<launch['started_at']-3:continue
            content=log.read_text(encoding='utf-8',errors='replace')
            if stem.lower() in content.lower():candidates.append((log,content))
        if not candidates:continue
        log,content=max(candidates,key=lambda pair:pair[0].stat().st_ctime)
        logs.append({'fresh':fresh,'path':str(log)})
        for line in content.splitlines():
            if PREFIX not in line:continue
            try: v=json.loads(line.split(PREFIX,1)[1])
            except ValueError:continue
            if v.get('kind')=='chunk':
                key=(fresh,v['packet']);c=chunks.setdefault(key,{})
                c[v['part']]=v['data']
                if len(c)!=v['total']:continue
                try:v=json.loads(''.join(c[i] for i in range(1,v['total']+1)))
                except (KeyError,ValueError):continue
            v['_fresh']=fresh;packets.append(v)
    return packets,logs

def snapshot():
    packets,logs=read_packets()
    checks={p['id']:p for p in packets if p.get('kind')=='check'}
    rules=json.loads((ROOT/'rules.json').read_text(encoding='utf-8'))
    dimensions={};total=unknown=failed=0
    for d,spec in rules['dimensions'].items():
        if spec.get('manual'):dimensions[d]={'status':'MANUAL_PENDING','maximum':10};continue
        passed=sum(c['weight'] for c in spec['checks'] if checks.get(c['id'],{}).get('status')=='PASS')
        pending=sum(c['weight'] for c in spec['checks'] if checks.get(c['id'],{}).get('status') not in ('PASS','FAIL_OBSERVED'))
        loss=spec['maximum_score']-passed-pending
        dimensions[d]={'confirmed':passed,'unresolved':pending,'failed':loss,'maximum':spec['maximum_score']}
        total+=passed;unknown+=pending;failed+=loss
    errors=[p for p in packets if p.get('kind') in ('error','segment_error')]
    done=[p for p in packets if p.get('kind')=='done']
    summary={'revision':REVISION,'automatic_confirmed':total,'automatic_failed':failed,'automatic_unresolved':unknown,'automatic_maximum':90,'dimensions':dimensions,'checks':checks,'errors':errors,'done':done,'last_events':packets[-4:],'logs':logs,'note':'Physical E keys drive gameplay prompts and terminal R verifies the original input handlers. Final sequence uses natural Humanoid movement; earlier bed setup uses QA character placement. Visual score is separate.'}
    write(ROOT/'current_result.json',summary)
    write(ROOT/'events.json',packets)
    print(json.dumps(summary,ensure_ascii=False,indent=2))
    return summary

if __name__=='__main__':
    mode=sys.argv[1] if len(sys.argv)>1 else '--prepare'
    if mode=='--prepare':prepare()
    elif mode=='--launch-main':launch()
    elif mode=='--launch-fresh':launch(True)
    elif mode=='--status':snapshot()
    else:raise SystemExit('Unknown option')
