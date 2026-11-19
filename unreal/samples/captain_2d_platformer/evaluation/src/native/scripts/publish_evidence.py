"""Create a portable, redacted evidence copy before review, D6 and scoring.

Never copies generated candidate workspaces. Original local evidence is retained.
SHA changes caused by path redaction are explicitly mapped in publication.json.
"""
import argparse
import os
import re
import shutil
from pathlib import Path
from runtime import REPO,load,write,sha,InfrastructureError
from seal_evidence import seal

def publish(source,destination):
    source=source.resolve();destination=destination.resolve()
    if destination.exists() and any(destination.iterdir()):raise InfrastructureError('PUBLISH_DESTINATION_NOT_EMPTY')
    if destination.is_relative_to(source) or source.is_relative_to(destination):raise InfrastructureError('PUBLISH_PATH_OVERLAP')
    raw=load(source/'raw-evaluation.json')
    if raw['status']!='collected':raise InfrastructureError('PUBLISH_SOURCE_INVALID')
    destination.mkdir(parents=True,exist_ok=True)
    replacements=[(str(source),'<run-root>'),(str(source.parent),'<authoring-root>'),
        (str(REPO),'<repository>')]
    for key in ('USERPROFILE','LOCALAPPDATA','TEMP'):
        if os.environ.get(key):replacements.append((os.environ[key],'<host-profile>'))
    def redact(value):
        if isinstance(value,dict):return {k:redact(v) for k,v in value.items()}
        if isinstance(value,list):return [redact(v) for v in value]
        if not isinstance(value,str):return value
        for old,new in replacements:
            value=value.replace(old,new).replace(old.replace('\\','/'),new)
        return re.sub(r'(?i)(?<![a-z0-9])[a-z]:[\\/][^\s"<>|]*','<host-path>',value)
    paths=[];original={}
    for p in sorted(source.rglob('*')):
        rel=p.relative_to(source)
        if not p.is_file() or rel.parts[0] in ('work','d6') or p.name in ('evidence-manifest.json','runtime-review.json','d6-result.json','evaluation-result.json'):continue
        if p.suffix.lower() not in ('.json','.png','.log'):continue
        q=destination/rel;q.parent.mkdir(parents=True,exist_ok=True);paths.append(rel);original[rel.as_posix()]=sha(p)
        if p.suffix=='.json':write(q,redact(load(p)))
        elif p.suffix=='.log':q.write_text(redact(p.read_text(encoding='utf-8',errors='replace')),encoding='utf-8')
        else:shutil.copyfile(p,q)
    # Capture contexts bind the typed capture receipt; update only that explicit
    # dependency after its host paths have been redacted. Image bytes do not change.
    receipt_map={original[p.as_posix()]:sha(destination/p) for p in paths if p.parts[0]=='receipts'}
    for rel in paths:
        if rel.name.endswith('.context.json'):
            p=destination/rel;data=load(p)
            if data.get('receipt_sha256') in receipt_map:data['receipt_sha256']=receipt_map[data['receipt_sha256']]
            write(p,data)
    write(destination/'publication.json',dict(schema_version='2.0.0',source_run_id=raw['run_id'],
        operation='Portable copy; host paths redacted, capture receipt digest dependencies updated; source evidence retained locally.',
        files=[dict(path=p.as_posix(),source_sha256=original[p.as_posix()],published_sha256=sha(destination/p)) for p in paths]))
    seal(destination)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path);a=p.parse_args()
    publish(a.source,a.destination);print(a.destination)
