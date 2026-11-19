"""Create an unfilled, evidence-bound human runtime review packet (D1-D5, no VLM)."""
import argparse
from pathlib import Path
from runtime import ROOT,load,write,sha
from score import valid_raw

def main():
    p=argparse.ArgumentParser();p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    raw=load(a.raw);catalog=valid_raw(raw);root=a.raw.resolve().parent;rows=[]
    for c in catalog['checkpoints']:
        actual=next(x for x in raw['checkpoints'] if x['id']==c['id'])
        if not c['runtime_picture_review_required'] or actual['verdict']!='pass':continue
        rows.append(dict(id=c['id'],question=c['question'],passed=None,reason='',evidence=[dict(path=x,sha256=sha(root/x)) for x in actual['evidence']]))
    write(a.output,dict(schema_version='2.0.0',method='fixed_human_runtime_review',reviewer='',raw_sha256=sha(a.raw),
        instructions='Review only actual candidate runtime pictures, normal-input receipts and matching state. Do not use reference-image similarity or VLM for D1-D5. Record visible contradictions. Inspect animation sequences and all supplied action variants. Never infer a pass from file presence.',checks=rows))
if __name__=='__main__':main()
