"""Validate public package structure, references and optional snapshot integrity."""
import argparse
import hashlib
import json
from pathlib import Path
import re

parser=argparse.ArgumentParser()
parser.add_argument('--input-root',type=Path,required=True)
parser.add_argument('--verify-snapshot',action='store_true')
args=parser.parse_args()
root=args.input_root.resolve()
failures=[]
def check(ok,message):
    if not ok: failures.append(message)
def read(name): return json.loads((root/name).read_text(encoding='utf-8-sig'))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def safe(name):
    path=(root/name).resolve()
    if not path.is_relative_to(root):raise ValueError('Path escapes input: '+name)
    return path

manifest=read('BENCHMARK_MANIFEST.json')
check(manifest['language']=='en','Language identity mismatch.')
check(manifest['engine']['version']=='5.7.4' and manifest['engine']['changelist']==51494982,'Engine identity mismatch.')
project=safe(manifest['paths']['project_file'])
check(project.is_file(),'Project descriptor is missing.')
check(read(manifest['paths']['project_file'])['EngineAssociation']=='5.7','Project engine association mismatch.')
gdd=(root/'GDD.md').read_text()
section=gdd.split('## 6. ',1)[1].split('## 7. ',1)[0]
defined=re.findall(r'^\| ([A-Z]+-\d{2}) \|',section,re.M)
check(len(defined)==len(set(defined)),'Duplicate requirement definition.')
check(len(defined)==manifest['requirements']['count'],'Requirement count differs from manifest.')
for token in re.findall(r'\b[A-Z]+-\d{2}\b',gdd): check(token in defined,'Undefined requirement: '+token)
maze=read('contracts/maze-layout.json')
rows=maze['cells']
check(len(rows)==28 and all(len(r)==30 for r in rows),'Maze dimensions mismatch.')
check(sum(sum(r.count(c) for c in '.TF') for r in rows)==299,'Ordinary dot total mismatch.')
check(sum(r.count('E') for r in rows)==4,'Energizer total mismatch.')
check(all(f'{i:02} {r}' in gdd for i,r in enumerate(rows)),'GDD diagram and machine maze differ.')
catalog=read('assets/ASSET_CATALOG.json')
license_paths={a['path'] for a in read('assets/legal/ASSET_LICENSE_MAP.json')['files']}
asset_manifest=read('ASSET_MANIFEST.json')
by_id={a['id']:a for a in catalog['assets']}
check(len(by_id)==len(catalog['assets']),'Duplicate resource ID.')
check({a['id'] for a in asset_manifest['resources']}==set(by_id),'Asset manifest and catalog resource sets differ.')
binding_ids=set(manifest['art']['required_use'])
check(binding_ids=={'ASSET-01','ASSET-02','ASSET-03','ASSET-04','ASSET-05'},'Required-art binding IDs differ.')
for item in asset_manifest['resources']:
    asset=by_id.get(item['id'],{})
    check(all(item.get(key)==asset.get(key) for key in ['path','required','replacement_allowed','modification_allowed','usage','requirements']),
          'Asset manifest and catalog policy differ: '+item['id'])
for a in catalog['assets']:
    path=safe(a['path']);check(path.is_file(),'Missing resource: '+a['path'])
    check(a['path'] in license_paths,'Resource lacks legal mapping: '+a['path'])
    check(all(r in defined for r in a['requirements']),'Resource has unknown requirement: '+a['id'])
    check(not a['replacement_allowed'],'Required art permits unrelated replacement: '+a['id'])
    check(bool(set(a['requirements'])&binding_ids),'Resource lacks mandatory-art mapping: '+a['id'])
    if a['path'].endswith('.uasset'):
        check(a['required'] and a['usage']=='mandatory_visible_role','UE resource lacks mandatory use: '+a['id'])
        check(a['engine_object_path'].startswith('/Game/Art/'),'Resource object path outside art root: '+a['id'])
    if 'reimport_source' in a:
        check(a['reimport_source'].startswith('starter-project/SourceArt/'),'Reimport source outside project source-art root: '+a['id'])
        check(safe(a['reimport_source']).is_file(),'Reimport source is missing: '+a['id'])
        check((path.parent/a['reimport_metadata']).resolve()==safe(a['reimport_source']),'Reimport path does not resolve: '+a['id'])
    if 'editing_source_for' in a:
        check(a['editing_source_for'] in by_id,'Source has no imported art target: '+a['id'])
        check(safe(a['project_copy']).is_file() and safe(a['reference_copy']).is_file(),'Source copy is missing: '+a['id'])
        if args.verify_snapshot:
            check(sha(safe(a['project_copy']))==sha(safe(a['reference_copy'])),'Source copies differ: '+a['id'])
    if args.verify_snapshot and path.is_file(): check(sha(path)==a['sha256'],'Resource hash differs: '+a['path'])
covered=set()
for role in read('ASSET_COVERAGE.json')['roles']:
    check(bool(role['resources']),'Uncovered static asset role: '+role['role'])
    for identifier in role['resources']:
        check(identifier in by_id,'Coverage references unknown resource: '+identifier)
        covered.add(identifier)
    check(all(identifier in defined for identifier in role['requirements']),'Coverage references unknown requirement: '+role['role'])
check({a['id'] for a in catalog['assets'] if a['required']}<=covered,'Mandatory resource lacks role coverage.')
index=read('tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.index.json')
check(sha(safe(index['catalog_file']))==index['catalog_sha256'],'Interface catalog hash mismatch.')










for p in root.rglob('*'):
    if not p.is_file():continue
    rel=p.relative_to(root).as_posix()
    if p.suffix.lower() in {'.md','.json','.py','.ps1','.ini','.cpp','.h','.cs','.uproject','.svg','.obj'}:
        text=p.read_text(encoding='utf-8-sig')
        check(not re.search('[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]',text),'Non-English text: '+rel)
        check(not re.search(r'(?i)[A-Z]:[\\/](?:Users|codes|Program Files)[\\/]',text),'Host path: '+rel)
        check(not re.search(r'(?i)(?:sk-proj-|ghp_)[A-Za-z0-9]{12,}',text),'Credential-like string: '+rel)
print(json.dumps({'status':'passed' if not failures else 'failed','requirements':len(defined),
    'required_ue_assets':sum(a['required'] for a in catalog['assets']),'catalog_resources':len(catalog['assets']),
    'ordinary_dots':299,'failures':failures},indent=2))
raise SystemExit(1 if failures else 0)
