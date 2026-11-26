"""File-layout/CLI compatibility for the supplied original game evaluators.

No gameplay check is implemented here. Native programs and their native reports
are retained; this module stages inputs, invokes those programs and exports v2.
"""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,math,os,re,shutil,subprocess,sys,uuid,zipfile

from visual_binding import validate_visual

MAXIMA={'D1':10,'D2':30,'D3':20,'D4':20,'D5':10,'D6':10}
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def dump(p,d): p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def tool(value):
    p=shutil.which(value) or (str(Path(value).resolve()) if Path(value).is_file() else None)
    if not p: raise RuntimeError('Declared external tool is unavailable: '+value)
    return p
def cmd(argv,cwd):
    result=subprocess.run([str(x) for x in argv],cwd=cwd,env={**os.environ,'PYTHONUTF8':'1','ROJO_EXE':str(cwd/'tools/rojo.exe')})
    return result.returncode
def pack(folder,path,prefix=''):
    path.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(folder.rglob('*')):
            if p.is_file(): z.write(p,(prefix+p.relative_to(folder).as_posix()))
def candidate_input(source,work,cfg):
    source=source.resolve()
    if source.is_file() and source.suffix.lower()=='.rbxlx' and cfg['family']=='dashboard':
        snapshot=work/'submission';snapshot.mkdir();shutil.copy2(source,snapshot/source.name)
        return snapshot,snapshot,snapshot/source.name
    if source.is_file():
        unpack=work/'unpacked';unpack.mkdir()
        with zipfile.ZipFile(source) as z:
            total=0
            for item in z.infolist():
                name=item.filename.replace('\\','/');p=PurePosixPath(name);total+=item.file_size
                if p.is_absolute() or '..' in p.parts or ':' in name or (item.external_attr>>16)&0o170000==0o120000:
                    raise ValueError('Unsafe ZIP member: '+name)
                if total>512*1024*1024: raise ValueError('Candidate ZIP exceeds 512 MiB')
            z.extractall(unpack)
        options=list(unpack.rglob('default.project.json'))
        if len(options)!=1:
            if cfg['family']!='dashboard':raise ValueError('Candidate ZIP needs one unambiguous default.project.json')
            children=list(unpack.iterdir());root=children[0] if len(children)==1 and children[0].is_dir() else unpack;project=root
        else:
            project=options[0].parent;root=project.parent if project.name=='project' else project
    else:
        if any(p.is_symlink() or (hasattr(p,'is_junction') and p.is_junction()) for p in source.rglob('*')): raise ValueError('Candidate symlinks/junctions are unsupported')
        options=list(source.rglob('default.project.json'))
        if len(options)!=1:
            if cfg['family']!='dashboard':raise ValueError('Candidate directory needs one unambiguous default.project.json')
            root=source;project=root
        else:
            project=options[0].parent;root=project.parent if project.name=='project' else project
    snapshot=work/'submission';shutil.copytree(root,snapshot)
    project=snapshot/project.relative_to(root)
    places=list(snapshot.rglob('*.rbxlx'))
    if not places and source.is_file():
        sidecar=source.parent/cfg['place']
        if sidecar.is_file():shutil.copy2(sidecar,snapshot/cfg['place']);places=[snapshot/cfg['place']]
    named=[p for p in places if p.name==cfg['place']]
    if not named and len(places)==1:named=places
    if len(named)!=1: raise ValueError('Candidate must include its delivered '+cfg['place'])
    return snapshot,project,named[0]
