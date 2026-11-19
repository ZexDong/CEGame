"""Explicit incremental repair, same candidate only; never select best scores."""
from common import *
import argparse,shutil

def merge(base,repairs,dest):
    base=Path(base).resolve();dest=Path(dest).resolve()
    if dest.exists():raise InfrastructureError('MERGE_DESTINATION_EXISTS')
    raw=load(base/'raw-evaluation.json')
    if raw['status']=='run_invalid' or raw['partial_selection']:raise InfrastructureError('BASE_NOT_COMPLETE')
    shutil.copytree(base,dest,ignore=shutil.ignore_patterns('assessment','d6','frame-analysis','rendered-review.json'))
    receipt={'base_run':base.name,'base_raw_sha256':sha(base/'raw-evaluation.json'),'candidate_identity':raw['candidate']['sha256'],'repairs':[]}
    for repair in repairs:
        source=Path(repair).resolve();r=load(source/'raw-evaluation.json')
        if r['status']=='run_invalid' or r['candidate']['sha256']!=raw['candidate']['sha256'] or not r['partial_selection']:raise InfrastructureError('INVALID_INCREMENTAL_REPAIR')
        prefix='increments/'+source.name;shutil.copytree(source,dest/prefix,ignore=shutil.ignore_patterns('assessment','d6'))
        checks=[k for k,v in r['checkpoints'].items() if not k.startswith('D1-')]
        for id in checks:
            row=r['checkpoints'][id];row['evidence']={'incremental_root':prefix,'original':row['evidence']};raw['checkpoints'][id]=row
        for id in r['case_selection']:raw['cases'][id]={**r['cases'][id],'source_run':source.name}
        # Fixed frame-analysis aliases refer to the superseding diagnostic run;
        # immutable originals remain available in base provenance and increments.
        for f in (source/'session/captures').iterdir():
            if f.name.startswith(('startup','d6-')):continue
            shutil.copy2(f,dest/'session/captures'/f.name)
        receipt['repairs'].append({'run':source.name,'raw_sha256':sha(source/'raw-evaluation.json'),'case_selection':r['case_selection'],'replaced_checks':checks,'policy':'Every selected case replaces prior evidence, regardless of score.'})
    raw['run_id']=dest.name;raw['status']='d6_pending';write(dest/'raw-evaluation.json',raw);write(dest/'evidence-merge.json',receipt)
    from d6 import prepare
    prepare(dest);return raw

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',required=True);p.add_argument('--repair',action='append',default=[]);p.add_argument('--dest',required=True);a=p.parse_args();merge(a.base,a.repair,a.dest)
