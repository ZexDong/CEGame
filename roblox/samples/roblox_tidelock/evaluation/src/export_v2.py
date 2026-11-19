"""Serialize original TideLock dimension results into the supplied v2 schema.

This module does not run checks, judge gameplay, reweight dimensions or replace
native checkpoint verdicts. The original report remains intact as evidence.
"""
from pathlib import Path
import json
import math
import uuid

MAXIMA={'D1':10,'D2':30,'D3':20,'D4':20,'D5':10,'D6':10}

def export_result(native, output, coverage, *, infrastructure_error=None, not_run=False):
    evidence=output/'evidence'
    evidence.mkdir(exist_ok=True)
    raw=evidence/'native-score.json'
    raw.write_text(json.dumps(native,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (evidence/'coverage.json').write_text(json.dumps(coverage,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    refs=['evidence/native-score.json']
    native_rows={r['dimension']:r for r in native.get('breakdown',[])}
    dimensions={}
    checks=[]
    mappings=coverage.get('requirements',[])
    for dimension,maximum in MAXIMA.items():
        row=native_rows.get(dimension,{})
        native_checks=row.get('checkpoints',[])
        executed=bool(row) and not not_run
        unresolved=any(c.get('status') in {'inconclusive','not_run'} for c in native_checks)
        value=row.get('score')
        resolved=(executed and type(value) in (int,float) and math.isfinite(value)
                  and 0<=value<=maximum and not unresolved)
        requirement_ids=[r['requirement_id'] for r in mappings
                         if any(cid.startswith(dimension.lower()+'.') for cid in r.get('existing_checkpoint_ids',[]))
                         or dimension=='D6' and r.get('dimension')=='D6']
        if not requirement_ids: requirement_ids=['TL-12.04']
        if resolved:
            status='pass' if value==maximum else 'fail' if value==0 else 'partial'
            score=value
            reason='Original dimension score copied without recomputation; native checkpoint details are retained in the evidence report.'
            dim_status='complete'
        else:
            status='inconclusive_evaluator' if executed else 'not_run'
            score=None
            reason='The native report has unresolved or unexecuted observations; its provisional number is retained only in the original evidence report.'
            dim_status='incomplete' if executed else 'not_run'
        dimensions[dimension]={'score':score,'max_score':maximum,'status':dim_status,'evidence':refs if executed else []}
        checks.append({'id':'native.'+dimension,'requirement_ids':requirement_ids,'dimension':dimension,
            'max_score':maximum,'score':score,'status':status,'reason':reason,'blocked_by':[],
            'evidence':refs if executed else []})
    native_final=native.get('official_score')
    final=(not infrastructure_error and native_final is not None and native.get('runner_valid') is True
           and native.get('adjudication_complete') is True and not native.get('unresolved')
           and not native.get('problems') and all(d['status']=='complete' for d in dimensions.values()))
    total=round(sum(d['score'] for d in dimensions.values()),6) if final else None
    if final and abs(total-native_final)>0.000001:
        final=False
        total=None
        reason='The native displayed dimensions and native official total differ; preserve both in the native report without inventing a corrected total.'
    else:
        reason='Original completed result serialized to v2; scores and original checkpoint verdicts preserved.' if final else (
            infrastructure_error or 'Original evaluation is not yet complete; v2 preserves unresolved states as null.')
    classification='scored' if final else 'infrastructure_failure' if infrastructure_error else 'not_run' if not_run else 'incomplete'
    result={'schema_version':'2.1','sample_id':'roblox_tidelock','sample_version':'3.3.0-template-v2',
        'evaluator_version':'original-tidelock-format-v2','run_id':'run-'+uuid.uuid4().hex,
        'evaluation_valid':final,'classification':classification,
        'coverage_status':'not_reviewed','reason':reason,
        'dimensions':dimensions,'checks':checks,'coverage_evidence':['evidence/coverage.json'],
        'final_score':total,'max_score':100,
        'extensions':{'native_format':'tide-lock-score-v1','native_official_score':native_final,
            'native_report':'evidence/native-score.json','native_checkpoint_verdicts_rewritten':False,
            'dimension_values_recomputed':False,
            'legacy_provenance_not_a_release_gate':'Existing original evaluator and workflow accepted as completed by the owner; this adapter adds no qualification gate.'}}
    (output/'score.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return result
