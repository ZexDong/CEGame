"""Canonical RollBall v4 scorer.

The collector produces evidence for independent cases. This scorer merges
those findings into exactly one primary result per catalog checkpoint, applies
only public checkpoint weights, and refuses to publish a number while evidence
or review is incomplete.
"""
import argparse
from pathlib import Path
from evidence import (InvalidEvidence, check_collection, read, write, sha,
                      verified, image_info, rounded)
ROOT = Path(__file__).resolve().parents[1]
EVALUATOR_REVISION = 'rollball-evaluator-4.1.0'

def _review_rows(path, run_root):
    if not path: return {}
    review=read(path)
    if review.get('version')!='4.0.0' or review.get('status')!='completed':
        raise InvalidEvidence('FUNCTIONAL_REVIEW_INCOMPLETE')
    if review.get('collection_sha256')!=sha(run_root/'collection.json'):
        raise InvalidEvidence('FUNCTIONAL_REVIEW_BINDING')
    rows=review.get('checks')
    if not isinstance(rows,dict): raise InvalidEvidence('FUNCTIONAL_REVIEW_CHECKS')
    out={}
    for cid,row in rows.items():
        if cid in out: raise InvalidEvidence('DUPLICATE_REVIEW_CHECKPOINT:'+cid)
        if row.get('verdict') not in ('pass','fail') or not row.get('reason'):
            raise InvalidEvidence('FUNCTIONAL_REVIEW_ROW_INVALID:'+cid)
        evidence=row.get('evidence',[])
        if not evidence: raise InvalidEvidence('FUNCTIONAL_REVIEW_EVIDENCE_MISSING:'+cid)
        for item in evidence:
            if not isinstance(item,dict): raise InvalidEvidence('FUNCTIONAL_REVIEW_EVIDENCE_INVALID:'+cid)
            verified(run_root,item.get('path',''),item.get('sha256',''))
        out[cid]=row
    return out

def _static_rows(path, run_root, catalog):
    if not path: return {}
    static=read(path)
    if static.get('version')!='4.0.0' or static.get('status')!='completed':
        raise InvalidEvidence('STATIC_RUN_INCOMPLETE')
    if static.get('faults'): raise InvalidEvidence('STATIC_RUN_FAULT')
    rows=static.get('checks')
    if not isinstance(rows,dict): raise InvalidEvidence('STATIC_CHECKS_MISSING')
    out={}; expected={c['id'] for c in catalog['checkpoints']}
    for cid,row in rows.items():
        if cid not in expected: raise InvalidEvidence('UNKNOWN_STATIC_CHECK:'+cid)
        if row.get('verdict') not in ('pass','fail'): raise InvalidEvidence('STATIC_VERDICT_INVALID:'+cid)
        if not row.get('reason') or not row.get('evidence'): raise InvalidEvidence('STATIC_EVIDENCE_MISSING:'+cid)
        # Static evidence is rooted beside static.json; collection evidence is
        # rooted beside collection.json.  Keeping those roots separate avoids
        # accidental path rebinding when a clean build is copied elsewhere.
        for item in row['evidence']: verified(Path(path).resolve().parent,item['path'],item['sha256'])
        out[cid]=dict(machine_verdict='supported' if row['verdict']=='pass' else 'fail',reason=row['reason'],facts=row.get('facts',{}),evidence=row['evidence'])
    return out

