import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent

def write_partial(output,checks):
    rules=json.loads((ROOT/'rules.json').read_text(encoding='utf-8'))
    dimensions={}
    total=0
    unknown=[]
    for name,definition in rules['dimensions'].items():
        if definition.get('manual'):
            dimensions[name]={'status':'MANUAL_REVIEW_REQUIRED','maximum':10}
            continue
        passed=unresolved=failed=0
        for item in definition['checks']:
            status=checks.get(item['id'],{}).get('status')
            if status=='PASS': passed+=item['weight']
            elif status=='FAIL_OBSERVED': failed+=item['weight']
            else:
                unresolved+=item['weight']
                unknown.append(item['id'])
        total+=passed
        dimensions[name]={'confirmed':passed,'unresolved':unresolved,'observed_failed_weight':failed,'maximum':definition['maximum_score']}
    payload={'evaluation_status':'IN_PROGRESS_OR_INTERRUPTED','assessment_complete':False,
             'automatic_score':None,'confirmed_automatic_score':total,'automatic_score_maximum':90,
             'manual_visual_score_maximum':10,'dimensions':dimensions,'checks':checks,'unresolved_checks':unknown}
    target=Path(output)/'score.partial.json'
    temporary=target.with_suffix('.tmp')
    temporary.write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf-8')
    temporary.replace(target)
