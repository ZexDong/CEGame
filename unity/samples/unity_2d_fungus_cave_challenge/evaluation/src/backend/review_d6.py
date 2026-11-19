"""Single-state, single-round visual review; no credentials in the release."""
import argparse,base64,hashlib,json,os,re,time,urllib.request
from pathlib import Path
KEYS=["Scene completeness and asset assembly","Composition and layout","Scale, hierarchy, and clarity","Style and color consistency","Overall polish"]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding="utf-8")
def main():
    ap=argparse.ArgumentParser();ap.add_argument("--evaluation",required=True,type=Path);ap.add_argument("--base-url-env",default="GAMECREATE_REVIEW_BASE_URL");ap.add_argument("--key-env",default="GAMECREATE_REVIEW_API_KEY");ap.add_argument("--actor-env",default="GAMECREATE_REVIEW_ACTOR");a=ap.parse_args()
    ev=Path(__file__).resolve().parent;out=a.evaluation.resolve();dest=out/"d6.json"
    if dest.exists():raise RuntimeError("Single round already retained; do not select a different review")
    score=json.loads((out/"automatic-score.json").read_text(encoding="utf-8-sig"));candidate=out/"main-play.png";reference=ev/"reference.png"
    if not reference.exists():raise RuntimeError("Frozen reference missing")
    if not candidate.exists():
        if score.get("infrastructure_error"):raise RuntimeError("Missing frame due to infrastructure is not candidate zero")
        # Build/entry defects with independent evidence make no game frame available.
        review=dict(status="no_candidate_frame_product_blocked",score=0,reference_sha256=sha(reference),model_call=False)
        dump(dest,review);return
    prompt=(ev/"d6-prompt.txt").read_text(encoding="utf-8")
    gdd=(ev.parent/"input/GDD.md").read_text(encoding="utf-8")
    # Only public visual requirements; never reveal behavior scores/candidate code.
    visual=re.search(r"- (?:FC-13|GG-10|PR-09):[\s\S]*?(?:\n\n|$)",gdd)
    prompt+="\nPublic visual goals (other gameplay requirements are not assessed):\n"+(visual.group(0) if visual else "")
    body=dict(model="gpt-5.6-sol",input=[dict(role="user",content=[dict(type="input_text",text=prompt)]+[dict(type="input_image",image_url="data:image/png;base64,"+base64.b64encode(p.read_bytes()).decode(),detail="high") for p in [reference,candidate]])],store=False)
    binding=dict(reference_sha256=sha(reference),candidate_sha256=sha(candidate),prompt_sha256=hashlib.sha256(prompt.encode()).hexdigest(),model="gpt-5.6-sol",rounds=1)
    reused_raw=(out/"d6-response.json").exists()
    if reused_raw:
        if json.loads((out/"d6-request-binding.json").read_text(encoding="utf-8"))!=binding:raise RuntimeError("Retained single review binding differs")
        raw=json.loads((out/"d6-response.json").read_text(encoding="utf-8"));seconds=None
    else:
        dump(out/"d6-request-binding.json",binding)
        headers={"Content-Type":"application/json","Authorization":"Bearer "+os.environ[a.key_env]}
        if os.environ.get(a.actor_env):headers["x-openai-actor-authorization"]=os.environ[a.actor_env]
        request=urllib.request.Request(os.environ[a.base_url_env].rstrip("/")+"/responses",data=json.dumps(body).encode(),headers=headers,method="POST")
        started=time.time()
        with urllib.request.urlopen(request,timeout=600) as response:raw=json.loads(response.read().decode())
        seconds=time.time()-started;dump(out/"d6-response.json",raw)
    if raw.get("model") and raw["model"]!="gpt-5.6-sol":raise RuntimeError("Review response reports unexpected model; preserve raw, do not substitute")
    output="\n".join(c.get("text","") for item in raw.get("output",[]) for c in item.get("content",[]) if c.get("type")=="output_text")
    (out/"d6-review.txt").write_text(output,encoding="utf-8")
    values={}
    for key in KEYS:
        m=re.search(re.escape(key)+r"[::]\s*([0-9.]+)\s*/\s*2",output)
        if not m or float(m.group(1)) not in [0,.5,1,1.5,2]:raise RuntimeError("Invalid review; retain raw response, no score substitution: "+key)
        values[key]=float(m.group(1))
    total=sum(values.values());m=re.search(r"Total[::]\s*([0-9.]+)\s*/\s*10",output)
    if not m or abs(float(m.group(1))-total)>1e-6:raise RuntimeError("Review total mismatch")
    dump(dest,dict(binding,status="reviewed",categories=values,score=total,seconds=seconds,parsed_retained_raw=reused_raw,usage=raw.get("usage"),raw_response_sha256=sha(out/"d6-response.json")))
if __name__=="__main__":main()
