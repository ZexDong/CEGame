"""Collect isolated diagnostic evidence; this is not the numeric scorer."""
from __future__ import annotations
import argparse,json,shutil,sys,time,traceback
from pathlib import Path
from support import *
from spec import fresh,enemies
from catalog import CHECKS
from cases import NORMAL,FIXTURES,normal,fixture

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate',type=Path,help='Returned input root; manifest determines the project root.')
    parser.add_argument('--project',type=Path,help='Direct reference/input project for authoring only.')
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--engine',type=Path,required=True)
    parser.add_argument('--mapping',type=Path)
    parser.add_argument('--cases',help='Authoring increment only; cannot publish a full score without all evidence.')
    parser.add_argument('--capture-d6',action='store_true',help='Collect the fixed visual states during a targeted authoring increment.')
    parser.add_argument('--reuse-build',type=Path,help='Development only: supplied already-built project; recorded as non-release collection.')
    parser.add_argument('--resume-from',type=Path,help='Recover an infrastructure-interrupted run with identical source and contracts into a new evidence directory.')
    args=parser.parse_args();run=args.run.resolve();run.mkdir(parents=True,exist_ok=False);engine=args.engine.resolve()
    result={'schema_version':'gemsbond-evidence-1.0','status':'collecting','static':{},'cases':{},'d6':{},'faults':[],
            'partial':bool(args.cases or args.reuse_build),'scoring_guide_sha256':sha(REPO/'gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md'),'gdd_sha256':sha(TASK/'input/GDD.md')}
    write(run/'collection.json',result)
    p=None
    def checkpoint():write(run/'collection.json',result)
    def static(key,ok,detail):result['static'][key]={'verdict':'pass' if ok else 'fail','detail':detail,'attribution':'candidate' if not ok else 'observed'};checkpoint()
    try:
        version=load(engine/'Engine/Build/Build.version')
        if (version['MajorVersion'],version['MinorVersion'],version['PatchVersion'],version['Changelist'])!=(5,7,4,51494982):raise InfrastructureError('ENGINE_IDENTITY_MISMATCH')
        static('engine',True,{'version':version,'mode':'editor_game','viewport':[1280,720]})
        if args.candidate:
            root=args.candidate.resolve()
            try:manifest=load(root/'BENCHMARK_MANIFEST.json');source=(root/manifest['project_root']).resolve();entry=(root/manifest['project_file']).resolve()
            except (OSError,ValueError,KeyError) as e:raise CandidateError('CANDIDATE_MANIFEST_MISSING_OR_MALFORMED') from e
            if not source.is_relative_to(root) or not entry.is_relative_to(source):raise CandidateError('CANDIDATE_MANIFEST_PATH_ESCAPE')
        else:
            if not args.project:raise InfrastructureError('PROJECT_ARGUMENT_REQUIRED')
            entry=args.project.resolve();source=entry.parent
        if not entry.is_file():raise CandidateError('PROJECT_DESCRIPTOR_MISSING')
        try:descriptor=load(entry)
        except (OSError,ValueError) as e:raise CandidateError('PROJECT_DESCRIPTOR_MALFORMED') from e
        if not isinstance(descriptor,dict):raise CandidateError('PROJECT_DESCRIPTOR_MALFORMED')
        static('project',isinstance(descriptor,dict) and descriptor.get('EngineAssociation')=='5.7',{'project_file':entry.name})
        ident=identity(source);write(run/'candidate-manifest.json',ident);result['candidate_identity']=ident['sha256'];result['source_project']=entry.name
        previous=None
        if args.resume_from:
            previous=args.resume_from.resolve();prior=load(previous/'collection.json')
            if prior['status']!='run_invalid' or args.reuse_build or bool(prior.get('partial'))!=bool(args.cases):raise InfrastructureError('RESUME_REQUIRES_MATCHING_SCOPE_INFRASTRUCTURE_INTERRUPTION')
            for field in ['candidate_identity','gdd_sha256','scoring_guide_sha256']:
                if prior.get(field)!=result.get(field):raise InfrastructureError('RESUME_IDENTITY_MISMATCH:'+field)
            if prior['static'].get('engine')!=result['static']['engine']:raise InfrastructureError('RESUME_ENGINE_MISMATCH')
            for name,row in prior['cases'].items():
                session=row.get('session')
                if not session:continue
                cleanup=load(previous/session/'cleanup.json')
                if cleanup.get('status')!='ok' or not cleanup['result'].get('input_lease_released'):raise InfrastructureError('RESUME_CLEANUP_NOT_PROVEN')
                if not (run/session).exists():shutil.copytree(previous/session,run/session)
                result['cases'][name]=row
            result['static']=prior['static'];result['d6']=prior['d6'];result['unfinished']=prior.get('unfinished',False)
            write(run/'recovery.json',{'source_run':previous.name,'source_collection_sha256':sha(previous/'collection.json'),'prior_faults':prior['faults'],'reused_cases':list(result['cases']),'reason':'Recover only uncompleted work after positively attributed infrastructure interruption.'})
            shutil.copy2(previous/'build.log',run/'build.log')
        target=run/'project'/entry.name
        if previous:
            target=previous/'project'/entry.name
        elif args.reuse_build:
            target=args.reuse_build.resolve();static('build',True,{'development_reuse':True,'path_withheld':True})
        else:
            clone(source,run/'project');code=compile_project(target,engine,run/'build.log');static('build',code==0,{'exit_code':code,'evidence':'build.log'})
            if code:raise CandidateError('CANDIDATE_BUILD_FAILED')
        selected=args.cases.split(',') if args.cases else NORMAL+list(FIXTURES)
        unknown=set(selected)-set(NORMAL)-set(FIXTURES)
        if unknown:raise InfrastructureError('UNKNOWN_CASES:'+str(unknown))
        selected=[x for x in selected if x not in result['cases']]
        if not previous:p=Player(REPO,target,engine,run/'normal',serial_limit=14000)
        try:
            if previous:
                if any(x in NORMAL for x in selected) or len(result['d6'])!=3:raise InfrastructureError('RESUME_NORMAL_STAGE_INCOMPLETE')
                unfinished=False
            else:
                p.start();p.capture('static-startup');image_health=inspect_image(p.root/'captures/static-startup.png');static('startup',not image_health['black'],{'evidence':'normal/captures/static-startup.png','no_player_input':True,'image_health':image_health})
                if image_health['black']:raise CandidateError('CANDIDATE_BLACK_SCREEN')
                try:report=snapshot_check.validate(p.state(),TASK/'input');static('observation',True,report)
                except (ValueError,KeyError,TypeError) as e:static('observation',False,{'reason':str(e)})
                unfinished=p.state().get('phase')=='not_ready'
            result['unfinished']=unfinished
            if unfinished:
                for name in selected:result['cases'][name]={'case':name,'error':'CANDIDATE_EXPLICITLY_NOT_READY','votes':{},'attribution':'candidate','evidence':['normal/captures/static-startup.png']}
                for state_id in ['opening','placement','combat']:result['d6'][state_id]={'status':'candidate_missing','reason':'CANDIDATE_EXPLICITLY_NOT_READY'}
            else:
                for name in [x for x in selected if x in NORMAL]:
                    if name!='opening':
                        p.case_budget=None
                        p.press('R')
                        try:p.wait(fresh,2)
                        except CandidateError:
                            # Restart defects cannot erase unrelated fresh-process cases.
                            p.reopen()
                    c=Case(p,name);error=None
                    try:normal(c)
                    except CandidateError as e:error=e
                    result['cases'][name]=c.finish(error);checkpoint();print(name+': '+('candidate failure '+str(error) if error else 'collected'),flush=True)
                # D6 is a separate stage using normal player inputs only.
                if (not args.cases or args.capture_d6) and not previous:
                    from window import WindowHost
                    p.case_budget=None;p.press('R');p.wait(fresh,2);WindowHost(p.process_id).resize(1920,1080);p.observe(.3)
                    c=Case(p,'d6_capture');result['d6']['opening']={'status':'captured',**p.capture('d6-opening')}
                    c.build('archer',[8,7]);c.wait(lambda x:units(x,'archer')[0]['state']!='constructing',2);c.click('build_mine');c.move('build_mine');result['d6']['placement']={'status':'captured',**p.capture('d6-placement')}
                    c.build('cannon',[12,7]);c.build('mine',[4,3]);c.key('Escape');c.wait(lambda x:len(enemies(x))>=5,7);result['d6']['combat']={'status':'captured',**p.capture('d6-combat')};c.finish();checkpoint()
        except CandidateError as e:
            result['faults'].append({'attribution':'candidate','reason':str(e),'stage':'normal'})
            # Preserve already captured states. A candidate failure before a
            # later state is not a lost evaluator artifact or an N/A score.
            if not args.cases or args.capture_d6:
                for state_id in ['opening','placement','combat']:
                    result['d6'].setdefault(state_id,{'status':'candidate_missing','reason':str(e)})
            if 'startup' not in result['static']:static('startup',False,{'reason':str(e)})
        finally:
            if p:p.case_budget=None;p.close();p=None
        if not result.get('unfinished') and any(x in FIXTURES for x in selected):
            if not args.mapping:raise InfrastructureError('REVIEWED_SEMANTIC_MAPPING_REQUIRED_FOR_ISOLATED_PRECONDITIONS')
            mapping=prepare_fixture(source,run/'fixture-project',args.mapping);write(run/'fixture-mapping.json',mapping)
            fixture_target=run/'fixture-project'/entry.name
            code=compile_project(fixture_target,engine,run/'fixture-build.log')
            if code:raise InfrastructureError('FIXTURE_MAPPING_COMPILE_FAILED')
            for name in [x for x in selected if x in FIXTURES]:
                p=Player(REPO,fixture_target,engine,run/name,serial_limit=360)
                try:
                    setup(p,FIXTURES[name],ident['sha256']);c=Case(p,name);error=None
                    try:fixture(c)
                    except CandidateError as e:error=e
                    result['cases'][name]=c.finish(error);checkpoint();print(name+': '+('candidate failure '+str(error) if error else 'collected'),flush=True)
                finally:
                    p.case_budget=None;p.close();p=None
        result['status']='collected';checkpoint();return 0
    except CandidateError as e:
        result['status']='candidate_failed';result['faults'].append({'attribution':'candidate','reason':str(e),'stage':'preflight'});checkpoint();return 1
    except Exception as e:
        result['status']='run_invalid';result['faults'].append({'attribution':'infrastructure','reason':str(e),'trace':traceback.format_exc()});checkpoint();return 2
    finally:
        if p:
            try:p.case_budget=None;p.close()
            except Exception as e:result['status']='run_invalid';result['faults'].append({'attribution':'infrastructure','reason':'CLEANUP:'+str(e)});checkpoint()

if __name__=='__main__':sys.exit(main())
