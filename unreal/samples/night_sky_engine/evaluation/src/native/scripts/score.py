"""Canonical, evidence-bound D1-D6 aggregation. Infrastructure failures are not scores."""
import argparse
import copy
from jsonschema import Draft202012Validator
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from runtime import ROOT,TASK,load,write,sha,inside,InfrastructureError,code_identity
from review_contract import CAPTURES,REVISION,SUBCLAUSES,validate_review,apply_verdict

DIMENSIONS={'D1':10,'D2':30,'D3':20,'D4':20,'D5':10,'D6':10}
REVIEW_IDS=set(CAPTURES)

def rounded(n):return float(Decimal(str(n)).quantize(Decimal('.1'),rounding=ROUND_HALF_UP))

def verify_binding(review,raw,path):
    for key in ('run_id','candidate_identity_sha256','catalog_sha256'):
        if review.get(key)!=raw.get(key):raise InfrastructureError('REVIEW_IDENTITY_MISMATCH:'+key)
    if review.get('raw_sha256')!=sha(path):raise InfrastructureError('REVIEW_RAW_HASH_MISMATCH')

def validate_raw(raw):
    catalog=load(ROOT/'catalog/checkpoints.json')
    contract=load(ROOT/'contracts/scoring-contract.json')
    if contract['dimensions']!=DIMENSIONS or catalog['dimensions']!=DIMENSIONS:
        raise InfrastructureError('DIMENSION_CONTRACT_MISMATCH')
    if raw.get('schema_version')!='3.0.0' or raw.get('scoring_contract_sha256')!=sha(ROOT/'contracts/scoring-contract.json'):
        raise InfrastructureError('SCORING_CONTRACT_MISMATCH')
    from runtime import REPO
    if sha(REPO/contract['scoring_guide'])!=contract['scoring_guide_sha256']:
        raise InfrastructureError('CANONICAL_GUIDE_CHANGED')
    if raw['status']!='completed' or any(f['domain']=='infrastructure' for f in raw['faults']):
        raise InfrastructureError('RUN_INVALID')
    if raw['catalog_sha256']!=sha(ROOT/'catalog/checkpoints.json') or raw['input_gdd_sha256']!=sha(TASK/'input/GDD.md'):
        raise InfrastructureError('CONTRACT_IDENTITY_MISMATCH')
    expected={c['id']:c['dimension'] for c in catalog['checkpoints']}
    actual={c['checkpoint_id']:c for c in raw['checkpoints']}
    if len(actual)!=len(raw['checkpoints']) or set(actual)!=set(expected):raise InfrastructureError('CHECKPOINT_CATALOG_MISMATCH')
    for id,c in actual.items():
        if c['dimension']!=expected[id] or c['verdict'] not in ('pass','fail','unreachable'):
            raise InfrastructureError('VERDICT_INVALID:'+id)
    return actual

def score(raw_path,semantic_path,d6_path):
    raw=load(raw_path);actual=validate_raw(raw);root=raw_path.parent
    if not Draft202012Validator(load(ROOT/'schemas/raw-evaluation.schema.json')).is_valid(raw):
        raise InfrastructureError('RAW_SCHEMA_INVALID')
    verify_evidence(raw,root)
    from reconcile import reconcile
    corrections=reconcile(actual,raw,root)
    review=load(semantic_path) if semantic_path else unreachable_review(raw,raw_path);verify_binding(review,raw,raw_path)
    if review.get('method') not in ('human_normal_input_capture_review','runtime_evidence_audit','candidate_unreachable_evidence') or review.get('status')!='completed':
        raise InfrastructureError('SEMANTIC_REVIEW_REQUIRED')
    if review['method']=='candidate_unreachable_evidence' and review!=unreachable_review(raw,raw_path):raise InfrastructureError('FALSE_UNREACHABLE_REVIEW')
    if set(review.get('checks',{}))!=REVIEW_IDS:raise InfrastructureError('SEMANTIC_COVERAGE_MISMATCH')
    validate_review(review,raw,root)
    for id,item in review['checks'].items():
        if type(item.get('pass')) is not bool or not item.get('reason'):raise InfrastructureError('SEMANTIC_VERDICT_INVALID')
        if not item.get('evidence'):raise InfrastructureError('SEMANTIC_VERDICT_WITHOUT_EVIDENCE')
        if item['pass'] and not any(e['path'] in {c['path'] for c in raw['captures'].values()} for e in item['evidence']):
            raise InfrastructureError('REVIEW_REQUIRES_RUN_CAPTURE')
        for e in item.get('evidence',[]):
            p=inside(root,e['path'])
            if not p.is_file() or sha(p)!=e['sha256'] or raw['evidence_sha256'].get(e['path'])!=e['sha256']:raise InfrastructureError('SEMANTIC_EVIDENCE_INVALID')
        apply_verdict(actual,id,item)
    from reviewed_boundaries import apply as apply_boundary_gate
    from source_review import load_run_review
    source = None if not raw.get('captures') and any(f.get('domain') == 'candidate' for f in raw['faults']) else load_run_review(raw,root)
    apply_boundary_gate(actual,raw,root,source)
    for c in actual.values():
        if c['verdict']=='pass':
            if not c['evidence']:raise InfrastructureError('CHECKPOINT_MISSING_EVIDENCE')
            for e in c['evidence']:
                if e not in raw['evidence_sha256']:raise InfrastructureError('CHECKPOINT_EVIDENCE_MISSING:'+e)
    d6=load(d6_path);verify_binding(d6,raw,raw_path)
    means=validate_d6(d6,raw,root)
    scores={}
    for dim,maximum in list(DIMENSIONS.items())[:5]:
        rows=[c for c in actual.values() if c['dimension']==dim]
        scores[dim]=rounded(maximum*sum(c['verdict']=='pass' for c in rows)/len(rows))
    scores['D6']=rounded(sum(means)/3)
    return {'schema_version':'3.0.0','run_id':raw['run_id'],'candidate_id':raw['candidate_id'],
        'candidate_identity_sha256':raw['candidate_identity_sha256'],'catalog_sha256':raw['catalog_sha256'],
        'scorer_sha256':sha(Path(__file__)),'raw_sha256':sha(raw_path),'semantic_review_sha256':sha(semantic_path) if semantic_path else None,
        'semantic_review_method':review['method'],
        'runtime_review_revision':review.get('review_revision'),
        'runtime_review_validator_sha256':sha(ROOT/'scripts/review_contract.py'),
        'observation_source_review_sha256':sha(root/'observation-source-review.json') if (root/'observation-source-review.json').exists() else None,
        'observation_source_validator_sha256':sha(ROOT/'scripts/reviewed_boundaries.py'),
        'reviewer':review.get('reviewer'),
        'd6_sha256':sha(d6_path),'rounds':d6['rounds'],'status':'diagnostic_completed','diagnostic_only':True,'formal_freeze_performed':False,
        'dimensions':scores,'functional_total':rounded(sum(scores[d] for d in list(DIMENSIONS)[:5])),
        'overall':rounded(sum(scores.values())),'d6_round_scores':[rounded(m) for m in means],
        'checkpoints':list(actual.values()),'faults':raw['faults'],
        'scoring_contract_sha256':raw['scoring_contract_sha256'],
        'visual_scorer_sha256':sha(ROOT/'scripts/visual.py'),
        'evaluator_corrections':corrections,'reconciliation_sha256':sha(ROOT/'scripts/reconcile.py'),
        'deductions':[{'checkpoint_id':c['checkpoint_id'],'dimension':c['dimension'],
            'reason_code':c['reason'],'attribution':'candidate','affected_checkpoint_ids':[c['checkpoint_id']],
            'awarded_points':0.0,'evidence':c['evidence']} for c in actual.values() if c['verdict']!='pass']}

