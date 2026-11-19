#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,subprocess,tempfile,xml.etree.ElementTree as ET,zipfile
from datetime import datetime,timezone
from pathlib import Path

def sha(p:Path)->str:
    h=hashlib.sha256();
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''): h.update(b)
    return h.hexdigest().upper()
def ev(p:Path,root:Path): return {"file":str(p.relative_to(root)).replace('\\','/'),"sha256":sha(p)}
def cp(status,detail,evidence): return {"status":status,"detail":detail,"evidence":evidence,"trace_ids":[]}
def main():
    root=Path(__file__).resolve().parent; original=root/'candidate'/'original'; source=root/'candidate'/'source'/'project'; audit=root/'audit'; audit.mkdir(exist_ok=True)
    package=original/'CoolantCargoProject.zip'; place=original/'CoolantCargoCandidate.rbxlx'; rojo=root/'tools'/'rojo.exe'; compiler=root/'tools'/'luau-compile.exe'
    expected={'default.project.json','src/shared/CoolantCargoSchema.luau','src/server/CoolantCargo.server.luau','src/client/Hud.client.luau','DEVELOPMENT_TRACE.txt','RUN_REPORT.txt'}
    checkpoints={}
    with zipfile.ZipFile(package) as z:
        names={n.replace('\\','/') for n in z.namelist() if not n.endswith('/')}; unsafe=[n for n in names if n.startswith(('/','\\')) or '..' in Path(n).parts]; bad=z.testzip(); mismatches=[]
        for n in expected & names:
            p=source/n
            if not p.is_file() or hashlib.sha256(z.read(n)).digest()!=hashlib.sha256(p.read_bytes()).digest(): mismatches.append(n)
    inventory=audit/'package_inventory.json'; inventory.write_text(json.dumps({"entries":sorted(names),"missing":sorted(expected-names),"unsafe":unsafe,"testzip_bad":bad,"extracted_mismatches":mismatches},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    ok=expected.issubset(names) and not unsafe and bad is None and not mismatches; checkpoints['d1.package_integrity']=cp('pass' if ok else 'fail','ZIP readable, safe and complete.' if ok else 'ZIP incomplete or unsafe.',[ev(package,root),ev(inventory,root)])
    records=[]; compile_ok=True
    for script in sorted((source/'src').rglob('*.luau')):
        run=subprocess.run([str(compiler),str(script)],capture_output=True); records.append({"file":str(script.relative_to(root)).replace('\\','/'),"exit_code":run.returncode}); compile_ok &= run.returncode==0
    clog=audit/'luau_compile.json'; clog.write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8'); checkpoints['d1.source_compile']=cp('pass' if compile_ok and len(records)==3 else 'fail',f'Luau compiler checked {len(records)} scripts.',[ev(clog,root)])
    with tempfile.TemporaryDirectory(prefix='ccp_clean_') as td:
        with zipfile.ZipFile(package) as z: z.extractall(td)
        built=audit/'CoolantCargo_clean_build.rbxlx'; run=subprocess.run([str(rojo),'build',str(Path(td)/'default.project.json'),'-o',str(built)],capture_output=True,text=True,encoding='utf-8',errors='replace')
    blog=audit/'rojo_clean_build.log'; blog.write_text(run.stdout+run.stderr,encoding='utf-8'); build_ok=run.returncode==0 and built.is_file() and built.stat().st_size>0; checkpoints['d1.rojo_clean_build']=cp('pass' if build_ok else 'fail','Clean ZIP extraction rebuilt with Rojo.' if build_ok else 'Clean build failed.',[ev(blog,root)]+([ev(built,root)] if built.exists() else []))
    try:
        tree=ET.parse(place); classes=[i.attrib.get('class','') for i in tree.getroot().findall('.//Item')]; place_ok=all(classes.count(x)>=1 for x in ('Script','LocalScript','ModuleScript')); detail=f'Delivered XML parsed with {len(classes)} Items and required script classes.'
    except Exception as e: place_ok=False; detail=f'Place parse failed: {e}'
    preport=audit/'delivered_place_audit.json'; preport.write_text(json.dumps({"parsed":place_ok,"detail":detail,"matches_clean_build":build_ok and sha(place)==sha(built)},indent=2)+'\n',encoding='utf-8'); checkpoints['d1.delivered_place_integrity']=cp('pass' if place_ok else 'fail',detail,[ev(place,root),ev(preport,root)])
    checkpoints['d1.studio_open_smoke']=cp('not_run','No-input Studio OpenPlaceSuccess smoke not run.',[])
    files=[]
    for p in sorted([place,package,*source.rglob('*')]):
        if p.is_file(): files.append({"file":str(p.relative_to(root)).replace('\\','/'),"sha256":sha(p),"bytes":p.stat().st_size,"scope":"candidate_original"})
    hashes=audit/'hashes.json'; hashes.write_text(json.dumps({"schema_version":"coolant-cargo-hashes-v1","files":files},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    result={"schema_version":"coolant-cargo-static-v1","audited_at_utc":datetime.now(timezone.utc).isoformat(),"candidate_place_sha256":sha(place),"candidate_zip_sha256":sha(package),"checkpoints":checkpoints,"hash_manifest":"audit/hashes.json"}; out=audit/'static_results.json'; out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); print(out); return 0 if all(v['status']=='pass' for k,v in checkpoints.items() if k!='d1.studio_open_smoke') else 2
if __name__=='__main__': raise SystemExit(main())
