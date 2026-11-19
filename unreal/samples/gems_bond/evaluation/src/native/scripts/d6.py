"""Prepare fixed dialogue requests, strictly parse answers, aggregate three rounds."""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
from support import load,write,sha,TASK,InfrastructureError,inspect_image
LABELS=['Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish']
def parse(text):
    scores=[]
    for label in LABELS:
        matches=re.findall(r'^'+re.escape(label)+r':\s*([0-2](?:\.\d+)?)\s*/2\s*$',text,re.M)
        if len(matches)!=1:raise ValueError('D6_LABEL_MISSING_OR_DUPLICATED:'+label)
        v=float(matches[0])
        if v not in [0,.5,1,1.5,2]:raise ValueError('D6_INVALID_COMPONENT')
        scores.append(v)
    total=re.findall(r'^Total:\s*([0-9]+(?:\.\d+)?)\s*/10\s*$',text,re.M)
    reason=re.findall(r'^Reason:\s*(.+)$',text,re.M)
    if len(total)!=1 or float(total[0])!=sum(scores) or len(reason)!=1 or not reason[0].strip():raise ValueError('D6_TOTAL_OR_REASON_INVALID')
    if len([x for x in text.strip().splitlines() if x.strip()])!=7:raise ValueError('D6_UNEXPECTED_LINES')
    return {'components':dict(zip(LABELS,scores)),'total':sum(scores),'reason':reason[0]}
def prepare(run):
    protocol=load(TASK/'evaluator/d6/protocol.json');collection=load(run/'collection.json')
    if sha(TASK/'evaluator/d6/prompt.txt')!=protocol['prompt_sha256']:raise InfrastructureError('D6_PROMPT_HASH')
    root=run/'d6';root.mkdir(exist_ok=True);pairs=[]
    for state in protocol['states']:
        ref=TASK/'evaluator/d6'/state['reference']
        if sha(ref)!=state['sha256']:raise InfrastructureError('D6_REFERENCE_HASH')
        item=collection.get('d6',{}).get(state['id'])
        if item is None:
            if collection['status']=='candidate_failed':item={'status':'candidate_missing','reason':'CANDIDATE_STARTUP_OR_BUILD_FAILURE'}
            else:raise InfrastructureError('D6_CAPTURE_NOT_COLLECTED:'+state['id'])
        pair={'state':state['id'],'label':state['label'],'reference':str(ref.relative_to(TASK)),'reference_sha256':state['sha256'],'candidate_status':item['status']}
        if item['status']=='captured':
            session=item.get('session','normal');candidate=(run/session/item['path']).resolve()
            if not candidate.is_relative_to(run.resolve()):raise InfrastructureError('D6_CAPTURE_PATH_ESCAPE')
            if not candidate.is_file() or sha(candidate)!=item['sha256']:raise InfrastructureError('D6_CAPTURE_ARTIFACT_LOST')
            health=inspect_image(candidate);pair.update(candidate=session+'/'+item['path'],candidate_sha256=sha(candidate),image_health=health)
            if health['black']:pair.update(candidate_status='candidate_black',zero_reason='D6_CANDIDATE_BLACK_SCREEN')
            elif [health['width'],health['height']]!=[1920,1080]:pair.update(candidate_status='candidate_broken',zero_reason='D6_CANDIDATE_VIEWPORT_WRONG')
        elif item['status'] in ['candidate_missing','candidate_black','candidate_broken']:
            pair['zero_reason']=item['reason']
        else:raise InfrastructureError('D6_UNKNOWN_CAPTURE_STATUS:'+str(item['status']))
        pairs.append(pair)
        prompt=(TASK/'evaluator/d6/prompt.txt').read_text(encoding='utf-8').replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',state['label'])
        for r in range(1,4):
            write(root/f'request-{r}-{state["id"]}.json',{'round':r,'pair':pair,'image_order':['reference','candidate'],'prompt':prompt,'prompt_template_sha256':protocol['prompt_sha256'],'backend':'direct_conversation'})
    write(root/'pairs.json',{'protocol_sha256':sha(TASK/'evaluator/d6/protocol.json'),'pairs':pairs,'rounds':3})
    write(root/'model-binding.template.json',{'backend':'direct_conversation','model_identity':'RECORD_ACTUAL_MODEL',
        'model_version':'Record the exposed version or explicitly state it is not exposed.',
        'parameters':{'temperature':'Record actual value or not exposed'},
        'same_model_all_rounds':False,'prompt_template_sha256':protocol['prompt_sha256'],
        'rated_pairs':{p['state']:{'reference_sha256':p['reference_sha256'],'candidate_sha256':p.get('candidate_sha256'),'candidate_status':p['candidate_status']} for p in pairs}})
    return pairs
def aggregate(run,binding=None):
    packet=load(run/'d6/pairs.json');pairs=packet['pairs'];rows=[]
    if packet.get('protocol_sha256')!=sha(TASK/'evaluator/d6/protocol.json'):raise InfrastructureError('D6_PAIR_PROTOCOL_CHANGED')
    protocol=load(TASK/'evaluator/d6/protocol.json')
    if [p['state'] for p in pairs]!=[s['id'] for s in protocol['states']]:raise InfrastructureError('D6_STATE_SET_INVALID')
    for r in range(1,4):
        states=[]
        for pair in pairs:
            raw=run/'d6'/f'response-{r}-{pair["state"]}.txt'
            if pair['candidate_status']=='captured':
                if not raw.is_file():raise InfrastructureError('D6_DIALOGUE_RESPONSE_REQUIRED:'+raw.name)
                try:parsed=parse(raw.read_text(encoding='utf-8'))
                except ValueError as e:raise InfrastructureError('D6_RESPONSE_INVALID:'+raw.name+':'+str(e)) from e
                parsed['raw_sha256']=sha(raw)
            else:parsed={'components':dict.fromkeys(LABELS,0.0),'total':0.0,'reason':pair['zero_reason'],'automatic_candidate_zero':True}
            states.append({'state':pair['state'],**parsed})
        rows.append({'round':r,'states':states,'mean':sum(s['total']for s in states)/len(states)})
    if any(p['candidate_status']=='captured' for p in pairs):
        if binding is None:
            try:binding=load(run/'d6/model-binding.json')
            except (OSError,ValueError) as e:raise InfrastructureError('D6_MODEL_BINDING_REQUIRED') from e
        if not isinstance(binding,dict) or binding.get('backend')!='direct_conversation' or not binding.get('model_identity') or binding.get('model_identity')=='RECORD_ACTUAL_MODEL' or binding.get('same_model_all_rounds') is not True:raise InfrastructureError('D6_MODEL_BINDING_REQUIRED')
        expected={p['state']:{'reference_sha256':p['reference_sha256'],'candidate_sha256':p.get('candidate_sha256'),'candidate_status':p['candidate_status']} for p in pairs}
        if binding.get('rated_pairs')!=expected or binding.get('prompt_template_sha256')!=protocol['prompt_sha256']:raise InfrastructureError('D6_RATED_IMAGES_OR_PROMPT_CHANGED')
    result={'protocol_sha256':sha(TASK/'evaluator/d6/protocol.json'),'binding':binding,'rounds':rows,'score':round(sum(r['mean'] for r in rows)/3,1),'status':'complete'}
    write(run/'d6/result.json',result);return result
if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('command',choices=['prepare','aggregate']);a.add_argument('--run',type=Path,required=True);args=a.parse_args()
    print(json.dumps(prepare(args.run) if args.command=='prepare' else aggregate(args.run),ensure_ascii=False,indent=2))
