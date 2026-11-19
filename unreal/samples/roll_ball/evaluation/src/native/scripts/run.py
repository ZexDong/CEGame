"""Bound RollBall evaluator entry point.

Runs static isolation/build first, then independent gameplay cases against the
clean project. It intentionally stops before review or VLM scoring: those are
separate commands so a failed case cannot contaminate later evidence.
"""
import argparse,subprocess,sys
from pathlib import Path

def invoke(script,args):
    cmd=[sys.executable,str(Path(__file__).with_name(script)),*args]
    return subprocess.run(cmd,check=False).returncode

def main():
    p=argparse.ArgumentParser();
    for k in ('candidate-project','engine','tools','pwsh','root'): p.add_argument('--'+k,required=True)
    p.add_argument('--cases');p.add_argument('--target');a=p.parse_args()
    root=Path(a.root).resolve()
    if root.exists() and any(root.iterdir()): raise SystemExit('RUN_DIRECTORY_NOT_EMPTY')
    root.mkdir(parents=True,exist_ok=True)
    static_args=['--candidate-project',a.candidate_project,'--engine',a.engine,'--tools',a.tools,'--pwsh',a.pwsh,'--run',str(root/'static')]
    if a.target: static_args += ['--target',a.target]
    rc=invoke('static.py',static_args)
    if rc: return rc
    uprojects=list((root/'static'/'project').glob('*.uproject'))
    if len(uprojects)!=1: raise SystemExit('ISOLATED_PROJECT_DESCRIPTOR_MISSING_OR_AMBIGUOUS')
    collect_args=['--project',str(uprojects[0]),'--engine',a.engine,'--tools',a.tools,'--pwsh',a.pwsh,'--root',str(root/'collection')]
    if a.cases: collect_args += ['--cases',a.cases]
    return invoke('collect.py',collect_args)
if __name__=='__main__': raise SystemExit(main())
