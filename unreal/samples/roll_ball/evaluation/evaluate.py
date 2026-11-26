"""Portable entry to the bundled, real native evaluator and canonical result adapter."""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, subprocess, sys, time, traceback, uuid
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE/'src'))
sys.path.insert(0, str(HERE.parent / 'input/self-check'))
from check_package import ARCHIVE, catalog_path
from score_adapter import convert_result
EXCLUDES={'.git','.vs','.idea','Binaries','Intermediate','Saved','DerivedDataCache','__pycache__'}

def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,value):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
def digest(data):return hashlib.sha256(data).hexdigest()
def inside(root,name):
 root=Path(root).resolve();p=(root/name).resolve()
 if not p.is_relative_to(root):raise ValueError('Path escapes its allowed root: '+name)
 return p
def copy_tree(source,target,skip=()):
 source=Path(source).resolve()
 if not source.is_dir():raise FileNotFoundError(source.name)
 for directory,dirs,names in os.walk(source,followlinks=False):
  dirs[:]=[d for d in dirs if d not in EXCLUDES]
  for n in dirs+names:
   p=Path(directory)/n
   if p.is_symlink() or not p.resolve().is_relative_to(source):raise ValueError('Linked paths are not supported in submitted trees')
  for n in names:
   if n.endswith(('.pyc','.pyo')) or n in skip:continue
   p=Path(directory)/n;q=target/p.relative_to(source);q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)

def restore_input(source,target,*,allow_project_changes=False):
 bindings=load(HERE/'src/input-layout.json')['files'];source=Path(source).resolve()
 for row in bindings:
  path=inside(source,row['published'])
  if row['published'] == ARCHIVE:
   path = catalog_path(source)
  if allow_project_changes and row['source'].startswith('project/'):continue
  data=path.read_bytes()

  if row.get('restore_edits'):
   lines=data.decode('utf-8').splitlines(keepends=True)
   for edit in reversed(row['restore_edits']):lines[edit['start']:edit['end']]=edit['lines']
   data=''.join(lines).encode('utf-8')

  dest=inside(target,row['source']);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
 if allow_project_changes:
  copy_tree(source/'starter-project',target/'project')
  for row in bindings:
   if not row['source'].startswith('project/') or not row.get('restore_edits'):continue
   path=inside(target,row['source'])
   if not path.is_file() or digest(path.read_bytes())!=row['published_sha256']:continue
   lines=path.read_bytes().decode('utf-8').splitlines(keepends=True)
   for edit in reversed(row['restore_edits']):lines[edit['start']:edit['end']]=edit['lines']
   path.write_bytes(''.join(lines).encode('utf-8'))

def stage(output,project,meta):
 repo=output/'_workspace';task=repo/'unreal'/meta['evaluation']['native_game'];native=task/'evaluator'
 copy_tree(HERE/'src/native',native)
 for name in ['d6','tests']:
  copy_tree(HERE/name,native/name,skip={'test_distribution.py'})
 copy_tree(HERE/'src/dependencies',repo)
 restore_input(HERE.parent/'input',task/'input')
 submitted=output/'submission';project=project.resolve()
 if (project/'BENCHMARK_MANIFEST.json').is_file() and (project/'starter-project').is_dir():
  restore_input(project,submitted,allow_project_changes=True);candidate=submitted/'project'
 else:
  candidate=project.parent if project.suffix.lower()=='.uproject' else project
  restore_input(HERE.parent/'input',submitted,allow_project_changes=False)
  # The submitted project completely replaces the starter, including deleted files.
  target=(submitted/'project').resolve()
  if not target.is_relative_to(output.resolve()):raise ValueError('Candidate isolation path escaped output')
  shutil.rmtree(target)
  copy_tree(candidate,target);candidate=target
 projects=list(candidate.glob('*.uproject'))
 entry=projects[0] if len(projects)==1 else candidate/'__missing_or_ambiguous__.uproject'
 write(output/'evidence/staging.json',{'status':'staged','native_game':meta['evaluation']['native_game'],'input_files':len(load(HERE/'src/input-layout.json')['files']),'candidate_modified':False,'private_workspace':'_workspace','candidate':'submission/project','frozen_bindings_restored':True})
 return repo,task,native,submitted,candidate,entry

