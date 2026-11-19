"""Canonical score arithmetic, evidence binding, and strict failure attribution."""
import argparse
import math
from decimal import Decimal,ROUND_HALF_UP
from pathlib import Path
from runtime import ROOT,TASK,load,write,sha,inside,InfrastructureError,code_identity

def rounded(n):return float(Decimal(str(n)).quantize(Decimal('.1'),rounding=ROUND_HALF_UP))
def require(ok,code):
    if not ok:raise InfrastructureError(code)
def valid_raw(raw):
    catalog=load(ROOT/'scoring-catalog.json')
    require(raw.get('status')=='collected' and raw.get('fault') is None,'RAW_RUN_INVALID')
    require(raw.get('cleanup_confirmed') is True,'CLEANUP_NOT_CONFIRMED')
    require(raw.get('catalog_sha256')==sha(ROOT/'scoring-catalog.json'),'CATALOG_IDENTITY_MISMATCH')
    require(raw.get('gdd_sha256')==sha(TASK/'input/GDD.md'),'GDD_IDENTITY_MISMATCH')
    require(raw.get('runtime_identity')==code_identity(),'RUNTIME_IDENTITY_MISMATCH')
    checks=raw.get('checkpoints',[]);expected={c['id']:c for c in catalog['checkpoints']}
    require(len(checks)==len(expected) and {c.get('id') for c in checks}==set(expected),'CHECKPOINT_SET_MISMATCH')
    for c in checks:
        require(c.get('verdict') in ('pass','fail','unreachable'),'CHECKPOINT_VERDICT_INVALID')
        require(c.get('dimension')==expected[c['id']]['dimension'],'CHECKPOINT_DIMENSION_INVALID')
        require(isinstance(c.get('reason'),str) and bool(c['reason']),'CHECKPOINT_REASON_MISSING')
        require(c.get('attribution')=='candidate','CHECKPOINT_ATTRIBUTION_INVALID')
        require(bool(c.get('evidence')),'CHECKPOINT_WITHOUT_EVIDENCE')
    return catalog

def validate_evidence(raw,root):
    manifest=load(root/'evidence-manifest.json');seen=set()
    for row in manifest.get('files',[]):
        require(row['path'] not in seen,'DUPLICATE_EVIDENCE_PATH');seen.add(row['path'])
        p=inside(root,row['path']);require(p.is_file(),'EVIDENCE_MISSING:'+row['path'])
        require(sha(p)==row['sha256'],'EVIDENCE_HASH_MISMATCH:'+row['path'])
    require('raw-evaluation.json' in seen,'RAW_NOT_SEALED')
    for c in raw['checkpoints']:
        if c['verdict']=='pass':
            for path in c['evidence']:require(path in seen,'CHECKPOINT_EVIDENCE_NOT_SEALED:'+path)
        else:require(any(p in seen for p in c['evidence']),'FAILURE_CAUSE_NOT_SEALED:'+c['id'])
    for capture in raw['captures'].values():
        require(capture['path'] in seen and capture['context'] in seen,'CAPTURE_NOT_SEALED')
        require(sha(inside(root,capture['path']))==capture['sha256'],'CAPTURE_IDENTITY_MISMATCH')
    return manifest

def validate_review(review,raw,raw_path,catalog,root):
    require(review.get('raw_sha256')==sha(raw_path),'PICTURE_REVIEW_WRONG_RUN')
    require(review.get('method')=='fixed_human_runtime_review','PICTURE_REVIEW_METHOD_INVALID')
    require(bool(review.get('reviewer')),'PICTURE_REVIEWER_MISSING')
    required={c['id'] for c in catalog['checkpoints'] if c['runtime_picture_review_required'] and next(x for x in raw['checkpoints'] if x['id']==c['id'])['verdict']=='pass'}
    rows=review.get('checks',[])
    require(len(rows)==len(required) and {r.get('id') for r in rows}==required,'PICTURE_REVIEW_SET_MISMATCH')
    for row in rows:
        require(type(row.get('passed')) is bool and bool(row.get('reason')) and bool(row.get('evidence')),'PICTURE_REVIEW_INCOMPLETE')
        for e in row['evidence']:
            require(sha(inside(root,e['path']))==e['sha256'],'PICTURE_REVIEW_EVIDENCE_CHANGED')
    return {r['id']:r for r in rows}

