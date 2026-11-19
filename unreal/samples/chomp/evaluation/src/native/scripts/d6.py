"""Fixed three-round, evidence-bound image-pair review."""
from common import *
import re,argparse

LABELS=['Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish']

def image_fault(path):
    from PIL import Image,ImageStat
    try:
        with Image.open(path) as source:im=source.convert('RGB')
    except (OSError,ValueError) as e:raise InfrastructureError('D6_CAPTURE_FILE_CORRUPT') from e
    if im.width<320 or im.height<180:return 'D6_CANDIDATE_FRAME_UNUSABLE'
    if abs(im.width/im.height-16/9)>.05:return 'D6_CANDIDATE_VIEWPORT_MISMATCH'
    stat=ImageStat.Stat(im)
    if max(stat.stddev)<1:return 'D6_CANDIDATE_BLACK_OR_EMPTY_FRAME'
    return None
def prepare(root):
    root=Path(root);raw=load(root/'raw-evaluation.json');reference=load(TASK/'evaluator/d6/reference-manifest.json');prompt=(TASK/'evaluator/d6/FIXED_PROMPT.txt').read_text(encoding='utf-8')
    model={'provider':None,'model_identity':None,'reviewer':None,'parameters':{'transport':'interactive image-pair review','rounds':3,'separate_state_reviews':True}}
    if (root/'d6/model-binding.json').is_file():model=load(root/'d6/model-binding.json')
    write(root/'d6/model-binding.json',model)
    for round in range(1,4):
        for state in reference['states']:
            candidate=raw['d6_captures'].get(state['id'],{'missing':True,'reason':'CANDIDATE_STATE_UNREACHABLE'})
            if candidate.get('path') and not candidate.get('missing'):
                fault=image_fault(root/candidate['path'])
                if fault:candidate={**candidate,'missing':True,'reason':fault}
            bound=prompt.replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',state['condition'])
            request={'round':round,'state':state['id'],'state_label':state['condition'],'prompt':bound,'prompt_sha256':reference['prompt_sha256'],'reference':{'path':str((TASK/'evaluator/d6'/state['path']).resolve()),'sha256':state['sha256']},'candidate':candidate,'model_binding':'model-binding.json','response_format':'canonical seven-line text','interactive_image_review':True}
            if 'path' in candidate:request['candidate']={**candidate,'path':str((root/candidate['path']).resolve())}
            write(root/f'd6/requests/round-{round}-{state["id"]}.json',request)
            if candidate.get('missing'):
                response='\n'.join(f'{label}:0.0/2' for label in LABELS)+'\nTotal:0.0/10\nReason:The candidate produced no image for this semantic state;'+candidate['reason']+'.\n'
                path=root/f'd6/responses/round-{round}-{state["id"]}.txt';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(response,encoding='utf-8')
                write(path.with_suffix('.receipt.json'),{'mode':'candidate_missing_image_zero','reason':candidate['reason'],'no_vlm_inference':True})
    write(root/'d6/README.json',{'status':'dialogue_review_required','instruction':'Read the fixed prompt and view Reference then Candidate for each state in each of three rounds. Save actual raw responses in responses/. Missing candidate states already receive zero. Never invent completed calls. Run score.py after all responses are present.'})
def parse(text):
    lines=[x.strip() for x in text.strip().splitlines() if x.strip()]
    if len(lines)!=7:raise InfrastructureError('D6_RESPONSE_LINE_COUNT')
    values=[]
    for i,label in enumerate(LABELS):
        m=re.fullmatch(re.escape(label)+r'\s*[::]\s*([0-2](?:\.\d+)?)\s*/\s*2',lines[i])
        if not m:raise InfrastructureError('D6_RESPONSE_COMPONENT:'+label)
        v=float(m.group(1))
        if v not in [0,.5,1,1.5,2]:raise InfrastructureError('D6_SCORE_STEP')
        values.append(v)
    m=re.fullmatch(r'Total\s*[::]\s*(\d+(?:\.\d+)?)\s*/\s*10',lines[5])
    if not m or abs(float(m.group(1))-sum(values))>1e-8:raise InfrastructureError('D6_RESPONSE_SUM')
    if not re.match(r'Reason\s*[::].+',lines[6]):raise InfrastructureError('D6_REASON_MISSING')
    return {'components':values,'total':sum(values),'reason':lines[6]}
def aggregate(root):
    root=Path(root)
    model=load(root/'d6/model-binding.json')
    if not (model.get('reviewer') or model.get('model_identity')):raise InfrastructureError('D6_REVIEWER_IDENTITY_REQUIRED')
    reference=load(TASK/'evaluator/d6/reference-manifest.json');rounds=[];records=[]
    for round in range(1,4):
        values=[]
        for state in reference['states']:
            req=load(root/f'd6/requests/round-{round}-{state["id"]}.json');path=root/f'd6/responses/round-{round}-{state["id"]}.txt'
            if not path.exists():raise InfrastructureError('D6_DIALOGUE_RESPONSE_PENDING:'+path.name)
            receipt_path=path.with_suffix('.receipt.json')
            if not receipt_path.exists():raise InfrastructureError('D6_RESPONSE_PROVENANCE_MISSING')
            receipt=load(receipt_path)
            if req['candidate'].get('missing'):
                if receipt.get('mode')!='candidate_missing_image_zero':raise InfrastructureError('D6_MISSING_IMAGE_RECEIPT')
            elif receipt.get('mode')!='direct_conversation_image_review' or receipt.get('request_sha256')!=sha(root/f'd6/requests/round-{round}-{state["id"]}.json') or receipt.get('response_sha256')!=sha(path):raise InfrastructureError('D6_DIALOGUE_RECEIPT_INVALID')
            if sha(root/req['reference']['path'])!=req['reference']['sha256']:raise InfrastructureError('D6_REFERENCE_CHANGED')
            if req['candidate'].get('path') and sha(root/req['candidate']['path'])!=req['candidate']['sha256']:raise InfrastructureError('D6_CANDIDATE_IMAGE_CHANGED')
            result=parse(path.read_text(encoding='utf-8'))
            if req['candidate'].get('missing') and result['total']!=0:raise InfrastructureError('D6_MISSING_CANDIDATE_MUST_SCORE_ZERO')
            expected=(TASK/'evaluator/d6/FIXED_PROMPT.txt').read_text(encoding='utf-8').replace('<short state label: menu, initial gameplay, mid/late game, management, success, or failure>',state['condition'])
            if req['prompt']!=expected or req['prompt_sha256']!=reference['prompt_sha256']:raise InfrastructureError('D6_FIXED_PROMPT_CHANGED')
            values.append(result['total']);records.append({'round':round,'state':state['id'],**result,'request_sha256':sha(root/f'd6/requests/round-{round}-{state["id"]}.json'),'response_sha256':sha(path)})
        rounds.append(sum(values)/len(values))
    result={'protocol':'canonical-three-round-equal-state','raw_rounds':rounds,'rounds':[round_decimal(v) for v in rounds],'score':round_decimal(sum(rounds)/3),'records':records,'model':load(root/'d6/model-binding.json')}
    write(root/'d6-result.json',result);return result
def round_decimal(n):
    from decimal import Decimal,ROUND_HALF_UP
    return float(Decimal(str(n)).quantize(Decimal('.1'),rounding=ROUND_HALF_UP))
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('operation',choices=['prepare','aggregate']);ap.add_argument('run');a=ap.parse_args();print(json.dumps(prepare(a.run) if a.operation=='prepare' else aggregate(a.run),ensure_ascii=False))
