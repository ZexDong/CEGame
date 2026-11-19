"""Contract and failure-attribution tests; no fabricated game variants."""
import copy
import json
import math
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from runtime import ROOT,TASK,REPO,sha,load,write,inside,classify,InfrastructureError,Observer,Budget,code_identity
from score import validate_raw,rounded,validate_d6,score,REVIEW_IDS
from d6 import parse,LABELS

class Contracts(unittest.TestCase):
    def test_runtime_review_cannot_override_failed_mechanics(self):
        from review_contract import apply_verdict
        actual={'D3-01':{'verdict':'fail','reason':'keeps sliding','evidence':['states/released.json']}}
        apply_verdict(actual,'D3-01',{'pass':True,'reason':'faces rival','evidence':[]})
        self.assertEqual(actual['D3-01']['verdict'],'fail')
        actual['D3-01']['verdict']='pass'
        apply_verdict(actual,'D3-01',{'pass':False,'reason':'wrong rendered facing','evidence':[{'path':'captures/walk.png'}]})
        self.assertEqual(actual['D3-01']['verdict'],'fail')
        self.assertIn('states/released.json',actual['D3-01']['evidence'])
        actual['D5-03']={'verdict':'fail','reason':'review pending','evidence':['raw-evaluation.json']}
        apply_verdict(actual,'D5-03',{'pass':True,'reason':'observed feedback','evidence':[{'path':'captures/bolt.png'}]})
        self.assertEqual(actual['D5-03']['evidence'],['captures/bolt.png'])

    def test_runtime_review_rejects_blanket_and_false_human_authority(self):
        from review_contract import validate_review,REVISION
        good={'review_revision':REVISION,'reviewer':{'kind':'agent_runtime_evidence_audit','identity':'test'},
              'method':'runtime_evidence_audit','blanket_approval':False,'checks':{}}
        for mutation in ('legacy','authority','blanket','human'):
            bad=copy.deepcopy(good)
            if mutation=='legacy':bad.pop('review_revision')
            if mutation=='authority':bad['review_authority']={'policy':'approve all'}
            if mutation=='blanket':bad['blanket_approval']=True
            if mutation=='human':bad['method']='human_normal_input_capture_review'
            with self.subTest(mutation=mutation),self.assertRaises(InfrastructureError):
                validate_review(bad,{},Path('.'))

    def test_runtime_review_requires_action_frames_and_linked_context(self):
        from review_contract import validate_review,REVISION,CAPTURES,SUBCLAUSES
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);write(root/'receipts/input.json',{'op':'press','key':'K'})
            receipt=sha(root/'receipts/input.json');captures={};evidence=[]
            for name in CAPTURES['D5-03']:
                context='captures/'+name+'.context.json';write(root/context,{'receipt_sha256':receipt})
                captures[name]={'path':'captures/'+name+'.png','context':context}
                evidence.extend([{'path':captures[name]['path']},{'path':context}])
            evidence.extend([{'path':'states/action.json'},{'path':'receipts/input.json'}])
            raw={'captures':captures,'evidence_sha256':{'receipts/input.json':receipt}}
            review={'review_revision':REVISION,'reviewer':{'kind':'human','identity':'test'},
                'method':'human_normal_input_capture_review','blanket_approval':False,
                'checks':{'D5-03':{'pass':True,'observations':['Observed transitions.'],'evidence':evidence,
                    'clause_observations':{key:{'pass':True,'observation':'Fixture observation',
                        'evidence':['states/action.json']} for key in SUBCLAUSES['D5-03']}}}}
            validate_review(review,raw,root)
            for missing in ('captures/bolt-cast.png','captures/bolt-cast.context.json','receipts/input.json','states/action.json'):
                bad=copy.deepcopy(review)
                bad['checks']['D5-03']['evidence']=[e for e in evidence if e['path']!=missing]
                with self.subTest(missing=missing),self.assertRaises(InfrastructureError):validate_review(bad,raw,root)
            write(root/'captures/bolt-cast.context.json',{'receipt_sha256':'unrelated'})
            with self.assertRaises(InfrastructureError):validate_review(review,raw,root)

    def test_fresh_state_rejects_nonempty_feedback_without_mutation(self):
        from atomic import fresh
        g={'phase':'active','player':{'health':100,'grounded':True,'action_state':'idle'},
            'rival':{'health':100,'action_state':'idle'},'combat':{'bolt_ready':True,'active_player_projectiles':0,'telegraph_active':False},
            'feedback':{'result_text':'','status_text':'FIGHT!','hit_feedback_visible':False,'guard_feedback_visible':False,'result_visible':False}}
        before=copy.deepcopy(g)
        self.assertFalse(fresh(g));self.assertEqual(g,before)
        g['feedback']['status_text']=''
        self.assertTrue(fresh(g))
        for value in ('FIGHT!', 'WHIFF'):
            bad=copy.deepcopy(g);bad['feedback']['status_text']=value;self.assertFalse(fresh(bad))
        bad=copy.deepcopy(g);bad['player']['action_state']='blocking';self.assertFalse(fresh(bad))

    def test_restart_cadence_uses_remaining_timer_not_late_sample_time(self):
        from reconcile import reconcile
        def fresh_state():
            return {'game_state':{'phase':'active','player':{'health':100,'grounded':True,'action_state':'idle'},
                'rival':{'health':100,'action_state':'idle'},'combat':{'bolt_ready':True,'active_player_projectiles':0,'telegraph_active':False},
                'feedback':{'result_text':'','status_text':''}}}
        for remaining,expected in ((505,True),(750,False)):
            with self.subTest(remaining=remaining),tempfile.TemporaryDirectory() as t:
                root=Path(t);index={}
                names=['restart-dirty','restart-in-flight','repeat-restart','restart-telegraph','restart-from-telegraph',
                       'restart-old-event-window','cancelled-pulse','fresh-cadence','player-win-restart','rival-win-restart']
                for name in names:
                    state=fresh_state()
                    if name=='restart-dirty':state['game_state']['player']['grounded']=False
                    if name=='fresh-cadence':state['game_state']['combat'].update(telegraph_active=True,round_time_ms=3245,telegraph_remaining_ms=remaining)
                    rel='states/'+name+'.json';write(root/rel,{'samples':[state]});index[rel]=sha(root/rel)
                actual={'D3-02':{'verdict':'unreachable'},'D3-10':{'verdict':'unreachable'},
                    'D4-04':{'verdict':'fail','reason':'ACTIVE_AND_TERMINAL_RESTART_CLEAR_STATE'}}
                raw={'evidence_sha256':index,'facts':{k:True for k in ('restart_available','player-win_restart','rival-win_restart')}}
                self.assertEqual(bool(reconcile(actual,raw,root)),expected)

    def test_checkpoint_repair_rejects_tampered_evidence_and_candidate(self):
        from reconcile import reconcile
        for corruption in (None,'evidence','candidate'):
            with self.subTest(corruption=corruption),tempfile.TemporaryDirectory() as t:
                root=Path(t);rel='bolt-repair/states/bolt.json';write(root/rel,{'samples':[]})
                raw={'candidate_identity_sha256':'candidate','evidence_sha256':{},'faults':[]};write(root/'raw-evaluation.json',raw)
                actual={'D3-02':{'verdict':'unreachable'},'D3-10':{'verdict':'unreachable'}}
                rows=[]
                for key,dim in (('D2-05','D2'),('D3-04','D3'),('D3-05','D3')):
                    actual[key]={'checkpoint_id':key,'dimension':dim,'verdict':'fail','reason':'prior'}
                    rows.append({'checkpoint_id':key,'dimension':dim,'verdict':'pass','reason':'recollected','evidence':[rel]})
                repair={'source_raw_sha256':sha(root/'raw-evaluation.json'),'candidate_identity_sha256':'candidate',
                    'collector_identity':code_identity(),'adapter':'scripts/repair_bolt.py','adapter_sha256':sha(ROOT/'scripts/repair_bolt.py'),
                    'checkpoints':rows,'evidence_sha256':{rel:sha(root/rel)}}
                if corruption=='candidate':repair['candidate_identity_sha256']='different'
                write(root/'checkpoint-repair.json',repair)
                if corruption=='evidence':write(root/rel,{'changed':True})
                if corruption:
                    with self.assertRaises(InfrastructureError):reconcile(actual,raw,root)
                else:self.assertEqual(len(reconcile(actual,raw,root)),3)

    def test_observer_fallback_preserves_independent_checks_and_binds_cause(self):
        from unittest.mock import patch
        import collect_with_observer_fallback as fallback
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);origin=root/'failed';target=root/'recovered'
            write(origin/'raw-evaluation.json',{'candidate_identity_sha256':'candidate','run_id':'failed'})
            write(origin/'receipts/0001-start.json',{'fault':{'code':'first_frame_state_timeout'}})
            write(origin/'state/engine-health.json',{'ready':True})
            class Collector:
                def __init__(self,args):self.args=args
                def run(self):
                    write(self.args.output/'raw-evaluation.json',{'candidate_identity_sha256':'candidate','faults':[],
                        'evidence_sha256':{},'checkpoints':[
                            {'checkpoint_id':'D1-03','verdict':'pass','evidence':['captures/initial.png']},
                            {'checkpoint_id':'D1-04','verdict':'pass','evidence':['states/initial.json']}]})
                    return 0
            argv=['fallback','--project',str(root/'project'),'--engine',str(root/'engine'),'--pwsh',str(root/'pwsh'),
                  '--output',str(target),'--failed-run',str(origin),'--run-id','recovered','--candidate-id','candidate']
            with patch.object(sys,'argv',argv),patch.object(fallback.evaluate,'Evaluation',Collector),patch.object(fallback.evaluate,'Player'),self.assertRaises(SystemExit) as exit:
                fallback.main()
            self.assertEqual(exit.exception.code,0)
            raw=load(target/'raw-evaluation.json')
            self.assertEqual([c['verdict'] for c in raw['checkpoints']],['pass','fail'])
            self.assertEqual(raw['evidence_sha256']['bridge-failure.json'],sha(target/'bridge-failure.json'))
            self.assertEqual(raw['diagnostic_adapter']['sha256'],sha(ROOT/'scripts/collect_with_observer_fallback.py'))

    def test_jump_reconciliation_does_not_excuse_a_longer_second_jump(self):
        from reconcile import reconcile
        def state(ms,grounded):
            return {'game_state':{'combat':{'round_time_ms':ms},'player':{'grounded':grounded,'normalized_position':{'y':.6}}}}
        for landing,expected in ((1000,True),(1500,False)):
            with self.subTest(landing=landing),tempfile.TemporaryDirectory() as t:
                root=Path(t);index={}
                data={'control-airborne':[state(500,False)],'control-landed':[state(1000,True)],
                      'airborne':[state(500,False)],'jump-before-second':[],
                      'jump-arc':[state(750,False)],'landed':[state(landing,True)]}
                for name,seq in data.items():
                    rel='states/'+name+'.json';write(root/rel,{'samples':seq});index[rel]=sha(root/rel)
                actual={'D3-02':{'verdict':'fail','reason':'AIRBORNE_INPUT_PRESERVES_CONTROL_ARC'},'D3-10':{'verdict':'unreachable'}}
                corrections=reconcile(actual,{'evidence_sha256':index},root)
                self.assertEqual(bool(corrections),expected)

    def test_jump_landing_seen_during_capture_is_not_late_landing(self):
        from reconcile import reconcile
        def state(ms,grounded,y=.8):
            return {'game_state':{'combat':{'round_time_ms':ms},
                'player':{'grounded':grounded,'normalized_position':{'y':y}}}}
        for delay,peak,expected in ((0,.67,True),(500,.67,False),(0,.4,False)):
            with self.subTest(delay=delay,peak=peak),tempfile.TemporaryDirectory() as t:
                root=Path(t);index={}
                data={'control-airborne':[state(585,False,.66)],
                    'control-landed':[state(837,False,.67),state(1088,True),state(1341,True)],
                    'airborne':[state(608,False,.66)],'jump-before-second':[],
                    'jump-arc':[state(860,False,peak),state(1111+delay,True)],
                    'landed':[state(1362+delay,True),state(1613+delay,True)]}
                for name,seq in data.items():
                    rel='states/'+name+'.json';write(root/rel,{'samples':seq});index[rel]=sha(root/rel)
                actual={'D3-02':{'verdict':'fail','reason':'AIRBORNE_INPUT_PRESERVES_CONTROL_ARC'},
                    'D3-10':{'verdict':'unreachable'}}
                self.assertEqual(bool(reconcile(actual,{'evidence_sha256':index},root)),expected)

    def test_terminal_reconciliation_accepts_frozen_pose_but_not_new_damage(self):
        from reconcile import reconcile
        def state(ms,health,phase):
            return {'monotonic_ms':ms,'game_state':{'phase':phase,'combat':{'round_time_ms':1000,'active_player_projectiles':0,'telegraph_active':False},
                'player':{'health':health,'action_state':'light_attack','normalized_position':{'x':.5,'y':.6}},
                'rival':{'health':0},'feedback':{'result_text':'PLAYER WINS'},
                'world':{'object_counts':{'player_fighters':1,'rival_fighters':1}}}}
        for health,expected in ((80,True),(60,False)):
            with self.subTest(health=health),tempfile.TemporaryDirectory() as t:
                root=Path(t);index={}
                for name,phase in (('player-win','player_won'),('rival-win','rival_won')):
                    for suffix,seq in (('',[state(1000,80,phase)]),('-lock',[state(4600,health,phase)])):
                        rel='states/'+name+suffix+'.json';write(root/rel,{'samples':seq});index[rel]=sha(root/rel)
                actual={'D3-02':{'verdict':'unreachable'},'D3-10':{'verdict':'fail','reason':'BOTH_TERMINALS_REJECT_INPUT_AND_OLD_CADENCE'}}
                self.assertEqual(bool(reconcile(actual,{'evidence_sha256':index},root)),expected)

    def test_boundary_accepts_public_250ms_cadence_without_accepting_motion(self):
        from types import SimpleNamespace
        from evaluate import Evaluation
        for cadence,moving,expected in ((25,False,True),(250,False,True),(250,True,False)):
            with self.subTest(cadence=cadence,moving=moving), tempfile.TemporaryDirectory() as t:
                runner=Evaluation.__new__(Evaluation);runner.root=Path(t)
                runner.o=SimpleNamespace(last={'game_state':{'player':{'normalized_position':{'x':.2}}}})
                def wait(name,predicate,timeout,stable):
                    rows=[];matched=0;found=None
                    for ms in range(cadence,int(timeout*1000)+1,cadence):
                        x=.2+ms/10000 if moving else min(.6,.2+ms/2500)
                        state={'combat':{'round_time_ms':ms},'player':{'normalized_position':{'x':x},'action_state':'moving'}}
                        rows.append({'game_state':state})
                        matched=matched+1 if predicate(state) else 0
                        if matched>=stable:found=rows[-1];break
                    write(runner.root/'states'/f'{name}.json',{'samples':rows})
                    return found
                runner.wait=wait
                self.assertEqual(bool(runner.boundary('boundary')),expected)

    def test_existing_http_provider_requires_explicit_recorded_opt_in(self):
        from visual import configured, digest
        config={'provider':'existing-provider','model':'vision-model','model_version':'alias',
                'base_url':'http://provider.example/v1'}
        with self.assertRaisesRegex(InfrastructureError,'VLM_ENDPOINT_REQUIRES_TLS'):
            configured(config)
        approved=configured({**config,'allow_configured_http':True})
        self.assertEqual(approved['transport_policy'],'explicit_existing_provider_http')
        self.assertNotEqual(digest(approved),digest({k:v for k,v in approved.items() if k!='transport_policy'}))
        for invalid in ('true',1,None):
            with self.assertRaisesRegex(InfrastructureError,'VLM_TRANSPORT_POLICY_INVALID'):
                configured({**config,'allow_configured_http':invalid})
        with self.assertRaises(InfrastructureError):
            configured({**config,'base_url':'ftp://provider.example/v1','allow_configured_http':True})

    def raw(self):
        c=load(ROOT/'catalog/checkpoints.json')
        return {'schema_version':'3.0.0','scoring_contract_sha256':sha(ROOT/'contracts/scoring-contract.json'),'status':'completed','faults':[],'catalog_sha256':sha(ROOT/'catalog/checkpoints.json'),
            'input_gdd_sha256':sha(TASK/'input/GDD.md'),'checkpoints':[{'checkpoint_id':x['id'],'dimension':x['dimension'],'verdict':'unreachable'} for x in c['checkpoints']]}

    def test_coverage_is_exact(self):
        import re
        section=(TASK/'input/GDD.md').read_text(encoding='utf-8').split('\n## 6.')[1].split('\n## 7.')[0]
        ids=set(re.findall(r'\b[A-Z]+-\d{2}\b',section))
        catalog=load(ROOT/'catalog/checkpoints.json')
        mapped={r for c in catalog['checkpoints'] for r in c['source_ids']}
        self.assertEqual(ids,mapped)
        self.assertEqual(len(ids),24)
        self.assertEqual(len(catalog['checkpoints']),36)
        for c in catalog['checkpoints']:
            self.assertEqual(c['stage'],'static' if c['dimension']=='D1' else 'dynamic')

    def test_dimension_spoof_rejected(self):
        raw=self.raw();raw['checkpoints'][0]['dimension']='D2'
        with self.assertRaises(InfrastructureError):validate_raw(raw)

    def test_duplicates_missing_unknown_rejected(self):
        for kind in ('duplicate','missing','unknown'):
            r=self.raw()
            if kind=='duplicate':r['checkpoints'].append(r['checkpoints'][0])
            if kind=='missing':r['checkpoints'].pop()
            if kind=='unknown':r['checkpoints'][0]['checkpoint_id']='D1-99'
            with self.subTest(kind=kind),self.assertRaises(InfrastructureError):validate_raw(r)

    def test_candidate_failure_not_null(self):
        self.assertEqual(len(validate_raw(self.raw())),36)
        r=self.raw();r['checkpoints'][0]['verdict']=None
        with self.assertRaises(InfrastructureError):validate_raw(r)
        for code in ('PROJECT_FILE_INVALID','PROCESS_EXITED_DURING_START','FIRST_FRAME_STATE_TIMEOUT','stop_grace_timeout'):
            self.assertEqual(classify({'status':'environment_fault','fault':{'code':code}}),'candidate')
        self.assertEqual(classify({'status':'executor_fault','fault':{'code':'ACTIVE_INPUT_SESSION_EXISTS'}}),'infrastructure')

    def test_infrastructure_partial_score_rejected(self):
        r=self.raw();r['faults']=[{'domain':'infrastructure'}]
        with self.assertRaises(InfrastructureError):validate_raw(r)

    def test_stale_contract_rejected(self):
        r=self.raw();r['catalog_sha256']='0'*64
        with self.assertRaises(InfrastructureError):validate_raw(r)

    def test_paths_cannot_escape(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(InfrastructureError):inside(Path(tmp),'../another-run/image.png')

    def test_fixed_prompt_matches_authorized_task_rubric(self):
        import re
        from visual import protocol
        g=(ROOT/'d6/VISUAL_RUBRIC_3_2.md').read_text(encoding='utf-8')
        p=re.search(r'```text\n(.*?)\n```',g,re.S)[1]+'\n'
        self.assertEqual(p,(ROOT/'d6/FIXED_VLM_PROMPT.txt').read_text(encoding='utf-8'))
        self.assertEqual(protocol()['protocol'],'nightsky-visual-3.2.0')

    def test_d6_rejects_old_labels_and_changed_rubric_binding(self):
        from unittest.mock import patch
        import visual
        old=['Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish']
        text='\n'.join(l+':1/2' for l in old)+'\nTotal:5/10\nReason:Old rubric.'
        with self.assertRaises(InfrastructureError):parse(text)
        manifest=load(ROOT/'d6/d6-reference-manifest.json')
        contract=load(ROOT/'d6/protocol.json')
        for field in ('rubric_sha256','revision'):
            bad=copy.deepcopy(contract);bad[field]='invalid'
            with patch.object(visual,'load',side_effect=lambda p:bad if p.name=='protocol.json' else manifest):
                with self.assertRaises(InfrastructureError):visual.protocol()

    def test_d6_parser_rejects_invented_values_or_sum(self):
        text='\n'.join(l+':1.5/2' for l in LABELS)+'\nTotal:7.5/10\nReason:Visible differences.'
        self.assertEqual(sum(parse(text)[0]),7.5)
        for invalid in (text.replace('7.5/10','8/10'),text.replace('1.5/2','1.4/2',1),text+'\nextra'):
            with self.assertRaises(InfrastructureError):parse(invalid)

    def test_reference_bytes_and_order(self):
        m=load(ROOT/'d6/d6-reference-manifest.json')
        self.assertEqual(len(m['states']),3)
        self.assertEqual(len({s['id'] for s in m['states']}),3)
        for state in m['states']:self.assertEqual(sha(ROOT/'d6'/state['reference']),state['sha256'])

    def test_rounding_at_final_boundary(self):
        self.assertEqual(rounded(7.25),7.3)

    def test_budget_has_headroom(self):
        b=load(ROOT/'contracts/budget.json')
        total=b['build_timeout_seconds']+b['max_start_rpcs']*b['start_rpc_timeout_seconds']+b['max_stop_rpcs']*b['stop_rpc_timeout_seconds']+b['cleanup_timeout_seconds']+b['local_wait_budget_seconds']+b['preparation_budget_seconds']+b['max_small_rpcs']*b['small_rpc_timeout_seconds']
        self.assertEqual(b['declared_serial_worst_case_seconds'],total)
        self.assertGreaterEqual(b['watchdog_seconds'],b['declared_serial_worst_case_seconds']+b['headroom_seconds'])

    def test_budget_is_enforced(self):
        b=Budget(clock=lambda:0)
        b.reserve_wait(b.contract['local_wait_budget_seconds'])
        with self.assertRaises(InfrastructureError):b.reserve_wait(.1)
        b=Budget(clock=lambda:0)
        for _ in range(b.contract['max_small_rpcs']):b.rpc_timeout('press')
        with self.assertRaises(InfrastructureError):b.rpc_timeout('capture')
        b.expired=True
        with self.assertRaises(InfrastructureError):b.check()

    def snapshot(self,root):
        s={'schema_version':'1.0.0','process_id':7,'process_token':'test-token','snapshot_id':1,
            'monotonic_ms':100,'round_id':'test-round','round_index':0,'restart_count':0,
            'bridge_ready':True,'provider_ready':False,'game_state':None}
        write(root/'state/duel-state.json',s);return s

    def test_observer_stale_regression_and_identity_rejected(self):
        import os,time
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);s=self.snapshot(root);o=Observer(root,{'process_id':7,'process_token':'test-token'})
            self.assertIsNotNone(o.read())
            for field,value in (('snapshot_id',0),('process_id',8),('monotonic_ms',99)):
                bad={**s,field:value};write(root/'state/duel-state.json',bad)
                self.assertIsNone(o.read())
            write(root/'state/duel-state.json',{**s,'snapshot_id':2,'monotonic_ms':200})
            os.utime(root/'state/duel-state.json',(time.time()-3,time.time()-3))
            self.assertIsNone(o.read());self.assertIn('stale',o.errors)

    def test_observer_atomic_swap_is_not_persistent_fault(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);o=Observer(root,{'process_id':7,'process_token':'test-token'})
            self.assertIsNone(o.read());self.assertFalse(o.errors)
            self.snapshot(root);self.assertIsNotNone(o.read());self.assertFalse(o.errors)

    def test_malformed_gameplay_field_does_not_erase_valid_independent_state(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);s=self.snapshot(root);s.update(provider_ready=True,game_state={'player':{'health':'bad'},'phase':'active'})
            write(root/'state/duel-state.json',s);o=Observer(root,{'process_id':7,'process_token':'test-token'})
            self.assertEqual(o.read()['game_state']['phase'],'active');self.assertTrue(o.errors)


    def evidence(self,root,visible=False):
        from PIL import Image,ImageDraw
        raw=self.raw()
        raw.update(run_id='fixture',candidate_id='fixture',candidate_identity_sha256='1'*64,
            evaluator_identity=code_identity(),captures={},budget={},faults=[] if visible else [{'domain':'candidate','code':'CANDIDATE_PROJECT_MISSING'}])
        write(root/'candidate-manifest.json',{'fixture_only':True})
        if visible:
            im=Image.new('RGB',(1280,720),(50,90,170));ImageDraw.Draw(im).rectangle((10,10,600,700),fill=(180,40,50))
            im.save(root/'candidate.png');write(root/'context.json',{'fixture_only':True})
            capture={'path':'candidate.png','sha256':sha(root/'candidate.png'),'visible':True,'width':1280,'height':720,'state_reached':True,'context':'context.json'}
            raw['captures']={state['candidate_capture']:copy.deepcopy(capture) for state in load(ROOT/'d6/d6-reference-manifest.json')['states']}
        for c in raw['checkpoints']:c.update(reason='EVIDENCE_FIXTURE_UNREACHABLE',evidence=['candidate-manifest.json'])
        raw['evidence_sha256']={p.name:sha(p) for p in root.iterdir() if p.is_file()}
        write(root/'raw.json',raw)
        return raw

    def config(self):
        return {'provider':'fixture-provider','model':'fixture-model','model_version':'test-1',
            'base_url':'https://example.invalid/v1','parameters':{'temperature':0},'image_detail':'high','timeout_seconds':30}

    def response(self,score=1,model='fixture-model-returned'):
        body='\n'.join(label+':'+str(score)+'/2' for label in LABELS)+'\nTotal:'+str(score*5)+'/10\nReason:Visible fixture differences.'
        return {'model':model,'choices':[{'message':{'content':body}}]}

    def test_candidate_missing_is_six_numeric_scores_without_manual_review_or_vlm(self):
        from d6 import run
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);raw=self.evidence(root)
            result=run(root/'raw.json',{},root/'d6.json',call=lambda *_:self.fail('No VLM for unreachable states'))
            self.assertEqual(validate_d6(result,raw,root),[0,0,0])
            scored=score(root/'raw.json',None,root/'d6.json')
            from jsonschema import Draft202012Validator
            Draft202012Validator(load(ROOT/'schemas/evaluation-result.schema.json')).validate(scored)
            Draft202012Validator(load(ROOT/'d6/d6-run.schema.json')).validate(result)
            self.assertEqual(scored['dimensions'],dict(D1=0,D2=0,D3=0,D4=0,D5=0,D6=0))
            self.assertEqual(scored['overall'],0)
            write(root/'candidate-manifest.json',{'altered':True})
            with self.assertRaises(InfrastructureError):score(root/'raw.json',None,root/'d6.json')

    def test_missing_capture_without_candidate_failure_is_invalid(self):
        from visual import candidate_status
        state=load(ROOT/'d6/d6-reference-manifest.json')['states'][0]
        with self.assertRaises(InfrastructureError):candidate_status({'captures':{},'faults':[]},Path('.'),state)

    def test_three_round_requests_parse_and_configuration_are_bound(self):
        from d6 import run
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);raw=self.evidence(root,True);calls=[]
            def call(payload,config):
                calls.append(payload)
                self.assertEqual(payload['temperature'],0)
                self.assertEqual(len(payload['messages'][0]['content']),3)
                return self.response(.5 if len(calls)<=3 else 1 if len(calls)<=6 else 1.5)
            result=run(root/'raw.json',self.config(),root/'d6.json',call)
            self.assertEqual(len(calls),9)
            self.assertEqual(validate_d6(result,raw,root),[2.5,5,7.5])
            for mutation in ('round','state','nan','model','parameters','capability','criteria','request','parser','image','reuse'):
                bad=copy.deepcopy(result);entry=bad['rounds'][0]['states'][0]
                if mutation=='round':bad['rounds'].pop()
                if mutation=='state':bad['rounds'][0]['states'].reverse()
                if mutation=='nan':entry['criteria'][0]=float('nan')
                if mutation=='model':bad['model_returned']='another'
                if mutation=='parameters':bad['model_config']['parameters']['temperature']=1
                if mutation=='capability':bad['capability_receipt']=None
                if mutation=='criteria':entry['criteria'][0]=2
                if mutation=='image':entry['candidate_sha256']='0'*64
                if mutation=='reuse':bad['rounds'][1]['states'][0]=copy.deepcopy(entry)
                if mutation in ('request','parser'):
                    data=load(root/entry[mutation]['path']);data['prompt' if mutation=='request' else 'reason']='changed'
                    path='tampered-'+mutation+'.json';write(root/path,data);entry[mutation]={'path':path,'sha256':sha(root/path)}
                with self.subTest(mutation=mutation),self.assertRaises(InfrastructureError):validate_d6(bad,raw,root)

    def test_black_and_broken_states_zero_with_evidence(self):
        from d6 import run
        from PIL import Image
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);raw=self.evidence(root,True)
            Image.new('RGB',(1280,720)).save(root/'black.png')
            c=next(iter(raw['captures'].values()));c.update(path='black.png',sha256=sha(root/'black.png'),visible=False)
            other=list(raw['captures'].values())[1]
            write(root/'review.json',{'method':'human_capture_review','candidate_sha256':other['sha256'],
                'status':'candidate_broken','reason':'Evidence fixture: severely broken frame.'})
            other['visual_failure_review']={'path':'review.json','sha256':sha(root/'review.json')}
            raw['evidence_sha256'].update({'black.png':sha(root/'black.png'),'review.json':sha(root/'review.json')})
            write(root/'raw.json',raw)
            result=run(root/'raw.json',self.config(),root/'d6.json',lambda *_:self.response())
            self.assertEqual(validate_d6(result,raw,root),[5/3]*3)
            for row in result['rounds']:self.assertEqual([e['status'] for e in row['states']],['candidate_black','candidate_broken','compared'])
            (root/'black.png').unlink()
            with self.assertRaises(InfrastructureError):validate_d6(result,raw,root)

    def test_vlm_failure_or_model_switch_never_becomes_zero(self):
        from d6 import run
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);self.evidence(root,True)
            count=[0]
            def changed(*_):
                count[0]+=1
                return self.response(model='model-'+str(count[0]))
            with self.assertRaises(InfrastructureError):run(root/'raw.json',self.config(),root/'out.json',changed)
            self.assertFalse((root/'out.json').exists())

    def test_cases_are_independent_and_bounded(self):
        from coverage_cases import CoverageCases as AtomicCases
        rows=load(ROOT/'catalog/trajectories.json')['trajectories']
        self.assertEqual(len({c['id'] for c in rows}),len(rows))
        for c in rows:
            self.assertEqual(c['clean_start'],'fresh_process');self.assertEqual(c['setup_method'],'normal_input')
            self.assertFalse(c['allowed_writes']);self.assertTrue(hasattr(AtomicCases,c['method']))
            self.assertGreaterEqual(c['max_serial_seconds'],c['max_wait_seconds'])
        self.assertEqual([c['stage'] for c in rows][-3:],['visual']*3)

    def test_failed_case_does_not_require_restart_or_suppress_next_case(self):
        from types import SimpleNamespace
        from evaluate import Evaluation
        from runtime import CandidateError
        class Transport:
            serial=0;session=None
            def __init__(self):self.calls=[]
            def call(self,op,**kwargs):
                self.serial+=1;self.calls.append(op)
                self.session={'process_id':self.serial} if op=='start' else None
            def begin_case(self,case):pass
            def end_case(self):return {'actions':0}
        with tempfile.TemporaryDirectory() as t:
            root=Path(t)
            e=Evaluation(SimpleNamespace(output=root,engine=root))
            e.project=root/'fixture.uproject';e.p=Transport();e.o=SimpleNamespace(bind=lambda s:None)
            e.active=lambda _:dict(process_id=e.p.serial,process_token='fixture',round_id='fixture-round',snapshot_id=1)
            def broken():raise CandidateError('FIXTURE_CANDIDATE_ACTION_FAILED')
            e.broken=broken;e.healthy=lambda:e.mark('D2-03',True,'INDEPENDENT_ACTION','fixture.json')
            e.isolated(dict(id='failed',method='broken',checkpoint_ids=['D2-02']))
            e.isolated(dict(id='later',method='healthy',checkpoint_ids=['D2-03']))
            self.assertEqual(e.verdicts['D2-02']['verdict'],'unreachable')
            self.assertEqual(e.verdicts['D2-03']['verdict'],'pass')
            self.assertEqual(e.p.calls,['start','stop','start','stop'])
            self.assertEqual(e.faults[0]['affected_checkpoint_ids'],['D2-02'])

    def test_function_presence_is_independent_of_wrong_damage(self):
        from coverage_cases import CoverageCases as AtomicCases
        class Case(AtomicCases):
            def __init__(self):self.facts={'whiff':True};self.results={}
            def approach(self,_):return {'game_state':{'rival':{'health':100}}}
            def press(self,_):pass
            def cap(self,_):pass
            def wait(self,*_):return {'game_state':{'rival':{'health':76}}}
            def check(self,id,passed,*_):self.results[id]=bool(passed)
            def available_states(self,*_):return []
        from types import SimpleNamespace
        c=Case();c.o=SimpleNamespace(window=lambda *_:[{'game_state':{'rival':{'health':76}}}])
        c.strike();c.aggregate_rules()
        self.assertTrue(c.results['D2-04'])
        self.assertFalse(c.results['D3-03'])

    def test_restart_availability_does_not_require_correct_reset_health(self):
        from types import SimpleNamespace
        from evaluate import Evaluation
        from runtime import CandidateError
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);e=Evaluation(SimpleNamespace(output=root,engine=root))
            e.o=SimpleNamespace(last={'round_id':'before'})
            e.press=lambda key:None
            def observe(name,*_args,**_kwargs):
                write(root/'states'/(name+'.json'),{'samples':[{'round_id':'after','game_state':{'phase':'active','player':{'health':75}}}]})
                return None
            e.wait=observe
            with self.assertRaises(CandidateError):e.restart('reset-health-failure')
            self.assertTrue(e.facts['restart_available'])

    def test_visual_protocol_accepts_only_three_to_five_unique_states(self):
        from unittest.mock import patch
        import visual
        manifest=load(ROOT/'d6/d6-reference-manifest.json')
        contract=load(ROOT/'d6/protocol.json')
        for count in (2,3,4,5,6):
            m=copy.deepcopy(manifest)
            m['states']=[{**manifest['states'][i%3],'id':'state-'+str(i)} for i in range(count)]
            def fixture_load(path):return contract if path.name=='protocol.json' else m
            with patch.object(visual,'load',side_effect=fixture_load):
                if 3<=count<=5:self.assertEqual(len(visual.protocol()['states']),count)
                else:
                    with self.assertRaises(InfrastructureError):visual.protocol()

    def test_score_rejects_unindexed_positive_evidence(self):
        from d6 import run
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);raw=self.evidence(root)
            write(root/'foreign.json',{'not_collected':True})
            raw['checkpoints'][0].update(verdict='pass',evidence=['foreign.json'])
            write(root/'raw.json',raw);run(root/'raw.json',{},root/'d6.json',lambda *_:self.fail())
            with self.assertRaises(InfrastructureError):score(root/'raw.json',None,root/'d6.json')

if __name__=='__main__':unittest.main()
