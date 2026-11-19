"""Isolate an artifact and attach a source-bound, private observation/setup adapter."""
from pathlib import Path
import json,hashlib,shutil,subprocess,sys,re
EV=Path(__file__).resolve().parents[1];TASK=EV.parent;REPO=TASK.parents[1]
sys.path.insert(0,str(REPO/'engine/observation-player/1.1'))
from runtime import identity,write,load,sha,InfrastructureError,CandidateError,GENERATED

def source_signature(root):
    root=Path(root);paths=sorted([p for base in ('Source','Config') for p in (root/base).rglob('*') if p.is_file()]+list(root.glob('*.uproject')))
    return {p.relative_to(root).as_posix():hashlib.sha256(p.read_text(encoding='utf-8-sig').encode('utf-8')).hexdigest() for p in paths}

def private_extension_build_error(text):
    return any(x in text for x in ['PrivateAdapter.cpp(', 'RenderEvidence.h(', 'NativeEvidence.h(', 'StateFixture.cpp(', 'PrivateAdapter.cpp.obj : error', 'StateFixture.cpp.obj : error'])

def prepare(source,output):
    source=Path(source).resolve();output=Path(output).resolve()
    if output.exists():raise InfrastructureError('ASSESSMENT_COPY_ALREADY_EXISTS')
    ident=identity(source);write(output.parent/'candidate-identity.json',ident)
    if not source.is_dir():raise CandidateError('CANDIDATE_PROJECT_MISSING')
    shutil.copytree(source,output,ignore=shutil.ignore_patterns(*GENERATED))
    copied={}
    for p in [REPO/'engine/shared/state-fixture/StateFixture.cpp',REPO/'engine/shared/state-fixture/StateFixture.h',EV/'fixtures/NativeEvidence.h',EV/'fixtures/RenderEvidence.h',EV/'fixtures'/binding['adapter']]:
        dest=module/('PrivateAdapter.cpp' if p.name.endswith('Adapter.cpp') else p.name);shutil.copy2(p,dest);copied[dest.relative_to(output).as_posix()]=sha(p)
    patch=[]
    renderer=binding.get('renderer')
    if renderer:
        hud=output/renderer['file'];s=hud.read_text(encoding='utf-8-sig');before=hashlib.sha256(s.encode()).hexdigest()
        include_after=renderer.get('include_after')
        if include_after:
            if s.count(include_after)!=1:raise InfrastructureError('RENDERER_INCLUDE_MAPPING_NO_LONGER_MATCHES')
            s=s.replace(include_after,include_after+'\n#include "RenderEvidence.h"',1)
        else:s='#include "RenderEvidence.h"\n'+s
        for replacement in renderer['replacements']:
            old,new=replacement
            if old not in s:raise InfrastructureError('RENDERER_MAPPING_NO_LONGER_MATCHES')
            s=s.replace(old,new)
        s=re.sub(r'(?<![A-Za-z0-9_:])DrawText\(', 'PrivateRender::Text(this,Canvas,',s)
        s=re.sub(r'(?<![A-Za-z0-9_:])DrawTexture\(', 'PrivateRender::Texture(this,Canvas,',s)
        hud.write_text(s,encoding='utf-8');patch.append({'path':hud.relative_to(output).as_posix(),'before_sha256':before,'after_sha256':sha(hud),'purpose':'read-only tap beside original draw; identical forwarded parameters'})
    build=output/binding['module_build_file'];s=build.read_text(encoding='utf-8-sig')
    if '"Slate"' not in s:s=s.replace('"Core",','"Slate", "SlateCore", "Core",',1);build.write_text(s,encoding='utf-8')
    receipt={'source_identity':ident['sha256'],'adapter_key':name,'adapter_version_file':binding['adapter'],'extension_files':copied,'renderer_taps':patch,'candidate_source_modified':False,'private_copy_only':True,'setup_methods_forbidden':['damage','pickup','cast','win','lose','restart','monster_step']}
    write(output.parent/'instrumentation.json',receipt)
    return receipt

def build(project,engine,log):
    log=Path(log);log.parent.mkdir(parents=True,exist_ok=True)
    command=[str(Path(engine)/'Engine/Build/BatchFiles/Build.bat'),'BoneMazeEditor','Win64','Development','-Project='+str(Path(project).resolve()),'-WaitMutex','-NoHotReloadFromIDE']
    with log.open('w',encoding='utf-8') as f:
        try:r=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT,timeout=600)
        except subprocess.TimeoutExpired:raise InfrastructureError('BUILD_HOST_BUDGET_EXHAUSTED')
    return r.returncode

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--engine-root',type=Path,required=True);a=p.parse_args()
    print(json.dumps(prepare(a.source,a.output),indent=2));code=build(a.output/'BoneMaze.uproject',a.engine_root,a.output.parent/'build.log');print('build_exit',code);sys.exit(code)