def _merge(data,catalog,static):
    by={}
    for case in data['cases']:
        for cid,row in case.get('findings',{}).items(): by.setdefault(cid,[]).append((case['id'],row))
    result={}
    for c in catalog['checkpoints']:
        cid=c['id']; rows=by.get(cid,[])
        if cid in static: rows=[('static',static[cid])]+rows
        if not rows: raise InvalidEvidence('CHECKPOINT_MISSING:'+cid)
        verdicts={r.get('machine_verdict') for _,r in rows}
        if not verdicts.issubset({'supported','review','fail','unreachable'}): raise InvalidEvidence('CHECKPOINT_CONFLICT:'+cid)
        # Duplicate observations are intentional for shared requirements (for
        # example D3-directions runs W, A, S and D). One proven failure or
        # candidate-unreachable result wins; otherwise an unresolved review
        # wins; only all-supported evidence is promoted automatically.
        machine='fail' if ('fail' in verdicts or 'unreachable' in verdicts) else ('review' if 'review' in verdicts else 'supported')
        case,row=next(((k,r) for k,r in rows if r.get('machine_verdict')==machine), rows[0])
        evidence=list(row.get('evidence',[]))
        if not evidence and case!='static':
            case_obj=next(x for x in data['cases'] if x['id']==case)
            for cap in case_obj.get('captures',[])[:2]:
                evidence.append(dict(path=f"{case}/{cap['path']}",sha256=cap['sha256']))
        if c.get('visible_review_required') and machine in ('supported','review'): final='review'
        elif machine=='supported': final='pass'
        elif machine in ('fail','unreachable'): final='fail'
        else: final='review'
        result[cid]=dict(id=cid,dimension=c['dimension'],requirement=c['requirement'],
            verdict=final,machine_verdict=machine,
            attribution='candidate' if machine in ('fail','unreachable') else 'observed',
            reason=row.get('reason') or 'No reason supplied',evidence=evidence,source_case=case,
            facts=row.get('facts',{}))
    return result

def _apply_review(results,review):
    needed={cid for cid,r in results.items() if r['verdict']=='review'}
    if needed and not review: raise InvalidEvidence('FUNCTIONAL_REVIEW_REQUIRED')
    if set(review)!=needed: raise InvalidEvidence('FUNCTIONAL_REVIEW_CHECKPOINT_SET')
    for cid,row in review.items():
        results[cid]['verdict']=row['verdict']; results[cid]['attribution']='candidate' if row['verdict']=='fail' else 'observed'
        results[cid]['reason']=row['reason']; results[cid]['evidence']=row['evidence']
    return results

def _candidate_capture(collection, run_root, name):
    aliases={'navigation':('direction-W','released'),'reopen':('reopen','fresh-process'),'initial':('entry','initial')}
    for case in collection['cases']:
        for cap in case.get('captures',[]):
            stem=Path(cap.get('path','')).stem
            alias=aliases.get(name)
            if stem==name or (name=='initial' and case['id']=='entry' and stem=='initial') or (alias and case['id']==alias[0] and stem==alias[1]):
                p=run_root/case['id']/cap['path']
                if p.is_file() and not image_info(p)[1]: return case['id'],cap,p
    return None

def _d6_score(d6_path, collection, run_root):
    refs=read(ROOT/'d6/references.json'); states=[s['id'] for s in refs.get('states',[])]
    if not states: raise InvalidEvidence('D6_REFERENCE_STATES')
    protocol=read(ROOT/'d6/protocol.json')
    if protocol.get('version')!='4.0.0' or protocol.get('rounds')!=3 or protocol.get('states')!=states or protocol.get('prompt_sha256')!=sha(ROOT/'d6/FIXED_PROMPT.txt'):
        raise InvalidEvidence('D6_PROTOCOL_BINDING')
    usable={name:_candidate_capture(collection,run_root,name) for name in states}
    usable={k:v for k,v in usable.items() if v}
    if not usable: return 0.0,[0.0,0.0,0.0]
    if not d6_path: raise InvalidEvidence('D6_REVIEW_REQUIRED')
    d6=read(d6_path)
    if d6.get('status')!='completed' or d6.get('collection_sha256')!=sha(run_root/'collection.json'):
        raise InvalidEvidence('D6_BINDING')
    if d6.get('references_sha256')!=sha(ROOT/'d6/references.json') or d6.get('prompt_sha256')!=sha(ROOT/'d6/FIXED_PROMPT.txt'):
        raise InvalidEvidence('D6_PROTOCOL_BINDING')
    rounds=d6.get('rounds')
    if not isinstance(rounds,list) or len(rounds)!=3: raise InvalidEvidence('D6_ROUNDS_INVALID')
    means=[]
    for i,rd in enumerate(rounds,1):
        rows=rd.get('states',[])
        if [x.get('state') for x in rows]!=states: raise InvalidEvidence('D6_STATE_ORDER')
        vals=[]
        for row in rows:
            criteria=row.get('criteria')
            if not isinstance(criteria,list) or len(criteria)!=5 or any(v not in (0,.5,1,1.5,2) for v in criteria): raise InvalidEvidence('D6_CRITERIA_INVALID')
            if row['state'] not in usable:
                if row.get('source')!='candidate_zero' or any(criteria): raise InvalidEvidence('D6_MISSING_STATE_NONZERO')
            else:
                if row.get('source')!='vlm': raise InvalidEvidence('D6_COMPARABLE_ZERO_BYPASS')
                for key in ('request','response'):
                    item=row.get(key) or {}; verified(run_root,item.get('path',''),item.get('sha256',''))
            vals.append(sum(criteria))
        means.append(sum(vals)/len(states))
    return rounded(sum(means)/3),[rounded(v) for v in means]

