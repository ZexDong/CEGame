"""Read-only route adjudication plus write-once derived capture packaging.

No Unity/model is started. Natural input frames require the frozen author-side
semantic image review; capture success is never fabricated as service success.
Raw attempts are copied byte-for-byte, retained and hash-bound.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

EVAL=Path(__file__).resolve().parents[1]
REPO=EVAL.parents[3]
sys.path.insert(0,str(REPO/'tools/experiments'))
import session_results as shared
_spec=importlib.util.spec_from_file_location('capture_png_observer',Path(__file__).with_name('inspect-capture-png.py'))
png=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(png)

def require(value,message):
    if not value:raise ValueError(message)
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x',encoding='utf8') as stream:json.dump(data,stream,ensure_ascii=False,indent=2);stream.write('\n')
def inside(root,value):
    root=Path(root).resolve();p=Path(value);p=(p if p.is_absolute() else root/p).resolve()
    require(p!=root and p.is_relative_to(root),'Evidence path escaped its root: '+str(value))
    require(not p.is_symlink() and not getattr(p,'is_junction',lambda:False)(),'Linked evidence is not accepted')
    return p
def binding(path):return dict(path=str(path),sha256=sha(path),bytes=path.stat().st_size)

def image_gate(receipt,image):
    info=png.inspect(image)
    require(info['valid'] and (info['width'],info['height'])==(1280,720),'Missing/corrupt/wrong-resolution frame')
    require(info['all_black'] is False,'All-black frame remains unattributed observer evidence, not a product zero')
    require(receipt.get('valid') is True and receipt.get('status')=='captured' and receipt.get('classification')=='observed','Raw capture is not valid observed imagery')
    identity=receipt.get('host_identity') or {}
    require(identity.get('enabled') is True and identity.get('valid') is True and identity.get('company')==identity.get('expected_company') and
            identity.get('product')==identity.get('expected_product') and identity.get('company','').startswith('GameCreateBenchmarkTemp-') and
            Path(identity.get('persistent_path','')).resolve().is_relative_to(Path(identity.get('expected_company_root','')).resolve()),
            'Actual host company/product/persistence is not the owned identity')
    require(receipt.get('requires_author_purity_review') is True,'Native full frame must retain the uniform pixel-purity review obligation')
    require(receipt.get('sha256')==info['sha256'] and receipt.get('bytes')==info['bytes'],'Image/raw receipt binding differs')
    report=receipt.get('render_report') or {}
    require(report.get('method')=='standalone-owned-window-native-frame-v2' and report.get('valid') is True and
            report.get('observer_render_configuration_untouched') is True and receipt.get('render_configuration_restored') is True,
            'Native whole-frame observer failed or changed render configuration')
    require(report.get('editor') is False and report.get('batchmode') is False and report.get('screen_capture_at_end_of_frame') is True,
            'Frame was not captured by the normal standalone render/GUI loop')
    require(report.get('process_id')==receipt.get('process_id') and bool(report.get('request_id')) and
            report.get('end_of_frame_count',0)>=3 and report.get('imgui_repaint_count',0)>=3 and
            report.get('capture_frame',0)>report.get('start_frame',0) and
            report.get('last_imgui_repaint_frame')==report.get('capture_frame') and
            report.get('rendered_frame_capture',0)-report.get('rendered_frame_start',0)>=3,
            'No bound fresh rendered frame and same-frame GUI repaint')
    window=report.get('window') or {}
    require(window.get('valid') is True and window.get('visible') is True and window.get('minimized') is False and
            window.get('matching_window_count')==1 and window.get('process_id')==receipt['process_id'] and
            window.get('hwnd',0)>0 and window.get('window_class')=='UnityWndClass' and
            (window.get('client_width'),window.get('client_height'))==(1280,720),
            'Frame does not belong to the exact owned visible player client')
    require(receipt.get('splash_finished') is True and receipt.get('post_splash_completed_frames',0)>=3,'Display readiness is unverified')
    return info

def service_gate(receipt):
    require(receipt.get('acquisition_route')=='service_commit' and receipt.get('session_service_verified') is True and receipt.get('state_verified') is True,'No verified service commit')
    require(receipt.get('committed_public_state_sha256') and receipt.get('committed_public_state_sha256')==receipt.get('captured_public_state_sha256'),
            'Public committed state changed while rendering')
    require(bool(receipt.get('save_json')),'Verified service capture has no actual save')

def natural_gate(receipt):
    require(receipt.get('acquisition_route')=='normal_input' and receipt.get('session_service_verified') is False and receipt.get('state_verified') is False,
            'Natural route must not masquerade as service verification')
    require(receipt.get('save_json') in (None,''),'Natural route must not manufacture a save')
    require(receipt.get('input_ready_before_scene') is True and receipt.get('input_keyboard_device_id',0)>0,'Input was not ready before candidate Awake')
    actions=receipt.get('input_actions',[])
    require([action.get('action') for action in actions]==['normal-key:Enter','normal-key:R'],'Wrong frozen normal-input route')
    require(all(action.get('keyboard_device_id')==receipt['input_keyboard_device_id'] and
                action.get('completed_frame',0)>action.get('queued_frame',0)>=receipt.get('input_bootstrap_frame',0)
                for action in actions),'Normal input frame/device evidence is invalid')

def review_gate(review,receipt,receipt_path,index,after,before):
    require(review.get('schema')=='stormbound-natural-entry-review/v1','Wrong review schema')
    require(review.get('decision')=='initial_gameplay_visible','Natural picture remains menu/ambiguous; do not manufacture a zero')
    require(bool(review.get('reviewer')) and bool(review.get('reason')),'Review must identify its author and visible evidence')
    require(review.get('candidate_source_sha256')==index['source_before']['sha256'] and
            review.get('player_receipt_sha256')==sha(receipt_path) and review.get('after_png_sha256')==sha(after) and
            review.get('process_id')==receipt.get('process_id'),'Review belongs to another source/frame/process')
    expected_before=sha(before) if before and before.exists() else None
    require(review.get('before_png_sha256')==expected_before,'Review did not bind the available pre-entry picture')
    return review

def native_review_bindings(receipt,receipt_path,index,index_path,profile_path,prompt,after,before):
    report=receipt.get('render_report') or {};window=report.get('window') or {};identity=receipt.get('host_identity') or {}
    return dict(candidate_source_sha256=index['source_before']['sha256'],player_receipt_sha256=sha(receipt_path),
        after_png_sha256=sha(after),before_png_sha256=sha(before) if before.exists() else None,
        process_id=receipt['process_id'],hwnd=window['hwnd'],request_id=report['request_id'],temporary_company=identity['expected_company'],
        profile_sha256=sha(profile_path),acquisition_index_sha256=sha(index_path),review_prompt_sha256=sha(prompt))

def native_review_gate(review,expected,route):
    require(review.get('schema')=='stormbound-native-frame-review/v1','Wrong native frame review schema')
    require(all(review.get(key)==value for key,value in expected.items()),'Native review belongs to different source/image/process/window/company/policy bytes')
    require(bool(review.get('reviewer')) and bool(review.get('reason')),'Native review must name its reviewer and visible evidence')
    require(review.get('decision')=='clean_game_frame','Native frame purity is unresolved or host-contaminated; not a product zero')
    if route=='normal_input':require(review.get('normal_entry_decision')=='initial_gameplay_visible','Natural frame is still menu/ambiguous; not a product zero')
    else:require(review.get('normal_entry_decision')=='not_applicable','Service route must not claim a separate normal-input entry observation')
    return review

def host_gate(host,build,receipt,receipt_path):
    for document in (host,build):
        require(document.get('valid') is True and document.get('run_id')==receipt.get('run_id') and document.get('capture_receipt_sha256')==sha(receipt_path),'Unbound capture host/build evidence')
    for name in ('import','build','player'):
        step=host.get(name) or {}
        require(step.get('exit_code')==0 and step.get('timed_out') is False and step.get('process_id',0)>0 and build.get(name)==step,'Failed/disagreeing host stage: '+name)
    require(host['player']['process_id']==receipt.get('process_id'),'Player receipt PID differs')
    player=host['player'];lease=player.get('window_lease') or {}
    require(player.get('visible_window_required') is True and lease.get('owned_window_confirmed') is True and
            lease.get('owned_pid')==receipt.get('process_id') and lease.get('captures_desktop_pixels') is False and
            lease.get('restore_status') not in (None,'pending'),
            'Owned player-window lifecycle was not proven by the host')

def finalize(index_path,profile_path,output,review_path=None):
    output=Path(output).resolve();index_path=inside(output,index_path);profile_path=inside(REPO,profile_path)
    index=read(index_path);profile=read(profile_path);cfg=profile['d6']
    require(index.get('schema')=='stormbound-capture-acquisitions/v1','Wrong acquisition index')
    require(index.get('profile_sha256')==sha(profile_path),'Capture profile changed after raw native acquisition')
    require(index['source_unchanged'] is True and index['source_before']['sha256']==index['source_after']['sha256'],'Candidate source changed during acquisition')
    require(shared.tree_hash(Path(index['candidate']))==index['source_before']['sha256'],'Current candidate differs from the captured immutable source')
    require(index['benchmark_id']==profile['benchmark_id'],'Wrong capture benchmark')
    prompt=inside(REPO,cfg['prompt_path']);reference=inside(REPO,cfg['reference_image'])
    require(reference.is_file(),'Frozen reference is missing')
    if cfg.get('reference_sha256'):require(sha(reference)==cfg['reference_sha256'],'Frozen reference bytes changed')
    required_routes=cfg['acquisition_routes']
    require(required_routes==['service_commit','normal_input'],'Unexpected acquisition policy')
    require(cfg.get('frame_review_required') is True and cfg.get('frame_review_schema')=='stormbound-native-frame-review/v1','Uniform native review policy is not declared')
    frame_prompt=inside(REPO,cfg['frame_review_prompt_path'])
    require(sha(frame_prompt)==cfg['frame_review_prompt_sha256'],'Native review prompt bytes changed')
    chosen=None;review_binding=None;reasons=[];attempt_bindings=[]
    for attempt in index['attempts']:
        route=attempt['route'];receipt_path=inside(output,attempt['receipt'])
        host_path=inside(output,attempt['host']);build_path=inside(output,attempt['build']);host=read(host_path);build=read(build_path)
        after=inside(output,attempt['image']);before=after.with_name('00_before_normal_entry.png')
        try:receipt=read(receipt_path)
        except (ValueError,OSError) as error:
            attempt_bindings.append(dict(route=route,receipt=binding(receipt_path),host=binding(host_path),build=binding(build_path),
                player_process_id=(host.get('player') or {}).get('process_id'),classification='malformed_original_receipt'))
            reasons.append(dict(route=route,reason=str(error)));continue
        attempt_bindings.append(dict(route=route,receipt=binding(receipt_path),host=binding(host_path),build=binding(build_path),
                                     player_process_id=receipt.get('process_id') or (host.get('player') or {}).get('process_id'),classification=receipt.get('classification')))
        if route=='build_failure':
            require(not after.exists() and receipt.get('classification')=='candidate_state_unavailable' and receipt.get('status') in ('candidate_state_missing_scene','candidate_compile_failure'),
                    'A build observer failure cannot become a product zero')
            chosen=(attempt,receipt,host,build,None);break
        try:
            require(receipt.get('state')==cfg['state_id'] and receipt.get('method')==cfg['capture_method'],'Raw capture identity differs from frozen target')
            info=image_gate(receipt,after);host_gate(host,build,receipt,receipt_path)
            if route=='service_commit':service_gate(receipt)
            elif route=='normal_input':
                natural_gate(receipt)
                prior=[a for a in attempt_bindings if a['route']=='service_commit']
                require(len(prior)==1 and prior[0]['player_process_id']!=receipt['process_id'],'Natural fallback did not use a fresh independent process')
            else:raise ValueError('Undeclared acquisition route')
            expected=native_review_bindings(receipt,receipt_path,index,index_path,profile_path,frame_prompt,after,before)
            if not review_path:
                request=output/'visual/native-frame-review-request.json'
                value=dict(schema='stormbound-native-frame-review-request/v1',status='manual_review_required',acquisition_route=route,
                    review_prompt=binding(frame_prompt),review_bindings=expected,player_receipt=binding(receipt_path),after_image=binding(after),
                    before_image=binding(before) if before.exists() else None,unverified_text_candidates=receipt.get('host_identity_presentation',[]),
                    service_verified=receipt.get('session_service_verified',False),score_or_product_failure_inferred=False)
                if request.exists():require(read(request)==value,'Existing pending native review request differs; preserve both versions')
                else:write(request,value)
                return dict(status='manual_review_required',review_kind='native_frame_purity',finalized=False,request=str(request),raw_attempts=attempt_bindings)
            review_file=inside(output,review_path);review=read(review_file)
            decision=output/'visual/native-frame-review-decision.json'
            require(not decision.exists(),'A native review decision was already published; never overwrite/reselect it')
            try:
                native_review_gate(review,expected,route)
            except (ValueError,KeyError) as error:
                write(decision,dict(schema='stormbound-native-frame-review-decision/v1',accepted=False,review=binding(review_file),reason=str(error),product_zero=False))
                raise
            review_binding=dict(**binding(review_file),document=review)
            write(decision,dict(schema='stormbound-native-frame-review-decision/v1',accepted=True,review=review_binding,expected_bindings=expected,product_zero=False))
            chosen=(attempt,receipt,host,build,info);break
        except (ValueError,OSError,KeyError) as error:reasons.append(dict(route=route,reason=str(error)))
    if chosen is None:
        return dict(status='observer_or_entry_unresolved',finalized=False,reasons=reasons,raw_attempts=attempt_bindings,product_zero=False)
    attempt,receipt,host,build,info=chosen
    canonical_receipt=inside(output,cfg['capture_receipt']);canonical_host=canonical_receipt.with_name('standalone-capture-host.json');canonical_build=canonical_receipt.with_name('standalone-build-host.json')
    image=inside(output,cfg['candidate_image']);validation_path=inside(output,cfg['capture_validation']);manifest_path=inside(output,cfg['input_path'])
    provenance=canonical_receipt.with_name('capture-provenance.json');selection=canonical_receipt.with_name('acquisition-selection.json')
    for path in (canonical_receipt,canonical_host,canonical_build,image,validation_path,manifest_path,provenance,selection):require(not path.exists(),'Refusing to overwrite derived or raw capture: '+str(path))
    for source,target in ((inside(output,attempt['receipt']),canonical_receipt),(inside(output,attempt['host']),canonical_host),(inside(output,attempt['build']),canonical_build)):
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    if info:
        image.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(inside(output,attempt['image']),image)
    valid=info is not None;raw_sha=sha(canonical_receipt)
    state=dict(id=cfg['state_id'],file=image.name,valid=valid,status='captured' if valid else 'missing',capture_source=cfg['capture_method'],
               width=info['width'] if valid else 0,height=info['height'] if valid else 0,bytes=info['bytes'] if valid else 0,sha256=info['sha256'] if valid else '',
               standalone_receipt=str(canonical_receipt),standalone_receipt_sha256=raw_sha,semantic_gate_reasons=[],pixel_observation=info or {})
    write(validation_path,dict(schema_version=3,valid=valid,required_resolution=[1280,720],formal_capture_source=cfg['capture_method'],states=[state],
          acquisition_route=attempt['route'],session_service_verified=receipt.get('session_service_verified',False),native_frame_review=review_binding,
          natural_entry_review=review_binding if attempt['route']=='normal_input' else None,
          acquisition_index=binding(index_path),raw_attempts=attempt_bindings,observer_status='frame_acquired' if valid else 'attributable_build_block'))
    write(manifest_path,dict(schema_version=3,benchmark_id=profile['benchmark_id'],protocol=cfg['protocol_id'],formal_reference_ready=True,
          primary_state_id=cfg['state_id'],required_rounds=1,formal_capture_source=cfg['capture_method'],manifest_role='frozen single-state D6 input',
          formal_capture_source_applies_to='candidate_image_only',reference_capture_source=cfg.get('reference_capture_method','unclassified'),
          reference_role=cfg.get('reference_role','context; no pixel-identity requirement'),
          visual_evaluator=dict(model='gpt-5.6-sol',rounds=1,prompt_sha256=sha(prompt)),capture_validation=str(validation_path),
          states=[dict(id=cfg['state_id'],label='initial archipelago',reference=str(reference),candidate=str(image))],diagnostic_inventory=[]))
    write(selection,dict(schema='stormbound-capture-selection/v1',selected_route=attempt['route'],raw_receipt=binding(inside(output,attempt['receipt'])),
          raw_attempts=attempt_bindings,native_frame_review=review_binding,service_failures_preserved=True))
    write(provenance,dict(schema_version=1,candidate=index['candidate'],source_before=index['source_before'],source_after=index['source_after'],source_unchanged=True,
          capture_receipt_sha256=raw_sha,capture_producer_sha256=index['capture_producer_sha256'],d6_protocol_sha256=sha(inside(REPO,cfg['protocol_path'])),
          reference_capture_source=cfg.get('reference_capture_method','unclassified'),reference_sha256=sha(reference),
          d6_prompt_sha256=sha(prompt),acquisition_selection=binding(selection),native_frame_review=review_binding))
    return dict(finalized=True,status='finalized',selected_route=attempt['route'],capture_valid=valid,receipt=str(canonical_receipt),validation=str(validation_path))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('index','profile','output-root'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--review',type=Path);args=parser.parse_args()
    result=finalize(args.index,args.profile,args.output_root,args.review);print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(0 if result['finalized'] else 3)