def copy_native(e,work,cfg,rojo,compiler,luau):
    dest=work/cfg['native_subdir']
    shutil.copytree(e/'src/original',dest,dirs_exist_ok=True)
    (work/'tools').mkdir(exist_ok=True)
    for name,source in [('rojo.exe',rojo),('luau-compile.exe',compiler),('luau.exe',luau)]:
        if source:shutil.copy2(source,work/'tools'/name)
    # Preserve the native source in the publication. Only runtime copies have
    # old executable locations rebound to the declared installed tools.
    for p in dest.rglob('*'):
        if p.suffix not in {'.py','.ps1','.cmd','.lua','.luau'}:continue
        text=p.read_text(encoding='utf-8-sig')
        for exe,source in [('rojo.exe',rojo),('luau-compile.exe',compiler),('luau.exe',luau)]:
            if source:
                pattern=r'(?i)[A-Z]:[\\/][^\"\'\r\n]*?'+re.escape(exe)
                text=re.sub(pattern,lambda _:Path(source).as_posix(),text)
        p.write_text(text,encoding='utf-8')
    return dest
def native_steps(work,native,cfg,snapshot,project,place,args):
    family=cfg['family'];python=sys.executable
    for d in ['candidate','audit','evidence','qa','results']:(work/d).mkdir(exist_ok=True)
    if family in {'nested','flat'}:
        original=work/'candidate/original'; original.mkdir(exist_ok=True)
        shutil.copy2(place,original/cfg['place'])
        shutil.copytree(project,work/'candidate/source/project')
        if cfg.get('zip_scope')=='project':pack(project,original/cfg['native_zip'])
        else:
            transport=work/'transport';transport.mkdir();shutil.copytree(project,transport/'project')
            pack(transport,original/cfg['native_zip'])
        shutil.copy2(native/'rules.json',work/'rules.json') if (native/'rules.json').is_file() and native!=work else None
        static=[python,native/'static_audit.py']
        if family=='nested':static+=['--root',work]
        code=cmd(static,work)
        if args.prepare_only:return
        if code not in (0,2):raise RuntimeError('Original static audit failed: '+str(code))
        code=cmd([python,native/'local_complete_eval.py','--run-kind','formal','--timeout',str(1320 if family=='nested' else 900)],work)
        if code:raise RuntimeError('Original native runtime returned '+str(code))
    elif family=='dashboard':
        if not args.prepare_only:
            command=[python,native/'player_runtime.py','--game',place,'--trace',work/'evidence/runtime-trace.jsonl']
            if cfg.get('checkpoint_script'):command+=['--script',native/'checkpoint-script.json']
            code=cmd(command,work)
            if code not in (0,3):raise RuntimeError('Original runtime failed: '+str(code))
        command=[python,native/'evaluate.py','--game',place,'--out',work/'evaluation-report.json']
        if args.source_zip:
            source_archive=args.source_zip.resolve()
            if not source_archive.is_file():raise ValueError('Source archive does not exist')
            command+=['--source-zip',source_archive]
        elif any(p.suffix in {'.lua','.luau','.py','.js'} for p in snapshot.rglob('*') if p.is_file()):
            pack(snapshot,work/'source.zip');command+=['--source-zip',work/'source.zip']
        trace=work/'evidence/runtime-trace.jsonl'
        if trace.exists():command+=['--trace',trace]
        if cfg.get('checkpoint_script'):command+=['--script',native/'checkpoint-script.json']
        failure=native/'evidence/candidate-runtime-failure.txt'
        if failure.exists():command+=['--candidate-runtime-failure',failure]
        code=cmd(command,work)
        if code not in (0,2):raise RuntimeError('Original report writer failed: '+str(code))
    elif family=='foundry':
        (work/'qa_project').mkdir()
        code=cmd([python,native/'static_audit.py','--candidate',snapshot,'--output',work/'results/static_audit.json'],work)
        if code:raise RuntimeError('Original static audit failed')
        if args.prepare_only:return
        powershell='powershell.exe'
        code=cmd([powershell,'-NoProfile','-ExecutionPolicy','Bypass','-File',native/'RUN_FORMAL_EVALUATION.ps1',
                  '-CandidateProject',project,'-OutputDirectory',work/'results/formal/current','-NoPause'],work)
        if code:raise RuntimeError('Original formal flow failed: '+str(code))
    elif family=='moonlit':
        shutil.copytree(project,work/'source/MoonlitGreenhouse')
        (work/'input').mkdir();shutil.copy2(place,work/'input/MoonlitGreenhouse.rbxlx')
        pack(snapshot,work/'input/MoonlitGreenhouse_Source.zip')
        p=native/'evaluate.py';text=p.read_text(encoding='utf-8')
        text=text.replace("ROOT/'input/MoonlitGreenhouse.rbxlx'", repr(str(work/'input/MoonlitGreenhouse.rbxlx')))
        p.write_text(text,encoding='utf-8')
        code=cmd([python,p,'--prepare'],work)
        if code:raise RuntimeError('Original Moonlit preflight failed: '+str(code))
        if not args.prepare_only:
            code=cmd([python,native/'run.py'],work)
            if code:raise RuntimeError('Original Moonlit runtime failed: '+str(code))
    elif family=='skyline':
        shutil.copytree(snapshot,work/'candidate');(work/'input').mkdir(exist_ok=True)
        pack(snapshot,work/'input/SkylineSwitchyard-project.zip')
        pack(snapshot,work/'input/SkylineSwitchyard_FULL_PACKAGE.zip','SkylineSwitchyard/')
        dump(work/'candidate_sha256.json',{'files':{p.relative_to(work).as_posix():sha(p) for p in (work/'candidate').rglob('*') if p.is_file()}})
        code=cmd([python,native/'run.py','--preflight-only'] if args.prepare_only else [python,native/'run.py'],work)
        if code:raise RuntimeError('Original Skyline process returned '+str(code))
    else:raise RuntimeError('Unknown native layout family')
