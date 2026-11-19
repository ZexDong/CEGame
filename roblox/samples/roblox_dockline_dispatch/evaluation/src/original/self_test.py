#!/usr/bin/env python3
from __future__ import annotations
import json, subprocess, sys, tempfile
from pathlib import Path

def main() -> int:
    root=Path(__file__).resolve().parents[1]
    rules=json.loads((root/'evaluation/rules.json').read_text(encoding='utf-8'))
    static={'checkpoints':{},'candidate_zip_sha256':'TEST'}
    dynamic={'checkpoints':{},'runner_status':'completed','host_fault':None,'metadata':{'formal_valid':True},'summary':{'executable':True,'solved':True}}
    for dim in rules['dimensions']:
        if dim['id']=='D6': continue
        target=static if dim['id']=='D1' else dynamic
        for cid in dim['checkpoints']: target['checkpoints'][cid]={'status':'pass','detail':'synthetic','trace_ids':['test-trace']}
    with tempfile.TemporaryDirectory(prefix='dockline_score_test_') as name:
        t=Path(name); sp=t/'static.json'; dp=t/'dynamic.json'; out=t/'score.json'
        sp.write_text(json.dumps(static),encoding='utf-8'); dp.write_text(json.dumps(dynamic),encoding='utf-8')
        command=[sys.executable,str(root/'evaluation/score_evidence.py'),'--rules',str(root/'evaluation/rules.json'),'--static',str(sp),'--dynamic',str(dp),'--output',str(out),'--allow-incomplete']
        subprocess.run(command,check=True,capture_output=True,text=True)
        score=json.loads(out.read_text(encoding='utf-8'))
        assert score['official_score'] is None and score['provisional_subtotal']==90.0
        for record in dynamic['checkpoints'].values(): record['status']='fail'; record['detail']='synthetic candidate failure'
        dp.write_text(json.dumps(dynamic),encoding='utf-8'); subprocess.run(command,check=True,capture_output=True,text=True)
        failed=json.loads(out.read_text(encoding='utf-8'))
        assert failed['provisional_subtotal']==10.0
        assert [x for x in failed['unresolved'] if x!='D6 visual evaluation not available']==[]
    formal=(root/'evaluation/runtime/formal_suite.lua').read_text(encoding='utf-8')
    for dim in rules['dimensions']:
        if dim['id'] in {'D2','D3','D4','D5'}:
            for cid in dim['checkpoints']:
                if cid!='d4.reopen_clean_session': assert cid in formal, cid
    assert 'bootstrap_failure_snapshot' in formal
    driver=(root/'evaluation/runtime/engine_driver.lua').read_text(encoding='utf-8')
    generator=(root/'evaluation/generate_runtime.py').read_text(encoding='utf-8')
    assert 'DD_LastSourceId==id' in driver and 'event_confirmed=confirmed' in driver
    assert 'driveTo(node.Position,0.8,4)' in driver and 'ready_at_semantic_node' in driver
    assert 'else 0.025' in driver and 'GetAttributeChangedSignal("DD_EventSeq")' in driver
    assert 'InputBegan %s was not observed' in generator and 'retry = true' in generator
    assert formal.count('local fullControl=')==1 and 'inside the one successful' in formal
    assert 'compactState' in generator and 'JSONEncode(compact)' in generator
    assert 'JSONEncode(payload))\n    return traceId' not in generator
    launcher=(root/'evaluation/local_complete_eval.py').read_text(encoding='utf-8')
    assert 'invalid_startup_attempt_1_studio.log' in launcher
    assert 'close_studio(runtime_place.stem, window)' in launcher
    assert 'window, session_log, launched_at = open_studio_place(runtime_place)' in launcher
    print(json.dumps({'passed':True,'checks':['weights','all-pass subtotal','all-dynamic-fail adjudication','D6 fail-closed','checkpoint coverage','bootstrap degradation','semantic prompt acknowledgement','tight semantic-node navigation','bounded InputBegan acknowledgement','single success journey','compact trace emission','fresh-process PlayClient startup retry']}))
    return 0
if __name__=='__main__': raise SystemExit(main())
