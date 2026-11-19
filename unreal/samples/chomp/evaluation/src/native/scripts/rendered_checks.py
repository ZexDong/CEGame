"""Deterministic dynamic frame checks. No reference images and no VLM.

Public semantic regions, color roles, native renderer receipts, and Windows OCR
corroborate the normal-input checks. Art derivations are bound per adapter.
"""
from common import *
from PIL import Image,ImageStat,ImageOps
import numpy as np,subprocess,re,argparse

def evaluate(root):
    root=Path(root).resolve();raw=load(root/'raw-evaluation.json');caps=root/'session/captures'
    catalog=load(TASK/'evaluator/catalog/checkpoints.json')['checks'];out={'candidate_identity':raw['candidate']['sha256'],'method':'deterministic pixels + Windows.Media.Ocr + actual renderer receipts; no VLM','checks':{}}
    def pixels(label):
        return np.asarray(Image.open(caps/(label+'.png')).convert('RGB')).astype(float)
    def color(label,role,rect=None):
        a=pixels(label)
        if rect:
            h,w=a.shape[:2];x,y,rw,rh=[rect[k] for k in ['x','y','width','height']];a=a[max(0,int(y*h)):min(h,int((y+rh)*h)+1),max(0,int(x*w)):min(w,int((x+rw)*w)+1)]
        if not a.size:return 0
        r,g,b=[a[:,:,i] for i in range(3)]
        masks={'yellow':(r>100)&(g>90)&(b<.75*np.minimum(r,g)), 'blue':(b>65)&(b>1.3*r)&(b>1.15*g),'white':(np.minimum(np.minimum(r,g),b)>125)&(np.maximum(np.maximum(r,g),b)-np.minimum(np.minimum(r,g),b)<45),'cyan':(g>100)&(b>100)&(r<.8*np.minimum(g,b)),'red':(r>100)&(r>1.6*g)&(r>1.5*b),'pink':(r>110)&(b>90)&(g<.8*np.minimum(r,b)),'orange':(r>130)&(g>65)&(g<.85*r)&(b<.55*g),'green':(g>70)&(g>1.2*r)&(g>1.3*b)}
        return int(masks[role].sum())
    def state(label):return load(caps/(label+'.json'))['before']['game_state']
    def ocr(label,crop=None,tag_suffix='hud',threshold=True):
        tag=label+('-'+tag_suffix if crop else '');cache=root/f'frame-analysis/{tag}-ocr.json'
        if cache.exists():return load(cache)['text']
        path=caps/(label+'.png')
        if crop:
            im=Image.open(path).convert('RGB');w,h=im.size;im=im.crop(tuple(int(v*n) for v,n in zip(crop,[w,h,w,h])))
            if threshold:
                a=np.asarray(im);lo=a.min(axis=2);hi=a.max(axis=2);mask=(lo>100)&((hi.astype(float)-lo)<55);im=Image.fromarray(np.where(mask,0,255).astype('uint8'))
            else:im=ImageOps.invert(ImageOps.autocontrast(im.convert('L')))
            im=im.resize((im.width*3,im.height*3))
            path=root/f'frame-analysis/{tag}.png';path.parent.mkdir(parents=True,exist_ok=True);im.save(path)
        r=subprocess.run(['powershell.exe','-NoProfile','-File',str(REPO/'engine/semantic-jsonl-player/1.0/Read-RenderedText.ps1'),'-ImagePath',str(path)],capture_output=True,text=True,encoding='utf-8',timeout=20)
        if r.returncode:raise InfrastructureError('WINDOWS_OCR_CAPABILITY_FAILED:'+r.stderr[-300:])
        receipt=json.loads(r.stdout);text=' '.join(line['text'] for line in receipt['lines']);write(cache,{'image':path.relative_to(root).as_posix(),'text':text,'receipt':receipt});return text
    def text_has(label,words):
        normalize=lambda s:re.sub(r'[^A-Z0-9]','',s.upper()).replace('I','L')
        def close(a,b):
            a,b=normalize(a),normalize(b);row=list(range(len(b)+1))
            for i,x in enumerate(a):
                nxt=[i+1]
                for j,y in enumerate(b):nxt.append(min(nxt[-1]+1,row[j+1]+1,row[j]+(x!=y)))
                row=nxt
            return bool(b) and row[-1]<=min(2,len(a)//3)
        text=ocr(label);missing=[w for w in words if normalize(w) not in normalize(text)]
        matched=[]
        if missing:
            for target in state(label).get('targets',[]):
                if any(normalize(w)==normalize(target['label']) for w in missing):
                    r=target['rect'];crop=(r['x'],r['y'],r['x']+r['width'],r['y']+r['height'])
                    optical=ocr(label,crop,'target-'+target['id'],False);text+=' '+optical
                    matched.extend(w for w in missing if close(w,optical))
        return all(normalize(w) in normalize(text) or w in matched for w in words)
    def add(id,labels,ok,reason):
        if raw['checkpoints'].get(id,{}).get('verdict')!='pass':return
        out['checks'][id]={'verdict':'pass' if ok else 'fail','reason':reason,'captures':[{'path':(caps/(x+'.png')).relative_to(root).as_posix(),'sha256':sha(caps/(x+'.png'))} for x in labels]}
    def present(label):return max(ImageStat.Stat(Image.open(caps/(label+'.png')).convert('RGB')).stddev)>3
    if raw.get('candidate_failure') or not any(c['verdict']=='pass' for k,c in raw['checkpoints'].items() if k.startswith(('D2-','D5-'))):write(root/'rendered-review.json',out);return out
    for id in ['D2-title','D5-title']:add(id,['entry-menu'],text_has('entry-menu',['CHOMP','HIGH SCORE','Start','Options','Quit']),'OCR_VISIBLE_TITLE_AND_CONTROLS')
    entry='entry-live';n=load(root/'session/entry-native-renderer.json')['state']['native'];components=n.get('render_components',[])
    add('D2-maze',[entry],color(entry,'blue')>500 and color(entry,'white')>100 and any(c['registered'] and c['visible'] for c in components),'RENDERED_MAZE_PIXELS_AND_ACTIVE_GEOMETRY; full topology is checked separately through public cells')
    # The binding is adapter-specific; scorer never assumes a Gold object path.
    mapping=load(root/'art-provenance.json') if (root/'art-provenance.json').exists() else None
    if mapping is None:raise InfrastructureError('ART_DERIVATION_REVIEW_REQUIRED')
    if mapping['candidate_identity']!=raw['candidate']['sha256']:raise InfrastructureError('ART_PROVENANCE_IDENTITY')
    refs={c.get('mesh','') for c in components}|{m for c in components for m in c.get('materials',[])}
    roles=mapping['roles'];used=lambda role:any(any(resource in ref for ref in refs) for resource in roles[role]['runtime_resource_fragments'])
    add('D2-actors',[entry],all(color(entry,c)>10 for c in ['yellow','red','cyan','pink','orange']) and all(used(r) for r in ['jaw','tooth','eye','ghost_head','ghost_body','wall','floor','gate','pickup']),'ACTUAL_RENDERED_ART_ROLES_AND_COLORS')
    hud=ocr(entry,(0,0,.30,.095));score=state(entry)['score'];h,w=pixels(entry).shape[:2];life=color(entry,'yellow',{'x':0,'y':.85,'width':.35,'height':.15})
    add('D5-hud',[entry],bool(re.search(r'\b'+str(score)+r'\b',hud)) and life>200 and roles['life_icon'].get('derivation_verified') is True,'OCR_SCORE_AND_RENDERED_YELLOW_LIFE_ART')
    simple={'D2-movement':['speed-after'],'D2-power':['power-active'],'D2-release':['release-30-after','release-60-after','release-90-after'],'D2-pursuit':['ghost-speed-0-after',entry],'D2-capture':['capture-returning'],'D2-recovery':['recovery-after','death-immediate'],'D2-extra_life':['extra_life-after'],'D5-power':['power-active','power-settled'],'D5-capture':['capture-returning','capture-later'],'D5-camera':['presentation-motion','presentation-reverse'],'D5-honesty':['presentation-motion','presentation-reverse']}
    for id,labels in simple.items():
        if raw['checkpoints'].get(id,{}).get('verdict')=='pass':
            ok=all(present(x) for x in labels)
            if id in ['D5-honesty','D5-camera','D2-movement']:
                ok=ok and all(state(x)['player']['screen_rect'] and color(x,'yellow',state(x)['player']['screen_rect'])>10 for x in labels)
            add(id,labels,ok,'DYNAMIC_SNAPSHOTS_CORROBORATED_BY_CLIENT_PIXELS_AND_NATIVE_RECEIPTS')
    if raw['checkpoints'].get('D2-fruit',{}).get('verdict')=='pass':add('D2-fruit',['fruit-visible','fruit-reward'],color('fruit-visible','orange')>5 and color('fruit-visible','green')>5 and used('fruit_body') and used('fruit_crown'),'SUPPLIED_FRUIT_GEOMETRY_AND_VISIBLE_BODY_CROWN')
    if raw['checkpoints'].get('D5-fruit',{}).get('verdict')=='pass':add('D5-fruit',['fruit-reward','fruit-settled'],text_has('fruit-reward',['1000']),'OCR_TRANSIENT_REWARD_OVERLAY')
    if raw['checkpoints'].get('D5-death',{}).get('verdict')=='pass':add('D5-death',['death-immediate'],text_has('death-immediate',['Restart']),'OCR_DEATH_RESTART_CONTROL')
    for id in ['D2-results','D5-results']:add(id,['victory-terminal','loss-terminal'],text_has('victory-terminal',['YOU WIN','SCORE','Restart','Main Menu']) and text_has('loss-terminal',['GAME OVER','SCORE','Restart']),'OCR_DISTINCT_TERMINAL_TITLES_AND_CONTROLS')
    add('D2-pause',['pause-frozen'],text_has('pause-frozen',['PAUSED','Resume','Restart','Options','Main Menu','Quit']),'OCR_PAUSE_ACTIONS')
    add('D2-menus',['menu-options','menu_navigation-after'],text_has('menu-options',['OPTIONS','VSync','Graphics','Resolution','Back','Revert','Apply']),'OCR_OPTIONS_ROWS_AND_ACTIONS')
    add('D5-options',['options-applied'],text_has('options-applied',['OPTIONS','VSync','Graphics','Resolution','Back','Revert','Apply']),'OCR_RESIZED_OPTIONS_CONTROLS')
    write(root/'rendered-review.json',out);return out

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('run');a=ap.parse_args();print(json.dumps(evaluate(a.run),indent=2))
