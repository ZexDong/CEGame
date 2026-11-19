"""Create an offline, evidence-bound human review form. No automated visual verdicts."""
import argparse,json,html
from pathlib import Path
from runtime import ROOT,load,sha
from score import template
from review_contract import CAPTURES,SUBCLAUSES

CHECKS={
 'D2-01':('Initial arena, floor, bounds, exactly two fighters, direct controls',['initial']),
 'D2-10':('All required HUD and resolution feedback is present',['initial','whiff','cooldown','bolt-hit','blocked','pulse-hit','player-win','rival-win']),
 'D2-11':('Both visible bodies use supplied articulated Manny, with distinct colors',['initial','walk-toward','strike-hit','reopened']),
 'D2-12':('All eight supplied clips visibly play their required roles; confirm with import provenance',['initial','idle-after-move','walk-away','walk-away-later','walk-toward','walk-toward-later','airborne','airborne-later','landed','strike-action','strike-hit','bolt-cast','bolt-hit','guard','guard-later','pulse-hit','pulse-hit-later']),
 'D5-01':('Controls, numeric health, proportional bars and bolt status are readable at 1280 x 720',['initial','bolt-cast','bolt-hit','reopened']),
 'D5-02':('Visible movement, jump, landing and release match input and state',['walk-away','walk-toward','airborne','airborne-later','landed','idle-after-move']),
 'D5-03':('Strike, bolt, hit, WHIFF and COOLDOWN visibly match their transitions',['strike-action','strike-hit','bolt-cast','bolt-hit','whiff','whiff-later','cooldown']),
 'D5-04':('Full warning, held block pose, guard flash/BLOCKED and hit reaction are distinct',['telegraph','guard','guard-later','blocked','pulse-hit','pulse-hit-later']),
 'D5-05':('Both result banners match health; terminal persists; Restart/Reopen visibly restore fresh state',['player-win','player-win-stable','rival-win','restart','reopened'])}

for checkpoint in load(ROOT/'catalog/checkpoints.json')['checkpoints']:
    key=checkpoint['id']
    if key in CAPTURES:
        CHECKS[key]=(CHECKS.get(key,(checkpoint['summary'],))[0],CAPTURES[key])

def main(raw_path,output):
    template(raw_path,raw_path.parent/'semantic-review.json')
    review=load(raw_path.parent/'semantic-review.json');raw=load(raw_path);parts=[]
    for id,(description,names) in CHECKS.items():
        evidence=[];figures=[]
        for name in names:
            c=raw['captures'].get(name)
            if not c:continue
            for rel in (c['path'],c['context']):evidence.append({'path':rel,'sha256':sha(raw_path.parent/rel)})
            figures.append(f'<figure><figcaption>{html.escape(name)}</figcaption><a href="{c["path"]}"><img src="{c["path"]}"></a><a href="{c["context"]}">Paired read-only state</a></figure>')
        # Include collected input/state evidence for causal review, not only still images.
        for rel,digest in raw['evidence_sha256'].items():
            if rel.startswith(('states/','receipts/','cases/')):
                evidence.append({'path':rel,'sha256':digest})
        if not evidence:
            evidence=[{'path':rel,'sha256':digest} for rel,digest in raw['evidence_sha256'].items()]
        review['checks'][id]['evidence']=evidence
        clause_form=''.join(f'<fieldset><legend>{html.escape(key)}</legend><label>Concrete clause observation<textarea id="c-{id}-{key}"></textarea></label><label>Relevant evidence paths, one per line<textarea id="e-{id}-{key}"></textarea></label></fieldset>' for key in SUBCLAUSES.get(id,()))
        parts.append(f'<section><h2>{id}: {html.escape(description)}</h2><label>Verdict <select id="v-{id}"><option value="">Pending</option><option value="pass">Pass</option><option value="fail">Fail</option></select></label><label>Concrete observation / failure reason<textarea id="r-{id}" rows="2"></textarea></label>'+clause_form+'<div class="frames">'+''.join(figures)+'</div></section>')
    code=json.dumps(review,ensure_ascii=True).replace('</','<\\/')
    page='''<!doctype html><html lang="en"><meta charset="utf-8"><title>Night Sky Duel fixed human review</title>
<style>body{font:16px system-ui;margin:32px;background:#151d2a;color:#edf5ff}a{color:#72cfff}section{border-top:1px solid #678;padding:24px 0}.frames{display:flex;flex-wrap:wrap;gap:12px}figure{margin:0;max-width:620px}img{width:100%}label{display:block;margin:12px 0}textarea{width:95%;display:block}button,select{padding:12px}</style>
<h1>Fixed human review</h1><label>Reviewer identity <input id="reviewer"></label><p>Inspect the original-size captures, input/state sequences and the linked contract. No selections are pre-approved. Imported files alone cannot prove visible asset playback. Record a concrete reason for every check. A missing acquisition interval is an evaluator evidence gap, not an inferred pass.</p>
<p>The full review contract is included below. Short feedback must last 0.30–1.25 seconds unless replaced. Inspect saved states as well as still frames; do not invent an observation.</p><pre>'''+html.escape((ROOT/'contracts/semantic-review.md').read_text(encoding='utf-8'))+'''</pre>'''+''.join(parts)+'''<button onclick="download()">Export completed semantic-review.json</button><script>
const review='''+code+''';
function download(){const reviewer=document.getElementById('reviewer').value.trim();if(!reviewer){alert('Provide the actual reviewer identity.');return;}review.reviewer.identity=reviewer;for(const id of Object.keys(review.checks)){const v=document.getElementById('v-'+id).value;const reason=document.getElementById('r-'+id).value.trim();if(!v||!reason){alert('Complete '+id+' with a verdict and reason.');return;}review.checks[id].pass=v==='pass';review.checks[id].reason=reason;review.checks[id].observations=[reason];if(v==='pass'){for(const key of Object.keys(review.checks[id].clause_observations||{})){const observation=document.getElementById('c-'+id+'-'+key).value.trim();const evidence=document.getElementById('e-'+id+'-'+key).value.split('\\n').map(s=>s.trim()).filter(Boolean);const allowed=new Set(review.checks[id].evidence.map(e=>e.path));if(!observation||!evidence.length||evidence.some(e=>!allowed.has(e))){alert('Complete the observation and valid evidence paths for '+id+' / '+key);return;}review.checks[id].clause_observations[key]={pass:true,observation,evidence};}}}review.status='completed';const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(review,null,2)+'\\n'],{type:'application/json'}));a.download='semantic-review.json';a.click();}
</script></html>'''
    output.write_text(page,encoding='utf-8')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();main(a.raw,a.output)
