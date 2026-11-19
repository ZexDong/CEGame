"""Execute the canonical fixed-prompt, three-round visual comparison independently."""
import argparse
import base64
import json
import os
import re
import urllib.request
import urllib.error
import sys
import time
from pathlib import Path
from runtime import ROOT,load,write,sha,inside,InfrastructureError
from score import valid_raw

LABELS=['Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish']

def parse(text):
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
    return scores,reason[1]

def image(path):
    return {'type':'image_url','image_url':{'url':'data:image/png;base64,'+base64.b64encode(path.read_bytes()).decode(),'detail':'high'}}

def reached(capture,state,root):
    if not capture or capture.get('state_reached') is False:return False
    context=load(inside(root,capture['context']))
    if not isinstance(context,dict):return False
    for sample in (context.get('before'),context.get('after')):
        if not isinstance(sample,dict) or sample.get('provider_ready') is not True:continue
        g=sample.get('game_state');
        if not isinstance(g,dict):continue
        p=g.get('player')
        if not isinstance(p,dict):p={}
        if g.get('phase')!='active':continue
        if state['id']=='initial':return True
        if state['id']=='sword' and p.get('attacking') is True:return True
        if state['id']=='airborne' and p.get('grounded') is False:return True
    return False

def select_capture(raw,state,root):
    """Use the first semantic match, never select by visual quality or VLM score.

    Sword variation frames are already collected by the same normal-input
    journey. A missed first frame must not hide valid evidence from that journey.
    Keep the primary name as the attributable missing/black fallback.
    """
    primary=state['candidate_capture'];captures=raw['captures']
    names=[primary]
    if state['id']=='sword':
        names+=sorted(n for n in captures if re.fullmatch(r'sword-variation-\d+',n))
    for name in names:
        capture=captures.get(name)
        if capture and capture['visible'] and reached(capture,state,root):return name,capture
    return primary,captures.get(primary)

