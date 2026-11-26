"""Execute the canonical fixed-prompt, three-round visual comparison independently."""
import argparse
import base64
import json
import os
import re
import urllib.request
import urllib.error
import sys
from pathlib import Path
from runtime import ROOT,load,write,sha,inside,InfrastructureError
from score import validate_raw,verify_evidence
from visual import protocol,configured,digest,candidate_status,request_receipt

LABELS=['Scene completeness and composition','Model detail','Model and spatial plausibility','HUD visual quality','Style and overall polish']

def parse(text):
    if not isinstance(text,str):raise InfrastructureError('VLM_RESPONSE_NOT_TEXT')
    lines=[s.strip() for s in text.strip().splitlines() if s.strip()]
    if len(lines)!=7:raise InfrastructureError('VLM_RESPONSE_LINE_COUNT')
    scores=[]
    for line,label in zip(lines,LABELS):
        match=re.fullmatch(re.escape(label)+r'[::]\s*(0(?:\.0)?|0\.5|1(?:\.0)?|1\.5|2(?:\.0)?)\s*/2',line)
        if not match:raise InfrastructureError('VLM_CRITERION_FORMAT')
        scores.append(float(match[1]))
    total=re.fullmatch(r'Total[::]\s*(\d+(?:\.\d+)?)\s*/10',lines[5])
    reason=re.fullmatch(r'Reason[::]\s*(\S.*)',lines[6])
    if not total or float(total[1])!=sum(scores) or not reason:raise InfrastructureError('VLM_TOTAL_OR_REASON_INVALID')
    if len([s for s in re.split(r'[.!?!?]|\.(?:\s|$)',reason[1]) if s.strip()])>2:raise InfrastructureError('VLM_REASON_TOO_LONG')
    return scores,reason[1]

def image(path,detail='high'):
    return {'type':'image_url','image_url':{'url':'data:image/png;base64,'+base64.b64encode(path.read_bytes()).decode(),'detail':detail}}

def main():
    p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--base-url',default=os.environ.get('NIGHTSKY_VLM_BASE_URL'));p.add_argument('--model',default=os.environ.get('NIGHTSKY_VLM_MODEL'))
    p.add_argument('--model-version',default=os.environ.get('NIGHTSKY_VLM_VERSION'))
    p.add_argument('--provider',default=os.environ.get('NIGHTSKY_VLM_PROVIDER'));p.add_argument('--config',type=Path)
    p.add_argument('--key-env',default='OPENAI_API_KEY');a=p.parse_args()
    config=load(a.config) if a.config else {'base_url':a.base_url,'model':a.model,'model_version':a.model_version,'provider':a.provider,'key_env':a.key_env}
    if a.output.exists():raise InfrastructureError('D6_OUTPUT_EXISTS')
    run(a.raw,config,a.output)

def call_vlm(payload,config):
    key=os.environ.get(config.get('key_env','OPENAI_API_KEY'))
    if not key:raise InfrastructureError('VLM_CREDENTIAL_UNAVAILABLE')
    request=urllib.request.Request(config['base_url'].rstrip('/')+'/chat/completions',data=json.dumps(payload,allow_nan=False).encode(),
        headers={'Content-Type':'application/json','Authorization':'Bearer '+key})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args,**kw):return None
    try:
        with urllib.request.build_opener(NoRedirect).open(request,timeout=config.get('timeout_seconds',180)) as response:return json.load(response)
    except urllib.error.HTTPError as e:raise InfrastructureError('VLM_HTTP_'+str(e.code)) from None
    except (urllib.error.URLError,TimeoutError,OSError):raise InfrastructureError('VLM_TRANSPORT_FAILED') from None

