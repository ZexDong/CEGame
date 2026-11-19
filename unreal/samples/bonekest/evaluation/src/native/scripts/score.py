"""Strict canonical numeric scoring; no subjective defaults or missing-value scores."""
from pathlib import Path
import json,re,argparse,hashlib,sys
EV=Path(__file__).resolve().parents[1]
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,v):p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
LABELS=['Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish']
def parse_response(text):
    text=text.strip();lines=text.splitlines()
    if len(lines)!=7:raise ValueError('D6 response must contain exactly seven canonical lines')
    scores=[]
    for label,line in zip(LABELS,lines):
        m=re.fullmatch(re.escape(label)+r':([0-2](?:\.[05])?)/2',line.strip())
        if not m:raise ValueError('Invalid canonical D6 category: '+line)
        v=float(m[1])
        if v not in (0,.5,1,1.5,2):raise ValueError('Invalid D6 increment')
        scores.append(v)
    m=re.fullmatch(r'Total:([0-9]+(?:\.[05])?)/10',lines[5].strip())
    if not m or float(m[1])!=sum(scores):raise ValueError('D6 total does not equal its five categories')
    if not lines[6].startswith('Reason:') or not lines[6][len('Reason:'):].strip():raise ValueError('D6 visible-evidence reason required')
    return {'categories':dict(zip(LABELS,scores)),'total':sum(scores),'reason':lines[6][len('Reason:'):]}
def requests(run):
    run=Path(run);refs=load(EV/'d6/reference-manifest.json');caps=load(run/'d6-captures.json')['states'];prompt=(EV/'d6/prompt.txt').read_text(encoding='utf-8')
    if sha(EV/'d6/prompt.txt')!=refs['prompt_sha256']:raise ValueError('Canonical D6 prompt changed')
    items=[]
    for rnd in range(1,4):
        for state in refs['states']:
            key=state['id'];cap=caps[key];reference=(EV/'d6'/state['reference']).resolve()
            if sha(reference)!=state['sha256']:raise ValueError('Reference identity changed')
            record={'round':rnd,'state':key,'reference':state['reference'],'reference_sha256':sha(reference),'label':state['label'],'transport':'direct_conversation','prompt':prompt.replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',state['label']),'prompt_template_sha256':refs['prompt_sha256'],'response':f'round-{rnd}/{key}.txt'}
            if cap['status']=='captured':
                p=run/cap['path'];record.update(candidate=cap['path'],candidate_sha256=sha(p),status='awaiting_conversation_review')
            else:record.update(status='candidate_zero_fallback',reason=cap.get('reason','candidate state unavailable'))
            items.append(record)
    write(run/'d6/requests.json',{'protocol_sha256':sha(EV/'d6/reference-manifest.json'),'items':items})
    return items
def finalize(run):
    run=Path(run)
    if (run/'run-invalid.json').exists():raise ValueError('Infrastructure-invalid run cannot publish scores')
    binding=load(run/'run-binding.json')
    if binding.get('authoring_subset'):raise ValueError('An authoring subset cannot publish a score')
    if binding.get('catalog_sha256')!=sha(EV/'checkpoint-catalog.json') or binding.get('d6_protocol_sha256')!=sha(EV/'d6/reference-manifest.json'):raise ValueError('Scoring contract changed after collection')
    cat=load(EV/'checkpoint-catalog.json');checks=load(run/'checks.json');by={x['id']:x for x in checks}
    if len(by)!=len(checks):raise ValueError('Duplicate check IDs')
    if set(by)!={r['id'] for r in cat['checkpoints']}:raise ValueError('Incomplete or foreign functional checkpoints')
    values={};counts={}
    for dim in ('D1','D2','D3','D4','D5'):
        rows=[r for r in cat['checkpoints'] if r['dimension']==dim]
        if any(by[r['id']]['status'] not in ('pass','fail','unreachable') for r in rows):raise ValueError('Unscored verdict')
        for r in rows:
            if by[r['id']]['status']!='pass' and (not by[r['id']].get('reason') or not by[r['id']].get('evidence')):raise ValueError('Candidate failure requires reason and evidence')
        passed=sum(by[r['id']]['status']=='pass' for r in rows);counts[dim]={'passed':passed,'total':len(rows)};values[dim]=round(cat['weights'][dim]*passed/len(rows),1)
    request=load(run/'d6/requests.json');model=load(run/'d6/model-binding.json')
    if request.get('protocol_sha256')!=binding['d6_protocol_sha256']:raise ValueError('D6 request protocol mismatch')
    if len(request['items'])!=12:raise ValueError('D6 requires exactly twelve state/round records')
    if not all(model.get(k) for k in ('provider','model','version','transport','parameters','capability_evidence')):raise ValueError('Actual conversation model binding required')
    if model['transport']!='direct_conversation':raise ValueError('This task selects direct conversation D6 transport')
    parsed=[];rounds=[]
    for rnd in range(1,4):
        group=[r for r in request['items'] if r['round']==rnd]
        if len(group)!=4 or {x['state'] for x in group}!={s['id'] for s in load(EV/'d6/reference-manifest.json')['states']}:raise ValueError('Incomplete or duplicate D6 state group')
        for item in group:
            if item['status']=='candidate_zero_fallback':row={'round':rnd,'state':item['state'],'total':0,'zero_reason':item['reason'],'method':'candidate_state_zero_rule'}
            else:
                if sha(run/item['candidate'])!=item['candidate_sha256']:raise ValueError('Candidate capture changed')
                path=run/'d6'/item['response'];row={'round':rnd,'state':item['state'],**parse_response(path.read_text(encoding='utf-8')),'raw_response_sha256':sha(path),'method':'direct_conversation'}
            parsed.append(row)
        rounds.append(sum(x['total'] for x in parsed if x['round']==rnd)/len(group))
    values['D6']=round(sum(rounds)/3,1);values['functional_total']=round(sum(values[d] for d in ('D1','D2','D3','D4','D5')),1);values['overall']=round(values['functional_total']+values['D6'],1)
    result={'schema_version':'bonemaze-scores-1.0','status':'diagnostic_complete','formal_score':False,'scores':values,'d6_rounds':[round(x,1) for x in rounds],'counts':counts,'candidate_identity':binding['candidate_identity'],'scorer_sha256':sha(__file__),'model_binding':model,'failed_checks':[r for r in checks if r['status']!='pass'],'d6_results':parsed}
    write(run/'score.json',result);write(run/'d6/parser-and-aggregation.json',{'rounds':rounds,'mean':sum(rounds)/3,'items':parsed});return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('operation',choices=['requests','finalize']);p.add_argument('run',type=Path);a=p.parse_args()
    try:r=requests(a.run) if a.operation=='requests' else finalize(a.run);print(json.dumps(r if a.operation=='finalize' else {'requests':len(r)},ensure_ascii=False,indent=2))
    except (ValueError,KeyError,OSError) as e:print('Evaluation incomplete: '+str(e),file=sys.stderr);sys.exit(3)
