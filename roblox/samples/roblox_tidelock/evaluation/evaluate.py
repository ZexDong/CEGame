#!/usr/bin/env python3
"""Forward an independent candidate through the existing TideLock CMD steps."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

EVALUATION=Path(__file__).resolve().parent
sys.path.insert(0,str(EVALUATION/'src'))
from export_v2 import export_result
from visual_binding import validate_visual

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def executable(value):
    resolved=shutil.which(value) or (str(Path(value).resolve()) if Path(value).is_file() else None)
    if not resolved: raise RuntimeError('Executable not found: '+value)
    return resolved

def stage_candidate(source,work):
    candidate=work/'candidate/original/TideLockCandidate'
    archive=work/'candidate/TideLockCandidate.zip'
    archive.parent.mkdir(parents=True)
    if source.is_file():
        unpacked=work/'unpacked'
        unpacked.mkdir()
        with zipfile.ZipFile(source) as z:
            total=0
            for item in z.infolist():
                total+=item.file_size
                name=item.filename.replace('\\','/')
                path=PurePosixPath(name)
                if path.is_absolute() or '..' in path.parts or ':' in name or (item.external_attr>>16)&0o170000==0o120000:
                    raise ValueError('Unsafe candidate ZIP member: '+name)
                if total>512*1024*1024: raise ValueError('Candidate ZIP exceeds 512 MiB extraction limit')
            z.extractall(unpacked)
        choices=[p.parent.parent for p in unpacked.rglob('default.project.json')
                 if p.parent.name=='project' and (p.parent.parent/'TideLockCandidate.rbxlx').is_file()]
        if len(choices)!=1: raise ValueError('ZIP must contain one complete TideLock candidate root')
        shutil.copytree(choices[0],candidate)
        shutil.copy2(source,archive)
    else:
        if not (source/'project/default.project.json').is_file():
            raise ValueError('Supply a candidate root containing project/default.project.json, or its ZIP')
        if any(p.is_symlink() or (hasattr(p,'is_junction') and p.is_junction()) for p in source.rglob('*')):
            raise ValueError('Candidate directory must not contain symlinks or junctions')
        shutil.copytree(source,candidate)
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
            for p in sorted(candidate.rglob('*')):
                if p.is_file(): z.write(p,p.relative_to(candidate).as_posix())
    return candidate,archive

def static_native_report(static):
    records=static.get('checkpoints',{})
    return {'schema_version':'tide-lock-score-v1','candidate_zip_sha256':static.get('candidate_zip_sha256'),
        'runner_valid':False,'adjudication_complete':False,'official_score':None,
        'provisional_subtotal':None,'possible':100,'unresolved':['Live Play has not run.'],'problems':[],
        'breakdown':[{'dimension':'D1','possible':10,'score':None,
                      'checkpoints':[{'id':key,**value} for key,value in records.items()]}]}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,required=True,help='Independent candidate directory or ZIP; no audit/result directory is required.')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--rojo',default='rojo')
    parser.add_argument('--luau-compile',default='luau-compile')
    parser.add_argument('--visual',type=Path,help='Original D6 JSON with three round_scores and final_score, for this same candidate.')
    parser.add_argument('--prepare-only',action='store_true',help='Run the original static audit/build only; do not open Studio.')
    args=parser.parse_args()
    if not args.project.is_absolute() or not args.output.is_absolute(): parser.error('--project and --output must be absolute')
    source,output=args.project.resolve(),args.output.resolve()
    if output.exists() or output.is_relative_to(source) or output.is_relative_to(EVALUATION.parent):
        parser.error('Use a new output directory outside the candidate and published sample')
    output.mkdir(parents=True)
    work=output/'native-workspace'; work.mkdir()
    native={}; error=None
    exit_code=3
    coverage=json.loads((EVALUATION/'coverage.json').read_text(encoding='utf-8'))
    try:
        rojo=executable(args.rojo); compiler=executable(args.luau_compile)
        candidate,archive=stage_candidate(source,work)
        # Stage the parameterized candidate audit and D6 capture profile
        # inside this evaluation's output workspace.
        shutil.copytree(EVALUATION/'src/d6_original',work/'evaluation',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
        for name in ['audit','qa','evidence']: (work/name).mkdir()
        runner=work/'evaluation/local_complete_eval.py'
        os.environ['ROJO_EXE']=rojo
        static_path=work/'audit/static_results.json'
        audit=subprocess.run([sys.executable,str(work/'evaluation/static_audit.py'),
            '--candidate-zip',str(archive),'--expected-zip-sha256',sha(archive),
            '--candidate-root',str(candidate),'--rojo',rojo,'--luau-compile',compiler,
            '--build-output',str(work/'audit/TideLockCandidate_clean_build.rbxlx'),
            '--output',str(static_path)],cwd=work)
        if static_path.is_file(): native=static_native_report(json.loads(static_path.read_text(encoding='utf-8')))
        if audit.returncode==0 and not args.prepare_only:
            subprocess.run([sys.executable,str(runner),'--open-smoke'],cwd=work,check=True)
            subprocess.run([sys.executable,str(runner),'--run-kind','formal'],cwd=work,check=True)
            runs=sorted((work/'evidence').glob('formal_*/score.json'))
            if not runs: raise RuntimeError('Original evaluator did not produce score.json')
            report=runs[-1]
            if args.visual:
                validate_visual(args.visual,EVALUATION,source,output)
                visual=output/'evidence/visual.json'
                subprocess.run([sys.executable,str(work/'evaluation/score_evidence.py'),
                    '--rules',str(work/'evaluation/rules.json'),'--static',str(static_path),
                    '--dynamic',str(report.parent/'evidence.json'),'--visual',str(visual),
                    '--output',str(report.parent/'score-with-visual.json'),'--allow-incomplete'],check=True)
                report=report.parent/'score-with-visual.json'
            native=json.loads(report.read_text(encoding='utf-8'))
        elif audit.returncode not in (0,2):
            raise RuntimeError('Original static-audit process failed with exit '+str(audit.returncode))
    except Exception as exc:
        error=str(exc); exit_code=2
    result=export_result(native,output,coverage,infrastructure_error=error)
    validation=subprocess.run([sys.executable,str(EVALUATION/'validate_score.py'),'--score',str(output/'score.json'),'--check-evidence'])
    if validation.returncode: return 2
    if result['evaluation_valid']: exit_code=0
    print(output/'score.json')
    return exit_code

if __name__=='__main__': raise SystemExit(main())
