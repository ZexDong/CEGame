"""Canonical collection entry. Functional evidence first; D6 finalizes separately."""
from pathlib import Path
import argparse,json,sys,subprocess,traceback,shutil,time
sys.dont_write_bytecode=True
from prepare import *
from session import Session
from extended_cases import CASES
from cases import exit_slot,safe_setup,cell

def static_rows(input_root,project_root,artifact,output):
    descriptor=project_root/'BoneMaze.uproject';manifest=input_root/'BENCHMARK_MANIFEST.json'
    entry=descriptor.is_file() and any((project_root/'Source').rglob('BoneMazeEditor.Target.cs'))
    required=load(TASK/'input/ASSET_CATALOG.json')['assets'];missing=[a['path'] for a in required if a.get('required') and not (project_root/'Content'/Path(a['path']).relative_to('project/Content')).is_file()]
    protected=[]






    write(output/'static-files.json',{'entry':entry,'missing_required_assets':missing,'changed_protected_files':protected})
    return entry,not missing and not protected

def run(a):
    if a.prepared_project and not a.cases:raise InfrastructureError('PREPARED_ARTIFACT_IS_AUTHORING_ONLY')
    root=a.output.resolve();root.mkdir(parents=True,exist_ok=False);input_root=a.input_root.resolve();project=(a.project_root or input_root/'project').resolve()
    version=load(a.engine_root/'Engine/Build/Build.version')
    if (version.get('MajorVersion'),version.get('MinorVersion'),version.get('PatchVersion'),version.get('Changelist'))!=(5,7,4,51494982):raise InfrastructureError('ENGINE_IDENTITY_MISMATCH')
    try:
        public_manifest=load(input_root/'BENCHMARK_MANIFEST.json')
        if not isinstance(public_manifest.get('project_root'),str):raise ValueError('Missing project root')
    except (OSError,ValueError,AttributeError):public_manifest={'project_root':'__invalid_manifest__'}
    if a.project_root is None:
        rel=public_manifest.get('project_root','project');project=(input_root/rel).resolve()
        if not project.is_relative_to(input_root):project=input_root/'__invalid_project_escape__'
    ident=identity(project);write(root/'candidate-identity.json',ident);write(root/'run-binding.json',{'candidate_identity':ident['sha256'],'gdd_sha256':sha(TASK/'input/GDD.md'),'scorer_source_identity':identity(EV)['sha256'],'engine_identity':version,'diagnostic_only':True,'authoring_subset':a.cases is not None,'adapter_contract':sha(EV/'fixtures/fixture-manifest.json')})
    binding=load(root/'run-binding.json');binding.update(catalog_sha256=sha(EV/'checkpoint-catalog.json'),d6_protocol_sha256=sha(EV/'d6/reference-manifest.json'));write(root/'run-binding.json',binding)
    entry,assets=static_rows(input_root,project,ident,root)
    catalog=load(EV/'checkpoint-catalog.json')['checkpoints']
    if not entry:
        checks=[{'id':x['id'],'dimension':x['dimension'],'status':'fail' if x['dimension']=='D1' else 'unreachable','reason_code':'CANDIDATE_PROJECT_ENTRY_MISSING','reason':'The expected project descriptor or editor target is absent.','attribution':'candidate','evidence':'static-files.json'} for x in catalog]
        write(root/'checks.json',checks);write(root/'d6-captures.json',{'states':{s['id']:{'status':'candidate_missing','reason':'project entry missing'} for s in load(EV/'d6/reference-manifest.json')['states']}});return
    private=root/'assessment/project'
    if a.prepared_project:
        private=a.prepared_project.resolve();instrumentation=load(private.parent/'instrumentation.json')
        if instrumentation['source_identity']!=ident['sha256']:raise InfrastructureError('PREPARED_ARTIFACT_IDENTITY_MISMATCH')
    else:instrumentation=prepare(project,private)
    if not a.prepared_project:
        code=build(private/'BoneMaze.uproject',a.engine_root,root/'build.log')
        if code:
            text=(root/'build.log').read_text(encoding='utf-8',errors='replace')
            if private_extension_build_error(text):raise InfrastructureError('PRIVATE_EXTENSION_BUILD_ERROR')
            checks=[{'id':x['id'],'dimension':x['dimension'],'status':'pass' if x['id']=='D1-entry' or (x['id']=='D1-assets' and assets) else 'fail' if x['dimension']=='D1' else 'unreachable','reason_code':'CANDIDATE_BUILD_FAILURE','reason':'Clean candidate compilation failed; dependent gameplay is unreachable.','attribution':'candidate','evidence':'build.log'} for x in catalog];write(root/'checks.json',checks);write(root/'d6-captures.json',{'states':{s['id']:{'status':'candidate_missing','reason':'candidate build failure'} for s in load(EV/'d6/reference-manifest.json')['states']}});return
    c=Session(private/'BoneMaze.uproject',a.engine_root,root/'runtime',ident['sha256'],instrumentation['adapter_key'])
    try:
        c.check('D1-entry',entry,'PROJECT_ENTRY','../static-files.json');c.check('D1-assets',assets,'REQUIRED_ASSETS_OR_PROTECTED_FILES','../static-files.json');c.check('D1-build',True,'CLEAN_BUILD','../build.log')
        c.p.start();s,n,k=c.snap('no-input-entry');inspector=REPO/'engine/observation-player/1.1/Inspect-Image.ps1'
        image_result=subprocess.run(['pwsh','-NoProfile','-File',str(inspector),'-Path',str(c.root/'captures'/f'{k}.png')],capture_output=True,text=True,timeout=20)
        if image_result.returncode:raise InfrastructureError('IMAGE_HEALTH_INSPECTOR_FAILED')
        image_health=json.loads(image_result.stdout);write(root/'image-health.json',image_health);c.check('D1-startup',not image_health['black'],'NORMAL_ENTRY_BLACK_OR_BROKEN','../image-health.json')
        sys.path.insert(0,str(TASK/'input/tools'));from check_observation import validate
        try:format_ok=validate(s,TASK/'input')['status']=='conformant'
        except (ValueError,KeyError):format_ok=False
        c.check('D1-observation',format_ok,'PUBLIC_OBSERVATION_FORMAT_OR_FRESHNESS',{'snapshot':'runtime/states/'+k+'.json'})
        names=a.cases.split(',') if a.cases else ['initial','interface','modes','content','arrangements','seed','movement','collision','spell','reveal','depleted','passage','monster','distribution','encounter','danger','pickups','economy','gate_range','gates','outcomes','restart','cancel','pause','menu','honesty','feedback','resolution','audio','presentation','focus','journey','reopen']
        for name in names:c.run_case(name,CASES[name]);write(root/'checks.json',list(c.results.values()))
        if not a.cases or a.capture_d6:
            # D6 is a distinct stage after all functional judgments. References
            # and visual similarity never feed a functional checkpoint.
            c.case_name='d6';c.p.case='d6';captures={}
            try:
                from window import WindowHost
                write(root/'d6-viewport.json',WindowHost(c.p.process_id).resize(1920,1080))
                c.restart();c.p.observe(.4);s,n,k=c.snap('chamber');captures['chamber']={'status':'captured','path':'runtime/captures/'+k+'.png'}
                c.p.hold(['W'],.35);s,n,k=c.snap('camera');captures['camera']={'status':'captured','path':'runtime/captures/'+k+'.png'}
                c.p.press('Q',60);c.p.wait(lambda s:s['slots']['reveal_active']==1,3);s,n,k=c.snap('reveal');captures['reveal']={'status':'captured','path':'runtime/captures/'+k+'.png'}
                c.restart();s=c.state();x=exit_slot(s)
                # Reach this state through the actual passage input. A fixture
                # may shorten the walk but never sets the destination/outcome.
                safe_setup(c,cell(s),anchor='passage',slot=x['slot']);c.cross(x['slot']);c.p.wait(lambda s:s['phase']=='exploring',3);s,n,k=c.snap('transfer');captures['transfer']={'status':'captured','path':'runtime/captures/'+k+'.png'}
            except CandidateError as e:
                for state in load(EV/'d6/reference-manifest.json')['states']:captures.setdefault(state['id'],{'status':'candidate_missing','reason':str(e)})
            write(root/'d6-captures.json',{'states':captures})
    except CandidateError as e:
        for row in catalog:
            if row['id'] not in c.results:c.results[row['id']]={'id':row['id'],'dimension':row['dimension'],'status':'unreachable','reason_code':'CANDIDATE_RUNTIME_FAILURE','reason':str(e),'attribution':'candidate','evidence':'runtime/receipts'}
        write(root/'d6-captures.json',{'states':{s['id']:{'status':'candidate_missing','reason':str(e)} for s in load(EV/'d6/reference-manifest.json')['states']}})
    finally:
        c.close();write(root/'checks.json',list(c.results.values()))
    write(root/'collection-status.json',{'status':'authoring_subset' if a.cases else 'functional_collection_complete','next':'D6 conversation request generation and strict finalizer','formal_score':False})

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input-root',type=Path,required=True);p.add_argument('--project-root',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--engine-root',type=Path,required=True);p.add_argument('--cases',help='Authoring-only subset; never finalizable as a score');p.add_argument('--prepared-project',type=Path,help='Authoring-only reuse of an already isolated instrumented build');p.add_argument('--capture-d6',action='store_true',help='Collect D6 states after a justified authoring repair; a subset still cannot finalize');args=p.parse_args()
    try:run(args)
    except InfrastructureError as e:write(args.output/'run-invalid.json',{'status':'run_invalid','attribution':'evaluator_or_host','reason':str(e)});print(str(e),file=sys.stderr);sys.exit(3)
    except Exception as e:write(args.output/'run-invalid.json',{'status':'run_invalid','attribution':'evaluator_authoring','reason':repr(e),'traceback':traceback.format_exc()});traceback.print_exc();sys.exit(3)