def run(raw_path,config,output,call=call_vlm):
    raw=load(raw_path);validate_raw(raw);root=raw_path.resolve().parent;d6=ROOT/'d6'
    verify_evidence(raw,root)
    manifest_path=d6/'d6-reference-manifest.json';m=protocol()
    prompt_path=d6/'FIXED_VLM_PROMPT.txt'
    if sha(prompt_path)!=m['prompt_sha256']:raise InfrastructureError('D6_FIXED_PROMPT_CHANGED')
    prompt=prompt_path.read_text(encoding='utf-8')
    prepared=[(state,*candidate_status(raw,root,state)) for state in m['states']]
    model_config=configured(config) if any(x[1]=='compared' for x in prepared) else {'execution':'not_required_all_states_candidate_zero'}
    evidence_dir=root/'d6'/output.stem
    if evidence_dir.exists() and any(evidence_dir.iterdir()):raise InfrastructureError('D6_EVIDENCE_OUTPUT_EXISTS')
    binding={'schema_version':'3.0.0','run_id':raw['run_id'],'candidate_identity_sha256':raw['candidate_identity_sha256'],
        'catalog_sha256':raw['catalog_sha256'],'raw_sha256':sha(raw_path),'manifest_sha256':sha(manifest_path),
        'prompt_sha256':sha(prompt_path),'protocol_sha256':sha(d6/'protocol.json'),'status':'completed',
        'model_config':model_config,'model_config_sha256':digest(model_config),'capability_receipt':None,'model_returned':None,'rounds':[]}
    for roundno in (1,2,3):
        states=[]
        for state,status,reason,capture in prepared:
            reference=inside(d6,state['reference'])
            if sha(reference)!=state['sha256']:raise InfrastructureError('D6_REFERENCE_CHANGED')
            entry={'id':state['id'],'status':status,'criteria':[0]*5,'reason':reason,
                'reference_sha256':state['sha256'],'candidate_sha256':capture['sha256'] if capture else None}
            if status=='compared':
                candidate=inside(root,capture['path'])
                if sha(candidate)!=capture['sha256']:raise InfrastructureError('D6_CANDIDATE_IMAGE_CHANGED')
                entry['candidate_sha256']=capture['sha256']
                if capture['visible']:
                    payload={'model':model_config['model'],**model_config['parameters'],'messages':[{'role':'user','content':[{'type':'text','text':prompt.replace('{{CURRENT_STATE_LABEL}}',state['label'])},image(reference,model_config['image_detail']),image(candidate,model_config['image_detail'])]}]}
                    prefix=f'd6/{output.stem}/round-{roundno}-{state["id"]}'
                    # Store request identity and the exact prompt/image hashes, avoiding duplicate base64 image blobs.
                    write(root/(prefix+'-request.json'),request_receipt(state,capture,model_config,roundno))
                    data=call(payload,config)
                    write(root/(prefix+'-response.json'),data)
                    returned=data.get('model')
                    if not returned or binding['model_returned'] not in (None,returned):raise InfrastructureError('VLM_MODEL_CHANGED')
                    binding['model_returned']=returned
                    criteria,reason=parse(data['choices'][0]['message']['content'])
                    write(root/(prefix+'-parser.json'),{'criteria':criteria,'reason':reason})
                    entry.update(status='compared',criteria=criteria,reason=reason)
                    for k in ('request','response','parser'):
                        rel=prefix+'-'+k+'.json';entry[k]={'path':rel,'sha256':sha(root/rel)}
                    if binding['capability_receipt'] is None:
                        binding['capability_receipt']={'model_config_sha256':digest(model_config),'returned_model':returned,
                            'two_images_accepted':True,'request':entry['request'],'response':entry['response']}
            states.append(entry)
        binding['rounds'].append({'number':roundno,'states':states})
    write(output,binding);return binding

if __name__=='__main__':
    try:main()
    except (InfrastructureError,KeyError,ValueError,TypeError,OSError) as e:
        code=str(e) if isinstance(e,InfrastructureError) else 'VLM_RESPONSE_PROTOCOL_INVALID'
        if '--output' in sys.argv:
            output=Path(sys.argv[sys.argv.index('--output')+1])
            if not output.exists():write(output,{'schema_version':'3.0.0','status':'invalid',
                'fault':{'domain':'infrastructure','code':code},'score_publication_allowed':False})
        print(code,file=sys.stderr)
        raise SystemExit(2)
