"""Collect real D1-D5 evidence, then prepare the independent dialogue D6 stage."""
from common import *
from fixture import Fixture,stage_adapter
from cases import Cases
import argparse,subprocess,shutil,time,traceback,zipfile,io,os

def build(project,engine,root):
    descriptors=list(project.glob('*.uproject'))
    if len(descriptors)!=1:raise CandidateError('PROJECT_DESCRIPTOR_MISSING_OR_AMBIGUOUS')
    targets=list((project/'Source').glob('*Editor.Target.cs'))
    if len(targets)!=1:raise CandidateError('EDITOR_TARGET_MISSING_OR_AMBIGUOUS')
    name=targets[0].name[:-len('.Target.cs')]
    command=[str(engine/'Engine/Build/BatchFiles/Build.bat'),name,'Win64','Development',f'-Project={descriptors[0]}','-WaitMutex','-NoHotReloadFromIDE']
    start=time.perf_counter()
    with (root/'build.log').open('w',encoding='utf-8') as log:
        try:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=600)
        except subprocess.TimeoutExpired as e:raise CandidateError('CANDIDATE_BUILD_TIMEOUT') from e
    write(root/'build-receipt.json',{'target':name,'engine':'5.7.4','exit_code':r.returncode,'elapsed_seconds':time.perf_counter()-start,'log':'build.log'})
    if r.returncode:
        log=(root/'build.log').read_text(encoding='utf-8',errors='replace')
        if any(('PrivateSemanticFixture.cpp' in line or 'StateFixture.cpp' in line) and 'error' in line.lower() for line in log.splitlines()):raise InfrastructureError('PRIVATE_ADAPTER_COMPILE_FAILED')
        raise CandidateError('CANDIDATE_BUILD_FAILED')
    return descriptors[0]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',required=True);ap.add_argument('--run',required=True);ap.add_argument('--engine',required=True);ap.add_argument('--adapter');ap.add_argument('--cases');ap.add_argument('--skip-build',action='store_true');ap.add_argument('--kind',choices=['gold','untouched','candidate'],default='candidate');args=ap.parse_args()
    candidate=Path(args.candidate).resolve();root=Path(args.run).resolve();engine=Path(args.engine).resolve()
    if root.exists():raise SystemExit('A new isolated run directory is required.')
    root.mkdir(parents=True);project=candidate
    if (candidate/'BENCHMARK_MANIFEST.json').exists():
        manifest=load(candidate/'BENCHMARK_MANIFEST.json');project=(candidate/manifest.get('project_root','project')).resolve()
        if not project.is_relative_to(candidate):raise CandidateError('PROJECT_ROOT_ESCAPE')
    elif (candidate/'project').is_dir():project=candidate/'project'
    catalog=load(TASK/'evaluator/catalog/checkpoints.json')['checks'];plan=load(TASK/'evaluator/catalog/cases.json')['cases'];budget=load(TASK/'evaluator/contracts/budget.json')
    selected=set(args.cases.split(',')) if args.cases else {c['id'] for c in plan}
    plan=[c for c in plan if c['id'] in selected]
    plan.sort(key=lambda c:c['id']=='persistence')
    if args.cases and len(plan)!=len(selected):raise InfrastructureError('UNKNOWN_CASE_SELECTION')
    raw={'version':'chomp-atomic-1.0.0','kind':args.kind,'status':'collecting','run_id':root.name,'candidate':identity(project),'checkpoints':{},'cases':{},'d6_captures':{},'partial_selection':bool(args.cases),'case_selection':sorted(selected)}
    write(root/'candidate-identity.json',raw['candidate']);write(root/'budget.json',budget)
    p=None;f=None;current='static';c_start=0;a_start=0;sample_start=0
    def record(id,passed,reason,details=None):
        if id not in {c['id'] for c in catalog}:raise InfrastructureError('UNKNOWN_CHECK:'+id)
        raw['checkpoints'][id]={'verdict':'pass' if passed else 'fail','reason':reason,'attribution':'observed_behavior' if passed else 'candidate','case':current,'details':details,'evidence':{'session':'session','captures':[x.relative_to(root).as_posix() for x in (root/'session/captures').glob(current+'*.png')] if (root/'session/captures').exists() else [],'samples':'session/samples.jsonl','actions':'session/actions.json'}}
        write(root/'raw-evaluation.json',raw)
    try:
        version=load(engine/'Engine/Build/Build.version')
        if [version[k] for k in ['MajorVersion','MinorVersion','PatchVersion','Changelist']]!=[5,7,4,51494982]:raise InfrastructureError('ENGINE_IDENTITY_MISMATCH')
        desc=list(project.glob('*.uproject')) if project.is_dir() else []
        require(len(desc)==1,'PROJECT_DESCRIPTOR_MISSING_OR_AMBIGUOUS');descriptor=load(desc[0]);require(isinstance(descriptor,dict),'PROJECT_DESCRIPTOR_INVALID');record('D1-project',True,'PROJECT_RESOLVED')
        stage=root/'assessment/project';stage.parent.mkdir(parents=True)
        shutil.copytree(project,stage,ignore=shutil.ignore_patterns(*GENERATED))
        write(root/'copy-receipt.json',{'operation':'direct clean copy','source_identity':raw['candidate']['sha256'],'destination':'assessment/project','excluded_generated':sorted(GENERATED),'candidate_modified':False})
        if args.adapter:raw['adapter']=stage_adapter(stage,Path(args.adapter).resolve(),raw['candidate']['sha256'])
        if args.skip_build:raise InfrastructureError('CLEAN_ASSESSMENT_REQUIRES_BUILD')
        uproject=build(stage,engine,root);record('D1-build',True,'CLEAN_BUILD_PASSED')
        p=GamePlayer(uproject,engine,root/'session',watchdog=budget['session_watchdog_seconds']);f=Fixture(p,raw['candidate']['sha256']) if args.adapter else None
        p.start();capture=p.capture('startup');from PIL import Image,ImageStat
        im=Image.open(p.root/capture['path']).convert('RGB');variation=max(ImageStat.Stat(im).stddev);record('D1-startup',variation>3,'RESPONSIVE_NONBLACK_CLIENT',{'pixel_stddev_max':variation})
        write(root/'observation-schema-sample.json',p.state())
        schema_check=subprocess.run(['pwsh','-NoProfile','-File',str(TASK/'input/tools/Test-Observation.ps1'),'-Path',str(root/'observation-schema-sample.json')],capture_output=True,text=True,encoding='utf-8')
        write(root/'observation-self-check.json',{'exit_code':schema_check.returncode,'stdout':schema_check.stdout,'stderr':schema_check.stderr});record('D1-observation',schema_check.returncode==0,'PUBLIC_SCHEMA_VALID' if schema_check.returncode==0 else 'PUBLIC_SCHEMA_INVALID')
        if f:write(root/'fixture-health.json',f.request('probe'))
        provider=p.state().get('provider_ready',False)
        if not provider:
            for c in catalog:
                if c['stage']=='dynamic':raw['checkpoints'][c['id']]={'verdict':'unreachable','reason':'GAMEPLAY_PROVIDER_UNAVAILABLE','attribution':'candidate','case':c['case'],'evidence':{'capture':'session/captures/startup.png','snapshot':'session/observation.json'}}
            raw['d6_captures']={'title':{'path':'session/captures/startup.png','sha256':capture['sha256']},'options':{'missing':True,'reason':'CANDIDATE_HAS_NO_OPTIONS'},'maze':{'missing':True,'reason':'CANDIDATE_HAS_NO_GAMEPLAY'}}
        else:
            test=Cases(p,f,record)
            # Real normal-input D6 capture preparation. The images are consumed
            # only after D1-D5; these actions are not scored twice.
            p.case='d6-title';s=p.game()
            if s['phase']=='menu':
                cap=p.capture('d6-title');raw['d6_captures']['title']={'path':'session/'+cap['path'],'sha256':cap['sha256']}
                try:
                    p.click_target('options');p.wait_game(lambda s:s['phase']=='options');cap=p.capture('d6-options');raw['d6_captures']['options']={'path':'session/'+cap['path'],'sha256':cap['sha256']};p.click_target('back');p.wait_game(lambda s:s['phase']=='menu')
                except CandidateError as e:raw['d6_captures']['options']={'missing':True,'reason':str(e)}
            else:raw['d6_captures']['title']={'missing':True,'reason':'NO_MAIN_MENU'}
            for cp in plan:
                current=cp['id'];p.case=current;c_start=time.perf_counter();a_start=len(p.actions);sample_start=len(p.samples)
                print('CASE',current,flush=True)
                try:
                    if cp['setup_method']!='normal_input' and f is None:raise InfrastructureError('PRIVATE_SEMANTIC_ADAPTER_REQUIRED:'+current)
                    test.run(current)
                    tested=[a for a in p.actions[a_start:] if a.get('phase','test')=='test' and a['operation'] in ['press','down','click','start','stop']]
                    if len(tested)>cp['max_actions']:raise InfrastructureError('AUTHORED_ACTION_BUDGET_EXCEEDED:'+current+':'+str(len(tested)))
                    if time.perf_counter()-c_start>cp['max_serial_seconds']+18*cp.get('setup_repetitions',1):raise InfrastructureError('AUTHORED_CASE_BUDGET_EXCEEDED:'+current)
                    if current=='entry':
                        cap=p.capture('d6-maze');raw['d6_captures']['maze']={'path':'session/captures/entry-live.png','sha256':sha(p.root/'captures/entry-live.png')}
                    for id in cp['check_ids']:
                        if id not in raw['checkpoints']:raise InfrastructureError('CHECK_NOT_EXECUTED:'+id)
                    raw['cases'][current]={'status':'completed','elapsed_seconds':time.perf_counter()-c_start,'rpc_count':len(p.actions)-a_start,'tested_actions':len(tested),'sample_count':len(p.samples)-sample_start}
                except CandidateError as e:
                    raw['cases'][current]={'status':'candidate_failure','reason':str(e),'elapsed_seconds':time.perf_counter()-c_start}
                    try:p.capture(current+'-failure',observation=False)
                    except Exception as capture_error:raw['cases'][current]['failure_capture_error']=str(capture_error)
                    for id in cp['check_ids']:
                        if id not in raw['checkpoints']:record(id,False,str(e))
                finally:
                    for key in list(p.held):p.up(key)
                    write(root/f'cases/{current}.json',raw['cases'].get(current,{'status':'interrupted'}));write(root/'raw-evaluation.json',raw)
        raw['status']='d6_pending';write(root/'raw-evaluation.json',raw)
    except InfrastructureError as e:
        raw['status']='run_invalid';raw['fault']={'attribution':'evaluator_or_host','reason':str(e),'case':current,'traceback':traceback.format_exc()};write(root/'raw-evaluation.json',raw);print(traceback.format_exc());return 3
    except (CandidateError,json.JSONDecodeError) as e:
        raw['status']='d6_pending';raw['candidate_failure']={'reason':str(e),'case':current}
        for c in catalog:
            if c['id'] not in raw['checkpoints']:raw['checkpoints'][c['id']]={'verdict':'unreachable','attribution':'candidate','reason':str(e),'case':c['case'],'evidence':{'build':'build.log','startup':'session/host.log'}}
        for state in ['title','options','maze']:
            raw['d6_captures'].setdefault(state,{'missing':True,'reason':str(e)})
        write(root/'raw-evaluation.json',raw)
    except Exception as e:
        raw['status']='run_invalid';raw['fault']={'attribution':'evaluator','reason':repr(e),'case':current,'traceback':traceback.format_exc()};write(root/'raw-evaluation.json',raw);print(traceback.format_exc());return 3
    finally:
        if p:
            try:p.close()
            except Exception as e:raw['status']='run_invalid';raw['fault']={'attribution':'host_cleanup','reason':repr(e)};write(root/'raw-evaluation.json',raw)
    if raw['status']=='run_invalid':return 3
    from d6 import prepare
    prepare(root);print('D6 dialogue evidence prepared:',root);return 4

if __name__=='__main__':raise SystemExit(main())
