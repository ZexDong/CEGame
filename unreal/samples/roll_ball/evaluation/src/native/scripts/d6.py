"""Run the fixed three-state visual comparison protocol.

Only the bound reference images and candidate captures are sent to the service.
Missing/black candidate states receive an explicit zero without an API call.
"""
import argparse,base64,io,os,re,urllib.request,urllib.error
from PIL import Image
from pathlib import Path
from evidence import InvalidEvidence,check_collection,read,write,sha,verified,image_info
ROOT=Path(__file__).resolve().parents[1]

def _prompt_parts():
    prompt=(ROOT/'d6/FIXED_PROMPT.txt').read_text(encoding='utf-8').strip()
    labels=[]; total=None; reason=None
    for line in prompt.splitlines():
        if '>/2' in line:
            labels.append(line.split(':',1)[0])
        if '>/10' in line: total=line.split(':',1)[0]
        if line.startswith('Reason:'): reason='Reason'
    if len(labels)!=5 or not total or not reason: raise InvalidEvidence('D6_PROMPT_FORMAT')
    return prompt,labels,total,reason

def parse_response(text):
    _,labels,total_label,reason_label=_prompt_parts(); lines=text.strip().splitlines()
    if len(lines)!=7: raise InvalidEvidence('VLM_RESPONSE_LINE_COUNT')
    values=[]
    allowed=r'(0(?:\.0)?|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)'
    for label,line in zip(labels,lines[:5]):
        m=re.fullmatch(re.escape(label)+r':'+allowed+r'/2',line.strip())
        if not m: raise InvalidEvidence('VLM_RESPONSE_CRITERION')
        values.append(float(m.group(1)))
    m=re.fullmatch(re.escape(total_label)+r':'+r'(\d+(?:\.\d+)?)/10',lines[5].strip())
    if not m or abs(float(m.group(1))-sum(values))>1e-9: raise InvalidEvidence('VLM_RESPONSE_TOTAL')
    if not re.fullmatch(re.escape(reason_label)+r':\S.+',lines[6].strip()): raise InvalidEvidence('VLM_RESPONSE_REASON')
    return values

def image_uri(path):
    with Image.open(path) as image:
        image=image.convert('RGB')
        if image.size!=(1920,1080):
            if abs(image.width/image.height-16/9)>.03: raise InvalidEvidence('CAPTURE_ASPECT_RATIO')
            image=image.resize((1920,1080),Image.Resampling.LANCZOS)
        out=io.BytesIO(); image.save(out,format='PNG')
    return 'data:image/png;base64,'+base64.b64encode(out.getvalue()).decode('ascii')

def payload(model,state,reference,candidate):
    prompt=(ROOT/'d6/FIXED_PROMPT.txt').read_text(encoding='utf-8').replace('{{CURRENT_STATE_LABEL}}',state)
    return dict(model=model,messages=[dict(role='user',content=[dict(type='text',text=prompt),dict(type='image_url',image_url={'url':image_uri(reference)}),dict(type='image_url',image_url={'url':image_uri(candidate)})])])

def _candidate(collection,run_root,name):
    aliases={'navigation':('direction-W','released'),'reopen':('reopen','fresh-process'),'initial':('entry','initial')}
    for case in collection['cases']:
        for cap in case.get('captures',[]):
            stem=Path(cap.get('path','')).stem
            alias=aliases.get(name)
            if stem==name or (name=='initial' and case['id']=='entry' and stem=='initial') or (alias and case['id']==alias[0] and stem==alias[1]):
                p=run_root/case['id']/cap['path']
                if p.is_file() and not image_info(p)[1]: return case['id'],cap,p
    return None