def find_report(work):
    names={'score.json','evaluation-report.json','current_result.json'}
    untrusted={'submission','unpacked','candidate','transport','source','input','qa_project','original'}
    choices=[p for p in work.rglob('*.json') if p.name in names and not untrusted.intersection(p.relative_to(work).parts)]
    for p in sorted(choices,key=lambda p:p.stat().st_mtime,reverse=True):
        d=read(p)
        if 'breakdown' in d or 'dimensions' in d:return p,d
    for p in sorted(work.rglob('static_results.json'))+sorted(work.rglob('static_audit.json')):
        if not untrusted.intersection(p.relative_to(work).parts):return p,{'static_report':read(p),'runtime_executed':False}
    return None,{}
def _extract_outcome_observations(raw, evidence_ref):
    obs = {}
    if not isinstance(raw, dict):
        return obs
    explicit = raw.get('outcome_observations')
    if isinstance(explicit, dict):
        for k, v in explicit.items():
            if k in ('journey', 'lifecycle', 'critical') and isinstance(v, dict):
                obs[k] = v
    checks = []
    for row in raw.get('breakdown', []) if isinstance(raw.get('breakdown'), list) else []:
        if isinstance(row, dict):
            cs = row.get('checkpoints', [])
            if isinstance(cs, dict):
                checks.extend({'id': str(k), **v} for k, v in cs.items() if isinstance(v, dict))
            elif isinstance(cs, list):
                checks.extend(v for v in cs if isinstance(v, dict))
    dims = raw.get('dimensions')
    if isinstance(dims, dict):
        for r in dims.values():
            if isinstance(r, dict):
                cs = r.get('checkpoints', [])
                if isinstance(cs, dict):
                    checks.extend({'id': str(k), **v} for k, v in cs.items() if isinstance(v, dict))
                elif isinstance(cs, list):
                    checks.extend(v for v in cs if isinstance(v, dict))
    for key in ('checkpoints', 'checks'):
        cs = raw.get(key)
        if isinstance(cs, dict):
            checks.extend({'id': str(k), **v} for k, v in cs.items() if isinstance(v, dict))
        elif isinstance(cs, list):
            checks.extend(v for v in cs if isinstance(v, dict))

    def _bit(item):
        v = item.get('status', item.get('verdict', item.get('passed')))
        if isinstance(v, bool):
            return 1 if v else 0
        s = str(v or '').strip().lower()
        if s in ('pass', 'passed', 'ok', 'true'):
            return 1
        if s in ('fail', 'failed', 'blocked_by_candidate', 'false'):
            return 0
        return None

    if 'journey' not in obs:
        j_rows = [c for c in checks if any(t in str(c.get('id', c.get('checkpoint_id', ''))).lower()
                  for t in ('complete_success', 'airlock_to_completion', 'end_to_end', 'journey', 'full_playthrough', 'complete_run'))]
        if j_rows:
            bits = [_bit(c) for c in j_rows]
            if 0 in bits:
                obs['journey'] = {'value': 0, 'evidence': [evidence_ref]}
            elif all(b == 1 for b in bits):
                obs['journey'] = {'value': 1, 'evidence': [evidence_ref]}
        elif isinstance(raw.get('journey'), bool) or raw.get('journey') in (0, 1):
            obs['journey'] = {'value': int(bool(raw['journey'])), 'evidence': [evidence_ref]}

    if 'lifecycle' not in obs:
        l_rows = [c for c in checks if any(t in str(c.get('id', c.get('checkpoint_id', ''))).lower()
                  for t in ('reopen', 'restart', 'reset', 'retry'))]
        if l_rows:
            bits = [_bit(c) for c in l_rows]
            if 0 in bits:
                obs['lifecycle'] = {'value': 0, 'evidence': [evidence_ref]}
            elif all(b == 1 for b in bits):
                obs['lifecycle'] = {'value': 1, 'evidence': [evidence_ref]}
    return obs

