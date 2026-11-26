"""The sole numeric scorer: equal checkpoints within each canonical dimension."""
from common import *
from d6 import aggregate,round_decimal
import argparse

def score(root):
    root=Path(root);raw=load(root/'raw-evaluation.json');catalog=load(TASK/'evaluator/catalog/checkpoints.json')
    if raw['status']=='run_invalid':raise InfrastructureError('RUN_INVALID_NO_SCORE')
    if raw.get('partial_selection'):raise InfrastructureError('PARTIAL_DIAGNOSTIC_REQUIRES_EXPLICIT_EVIDENCE_MERGE')
    ids={c['id'] for c in catalog['checks']}
    if set(raw['checkpoints'])!=ids:raise InfrastructureError('CHECKPOINT_SET_MISMATCH')
    from visual_review import apply
    raw=apply(root,raw,catalog)
    dims={};details={}
    for dim in ['D1','D2','D3','D4','D5']:
        checks=[c for c in catalog['checks'] if c['dimension']==dim];passed=0
        for c in checks:
            r=raw['checkpoints'][c['id']]
            if r['verdict'] not in ['pass','fail','unreachable']:raise InfrastructureError('INVALID_VERDICT')
            if r['verdict']=='pass':passed+=1
            elif not r.get('reason') or not r.get('evidence'):raise InfrastructureError('FAILURE_WITHOUT_REASON_EVIDENCE')
        dims[dim]=round_decimal(catalog['dimensions'][dim]*passed/len(checks));details[dim]={'passed':passed,'total':len(checks),'maximum':catalog['dimensions'][dim]}
    d6=aggregate(root);dims['D6']=d6['score'];functional=round_decimal(sum(dims[d] for d in ['D1','D2','D3','D4','D5']))
    result={'schema_version':'1.0.0','status':'diagnostic_complete','candidate_identity':raw['candidate']['sha256'],'scorer_identity':sha(Path(__file__)),'contract_identity':sha(TASK/'evaluator/catalog/checkpoints.json'),'scores':dims,'functional_total':functional,'overall':round_decimal(functional+dims['D6']),'d6_rounds':d6['rounds'],'d6_results':d6['records'],'checkpoint_counts':details,'failures':{k:v for k,v in raw['checkpoints'].items() if v['verdict']!='pass'},'not_formal_frozen_score':True}
    write(root/'result.json',result)
    write(root/'scored-checkpoints.json',raw['checkpoints'])
    row='| '+raw['kind']+' | '+' | '.join(f'{dims[d]:.1f}' for d in ['D1','D2','D3','D4','D5'])+f' | {functional:.1f} | {dims["D6"]:.1f} ('+', '.join(f'{v:.1f}' for v in d6['rounds'])+f') | {result["overall"]:.1f} |'
    (root/'RESULT.md').write_text('# Chomp diagnostic result\n\n| Artifact | D1 /10 | D2 /30 | D3 /20 | D4 /20 | D5 /10 | Functional /90 | D6 /10 (rounds) | Overall /100 |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|\n'+row+'\n\nDiagnostic authoring evidence; not a formal frozen benchmark result.\n',encoding='utf-8')
    return result
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('run');a=ap.parse_args()
    try:
        result=score(a.run);print(json.dumps(result,indent=2));raise SystemExit(2 if result['failures'] else 0)
    except InfrastructureError as e:
        print(json.dumps({'status':'evaluation_incomplete','reason':str(e),'score_published':False}));raise SystemExit(3)