def aggregate_d6(data,raw,raw_path,root):
    manifest=load(ROOT/'d6/reference-manifest.json');ids={s['id'] for s in manifest['states']}
    require(3<=len(ids)<=5,'D6_STATE_COUNT_INVALID')
    require(data.get('status')=='completed' and data.get('raw_sha256')==sha(raw_path),'D6_INVALID_OR_WRONG_RUN')
    require(data.get('manifest_sha256')==sha(ROOT/'d6/reference-manifest.json'),'D6_REFERENCE_MANIFEST_CHANGED')
    require(data.get('prompt_sha256')==sha(ROOT/'d6/FIXED_VLM_PROMPT.txt'),'D6_PROMPT_CHANGED')
    # This revision intentionally leaves provider-model choice to the caller.
    # Keep the chosen/requested and returned identities auditable per run, but
    # do not bind them to the historical manifest default.
    rounds=data.get('rounds',[]);require(len(rounds)==3 and [r.get('number') for r in rounds]==[1,2,3],'D6_ROUNDS_INVALID')
    means=[];model=None
    for r in rounds:
        rows=r.get('states',[]);require(len(rows)==len(ids) and {s.get('id') for s in rows}==ids,'D6_STATES_INVALID')
        scores=[]
        for s in rows:
            criteria=s.get('criteria',[])
            require(len(criteria)==5 and all(type(v) in (int,float) and v in (0,.5,1,1.5,2) for v in criteria),'D6_CRITERIA_INVALID')
            state=next(x for x in manifest['states'] if x['id']==s['id'])
            require(sha(inside(ROOT/'d6',state['reference']))==state['sha256'],'D6_REFERENCE_FILE_CHANGED')
            from d6 import reached,select_capture
            capture_name,capture=select_capture(raw,state,root)
            require(s.get('candidate_capture',state['candidate_capture'])==capture_name,'D6_CAPTURE_SELECTION_MISMATCH')
            require(s.get('reference_sha256')==state['sha256'],'D6_REFERENCE_IDENTITY_MISMATCH')
            if s.get('status')=='compared':
                require(bool(capture) and capture['visible'] and reached(capture,state,root),'D6_COMPARE_MISSING_IMAGE')
                require(s.get('candidate_sha256')==capture['sha256'],'D6_CANDIDATE_IDENTITY_MISMATCH')
                for k in ('request','response','parser'):
                    require(k in s and sha(inside(root,s[k]['path']))==s[k]['sha256'],'D6_RAW_RECEIPT_MISSING_OR_CHANGED')
                response=load(inside(root,s['response']['path']));returned=response.get('model')
                require(bool(returned) and model in (None,returned),'D6_MODEL_CHANGED');model=returned
                from d6 import parse
                parsed,reason=parse(response['choices'][0]['message']['content'])
                require(criteria==parsed,'D6_PARSED_SCORE_MISMATCH')
                parser_receipt=load(inside(root,s['parser']['path']))
                require(parser_receipt.get('criteria')==parsed and parser_receipt.get('reason')==reason,'D6_PARSER_RECEIPT_MISMATCH')
                request=load(inside(root,s['request']['path']))
                require(request.get('model')==data.get('model_requested'),'D6_REQUEST_MODEL_RECEIPT_MISMATCH')
                expected_prompt=(ROOT/'d6/FIXED_VLM_PROMPT.txt').read_text(encoding='utf-8').replace('{{CURRENT_STATE_LABEL}}',state['label'])
                require(request.get('prompt')==expected_prompt and request.get('image_order')==['reference','candidate'],'D6_REQUEST_PROTOCOL_CHANGED')
                require(request.get('reference_sha256')==state['sha256'] and request.get('candidate_sha256')==capture['sha256'],'D6_REQUEST_IMAGE_BINDING_CHANGED')
            else:
                require(s.get('status') in ('candidate_missing','candidate_black'),'D6_STATUS_INVALID')
                require(all(v==0 for v in criteria),'D6_FAILURE_NOT_ZERO')
                require(not capture or not capture['visible'] or not reached(capture,state,root),'D6_FALSE_MISSING')
            scores.append(sum(criteria))
        means.append(sum(scores)/len(scores))
    return rounded(sum(means)/3),[rounded(n) for n in means]

def score(raw,catalog,review,d6):
    results=[];scores={}
    for c in raw['checkpoints']:
        result=dict(c)
        if c['id'] in review and not review[c['id']]['passed']:
            result.update(verdict='fail',reason='RUNTIME_PICTURE_REVIEW_FAILED:'+review[c['id']]['reason'])
        results.append(result)
    for dimension,maximum in catalog['maxima'].items():
        if dimension=='D6':continue
        subset=[c for c in results if c['dimension']==dimension]
        scores[dimension]=rounded(maximum*sum(c['verdict']=='pass' for c in subset)/len(subset))
    scores['functional_total']=rounded(sum(scores.values()));scores['D6']=rounded(d6[0])
    scores['Overall']=rounded(scores['functional_total']+scores['D6'])
    return dict(schema_version='2.0.0',status='diagnostic_complete',formal_frozen=False,run_id=raw['run_id'],
        scores=scores,d6_rounds=d6[1],checkpoints=results,candidate_identity_sha256=raw['candidate_identity_sha256'],
        catalog_sha256=raw['catalog_sha256'],low_score_causes=[c for c in results if c['verdict']!='pass'])

def main():
    p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--review',type=Path,required=True)
    p.add_argument('--d6',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    try:
        raw=load(args.raw);catalog=valid_raw(raw);root=args.raw.resolve().parent;validate_evidence(raw,root)
        review=validate_review(load(args.review),raw,args.raw,catalog,root)
        d6=aggregate_d6(load(args.d6),raw,args.raw,root)
        result=score(raw,catalog,review,d6);result.update(raw_sha256=sha(args.raw),review_sha256=sha(args.review),d6_sha256=sha(args.d6),scorer_sha256=sha(Path(__file__)))
        write(args.output,result);print(result['scores']);return 0
    except (InfrastructureError,OSError,ValueError,KeyError,TypeError) as e:
        write(args.output,dict(status='evaluation_incomplete',fault=dict(domain='infrastructure',code=str(e)),score_publication_allowed=False))
        print(str(e));return 2
if __name__=='__main__':raise SystemExit(main())