def score(collection_path, static_path=None, review_path=None, d6_path=None):
    collection_path=Path(collection_path).resolve(); run_root=collection_path.parent
    data,catalog=check_collection(collection_path)
    static=_static_rows(static_path,run_root,catalog); results=_merge(data,catalog,static)
    results=_apply_review(results,_review_rows(review_path,run_root))
    if any(r['verdict']=='review' for r in results.values()): raise InvalidEvidence('UNRESOLVED_REVIEW')
    scores={}
    for dim,cap in catalog['dimensions'].items():
        if dim=='D6': continue
        subset=[r for r in results.values() if r['dimension']==dim]
        scores[dim]=rounded(cap*sum(r['verdict']=='pass' for r in subset)/len(subset))
    d6,rounds=_d6_score(d6_path,data,run_root); scores['D6']=d6
    scores['functional_total']=rounded(sum(scores[d] for d in ('D1','D2','D3','D4','D5')))
    scores['overall']=rounded(scores['functional_total']+d6)
    candidate_failures=[]
    for row in results.values():
        if row.get('machine_verdict') in ('fail','unreachable'):
            candidate_failures.append(dict(checkpoint_id=row['id'],reason_code=row.get('reason','CANDIDATE_FAILURE'),
                attribution='candidate',source_case=row.get('source_case'),evidence=row.get('evidence',[]),
                score_impact='checkpoint_zero'))
    return dict(version='4.0.0',evaluator_revision=EVALUATOR_REVISION,status='completed',formal_freeze=False,
                collection_sha256=sha(collection_path),static_sha256=sha(static_path) if static_path else None,
                review_sha256=sha(review_path) if review_path else None,d6_sha256=sha(d6_path) if d6_path else None,
                catalog_sha256=sha(ROOT/'catalog/checkpoints.json'),gdd_sha256=catalog['gdd_sha256'],
                scores=scores,d6_rounds=rounds,checkpoints=list(results.values()),candidate_failures=candidate_failures,
                unresolved=[],score_publication_allowed=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('--collection',required=True);p.add_argument('--static');p.add_argument('--review');p.add_argument('--d6');p.add_argument('--output',required=True);a=p.parse_args()
    try:
        out=score(a.collection,a.static,a.review,a.d6);write(a.output,out);print(out['scores']);return 0
    except Exception as exc:
        out=dict(version='4.0.0',evaluator_revision=EVALUATOR_REVISION,status='evaluation_incomplete',score_publication_allowed=False,
                 fault=dict(type=type(exc).__name__,reason=str(exc)),scores=None)
        write(a.output,out);print(type(exc).__name__+': '+str(exc));return 2
if __name__=='__main__': raise SystemExit(main())
