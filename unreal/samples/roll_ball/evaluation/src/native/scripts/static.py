"""Build and smoke-start one candidate in a clean, isolated copy.

The command never mutates ``input`` or the supplied candidate. Generated UE
folders are excluded from the identity manifest. Static checks produce evidence
consumed by scripts/score.py; gameplay findings still come from collect.py.
"""
import argparse,hashlib,json,os,shutil,subprocess,time
from pathlib import Path
from runtime import INPUT,Player,InfrastructureError,CandidateError,load,write,sha

generated={'Binaries','Intermediate','Saved','DerivedDataCache','.vs'}

def _cell(value):
    if not isinstance(value,dict) or set(('x','y'))-set(value): raise ValueError('LAYOUT_CELL_INVALID')
    if any(type(value[key]) is not int for key in ('x','y')): raise ValueError('LAYOUT_CELL_INTEGER_REQUIRED')
    return (value['x'],value['y'])

def _layout_signature(value):
    """Compare the public fixture semantically, independent of JSON formatting."""
    if not isinstance(value,dict): raise ValueError('LAYOUT_OBJECT_INVALID')
    required=('layout_id','coordinate_system','grid','start_cell','exit_cell','trap_cells','vertical_walls','horizontal_walls')
    if any(key not in value for key in required): raise ValueError('LAYOUT_FIELD_MISSING')
    result={key:value[key] for key in required if key not in ('trap_cells','vertical_walls','horizontal_walls')}
    for key in ('trap_cells','vertical_walls','horizontal_walls'):
        rows=value[key]
        if not isinstance(rows,list): raise ValueError('LAYOUT_ARRAY_INVALID:'+key)
        result[key]=sorted(_cell(row) for row in rows)
    result['start_cell']=_cell(value['start_cell']); result['exit_cell']=_cell(value['exit_cell'])
    return json.dumps(result,sort_keys=True,separators=(',',':'),ensure_ascii=False)

def _public_assets():
    catalog=load(INPUT/'ASSET_CATALOG.json')
    return {item['relative_path'].removeprefix('project/'):item for item in catalog['items']
            if item.get('required') and item.get('relative_path','').startswith('project/')}
def inside(root,path):
    root=root.resolve(); p=Path(path).resolve()
    if p==root or root not in p.parents: raise ValueError('PATH_OUTSIDE_RUN')
    return p

def copy_clean(src,dst):
    src=src.resolve(); dst=dst.resolve()
    if src==dst or src in dst.parents or dst in src.parents: raise ValueError('COPY_PATH_OVERLAP')
    if dst.exists(): raise ValueError('DESTINATION_EXISTS')
    def ignore(directory,names): return [n for n in names if n in generated or n.startswith('Saved-')]
    shutil.copytree(src,dst,ignore=ignore)

def manifest(project):
    rows=[]
    for p in sorted(project.rglob('*')):
        if not p.is_file() or any(part in generated for part in p.relative_to(project).parts): continue
        rows.append(dict(path=p.relative_to(project).as_posix(),sha256=sha(p),byte_length=p.stat().st_size))
    return rows

def entry_map_audit(project):
    """Read the candidate's map settings without depending on UE internals."""
    config = project/'Config'/'DefaultEngine.ini'
    values = {}
    if config.is_file():
        for line in config.read_text('utf-8', errors='replace').splitlines():
            line = line.strip()
            if not line or line.startswith(';') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            if key in ('GameDefaultMap', 'EditorStartupMap'):
                values[key] = value.strip()
    game = values.get('GameDefaultMap')
    editor = values.get('EditorStartupMap')
    # Both entry points must resolve to a map owned by the candidate project.
    # Engine preview maps (for example /Engine/Maps/Entry) are intentionally
    # rejected even when they happen to render successfully.
    game_owned = isinstance(game, str) and game.startswith('/Game/') and len(game) > len('/Game/')
    editor_owned = isinstance(editor, str) and editor.startswith('/Game/') and len(editor) > len('/Game/')
    def map_asset_exists(value):
        if not isinstance(value, str) or not value.startswith('/Game/'):
            return False
        rel = value.removeprefix('/Game/').split('.', 1)[0].strip('/')
        return bool(rel) and (project / 'Content' / (rel + '.umap')).is_file()
    return dict(game_default_map=game, editor_startup_map=editor,
                game_default_map_is_game=game_owned,
                editor_startup_map_is_game=editor_owned,
                game_default_map_exists=map_asset_exists(game),
                editor_startup_map_exists=map_asset_exists(editor),
                project_owned=bool(game_owned and editor_owned),
                project_maps_exist=bool(map_asset_exists(game) and map_asset_exists(editor)))

