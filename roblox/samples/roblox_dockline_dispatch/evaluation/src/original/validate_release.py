#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, py_compile, subprocess, sys
from pathlib import Path

def sha(path:Path)->str: return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def main()->int:
    root=Path(__file__).resolve().parents[1]; problems=[]
    rules=json.loads((root/'evaluation/rules.json').read_text(encoding='utf-8'))
    expected={'D1':10,'D2':30,'D3':20,'D4':20,'D5':10,'D6':10}
    if {d['id']:d['points'] for d in rules['dimensions']}!=expected: problems.append('frozen dimension weights mismatch')
    ids=[c for d in rules['dimensions'] for c in d['checkpoints']]
    if len(ids)!=len(set(ids)): problems.append('duplicate checkpoint id')
    budget=json.loads((root/'evaluation/runtime/budget_plan.json').read_text(encoding='utf-8'))
    for session in budget['sessions']:
        required=session['declared_serial_worst_case_seconds']+session['evaluator_render_evidence_margin_seconds']
        if session['hard_watchdog_seconds']<required: problems.append('watchdog invariant: '+session['id'])
        if session['watchdog_headroom_seconds']!=session['hard_watchdog_seconds']-session['declared_serial_worst_case_seconds']: problems.append('watchdog headroom: '+session['id'])
    manifest=json.loads((root/'candidate/candidate_manifest.json').read_text(encoding='utf-8'))
    for key in ('delivered_place','source_package'):
        path=root/manifest[key]['path']
        if not path.is_file() or sha(path)!=manifest[key]['sha256']: problems.append('candidate hash mismatch: '+key)
    for script in (root/'evaluation').glob('*.py'):
        try: py_compile.compile(str(script),doraise=True)
        except py_compile.PyCompileError as error: problems.append(str(error))
    generated=root/'evaluation/generated'; generated.mkdir(parents=True,exist_ok=True)
    for mode in ('formal','reopen'):
        runner=generated/f'dockline_dispatch_{mode}_runner.client.luau'
        result=subprocess.run([sys.executable,str(root/'evaluation/generate_runtime.py'),'--runtime-dir',str(root/'evaluation/runtime'),'--output',str(runner),'--mode',mode],capture_output=True,text=True)
        if result.returncode: problems.append('runtime generation '+mode+': '+result.stderr[-500:]); continue
        compiled=subprocess.run([str(root/'tools/luau-compile.exe'),str(runner)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
        if compiled.returncode: problems.append('runtime compile '+mode+': '+compiled.stderr[-500:])
    policy=root/'evaluation/generated/policy_audit.json'
    sources=[root/'evaluation/generated/dockline_dispatch_formal_runner.client.luau',root/'evaluation/generated/dockline_dispatch_reopen_runner.client.luau',root/'evaluation/runtime/qa_observer.client.luau']
    subprocess.run([sys.executable,str(root/'evaluation/static_policy_check.py'),*[str(x) for x in sources],'--output',str(policy)],check=False,capture_output=True,text=True)
    if not policy.is_file() or not json.loads(policy.read_text(encoding='utf-8')).get('passed'): problems.append('evaluator policy audit failed')
    report={'schema_version':'dockline-dispatch-release-validation-v1','passed':not problems,'problems':problems}
    (root/'audit').mkdir(exist_ok=True); (root/'audit/release_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False)); return 0 if not problems else 2
if __name__=='__main__': raise SystemExit(main())