def main():
    p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--resume',type=Path,help='Reuse unchanged compared pairs from a prior result; scorer revalidates every receipt.')
    p.add_argument('--base-url',default=os.environ.get('CAPTAIN_VLM_BASE_URL'));p.add_argument('--model',default=os.environ.get('CAPTAIN_VLM_MODEL'))
    p.add_argument('--key-env',default='NEWAPI_API_KEY');a=p.parse_args()
    raw=load(a.raw);valid_raw(raw);root=a.raw.resolve().parent;d6=ROOT/'d6'
    manifest_path=d6/'reference-manifest.json';m=load(manifest_path)
    # Model selection is caller-configured for this evaluation revision.  The
    # fixed contract binds the prompt, references, states and parser, but does
    # not require a particular provider model identity.
    if a.model is None:a.model=m['model_requested']
    prompt_path=d6/'FIXED_VLM_PROMPT.txt'
    if sha(prompt_path)!=m['prompt_sha256']:raise InfrastructureError('D6_FIXED_PROMPT_CHANGED')
    prompt=prompt_path.read_text(encoding='utf-8')
    binding={'schema_version':'2.0.0','run_id':raw['run_id'],'candidate_identity_sha256':raw['candidate_identity_sha256'],
        'catalog_sha256':raw['catalog_sha256'],'raw_sha256':sha(a.raw),'manifest_sha256':sha(manifest_path),
        'prompt_sha256':sha(prompt_path),'status':'completed','model_requested':a.model,'model_returned':None,'rounds':[]}
    previous=load(a.resume) if a.resume else None
    if previous:
        for key in ('raw_sha256','manifest_sha256','prompt_sha256','model_requested'):
            if previous.get(key)!=binding[key]:raise InfrastructureError('D6_RESUME_BINDING_MISMATCH')
        if previous.get('status')!='completed':raise InfrastructureError('D6_RESUME_INCOMPLETE')
        binding['resumed_from_sha256']=sha(a.resume)
        binding['model_returned']=previous.get('model_returned')
    for roundno in (1,2,3):
        states=[]
        for state in m['states']:
            reference=inside(d6,state['reference'])
            if sha(reference)!=state['sha256']:raise InfrastructureError('D6_REFERENCE_CHANGED')
            capture_name,capture=select_capture(raw,state,root)
            if previous and capture and capture['visible'] and reached(capture,state,root):
                old=next((s for r in previous['rounds'] if r['number']==roundno for s in r['states'] if s['id']==state['id']),None)
                if old and old['status']=='compared' and old['candidate_sha256']==capture['sha256']:
                    entry=dict(old,candidate_capture=capture_name)
                    states.append(entry)
                    print(f'D6 round {roundno}: {state["id"]} (unchanged evidence reused)',flush=True)
                    continue
            entry={'id':state['id'],'status':'candidate_missing','criteria':[0]*5,'reason':'Candidate did not reach this state.',
                'reference_sha256':state['sha256'],'candidate_sha256':None,'candidate_capture':capture_name}
            if capture and (not capture['visible'] or reached(capture,state,root)):
                candidate=inside(root,capture['path'])
                if sha(candidate)!=capture['sha256']:raise InfrastructureError('D6_CANDIDATE_IMAGE_CHANGED')
                entry['candidate_sha256']=capture['sha256']
                if not capture['visible']:entry.update(status='candidate_black',reason='Candidate produced a black frame.')
                else:
                    if not a.base_url or not a.model or not os.environ.get(a.key_env):raise InfrastructureError('VLM_CONFIGURATION_REQUIRED')
                    payload={'model':a.model,'stream':False,'messages':[{'role':'user','content':[{'type':'text','text':prompt.replace('{{CURRENT_STATE_LABEL}}',state['label'])},image(reference),image(candidate)]}]}
                    prefix=f'd6/round-{roundno}-{state["id"]}'
                    # Store request identity and the exact prompt/image hashes, avoiding duplicate base64 image blobs.
                    request_receipt={'model':a.model,'prompt':payload['messages'][0]['content'][0]['text'],'image_order':['reference','candidate'],
                        'reference_sha256':sha(reference),'candidate_sha256':sha(candidate)}
                    write(root/(prefix+'-request.json'),request_receipt)
                    print(f'D6 round {roundno}: {state["id"]}',flush=True)
                    request=urllib.request.Request(a.base_url.rstrip('/')+'/chat/completions',data=json.dumps(payload).encode(),
                        headers={'Content-Type':'application/json','Authorization':'Bearer '+os.environ[a.key_env]})
                    data=None
                    for attempt in range(3):
                        try:
                            with urllib.request.urlopen(request,timeout=180) as response:data=json.load(response)
                            break
                        except urllib.error.HTTPError as e:
                            if e.code in (500,502,503,504) and attempt < 2:
                                time.sleep(2 * (attempt + 1))
                                continue
                            raise InfrastructureError('VLM_HTTP_'+str(e.code)) from None
                        except (urllib.error.URLError,TimeoutError,OSError):
                            if attempt < 2:
                                time.sleep(2 * (attempt + 1))
                                continue
                            raise InfrastructureError('VLM_TRANSPORT_FAILED') from None
                    write(root/(prefix+'-response.json'),data)
                    returned=data.get('model')
                    if not returned or binding['model_returned'] not in (None,returned):raise InfrastructureError('VLM_MODEL_CHANGED')
                    binding['model_returned']=returned
                    criteria,reason=parse(data['choices'][0]['message']['content'])
                    write(root/(prefix+'-parser.json'),{'criteria':criteria,'reason':reason})
                    entry.update(status='compared',criteria=criteria,reason=reason)
                    for k in ('request','response','parser'):
                        rel=prefix+'-'+k+'.json';entry[k]={'path':rel,'sha256':sha(root/rel)}
            states.append(entry)
        binding['rounds'].append({'number':roundno,'states':states})
    write(a.output,binding);print(a.output)

if __name__=='__main__':
    try:main()
    except (InfrastructureError,KeyError,ValueError,TypeError,OSError) as e:
        code=str(e) if isinstance(e,InfrastructureError) else 'VLM_RESPONSE_PROTOCOL_INVALID'
        if '--output' in sys.argv:
            write(Path(sys.argv[sys.argv.index('--output')+1]),{'schema_version':'2.0.0','status':'invalid',
                'fault':{'domain':'infrastructure','code':code},'score_publication_allowed':False})
        print(code,file=sys.stderr)
        raise SystemExit(2)

