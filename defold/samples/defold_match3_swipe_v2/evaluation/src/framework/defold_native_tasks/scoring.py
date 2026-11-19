"""Evidence-bound, fixed-weight scoring; absent checks never receive credit."""
import hashlib
import json
from pathlib import Path

MAXIMA = {'D1':10, 'D2':30, 'D3':20, 'D4':20, 'D5':10}
VERDICTS = {'pass', 'fail', 'blocked', 'excluded', 'pending'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate_catalog(catalog):
    checks = catalog['checks']
    ids = [c['id'] for c in checks]
    if len(ids) != len(set(ids)):
        raise ValueError('DUPLICATE_CHECK_ID')
    for dim in MAXIMA:
        if not any(c['dimension']==dim for c in checks):
            raise ValueError('EMPTY_DIMENSION:'+dim)
    for c in checks:
        if (c['dimension'] not in MAXIMA or c['weight'] not in (1,2,3)
                or not c.get('requirements') or not c.get('description')
                or c.get('evidence_method') not in ('static','input_read','lifecycle','visual')):
            raise ValueError('INVALID_CHECK:'+c['id'])
    return catalog


def visual_score(review, *, candidate_identity, capture_hashes, protocol_hash):
    """Require all frozen states in each of three independently recorded rounds."""
    if review['candidate_identity'] != candidate_identity:
        raise ValueError('D6_CANDIDATE_IDENTITY_MISMATCH')
    if review['protocol_sha256'] != protocol_hash:
        raise ValueError('D6_PROTOCOL_MISMATCH')
    states = review['states']
    if len(states) not in (3,4,5) or len(states)!=len(set(states)):
        raise ValueError('D6_STATE_SET')
    if set(states) != set(capture_hashes) or review['capture_hashes'] != capture_hashes:
        raise ValueError('D6_CAPTURE_BINDING_MISMATCH')
    if not review.get('model') or len(review['rounds']) != 3:
        raise ValueError('D6_REQUIRES_ONE_MODEL_THREE_ROUNDS')
    request_ids=set(); values=[]
    for round_ in review['rounds']:
        if set(round_) != set(states):
            raise ValueError('D6_MISSING_STATE')
        totals=[]
        for state in states:
            r=round_[state]
            scores=r['subscores']
            if len(scores)!=5 or any(isinstance(x,bool) or x not in (0,.5,1,1.5,2) for x in scores):
                raise ValueError('D6_SUBSCORES')
            if not r.get('request_id') or r['request_id'] in request_ids:
                raise ValueError('D6_INDEPENDENT_RESPONSE_REQUIRED')
            if not r.get('reason') or not r.get('raw_response_sha256'):
                raise ValueError('D6_RESPONSE_EVIDENCE_MISSING')
            request_ids.add(r['request_id'])
            totals.append(sum(scores))
        values.append(sum(totals)/len(states))
    return {'max':10,'score':round(sum(values)/3,1),'round_scores':values,
            'model':review['model'],'states':states}


def score(catalog, results, *, infrastructure_error=None, d6=None):
    validate_catalog(catalog)
    expected={c['id']:c for c in catalog['checks']}
    observed={}
    for r in results:
        key=r['id']
        if key not in expected or key in observed:
            raise ValueError('UNEXPECTED_OR_DUPLICATE_RESULT:'+key)
        if r['verdict'] not in VERDICTS:
            raise ValueError('UNKNOWN_VERDICT:'+key)
        if r['verdict']=='pass' and not r.get('evidence'):
            raise ValueError('PASS_WITHOUT_EVIDENCE:'+key)
        observed[key]=r
    records=[observed.get(key,{'id':key,'verdict':'pending','reason':'not executed','evidence':[]})
             for key in expected]
    incomplete=any(r['verdict']=='pending' for r in records)
    invalid=bool(infrastructure_error) or any(r['verdict']=='excluded' for r in records)
    unresolved=[{'id':r['id'],'verdict':r['verdict'],'reason':r.get('reason','')}
                for r in records if r['verdict'] in ('excluded','pending')]
    if not infrastructure_error and any(r['verdict']=='excluded' for r in records):
        infrastructure_error='EVIDENCE_UNRESOLVED:'+','.join(r['id'] for r in records if r['verdict']=='excluded')
    dims={}; shares={v:0.0 for v in VERDICTS}
    for dim, maximum in MAXIMA.items():
        checks=[c for c in catalog['checks'] if c['dimension']==dim]
        total=sum(c['weight'] for c in checks)
        points=0.0
        for c in checks:
            verdict=observed.get(c['id'],{}).get('verdict','pending')
            value=maximum*c['weight']/total
            shares[verdict]+=value
            if verdict=='pass': points+=value
        dims[dim]={'max':maximum,'verified_points':round(points,8),
                   'score':None if invalid or incomplete else round(points,8),
                   'check_count':len(checks),'total_weight':total}
    functional=None if invalid or incomplete else round(sum(d['verified_points'] for d in dims.values()),6)
    total=None if functional is None or d6 is None else round(functional+d6['score'],6)
    return {'schema_version':1,'task':catalog['task_id'],
            'evaluation_status':'infrastructure_invalid' if invalid else 'incomplete' if incomplete else 'valid',
            'dimensions':dims,'nonvisual_max':90,'nonvisual_score':functional,'D6':d6,
            'total_max':100,'total_score':total,
            'full_score_verified':total==100,
            'weighted_outcomes_percent':{k:round(v/90*100,6) for k,v in shares.items()},
            'infrastructure_error':infrastructure_error,'unresolved_checks':unresolved,'checks':records,
            'note':'D6 is separately evidence-bound; missing visual review never supplies ten points.'}
