"""Canonical D1-D6 diagnostic scorer. No source-similarity or Gold dependency."""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
from support import *
from spec import DIMENSIONS
from catalog import CHECKS
import d6

def visual_review_errors(id,review):
    """Prevent source-only or partial review from becoming a positive verdict."""
    required=load(TASK/'evaluator/rendered-review-criteria.json')['checks'].get(id,[])
    if review.get('verdict')!='pass' or not required:return []
    criteria=review.get('criteria',{});errors=[]
    for key in required:
        row=criteria.get(key,{})
        permitted=['rendered','rendered_and_dynamic']
        if key=='representative_event_audio':permitted+=['recorded_audio']
        if (row.get('verdict')!='pass' or row.get('basis') not in permitted or not row.get('facts') or not row.get('evidence')
            or not set(row.get('evidence',[]))<=set(review.get('evidence',[]))):
            errors.append('VISUAL_SUBCRITERION_NOT_PROVEN:'+id+':'+key)
    return errors

def score(run):
    collection=load(run/'collection.json')
    if collection['status'] not in ['collected','candidate_failed']:raise InfrastructureError('COLLECTION_NOT_COMPLETED')
    if any(f.get('attribution')=='infrastructure' for f in collection.get('faults',[])):raise InfrastructureError('COLLECTION_INFRASTRUCTURE_FAULT')
    if collection.get('partial'):raise InfrastructureError('PARTIAL_AUTHORING_COLLECTION_NOT_SCOREABLE')
    if collection['gdd_sha256']!=sha(TASK/'input/GDD.md'):raise InfrastructureError('GDD_IDENTITY_CHANGED')
    if collection['scoring_guide_sha256']!=sha(REPO/'gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md'):raise InfrastructureError('SCORING_GUIDE_CHANGED')
    reviews=load(run/'rendered-review.json') if (run/'rendered-review.json').exists() else {}
    results=[];blocking=[]
    global_failure=collection['status']=='candidate_failed' or any(f['attribution']=='candidate' for f in collection.get('faults',[]))
    for id,check in CHECKS.items():
        reasons=[];verdict='pass';evidence=[]
        if check['stage']=='static':
            row=collection['static'].get(id)
            if row is None:
                if not global_failure:blocking.append('MISSING_STATIC_RESULT:'+id)
                verdict='unreachable';reasons.append('CANDIDATE_PREFLIGHT_FAILED')
            else:verdict=row['verdict'];reasons.append(row.get('detail'))
            evidence.append('collection.json')
        else:
            for name in check['cases']:
                case=collection['cases'].get(name)
                if case is None:
                    if not global_failure:blocking.append('MISSING_CASE:'+name)
                    verdict='unreachable';reasons.append('CANDIDATE_PRECONDITION_UNREACHABLE:'+name);continue
                evidence.append(case.get('session','normal')+'/cases/'+name+'.json')
                vote=case.get('votes',{}).get(id)
                if not vote:
                    if not case.get('error'):blocking.append('MISSING_ASSERTION:'+name+':'+id)
                    verdict='unreachable';reasons.append(case.get('error') or 'AUTHORING_ASSERTION_MISSING');continue
                if vote['verdict']!='pass':verdict='fail';reasons.append(vote)
                if vote['verdict']=='pass':
                    if not case.get('captures'):blocking.append('PASS_LACKS_CAPTURE:'+name)
                    session=run/case['session']
                    if not (session/'samples.jsonl').exists() or not (session/'cleanup.json').exists():blocking.append('PASS_LACKS_SAMPLES_OR_CLEANUP:'+name)
                    else:
                        cleanup=load(session/'cleanup.json');detail=cleanup.get('result',{})
                        if cleanup.get('status')!='ok' or not detail.get('process_exited') or not detail.get('input_lease_released') or not detail.get('input_cleanup',{}).get('all_released') or detail.get('job_active_process_count_after_wait')!=0:blocking.append('CLEANUP_NOT_CONFIRMED:'+name)
                        for artifact in case['captures']:
                            path=(session/artifact).resolve()
                            if not path.is_relative_to(run.resolve()) or not path.is_file():blocking.append('CAPTURE_MISSING_OR_UNSAFE:'+name)
                            elif not path.with_suffix('.json').is_file() or sha(path)!=load(path.with_suffix('.json')).get('sha256'):blocking.append('CAPTURE_HASH_MISMATCH:'+name)
            if check['visible_review'] and verdict=='pass':
                review=reviews.get(id)
                if not review:blocking.append('RENDERED_REVIEW_REQUIRED:'+id)
                elif review.get('verdict') not in ['pass','fail'] or not review.get('facts') or not review.get('evidence'):blocking.append('RENDERED_REVIEW_INVALID:'+id)
                else:
                    blocking.extend(visual_review_errors(id,review))
                    if review['verdict']=='fail':verdict='fail';reasons.append(review)
                    for artifact in review['evidence']:
                        path=(run/artifact).resolve()
                        if not path.is_relative_to(run.resolve()) or not path.is_file():blocking.append('REVIEW_EVIDENCE_MISSING_OR_UNSAFE:'+id)
                    evidence.extend(review['evidence'])
        results.append({**check,'verdict':verdict,'passed':verdict=='pass','attribution':'candidate' if verdict!='pass' else 'observed','reasons':reasons,'evidence':evidence})
    if blocking:
        write(run/'scoring-incomplete.json',{'status':'evaluation_incomplete','reasons':sorted(set(blocking))});raise InfrastructureError('EVIDENCE_COMPLETION_REQUIRED:'+str(len(set(blocking))))
    d6.prepare(run);visual=d6.aggregate(run)
    scores={}
    for dim in ['D1','D2','D3','D4','D5']:
        items=[r for r in results if r['dimension']==dim];scores[dim]=round(DIMENSIONS[dim]*sum(x['passed'] for x in items)/len(items),1)
    scores['D6']=visual['score'];scores['functional_total']=round(sum(scores[d] for d in ['D1','D2','D3','D4','D5']),1);scores['Overall']=round(scores['functional_total']+scores['D6'],1)
    result={'schema_version':'gemsbond-score-1.0','status':'diagnostic_complete','candidate_identity':collection.get('candidate_identity','missing-artifact'),
            'canonical_scorer_sha256':sha(Path(__file__)),'catalog_sha256':sha(Path(__file__).with_name('catalog.py')),'scores':scores,
            'd6_rounds':[round(r['mean'],1)for r in visual['rounds']],'checks':results,'formal_freeze':False,'solved_claim':False}
    write(run/'score.json',result);return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',type=Path,required=True);a=p.parse_args()
    try:print(json.dumps(score(a.run)['scores']));sys.exit(0)
    except InfrastructureError as e:print(json.dumps({'status':'evaluation_incomplete','reason':str(e)}));sys.exit(2)
