"""Run one frozen v2 campaign evaluator and emit an evidence-bound /90 report."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

from framework.defold_campaign_dashboard.dashboard_self_check import validate_naming_tables,validate_snapshot
from framework.defold_cross_engine.native import project_path
from framework.defold_native_tasks.scoring import score

ROOT=Path(__file__).resolve().parents[2]
MODULES={
    'defold_match3_swipe_v2':'framework.defold_campaign_playtest.play_match3',
    'defold_driller_path_v2':'framework.defold_campaign_playtest.play_driller',
    'defold_defrog_crossing_v2':'framework.defold_campaign_playtest.play_defrog',
    'defold_typhoon_balloon_v2':'framework.defold_campaign_playtest.play_typhoon',
}
INFRASTRUCTURE_MARKERS=(
    'BlockingIOError: [Errno 11]',
    'DESKTOP_NOT_READY',
    'EvidenceInfrastructureError',
    'FOREGROUND_LOST',
    'NATIVE_HELPER_TIMEOUT',
    'NATIVE_HELPER_EXITED',
    'NATIVE_HELPER_PROTOCOL_INVALID',
    'NATIVE_HELPER_COMPILE_FAILED',
    'OWNED_PROCESS_CLEANUP_UNVERIFIED',
)

def read(path):return json.loads(path.read_text())
def write(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')

def validate_trace(path,tables):
    previous=0;payload=None;count=0
    for line in path.read_text().splitlines():
        snapshot=json.loads(line);validate_snapshot(snapshot,tables,previous)
        current={key:value for key,value in snapshot.items() if key!='revision'}
        if current==payload:raise ValueError('revision changed without payload change')
        previous=snapshot['revision'];payload=current;count+=1
    if count==0:raise ValueError('empty trace')

def infrastructure_error(completed,source_unchanged):
    transcript=completed.stdout+'\n'+completed.stderr
    marker=next((value for value in INFRASTRUCTURE_MARKERS if value in transcript),None)
    if marker:return 'PLAYTEST_INFRASTRUCTURE:'+marker
    if source_unchanged is False:return 'CANDIDATE_SOURCE_CHANGED_DURING_EVALUATION'
    return None

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sample',choices=sorted(MODULES),required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();candidate=args.candidate.resolve();output=args.output.resolve()
    if not candidate.is_dir():parser.error('candidate must be a directory')
    if output.exists():parser.error('output must be a new directory')
    output.mkdir(parents=True);playtest=output/'playtest'
    sample=ROOT/'samples'/args.sample;catalog=read(sample/'evaluation/rules.json')
    command=[sys.executable,'-B','-m',MODULES[args.sample],'--candidate',str(candidate),'--output',str(playtest)]
    completed=subprocess.run(command,cwd=ROOT,text=True,capture_output=True)
    write(output/'runner.json',{'command':command,'returncode':completed.returncode,'stdout':completed.stdout,'stderr':completed.stderr})
    passed=set(read(playtest/'progress.json').get('passed_checks',[])) if (playtest/'progress.json').is_file() else set()
    results=[]
    def record(check_id,verdict,reason,paths):
        results.append({'id':check_id,'verdict':verdict,'reason':reason,'evidence':paths})
    try:project_path(candidate);project_ok=True
    except ValueError:project_ok=False
    record('D1.PROJECT','pass' if project_ok else 'fail','game.project present' if project_ok else 'game.project missing',['runner.json'])
    build=read(playtest/'build-host.json') if (playtest/'build-host.json').is_file() else {}
    build_ok=build.get('exit_code')==0 and not build.get('timed_out',False)
    record('D1.BUILD','pass' if build_ok else 'fail','isolated Bob build succeeded' if build_ok else 'Bob build failed',['playtest/build-host.json'] if build else ['runner.json'])
    traces=sorted(playtest.glob('session-*/dashboard.jsonl'))
    start_ok=bool(traces) and any(path.stat().st_size for path in traces)
    trace_evidence=['playtest/'+str(path.relative_to(playtest)) for path in traces] or ['runner.json']
    record('D1.START','pass' if start_ok else 'fail','native process published a snapshot' if start_ok else 'no native snapshot',trace_evidence)
    contract_ok=start_ok;contract_reason='all observed traces satisfy Dashboard v3'
    try:
        tables=validate_naming_tables(read(sample/'input/naming-tables.json'))
        for path in traces:validate_trace(path,tables)
    except Exception as error:
        contract_ok=False;contract_reason=type(error).__name__+':'+str(error)
    record('D1.CONTRACT','pass' if contract_ok else 'fail',contract_reason,trace_evidence)
    progress_evidence=['playtest/progress.json'] if (playtest/'progress.json').is_file() else ['runner.json']
    for check in catalog['checks']:
        if check['id'].startswith('D1.'):continue
        verdict='pass' if check['id'] in passed else 'fail'
        reason='native checkpoint passed' if verdict=='pass' else 'native checkpoint not reached or assertion failed'
        record(check['id'],verdict,reason,progress_evidence)
    source_unchanged=read(playtest/'source-after.json').get('unchanged') if (playtest/'source-after.json').is_file() else None
    infra=infrastructure_error(completed,source_unchanged)
    report=score(catalog,results,infrastructure_error=infra)
    report['playtest_returncode']=completed.returncode
    report['playtest_completed']=(playtest/'acceptance.json').is_file()
    report['source_unchanged']=source_unchanged
    report['visual_review']={'max':10,'score':None,'status':'not_run'}
    write(output/'score.json',report)
    print(json.dumps({'evaluation_status':report['evaluation_status'],'nonvisual_score':report['nonvisual_score'],'visual_score':None,'report':str(output/'score.json')},ensure_ascii=False),flush=True)
    return 2 if report['evaluation_status']=='infrastructure_invalid' else 3 if report['evaluation_status']=='incomplete' else 0

if __name__=='__main__':raise SystemExit(main())