def evidence(run,rel):
    p=run/rel; return dict(path=Path(rel).as_posix(),sha256=sha(p))

def run(args):
    run=Path(args.run).resolve()
    if run.exists() and any(run.iterdir()): raise ValueError('RUN_DIRECTORY_NOT_EMPTY')
    run.mkdir(parents=True,exist_ok=True)
    source=Path(args.candidate_project).resolve()
    if not source.is_dir(): raise ValueError('CANDIDATE_PROJECT_MISSING')
    project=run/'project'; copy_clean(source,project)
    rows=manifest(project); write(run/'candidate-manifest.json',dict(version='4.0.0',root='project',files=rows))
    entry_maps=entry_map_audit(project)
    checks={}; faults=[]
    def add(cid,ok,reason,paths=(),**facts): checks[cid]=dict(verdict='pass' if ok else 'fail',reason=reason,evidence=[evidence(run,p) for p in paths],facts=facts)
    uproject=project/next((p.name for p in project.glob('*.uproject')), '')
    valid=False
    try: data=json.loads(uproject.read_text('utf-8')); valid=isinstance(data,dict) and isinstance(data.get('FileVersion'),int)
    except Exception: data={}
    add('D1-entry',valid,'Project descriptor is valid JSON with an Unreal file version.',('candidate-manifest.json',) if valid else ())
    layout=project/'Config'/'FixedRollBallLayout.json'; assets=[project/'Content'/'StarterContent'/'Architecture'/'Floor_400x400.uasset',project/'Content'/'StarterContent'/'Architecture'/'Floor_400x400_Hole.uasset',project/'Content'/'StarterContent'/'Architecture'/'Wall_400x200.uasset',project/'Content'/'StarterContent'/'Shapes'/'Shape_Sphere.uasset']
    layout_match=False; layout_error=None
    try: layout_match=layout.is_file() and _layout_signature(load(layout))==_layout_signature(load(INPUT/'project/Config/FixedRollBallLayout.json'))
    except Exception as exc: layout_error=type(exc).__name__+':'+str(exc)
    try: expected_assets=_public_assets()
    except Exception as exc: expected_assets={}; layout_error=layout_error or (type(exc).__name__+':'+str(exc))
    asset_rows=[]
    for p in assets:
        rel=p.relative_to(project).as_posix(); expected=expected_assets.get(rel,{})
        present=p.is_file(); actual_sha=sha(p) if present else None; actual_len=p.stat().st_size if present else None
        asset_rows.append(dict(path=rel,sha256=actual_sha,byte_length=actual_len,
            expected_sha256=expected.get('sha256'),expected_byte_length=expected.get('byte_length'),
            match=present and actual_sha==expected.get('sha256') and actual_len==expected.get('byte_length')))
    assets_match=bool(asset_rows) and all(row['match'] for row in asset_rows)
    static_ok=layout_match and assets_match
    write(run/'public-content-check.json',dict(layout_sha256=sha(layout) if layout.is_file() else None,
        public_layout_sha256=sha(INPUT/'project/Config/FixedRollBallLayout.json'),layout_semantic_match=layout_match,
        assets=asset_rows,error=layout_error))
    entry_ok = valid and static_ok and entry_maps['project_owned'] and entry_maps['project_maps_exist']
    add('D1-entry',entry_ok,'Descriptor, fixed content, and project-owned runtime entry are present.' if entry_ok else 'Descriptor, fixed layout, supplied mesh identity, or runtime entry failed.',('candidate-manifest.json','public-content-check.json') if valid else ('candidate-manifest.json',),layout_semantic_match=layout_match,assets_match=assets_match,entry_map=entry_maps)
    engine=Path(args.engine).resolve(); buildver=engine/'Engine'/'Build'/'Build.version'
    try: ev=load(buildver); engine_ok=ev.get('MajorVersion')==5 and ev.get('MinorVersion')==7 and ev.get('PatchVersion')==4
    except Exception: ev={};engine_ok=False
    target=args.target or 'RollBallStarterEditor'; buildbat=engine/'Engine'/'Build'/'BatchFiles'/'Build.bat'; log=run/'build.log'
    command=[str(buildbat),target,'Win64','Development',f'-Project={uproject}','-WaitMutex','-NoHotReloadFromIDE']
    started=time.monotonic()
    with log.open('w',encoding='utf-8',errors='replace') as fh:
        proc=subprocess.run(command,stdout=fh,stderr=subprocess.STDOUT,timeout=args.build_timeout)
    build_ok=proc.returncode==0
    add('D1-build',build_ok and engine_ok,'UE 5.7.4 build completed in an isolated copy.' if build_ok and engine_ok else 'Build or bound engine identity failed.',('build.log',),engine=ev,returncode=proc.returncode,seconds=time.monotonic()-started)
    # The static launch is deliberately input-free and uses the public bridge.
    runtime_root=run/'static-runtime'
    p=None; state=None; start_error=None
    try:
        p=Player(args.pwsh,args.tools,args.engine,str(uproject),runtime_root)
        state=p.start(gameplay=False); p.capture('initial')
        # Give the read-only provider one bounded sampling interval after the
        # capture before checking progression.  A same-tick read is valid but
        # cannot establish monotonic progress and previously caused a false
        # D1-contract failure on healthy candidates.
        p.observe(.10); state2=p.read(False)
        rendered=not __import__('evidence').image_info(runtime_root/'initial.png')[1]
        add('D1-start',rendered,'Normal entry produced a rendered window without player input.',('static-runtime/initial.png',),process_id=p.pid)
        progressing=state2.get('snapshot_id',0)>state.get('snapshot_id',0) and state2.get('monotonic_ms',0)>=state.get('monotonic_ms',0)
        contract=bool(state.get('provider_ready')) and bool(state.get('bridge_ready')) and progressing and not p.errors
        add('D1-contract',contract,'Public provider is ready and snapshots progress with valid transport.' if contract else 'Provider or snapshot contract did not become ready.',('static-runtime/initial.json',),errors=p.errors)
    except Exception as exc:
        start_error=type(exc).__name__+':'+str(exc); add('D1-start',False,start_error,('build.log',)); add('D1-contract',False,start_error,('build.log',))
    finally:
        if p:
            try:p.close()
            except CandidateError as exc:
                start_error=start_error or ('CANDIDATE_CLEANUP:'+str(exc))
            except Exception as exc:faults.append(dict(code=type(exc).__name__,reason=str(exc)))
    # Preserve one primary D1-entry row after the content check above.
    if not entry_ok:
        checks['D1-entry']=dict(verdict='fail',reason='Project descriptor, fixed layout, supplied mesh identity, or runtime entry failed.',
            evidence=[evidence(run,'candidate-manifest.json'),evidence(run,'public-content-check.json')],
            facts=dict(layout_semantic_match=layout_match,assets_match=assets_match,error=layout_error,entry_map=entry_maps))
    out=dict(version='4.0.0',status='completed' if not faults else 'incomplete',candidate_manifest_sha256=sha(run/'candidate-manifest.json'),engine=ev,checks=checks,faults=faults,build_command=command,start_error=start_error)
    write(run/'static.json',out); return out

def main():
    p=argparse.ArgumentParser()
    for k in ('candidate-project','engine','tools','pwsh','run'): p.add_argument('--'+k,required=True)
    p.add_argument('--target');p.add_argument('--build-timeout',type=int,default=900);a=p.parse_args()
    try: out=run(a); print(out['status']); return 0 if out['status']=='completed' else 2
    except Exception as exc: print(type(exc).__name__+': '+str(exc)); return 2
if __name__=='__main__': raise SystemExit(main())


