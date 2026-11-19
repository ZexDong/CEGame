"""Collect D1 and normal-player evidence; score only after required reviews exist."""
import argparse
import math
import os
import shutil
import subprocess
import time
from pathlib import Path
from runtime import (ROOT,TASK,REPO,EXCLUDES,Player,Observer,CandidateError,InfrastructureError,
                     load,write,sha,identity,inside,Budget,code_identity)

from atomic import AtomicCases, field, game, number, fresh, span
from coverage_cases import CoverageCases

class Evaluation(CoverageCases):
    def __init__(self,args):
        self.args=args;self.root=args.output.resolve();self.p=None;self.o=None
        self.start=time.monotonic();self.faults=[];self.captures={};self.facts={};self.journeys=[]
        self.budget=Budget();self.binding=code_identity()
        self.catalog=load(ROOT/'catalog/checkpoints.json');self.cases=load(ROOT/'catalog/trajectories.json')['trajectories']
        self.verdicts={c['id']:{'checkpoint_id':c['id'],'dimension':c['dimension'],'verdict':'unreachable',
            'reason':'CANDIDATE_PRECONDITION_UNREACHABLE','evidence':[]} for c in self.catalog['checkpoints']}

    def mark(self,id,passed,reason,*evidence):
        self.verdicts[id].update(verdict='pass' if passed else 'fail',reason=reason,evidence=list(evidence))

    def cap(self,name):
        self.captures[name]=self.p.capture(name)
        return self.captures[name]

    def boundary(self,name,timeout=5):
        positions=[];start=number(game(self.o.last),'player.normalized_position.x')
        def stopped(g):
            x=number(g,'player.normalized_position.x')
            clock=number(g,'combat.round_time_ms')
            if positions and abs(x-positions[0][1])>=.001: positions.clear()
            positions.append((clock,x))
            # A short pause can be caused by a hit/action commitment. Require a
            # sustained stationary window while held input remains active and the
            # player is no longer in a transient hit/action state.
            # The public bridge permits 250 ms publication. Measure elapsed
            # game time rather than demanding 20 updates inside five seconds.
            return (len(positions)>=3 and clock-positions[0][0]>=500 and abs(x-start)>.01
                and field(g,'player.action_state') in ('idle','moving'))
        found=self.wait(name,stopped,timeout,2)
        return load(self.root/'states'/f'{name}.json')['samples'] if found else []

    def wait(self,name,predicate,timeout=2,stable=1):
        return self.o.wait(name,predicate,timeout,stable)

    def press(self,key): self.p.call('press',key=key)

    def restart(self,name):
        old=self.o.last
        self.press('R')
        result=self.wait(name,lambda g:fresh(g) and number(g,'combat.round_time_ms')>=80,1,stable=2)
        # Availability is a separate question from exact restoration of every field.
        observed=load(self.root/'states'/f'{name}.json')['samples']
        if old and any(s.get('round_id')!=old['round_id'] and field(game(s),'phase')=='active' for s in observed):
            self.facts['restart_available']=True
        if not result or not old or result['round_id']==old['round_id']:
            raise CandidateError('RESTART_NOT_FRESH:'+name)
        initial=game(getattr(self,'case_initial',self.facts.get('initial')))
        if initial and (abs(number(game(result),'player.normalized_position.x')-number(initial,'player.normalized_position.x'))>.003
            or abs(number(game(result),'rival.normalized_position.x')-number(initial,'rival.normalized_position.x'))>.003):
            raise CandidateError('RESTART_POSITION_NOT_RESTORED:'+name)
        return result

    def isolated(self, case):
        name=case['id']; print('Running '+name,flush=True)
        receipt_start=self.p.serial+1
        record={'id':name,'setup_method':'normal_input','clean_start':'fresh_process',
                'checkpoint_ids':case['checkpoint_ids'],'status':'completed'}
        try:
            if self.p.session:self.p.call('stop')
            self.p.call('start',project=str(self.project),engine=str(self.args.engine),root=str(self.root))
            self.o.bind(self.p.session)
            self.case_initial=self.active(name+'-initial')
            record['initial_identity']={k:self.case_initial[k] for k in ('process_id','process_token','round_id','snapshot_id')}
            self.p.begin_case(case)
            getattr(self,case['method'])()
        except CandidateError as e:
            record.update(status='candidate_failure',reason=str(e))
            affected=[]
            for key in case['checkpoint_ids']:
                c=self.verdicts[key]
                if c['verdict']=='unreachable':
                    c['reason']=str(e);c['evidence']=['cases/'+name+'.json'];affected.append(key)
            self.faults.append({'domain':'candidate','code':str(e),'case_id':name,
                'affected_checkpoint_ids':affected,'attribution':'Bounded normal-input case with successful host transport.',
                'evidence':['cases/'+name+'.json']})
        except InfrastructureError as e:
            record.update(status='invalid',reason=str(e))
            raise
        finally:
            record['execution']=self.p.end_case()
            try:
                if self.p.session:self.p.call('stop')
                record['cleanup']='completed'
            except CandidateError as e:
                record['cleanup']=str(e)
                self.faults.append({'domain':'candidate','code':str(e),'case_id':name,
                    'affected_checkpoint_ids':['D4-05'],'evidence':['cases/'+name+'.json']})
                self.mark('D4-05',False,'CANDIDATE_CLEANUP_FAILED','cases/'+name+'.json')
            record['receipts']=[p.relative_to(self.root).as_posix() for p in sorted((self.root/'receipts').glob('*.json'))
                                if int(p.name.split('-')[0])>=receipt_start]
            record['state_evidence']=['states/'+name+'-initial.json']
            write(self.root/'cases'/ (name+'.json'),record)
            self.journeys.append(record)

    def run(self):
        if self.root.exists() and any(self.root.iterdir()):raise InfrastructureError('OUTPUT_NOT_EMPTY')
        candidate_argument=self.args.project.resolve()
        candidate_boundary=candidate_argument if candidate_argument.is_dir() else candidate_argument.parent
        if self.root.is_relative_to(candidate_boundary):raise InfrastructureError('OUTPUT_INSIDE_CANDIDATE')
        self.root.mkdir(parents=True,exist_ok=True)
        self.budget.arm()
        project=self.args.project.resolve()
        if project.is_dir():project=project/'BENCHMARK_MANIFEST.json'
        candidate_root=project.parent
        manifest_error=None
        if project.name=='BENCHMARK_MANIFEST.json':
            try:
                m=load(project);declared_root=inside(candidate_root,m['paths']['project_root']);project=inside(candidate_root,m['paths']['project_file'])
                if not project.is_relative_to(declared_root):raise ValueError('project outside declared root')
            except (OSError,ValueError,KeyError,TypeError,InfrastructureError):
                project=candidate_root/'missing-candidate.uproject';manifest_error='CANDIDATE_MANIFEST_INVALID'
        artifact={'sha256':__import__('hashlib').sha256((self.args.candidate_id+project.name).encode()).hexdigest(),'files':[],'missing':True}
        version={}
        status='completed'
        try:
            if candidate_root.exists():artifact=identity(candidate_root)
            write(self.root/'candidate-manifest.json',artifact)
            if getattr(self.args, 'source_review', None):
                from source_review import validate, REVIEW_PATH
                review = validate(load(self.args.source_review), artifact)
                write(self.root/REVIEW_PATH, review)
            try:version=load(self.args.engine/'Engine/Build/Build.version')
            except (OSError,ValueError):raise InfrastructureError('ENGINE_IDENTITY_UNAVAILABLE') from None
            if [version.get(k) for k in ('MajorVersion','MinorVersion','PatchVersion','Changelist')]!=[5,7,4,51494982]:raise InfrastructureError('ENGINE_IDENTITY_MISMATCH')
            if manifest_error:raise CandidateError(manifest_error)
            if not project.is_file():raise CandidateError('CANDIDATE_PROJECT_MISSING')
            if self.root.is_relative_to(project.parent):raise InfrastructureError('OUTPUT_INSIDE_CANDIDATE')
            try: descriptor=load(project)
            except (OSError,ValueError):raise CandidateError('CANDIDATE_DESCRIPTOR_INVALID') from None
            valid=isinstance(descriptor,dict) and descriptor.get('FileVersion')==3
            # The actual build/runtime identity is authoritative; a source-build GUID is legal.
            self.mark('D1-01',valid,'PROJECT_DESCRIPTOR','candidate-manifest.json')
            if not valid:raise CandidateError('CANDIDATE_DESCRIPTOR_INVALID')
            dest=self.root/'project'
            shutil.copytree(project.parent,dest,ignore=shutil.ignore_patterns(*EXCLUDES))
            if time.monotonic()-self.start>self.budget.contract['preparation_budget_seconds']:
                raise CandidateError('CANDIDATE_PREPARATION_TIMEOUT')
            target=next(iter(dest.glob('Source/*Editor.Target.cs')),None)
            if target:
                targetname=target.name.removesuffix('.Target.cs')
                build=[str(self.args.engine/'Engine/Build/BatchFiles/Build.bat'),targetname,'Win64','Development',f'-Project={dest/project.name}','-WaitMutex','-NoHotReloadFromIDE']
                with (self.root/'build.log').open('w',encoding='utf-8') as log:
                    process=subprocess.Popen(build,stdout=log,stderr=subprocess.STDOUT)
                    self.budget.processes.append(process)
                    try:code=process.wait(timeout=self.budget.contract['build_timeout_seconds'])
                    except subprocess.TimeoutExpired:
                        subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True,timeout=15)
                        raise CandidateError('CANDIDATE_BUILD_TIMEOUT') from None
                # Sanitize build diagnostics before evidence can be delivered.
                text=(self.root/'build.log').read_text(encoding='utf-8',errors='replace')
                for original,alias in ((str(self.args.engine),'<Engine>'),(str(REPO),'<Repository>'),(os.environ.get('USERPROFILE',''),'<UserProfile>')):
                    if original:text=text.replace(original,alias).replace(original.replace('\\','/'),alias)
                (self.root/'build.log').write_text(text,encoding='utf-8')
            else:code=0 if not descriptor.get('Modules') else 1
            self.mark('D1-02',code==0,'EDITOR_BUILD','build.log' if target else 'candidate-manifest.json')
            if code:raise CandidateError('CANDIDATE_BUILD_FAILED')
            self.project=dest/project.name
            self.p=Player(self.args.pwsh,self.root,self.budget)
            self.p.call('start',project=str(dest/project.name),engine=str(self.args.engine),root=str(self.root))
            self.o=Observer(self.root,self.p.session,self.budget)
            initial=self.wait('initial',lambda g:field(g,'phase')=='active' and number(g,'combat.round_time_ms')>=150,2,2)
            cap=self.cap('initial')
            cap['state_reached']=bool(initial)
            self.mark('D1-03',cap['visible'],'NO_INPUT_RENDERED_START','captures/initial.png')
            self.mark('D1-04',bool(self.o.last) and not self.o.errors,'PUBLIC_BRIDGE_SCHEMA_AND_IDENTITY','states/initial.json')
            self.facts['initial']=initial
            self.mark('D4-01',bool(initial),'DIRECT_PLAYER_ENTRY','states/initial.json')
            if not initial:
                # Independent presentation can still be reviewed; do not globally erase visible content.
                raise CandidateError('GAMEPLAY_PROVIDER_UNREACHABLE')
            for case in self.cases:
                if case['stage']=='dynamic':self.isolated(case)
            self.aggregate_rules()
            samples=self.o.samples
            invariants=bool(samples) and all(0<=number(game(s),'player.health')<=100 and 0<=number(game(s),'rival.health')<=100
                and number(game(s),'world.object_counts.player_fighters')==1 and number(game(s),'world.object_counts.rival_fighters')==1
                and number(game(s),'world.object_counts.player_projectiles')==number(game(s),'combat.active_player_projectiles')
                and number(game(s),'feedback.hud_player_health')==number(game(s),'player.health') and number(game(s),'feedback.hud_rival_health')==number(game(s),'rival.health')
                for s in samples if s.get('provider_ready'))
            self.mark('D3-08',invariants and number(game(initial),'player.health')==100 and number(game(initial),'rival.health')==100,
                'INITIAL_HEALTH_AND_OBSERVED_HEALTH_COUNTS_HUD_INVARIANTS',
                *[p.relative_to(self.root).as_posix() for p in sorted((self.root/'states').glob('*.json'))])
            for case in self.cases:
                if case['stage']=='visual':self.isolated(case)
        except CandidateError as e:
            self.faults.append({'domain':'candidate','code':str(e)})
            for id,c in self.verdicts.items():
                if c['verdict']=='unreachable':c['reason']=str(e)
        except InfrastructureError as e:
            status='invalid';self.faults.append({'domain':'infrastructure','code':str(e)})
        except Exception as e:
            status='invalid';self.faults.append({'domain':'infrastructure','code':'EVALUATOR_EXCEPTION','exception_type':type(e).__name__})
        finally:
            if self.p:
                try:
                    if self.p.session:self.p.call('stop')
                except CandidateError as e:
                    self.faults.append({'domain':'candidate','code':str(e)})
                    self.mark('D4-05',False,'CANDIDATE_DID_NOT_EXIT_CLEANLY')
                except InfrastructureError as e:
                    status='invalid';self.faults.append({'domain':'infrastructure','code':str(e)})
                finally:
                    try:self.p.close()
                    except InfrastructureError as e:
                        status='invalid';self.faults.append({'domain':'infrastructure','code':str(e)})
            self.budget.close()
            from coverage_gate import collect_boundary_report
            collect_boundary_report(self)
            for c in self.verdicts.values():
                if c['verdict']!='pass' and not c['evidence']:c['evidence']=['raw-evaluation.json']
            evidence_files=[p for d in ('states','captures','receipts','cases') for p in (self.root/d).glob('*') if p.is_file()]
            evidence_files += [p for p in (self.root/'candidate-manifest.json',self.root/'build.log') if p.is_file()]
            evidence_index={p.relative_to(self.root).as_posix():sha(p) for p in evidence_files}
            output={'schema_version':'3.0.0','run_id':self.args.run_id,'candidate_id':self.args.candidate_id,
                'candidate_identity_sha256':artifact['sha256'],'input_gdd_sha256':sha(TASK/'input/GDD.md'),
                'scoring_contract_sha256':sha(ROOT/'contracts/scoring-contract.json'),
                'catalog_sha256':sha(ROOT/'catalog/checkpoints.json'),'status':status,'checkpoints':list(self.verdicts.values()),
                'captures':self.captures,'facts':self.facts,'journeys':self.journeys,'faults':self.faults,
                'observer_errors':self.o.errors if self.o else [],'elapsed_seconds':round(time.monotonic()-self.start,2),
                'evaluator_identity':self.binding,'engine_identity':version,'evidence_sha256':evidence_index,
                'environment':{'platform':'Windows','python':__import__('platform').python_version(),'viewport':[1280,720]},
                'budget':self.budget.report()}
            write(self.root/'raw-evaluation.json',output)
            print('Evidence: '+str(self.root/'raw-evaluation.json'),flush=True)
        return 0 if status=='completed' else 2

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--project',type=Path,required=True);p.add_argument('--engine',type=Path,required=True)
    p.add_argument('--pwsh',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--run-id',required=True);p.add_argument('--candidate-id',required=True)
    p.add_argument('--source-review',type=Path,help='Completed source review for DRAW and missed-bolt cleanup')
    args=p.parse_args()
    raise SystemExit(Evaluation(args).run())

if __name__=='__main__':main()