def export(e,out,raw,cfg,error,visual,runtime_completed=False):
    evidence=out/'evidence';evidence.mkdir(exist_ok=True)
    dump(evidence/'native-report.json',raw);shutil.copy2(e/'coverage.json',evidence/'coverage.json')
    rows=dict(raw.get('dimensions',{})) if isinstance(raw.get('dimensions',{}),dict) else {}
    if not isinstance(rows,dict):rows={}
    rows.update({r['dimension']:r for r in raw.get('breakdown',[])})
    dims={};checks=[]
    for d,maximum in MAXIMA.items():
        r=rows.get(d,{})
        if not isinstance(r,dict):r={'score':r} if type(r) in (int,float) else {}
        value=next((r[k] for k in ['score','confirmed','confirmed_score','earned'] if k in r),None)
        pending=r.get('unresolved',0) or r.get('pending',0)
        cs=r.get('checkpoints',[]);cs=list(cs.values()) if isinstance(cs,dict) else cs
        state=str(r.get('status','')).lower()
        pending=(bool(pending) or any(token in state for token in ['not_evaluated','unresolved','evaluator_error','incomplete','pending','not_run'])
                 or any(str(c.get('status','')).lower() in {'inconclusive','not_run','evaluator_error','not_evaluated'} for c in cs if isinstance(c,dict)))
        if d=='D6':value=visual;pending=visual is None
        resolved=type(value) in (int,float) and math.isfinite(value) and 0<=value<=maximum and not pending
        value=round(value,6) if resolved else value
        status='pass' if resolved and value==maximum else 'fail' if resolved and value==0 else 'partial' if resolved else 'inconclusive_evaluator' if r else 'not_run'
        refs=['evidence/native-report.json'] if r else []
        if d=='D6' and visual is not None:refs=['evidence/visual.json']
        dims[d]={'score':value if resolved else None,'max_score':maximum,'status':'complete' if resolved else 'incomplete' if r else 'not_run','evidence':refs}
        checks.append({'id':'native.'+d,'requirement_ids':[cfg['requirement_prefix']+'-GDD-1'],
          'dimension':d,'max_score':maximum,'score':value if resolved else None,'status':status,
          'reason':'Native dimension value copied; original per-checkpoint evidence retained.' if d!='D6' else 'Shared D6 protocol: supplied three-round visual result, no model inference is invented.',
          'blocked_by':[],'evidence':refs})
    unresolved=raw.get('unresolved',raw.get('unresolved_checks',[]))
    if not isinstance(unresolved,list):unresolved=[unresolved] if unresolved else []
    # An externally completed D6 stage may resolve a native D6-only pending item;
    # it cannot resolve unknown gameplay observations.
    gameplay_pending=[x for x in unresolved if not (visual is not None and isinstance(x,str) and x.startswith('D6'))]
    native_invalid=(not runtime_completed
                    or any(raw.get(k) is False for k in ['runner_valid','completed','assessment_complete','evaluation_valid','valid_score'])
                    or raw.get('score_status')=='invalid_controller_run' or bool(raw.get('host_fault')) or bool(raw.get('runner_error'))
                    or bool(gameplay_pending) or bool(raw.get('problems')) or bool(raw.get('errors'))
                    or bool(raw.get('trace_errors')) or raw.get('runtime_executed') is False)
    if cfg['family'] in {'flat','nested'}:
        native_invalid=native_invalid or raw.get('runner_valid') is not True
    final=not error and not native_invalid and all(v['status']=='complete' for v in dims.values())
    result={'schema_version':'2.1','sample_id':cfg['sample_id'],'sample_version':'1.0.0',
      'evaluator_version':'original-native-template-v2','run_id':'run-'+uuid.uuid4().hex,
      'evaluation_valid':bool(final),'classification':'scored' if final else 'infrastructure_failure' if error else 'incomplete',
      'coverage_status':'not_reviewed','reason':error or ('Original observations and shared D6 result exported to v2.' if final else 'Current original run has unresolved/unexecuted dimensions; no final total.'),
      'dimensions':dims,'checks':checks,'coverage_evidence':['evidence/coverage.json'],
      'final_score':round(sum(v['score'] for v in dims.values()),6) if final else None,'max_score':100,
      'extensions':{'native_report':'evidence/native-report.json','native_scoring_rewritten':False,
                    'existing_experiment_rerun_for_packaging':False,
                    'fresh_runtime_completed':runtime_completed}}
    sys.path.insert(0, str(e))
    from validate_score import apply_scorecard
    observations = _extract_outcome_observations(raw, 'evidence/native-report.json') if not error and not native_invalid else {}
    apply_scorecard(result, observations)
    dump(out/'score.json',result)
    return result
