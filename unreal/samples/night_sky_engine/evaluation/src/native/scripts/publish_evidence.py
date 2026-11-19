"""Publish a sanitized derivation of existing evidence, without running gameplay again."""
import argparse,os,shutil
from pathlib import Path
from runtime import REPO,load,write,sha

def publish(source,dest,engine):
    source=source.resolve();dest=dest.resolve()
    if dest.exists() and any(dest.iterdir()):raise ValueError('DELIVERY_DIRECTORY_NOT_EMPTY')
    dest.mkdir(parents=True,exist_ok=True)
    raw=load(source/'raw-evaluation.json');source_hash=sha(source/'raw-evaluation.json')
    mappings=[(str(source),'<RunRoot>'),(str(engine.resolve()),'<Engine>'),(str(REPO),'<Repository>'),
        (os.environ.get('USERPROFILE',''),'<UserProfile>'),
        (os.environ.get('ProgramFiles(x86)',''),'<ProgramFilesX86>'),(os.environ.get('ProgramFiles',''),'<ProgramFiles>')]
    def clean(text):
        for old,new in mappings:
            if old:
                text=text.replace(old,new).replace(old.replace('\\','/'),new).replace(old.replace('\\','\\\\'),new)
        return text
    receipts={}
    for folder in ('receipts','states','captures','cases'):
        (dest/folder).mkdir(exist_ok=True)
        for p in (source/folder).glob('*'):
            if not p.is_file():continue
            target=dest/folder/p.name
            if p.suffix=='.json':target.write_text(clean(p.read_text(encoding='utf-8-sig')),encoding='utf-8')
            else:shutil.copyfile(p,target)
            if folder=='receipts':receipts[sha(p)]=sha(target)
    for p in (dest/'captures').glob('*.context.json'):
        context=load(p)
        context['receipt_sha256']=receipts.get(context['receipt_sha256'],context['receipt_sha256'])
        write(p,context)
    for name in ('build.log','candidate-manifest.json','bridge-failure.json'):
        p=source/name
        if p.is_file():(dest/name).write_text(clean(p.read_text(encoding='utf-8-sig')),encoding='utf-8')
    diagnostic=[]
    for p in (source/'project/Saved/Logs').glob('*.log'):
        for line in p.read_text(encoding='utf-8-sig',errors='replace').splitlines():
            if any(w in line for w in ('Error:','Warning:','Fatal error','Critical error')):
                diagnostic.append(clean(line))
    (dest/'runtime-diagnostics.txt').write_text('\n'.join(dict.fromkeys(diagnostic))+'\n',encoding='utf-8')
    raw['evidence_sha256']={p.relative_to(dest).as_posix():sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    raw['delivery_derivation']={'source_raw_sha256':source_hash,'operation':'Replace host paths with aliases; rebind changed receipt/context/evidence hashes. Pixels and state observations unchanged.'}
    write(dest/'raw-evaluation.json',raw)
    return raw

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--engine',type=Path,required=True)
    a=p.parse_args();publish(a.source,a.output,a.engine)