def collect_command(game,native,run,repo,submitted,candidate,entry,args):
 py=[sys.executable,'-B'];ps=[args.pwsh,'-NoProfile','-File'];scripts=native/'scripts';engine=str(args.engine)
 if game=='ActionRoguelike':
  cmd=ps+[str(scripts/'Invoke-ActionRoguelikeCanonicalEvaluation.ps1'),'-CandidateProject',str(entry),'-EngineRoot',engine,'-OutputDirectory',str(run)]
  if args.adapter:cmd+=['-FixtureBindingsPath',str(args.adapter)]
 elif game=='Bomber':
  cmd=ps+[str(scripts/'Invoke-BomberCanonicalEvaluation.ps1'),'-CandidateProject',str(entry),'-EngineRoot',engine,'-OutputDirectory',str(run)]
  cmd += ['-D6RunPath',str(args.d6)] if args.d6 else ['-DiagnosticsOnly']
 elif game=='BioFood':
  cmd=py+[str(scripts/'evaluate.py'),'collect','--project',str(candidate),'--out',str(run),'--engine',engine]
  if args.adapter:cmd+=['--adapter',str(args.adapter)]
 elif game=='Bonekest':cmd=py+[str(scripts/'evaluate.py'),'--input-root',str(submitted),'--project-root',str(candidate),'--output',str(run),'--engine-root',engine]
 elif game=='Captain2DPlatformer':cmd=py+[str(scripts/'evaluate.py'),'--candidate',str(submitted),'--output',str(run),'--engine',engine,'--pwsh',args.pwsh]
 elif game=='Chomp':
  cmd=py+[str(scripts/'evaluate.py'),'--candidate',str(submitted),'--run',str(run),'--engine',engine]
  if args.adapter:cmd+=['--adapter',str(args.adapter)]
 elif game=='GemsBond':
  cmd=py+[str(scripts/'collect.py'),'--candidate',str(submitted),'--run',str(run),'--engine',engine]
  if args.adapter:cmd+=['--mapping',str(args.adapter)]
 elif game=='NightSkyEngine':cmd=py+[str(scripts/'evaluate.py'),'--project',str(entry),'--engine',engine,'--pwsh',args.pwsh,'--output',str(run),'--run-id',run.parent.name,'--candidate-id','submitted-project']
 elif game=='OhScrap':cmd=py+[str(scripts/'evaluate.py'),'--candidate',str(submitted),'--output',str(run),'--engine',engine]
 elif game=='RollBall':cmd=py+[str(scripts/'run.py'),'--candidate-project',str(entry),'--engine',engine,'--tools',str(repo),'--pwsh',args.pwsh,'--root',str(run)]
 else:raise ValueError('Unsupported native game')
 return cmd