def validate_d6(d6,raw,root):
    from visual import validate_result
    return validate_result(d6,raw,root)

def verify_evidence(raw,root):
    if raw.get('evaluator_identity')!=code_identity():raise InfrastructureError('RUNNER_IDENTITY_MISMATCH')
    if raw.get('diagnostic_adapter'):
        adapter=raw['diagnostic_adapter']
        if adapter.get('path')!='scripts/collect_with_observer_fallback.py' or adapter.get('sha256')!=sha(ROOT/adapter['path']):
            raise InfrastructureError('DIAGNOSTIC_ADAPTER_IDENTITY_MISMATCH')
        if adapter.get('provenance') not in raw.get('evidence_sha256',{}):
            raise InfrastructureError('DIAGNOSTIC_ADAPTER_PROVENANCE_MISSING')
    index=raw.get('evidence_sha256',{})
    if not index:raise InfrastructureError('RUN_EVIDENCE_INDEX_REQUIRED')
    for path,digest in index.items():
        p=inside(root,path)
        if not p.is_file() or sha(p)!=digest:raise InfrastructureError('RUN_EVIDENCE_CHANGED:'+path)
    for capture in raw['captures'].values():
        if index.get(capture['path'])!=capture['sha256']:raise InfrastructureError('UNINDEXED_CAPTURE')
        if capture.get('context') not in index:raise InfrastructureError('CAPTURE_CONTEXT_REQUIRED')

def unreachable_review(raw,raw_path):
    if raw.get('captures') or not any(f.get('domain')=='candidate' for f in raw['faults']):
        raise InfrastructureError('VISIBLE_EVIDENCE_REQUIRES_SEMANTIC_REVIEW')
    return {'schema_version':'3.0.0','run_id':raw['run_id'],'candidate_identity_sha256':raw['candidate_identity_sha256'],
        'catalog_sha256':raw['catalog_sha256'],'raw_sha256':sha(raw_path),'method':'candidate_unreachable_evidence',
        'status':'completed','checks':{id:{'pass':False,'reason':'CANDIDATE_NO_RUNTIME_CAPTURE',
        'evidence':[{'path':path,'sha256':digest} for path,digest in raw['evidence_sha256'].items()]} for id in sorted(REVIEW_IDS)}}

def template(raw_path,path):
    if path.exists():raise InfrastructureError('SEMANTIC_REVIEW_OUTPUT_EXISTS')
    raw=load(raw_path);validate_raw(raw)
    write(path,{'schema_version':'3.0.0','run_id':raw['run_id'],'candidate_identity_sha256':raw['candidate_identity_sha256'],
        'catalog_sha256':raw['catalog_sha256'],'raw_sha256':sha(raw_path),'method':'human_normal_input_capture_review',
        'status':'pending','review_revision':REVISION,'blanket_approval':False,
        'reviewer':{'kind':'human','identity':''},
        'checks':{id:{'pass':None,'reason':'','observations':[],'evidence':[],
            **({'clause_observations':{key:{'pass':None,'observation':'','evidence':[]}
                                      for key in SUBCLAUSES[id]}} if id in SUBCLAUSES else {})}
                  for id in sorted(REVIEW_IDS)}})

def main():
    p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--semantic',type=Path)
    p.add_argument('--d6',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--template',action='store_true')
    a=p.parse_args()
    if a.template:template(a.raw,a.output)
    else:
        if not a.d6:raise InfrastructureError('COMPLETE_D6_REQUIRED')
        write(a.output,score(a.raw,a.semantic,a.d6));print(a.output)

if __name__=='__main__':main()
