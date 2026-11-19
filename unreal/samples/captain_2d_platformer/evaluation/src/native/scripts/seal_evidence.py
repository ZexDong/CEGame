"""Seal collected run evidence, excluding mutable workspaces and generated engine output."""
import argparse
from pathlib import Path
from runtime import load,write,sha,InfrastructureError

def seal(root):
    raw=load(root/'raw-evaluation.json')
    if raw['status']!='collected':raise InfrastructureError('CANNOT_SEAL_INVALID_RUN')
    rows=[]
    for p in sorted(root.rglob('*')):
        rel=p.relative_to(root)
        if not p.is_file() or rel.parts[0] in ('work','d6') or p.name in ('evidence-manifest.json','evaluation-result.json','runtime-review.json','d6-result.json'):continue
        if p.suffix.lower() not in ('.json','.png','.log'):continue
        rows.append(dict(path=rel.as_posix(),sha256=sha(p),size=p.stat().st_size))
    result=dict(schema_version='2.0.0',run_id=raw['run_id'],candidate_identity_sha256=raw['candidate_identity_sha256'],files=rows)
    write(root/'evidence-manifest.json',result)
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('root',type=Path);args=p.parse_args();seal(args.root.resolve())