def finalizer_command(game,native,run,args):
 py=[sys.executable,'-B'];ps=[args.pwsh,'-NoProfile','-File'];scripts=native/'scripts';summary=run/'native-summary.json'
 review=args.review;d6=args.d6
 if game=='BioFood':return py+[str(scripts/'evaluate.py'),'finalize','--run',str(run)]
 if game=='Bonekest':return py+[str(scripts/'score.py'),'finalize',str(run)]
 if game=='Chomp':return py+[str(scripts/'score.py'),str(run)]
 if game=='GemsBond':return py+[str(scripts/'score.py'),'--run',str(run)]
 if game=='OhScrap':
  if review:
   return py+[str(scripts/'evaluate.py'),'--output',str(run),'--finalize','--review',str(review)]+(['--vlm-config',str(args.vlm_config)] if args.vlm_config else [])
  return py+[str(scripts/'score.py'),str(run)]
 if game in ['ActionRoguelike','Bomber']:
  if not d6:raise ValueError('A complete native D6 run is required with --d6')
  verdict=next((p for name in ['verdicts.json','raw-evaluation.json','checkpoint-verdicts.json'] if (p:=run/name).is_file()),None)
  if not verdict:raise ValueError('Native checkpoint verdicts are missing')
  cmd=ps+[str(scripts/f'Invoke-{game}CanonicalScorer.ps1'),'-VerdictsPath',str(verdict),'-D6RunPath',str(d6),'-OutputPath',str(summary)]
  if game=='ActionRoguelike' and review:cmd+=['-EvidenceReviewPath',str(review)]
  return cmd
 if game=='Captain2DPlatformer':
  if not d6:raise ValueError('Native D6 evidence is required')
  return py+[str(scripts/'score.py'),'--raw',str(run/'raw-evaluation.json'),'--d6',str(d6),'--output',str(summary)]+(['--review',str(review)] if review else [])
 if game=='NightSkyEngine':
  if not d6:raise ValueError('Native D6 evidence is required')
  return py+[str(scripts/'score.py'),'--raw',str(run/'raw-evaluation.json'),'--d6',str(d6),'--output',str(summary)]+(['--semantic',str(review)] if review else [])
 if game=='RollBall':
  if not d6:raise ValueError('Native D6 evidence is required')
  return py+[str(scripts/'score.py'),'--collection',str(run/'collection/collection.json'),'--static',str(run/'static/static.json'),'--d6',str(d6),'--output',str(summary)]+(['--review',str(review)] if review else [])
 raise ValueError('Unsupported finalizer')