def main():
    e=Path(__file__).resolve().parents[1];cfg=read(e/'src/native-config.json')
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--rojo',default='rojo');p.add_argument('--luau-compile',default='luau-compile');p.add_argument('--luau',default='luau')
    p.add_argument('--visual',type=Path);p.add_argument('--source-zip',type=Path);p.add_argument('--prepare-only',action='store_true')
    args=p.parse_args();source=args.project.resolve();out=args.output.resolve()
    if not args.project.is_absolute() or not args.output.is_absolute() or out.exists() or out.is_relative_to(source) or out.is_relative_to(e.parent):p.error('Use absolute candidate and new output paths outside the sample/candidate')
    out.mkdir(parents=True);work=out/'native-workspace';work.mkdir();error=None;raw={};visual=None;runtime_completed=False
    try:
        rojo=tool(args.rojo);compiler=tool(args.luau_compile)
        luau=tool(args.luau) if cfg['family'] in {'moonlit'} else None
        native=copy_native(e,work,cfg,rojo,compiler,luau)
        snapshot,project,place=candidate_input(source,work,cfg)
        native_steps(work,native,cfg,snapshot,project,place,args)
        runtime_completed=not args.prepare_only
        report,raw=find_report(work)
        if args.visual:
            v=validate_visual(args.visual,e,source,out)
            visual=v['final_score']
    except Exception as exc:
        error=str(exc)
        report,raw=find_report(work)
    result=export(e,out,raw,cfg,error,visual,runtime_completed=runtime_completed)
    check=subprocess.run([sys.executable,str(e/'validate_score.py'),'--score',str(out/'score.json'),'--check-evidence'])
    print(out/'score.json')
    return 2 if check.returncode or error else 0 if result['evaluation_valid'] else 3