def execute(collection_path,base_url,model,output):
    collection_path=Path(collection_path).resolve(); collection,catalog=check_collection(collection_path); run_root=collection_path.parent
    refs=read(ROOT/'d6/references.json'); protocol=read(ROOT/'d6/protocol.json'); states=refs['states']; binding=read(ROOT/'d6/model-binding.json')
    if protocol.get('version')!='4.0.0' or protocol.get('rounds')!=3 or protocol.get('states')!=[s['id'] for s in states] or protocol.get('prompt_sha256')!=sha(ROOT/'d6/FIXED_PROMPT.txt'):
        raise InvalidEvidence('D6_PROTOCOL_BINDING')
    if model!=binding['model']: raise InvalidEvidence('VLM_MODEL_BINDING')
    if Path(output).exists(): raise InvalidEvidence('D6_OUTPUT_EXISTS')
    folder=run_root/'d6';
    if folder.exists(): raise InvalidEvidence('D6_RUN_DIRECTORY_EXISTS')
    folder.mkdir(); rounds=[]; returned_model=None
    usable={s['id']:_candidate(collection,run_root,s['id']) for s in states}
    for n in range(1,4):
        rows=[]
        for state in states:
            name=state['id']; ref=verified(ROOT/'d6',state['reference'],state['sha256']); match=usable.get(name)
            if not match:
                rows.append(dict(state=name,source='candidate_zero',reason='CANDIDATE_STATE_MISSING_OR_BLACK',criteria=[0]*5)); continue
            api_key = (os.environ.get('D6_API_KEY') or
                       os.environ.get('OPENAI_API_KEY'))
            if not base_url or not api_key: raise InvalidEvidence('VLM_CONFIGURATION_REQUIRED')
            request_data=payload(model,state['label'],ref,match[2])
            request_path=folder/f'{n}-{name}-request.json';response_path=folder/f'{n}-{name}-response.json'; write(request_path,request_data)
            req=urllib.request.Request(base_url.rstrip('/')+'/chat/completions',data=__import__('json').dumps(request_data).encode(),headers={'Authorization':'Bearer '+api_key,'Content-Type':'application/json'})
            try:
                with urllib.request.urlopen(req,timeout=90) as response: body=response.read()
            except urllib.error.HTTPError as exc: raise InvalidEvidence('VLM_HTTP_'+str(exc.code)) from None
            except Exception as exc: raise InvalidEvidence('VLM_TRANSPORT_'+type(exc).__name__) from None
            response_path.write_bytes(body); response=read(response_path)
            if response.get('model') != binding['model']: raise InvalidEvidence('VLM_MODEL_DRIFT')
            returned_model=response['model']; criteria=parse_response(response['choices'][0]['message']['content'])
            rows.append(dict(state=name,source='vlm',criteria=criteria,request=dict(path=request_path.relative_to(run_root).as_posix(),sha256=sha(request_path)),response=dict(path=response_path.relative_to(run_root).as_posix(),sha256=sha(response_path))))
            print(f'D6 round {n}, {name}: parsed',flush=True)
        rounds.append(dict(round=n,states=rows))
    write(output,dict(version='4.0.0',status='completed',collection_sha256=sha(collection_path),references_sha256=sha(ROOT/'d6/references.json'),prompt_sha256=sha(ROOT/'d6/FIXED_PROMPT.txt'),model=model,returned_model=returned_model,rounds=rounds))

def main():
    p=argparse.ArgumentParser();p.add_argument('--collection',required=True);p.add_argument('--base-url',default=os.getenv('ROLLBALL_VLM_BASE_URL'));p.add_argument('--model',default=os.getenv('ROLLBALL_VLM_MODEL','gpt-5.6-sol'));p.add_argument('--output',required=True);a=p.parse_args()
    try: execute(a.collection,a.base_url,a.model,a.output); return 0
    except Exception as exc:
        if not Path(a.output).exists(): write(a.output,dict(version='4.0.0',status='evaluation_incomplete',fault=type(exc).__name__+':'+str(exc)))
        print(type(exc).__name__+': '+str(exc)); return 2
if __name__=='__main__': raise SystemExit(main())