def invoke(command,output,phase):
 log=output/'evidence'/f'{phase}.log';log.parent.mkdir(parents=True,exist_ok=True)
 env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1',PYTHONIOENCODING='utf-8')
 env['PATH']=str(Path(sys.executable).parent)+os.pathsep+env.get('PATH','')
 started=time.time_ns()
 with log.open('w',encoding='utf-8') as stream:
  process=subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,env=env,cwd=output,check=False)
 write(output/'evidence'/f'{phase}.json',{'command':command,'returncode':process.returncode,'started_ns':started,'log':log.relative_to(output).as_posix()})
 return process.returncode

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--engine',type=Path)
 p.add_argument('--pwsh',default='pwsh');p.add_argument('--adapter',type=Path)
 p.add_argument('--phase',choices=['collect','stage','finalize'],default='collect',help='stage only validates and reconstructs dependencies; finalize explicitly resumes an existing run with bound D6 visual evidence.')
 p.add_argument('--review',type=Path);p.add_argument('--d6',type=Path);p.add_argument('--vlm-config',type=Path)
 args=p.parse_args();meta=load(HERE.parent/'sample.json')
 if not args.project.is_absolute() or not args.output.is_absolute():p.error('--project and --output must be absolute')
 output=args.output.resolve();project=args.project.resolve();sample=HERE.parent.resolve()
 if output==project or output.is_relative_to(project) or output==sample or output.is_relative_to(sample):p.error('Output must be outside the candidate and published sample')
 if args.phase!='finalize':
  if output.exists():p.error('--output must name a new directory')
  output.mkdir(parents=True)
 elif not (output/'evidence/staging.json').is_file():p.error('finalize requires an existing staged evaluation output')
 write(output/'evidence/entry.json',{'phase':args.phase,'sample_id':meta['sample_id'],'evaluator_version':meta['evaluation']['version']})
 infrastructure=False;reason='Native collection completed; D6 visual evidence completion remains required.'
 try:
  if args.phase=='finalize':
   native=output/'_workspace/unreal'/meta['evaluation']['native_game']/'evaluator'
   command=finalizer_command(meta['evaluation']['native_game'],native,output/'native',args)
   code=invoke(command,output,'finalize')
   reason='Native finalizer returned '+str(code)+'. A final score requires all six native observations and the fixed visual evidence.'
  else:
   repo,task,native,submitted,candidate,entry=stage(output,project,meta)
   if args.phase=='stage':reason='Dependency staging only; gameplay and D6 have not been executed.'
   else:
    if args.engine is None or not args.engine.is_absolute():raise ValueError('--engine must be the absolute installed Unreal Engine root')
    engine=load(args.engine/'Engine/Build/Build.version')
    public_manifest=load(HERE.parent/'input/BENCHMARK_MANIFEST.json')
    expected=public_manifest.get('engine') or public_manifest.get('target_engine_identity') or {}
    if expected.get('version') and '.'.join(str(engine[k]) for k in ['MajorVersion','MinorVersion','PatchVersion'])!=expected['version']:raise ValueError('Installed engine differs from the task toolchain')
    if expected.get('changelist') is not None and engine.get('Changelist')!=expected['changelist']:raise ValueError('Installed engine differs from the task toolchain')
    args.pwsh=shutil.which(args.pwsh) or args.pwsh
    code=invoke(collect_command(meta['evaluation']['native_game'],native,output/'native',repo,submitted,candidate,entry,args),output,'collect')
    write(output/'evidence/next-stage.json',{'native_exit_code':code,'native_scripts':native.relative_to(output).as_posix()+'/scripts','review_protocols':'See the fixed D6 contracts and native CLI --help. Supply identity-bound D6 visual evidence; never infer missing scores.','finalize_command':[sys.executable,str(HERE/'evaluate.py'),'--project',str(project),'--output',str(output),'--phase','finalize']})
    # Native collector exit codes are not canonical scoring exit codes. Inspect actual faults.
    if code and not any((output/'native'/n).is_file() for n in ['raw-evaluation.json','collected-checks.json','checks.json','verdicts.json','collection.json','collection/collection.json']):
     if meta['evaluation']['native_game']=='RollBall' and not entry.is_file():
      write(output/'native/entry-inspection.json',{'project_descriptor_files':[p.name for p in candidate.glob('*.uproject')],'requirement':'QUALITY-01','result':'CANDIDATE_PROJECT_MISSING_OR_AMBIGUOUS'})
      write(output/'native/checks.json',{'D1-entry':{'verdict':'fail','reason':'CANDIDATE_PROJECT_MISSING_OR_AMBIGUOUS','attribution':'candidate','evidence':['entry-inspection.json']}})
      reason='The submitted project descriptor is missing or ambiguous. Other checks remain unobserved.'
     else:
      infrastructure=True;reason='Native collector failed before producing checkpoint evidence; see evidence/collect.log.'
 except (Exception,KeyboardInterrupt) as error:
  infrastructure=True;reason=type(error).__name__+': '+str(error)
  write(output/'evidence/entry-fault.json',{'type':type(error).__name__,'reason':str(error),'traceback':traceback.format_exc()})
 result=convert_result(HERE,output,meta,reason,infrastructure=infrastructure)
 from validate_score import apply_scorecard
 apply_scorecard(result, result.get('extensions', {}).pop('outcome_observations', None))
 write(output/'score.json',result)
 validation=subprocess.run([sys.executable,'-B',str(HERE/'validate_score.py'),'--score',str(output/'score.json'),'--check-evidence'],capture_output=True,text=True,encoding='utf-8')
 if validation.returncode:
  write(output/'evidence/validation-error.json',{'stdout':validation.stdout,'stderr':validation.stderr})
  print('Result validation failed; inspect evidence/validation-error.json',file=sys.stderr);return 2
 print(json.dumps({'classification':result['classification'],'final_score':result['final_score'],'score':str(output/'score.json')},ensure_ascii=True))
 return 2 if result['classification']=='infrastructure_failure' else 0 if result['evaluation_valid'] else 3

if __name__=='__main__':raise SystemExit(main())
