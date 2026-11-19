"""Adversarial protocol/scorer tests; never construct deliberately broken game projects."""
import copy
import json
import math
import sys
import tempfile
import unittest
import os
import time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from schema import errors
from runtime import ROOT,TASK,load,write,inside,identity,InfrastructureError,CandidateError,classify,Observer,sha,code_identity,cleanup_verified
from score import rounded,valid_raw,score,aggregate_d6,validate_evidence
from d6 import parse,reached,select_capture

class EvaluatorTests(unittest.TestCase):
    def test_d6_recovers_existing_semantic_sword_frame(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);state=dict(id='sword',candidate_capture='sword')
            for name,attacking in [('missed',False),('active',True)]:
                write(root/(name+'.json'),dict(before=dict(provider_ready=True,game_state=dict(phase='active',player=dict(attacking=attacking)))))
            missed=dict(visible=True,context='missed.json');active=dict(visible=True,context='active.json')
            raw=dict(captures={'sword':missed,'sword-variation-2':active,'sword-variation-1':active})
            self.assertEqual(select_capture(raw,state,root)[0],'sword-variation-1')
            raw['captures']['sword']=active
            self.assertEqual(select_capture(raw,state,root)[0],'sword')
            raw['captures']={'sword':missed,'unrelated':active}
            self.assertEqual(select_capture(raw,state,root),('sword',missed))
    def test_unknown_schema_keyword_rejected(self):
        with self.assertRaises(ValueError):errors(1,{'customConstraint':True})
    def test_booleans_not_numbers_or_constants(self):
        self.assertTrue(errors(True,{'type':'number'}));self.assertTrue(errors(True,{'const':1}));self.assertTrue(errors(False,{'enum':[0]}))
    def test_nonfinite_and_duplicate_json(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'x.json'
            for text in ('{"a": NaN}','{"a": Infinity}','{"a": 1,"a": 2}'):
                p.write_text(text)
                with self.assertRaises(ValueError):load(p)
    def test_path_escape(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(InfrastructureError):inside(Path(d),'../outside')
    def test_required_schema_fields(self):
        schema=load(TASK/'input/contracts/game-state.schema.json')
        sample=dict(schema_version='2.0.0',process_token='token',process_id=1,snapshot_id=0,round_id='r',round_index=0,
            restart_count=0,monotonic_ms=0,bridge_ready=True,provider_ready=False,game_state=None)
        self.assertEqual(errors(sample,schema),[])
        for key in sample:
            broken=dict(sample);broken.pop(key);self.assertTrue(errors(broken,schema),key)
        sample['provider_ready']=True;self.assertTrue(errors(sample,schema))
    def test_nested_unknown_fields(self):
        self.assertTrue(errors({'x':1,'cheat':True},{'type':'object','properties':{'x':{'type':'integer'}},'additionalProperties':False}))
    def test_conditional_and_union(self):
        schema={'oneOf':[{'type':'number'},{'type':'integer'}]}
        self.assertTrue(errors(1,schema));self.assertFalse(errors(1.2,schema))
        schema={'if':{'const':True},'then':{'const':False},'else':{'type':'string'}}
        self.assertTrue(errors(True,schema));self.assertFalse(errors('yes',schema))
    def test_candidate_faults_not_infrastructure(self):
        for c in ['PROJECT_FILE_INVALID','PROCESS_EXITED_DURING_START','WINDOW_DISCOVERY_TIMEOUT','FIRST_FRAME_TIMEOUT','STATE_FILE_UNAVAILABLE','STATE_SCHEMA_INVALID','PROCESS_EXITED']:
            self.assertEqual(classify({'status':'fault','fault':{'code':c}}),'candidate',c)
        self.assertEqual(classify({'status':'fault','fault':{'code':'STATE_PATH_CONFLICT'}}),'infrastructure')
    def test_score_unreachable_is_numeric_zero(self):
        catalog=load(ROOT/'scoring-catalog.json')
        raw=dict(run_id='test',candidate_identity_sha256='0'*64,catalog_sha256='0'*64,checkpoints=[dict(id=c['id'],dimension=c['dimension'],verdict='unreachable',reason='MISSING') for c in catalog['checkpoints']])
        result=score(raw,catalog,{},(0,[0,0,0]))
        self.assertEqual(result['scores']['Overall'],0);self.assertTrue(all(type(v) is float for v in result['scores'].values()))
        raw['checkpoints'][0]['verdict']='pass';result=score(raw,catalog,{},(0,[0,0,0]))
        self.assertEqual(result['scores']['D1'],2);self.assertEqual(result['scores']['D2'],0)
    def test_duplicate_missing_unknown_checkpoints(self):
        catalog=load(ROOT/'scoring-catalog.json')
        raw=dict(status='collected',fault=None,cleanup_confirmed=True,catalog_sha256=sha(ROOT/'scoring-catalog.json'),gdd_sha256=sha(TASK/'input/GDD.md'),
            runtime_identity=code_identity(),checkpoints=[dict(id=c['id'],dimension=c['dimension'],verdict='fail',reason='CANDIDATE',attribution='candidate',evidence=['journeys.json']) for c in catalog['checkpoints']])
        valid_raw(raw)
        for mutation in ('duplicate','missing','unknown','null','wrong_dimension','empty_evidence'):
            b=copy.deepcopy(raw)
            if mutation=='duplicate':b['checkpoints'][-1]=b['checkpoints'][0]
            elif mutation=='missing':b['checkpoints'].pop()
            elif mutation=='unknown':b['checkpoints'][0]['id']='D7-99'
            elif mutation=='null':b['checkpoints'][0]['verdict']=None
            elif mutation=='wrong_dimension':b['checkpoints'][0]['dimension']='D6'
            else:b['checkpoints'][0].update(verdict='pass',evidence=[])
            with self.assertRaises(InfrastructureError,msg=mutation):valid_raw(b)
    def test_d6_strict_parser(self):
        labels=['Scene completeness and asset assembly','Composition and layout','Scale, hierarchy, and clarity','Style and color consistency','Overall polish']
        text='\n'.join(x+':1.5/2' for x in labels)+'\nTotal:7.5/10\nReason:Assets are complete; interface proportions differ.'
        self.assertEqual(parse(text)[0],[1.5]*5)
        for bad in (text.replace('7.5/10','8/10'),text.replace('1.5/2','1.7/2',1),text+'\nextra',text.replace('Reason:','wrong:')):
            with self.assertRaises(InfrastructureError):parse(bad)
    def test_canonical_coverage_and_dimensions(self):
        import re
        gdd=(TASK/'input/GDD.md').read_text(encoding='utf-8');section=gdd.split('## 6.',1)[1].split('## 7.',1)[0]
        ids=set(re.findall(r'\| `([A-Z]+-\d+)` \|',section));catalog=load(ROOT/'scoring-catalog.json')
        covered={r for c in catalog['checkpoints'] for r in c['requirement_ids']}
        self.assertEqual(ids,covered)
        self.assertEqual(catalog['maxima'],dict(D1=10,D2=30,D3=20,D4=20,D5=10,D6=10))
        for c in catalog['checkpoints']:self.assertEqual(c['stage'],'static' if c['dimension']=='D1' else 'dynamic')
    def test_budget_headroom(self):
        b=load(ROOT/'contracts/budget.json')
        worst=b['build_timeout_seconds']+2*b['start_rpc_timeout_seconds']+b['stop_rpc_timeout_seconds']+b['max_small_rpcs']*b['small_rpc_timeout_seconds']+b['max_captures']*(b['capture_rpc_timeout_seconds']-b['small_rpc_timeout_seconds'])+b['local_wait_budget_seconds']+b['preparation_budget_seconds']+b['cleanup_timeout_seconds']
        self.assertEqual(worst,b['declared_serial_worst_case_seconds']);self.assertEqual(b['watchdog_seconds']-worst,b['headroom_seconds']);self.assertGreater(b['headroom_seconds'],0)
    def test_rounding(self):self.assertEqual(rounded(1.25),1.3)

    def test_observer_identity_regression_staleness_and_recovery(self):
        sample=dict(schema_version='2.0.0',process_token='token',process_id=1,snapshot_id=1,round_id='r',round_index=0,
            restart_count=0,monotonic_ms=100,bridge_ready=True,provider_ready=False,game_state=None)
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);p=root/'state/game-state.json';o=Observer(root,dict(process_id=1,process_token='token'))
            write(p,sample);self.assertIsNotNone(o.read());self.assertIsNone(o.read())
            for patch in ({'process_id':2},{'process_token':'other'},{'snapshot_id':0},{'monotonic_ms':99},{'snapshot_id':2}):
                write(p,{**sample,**patch});self.assertIsNone(o.read(),patch)
            write(p,{**sample,'snapshot_id':2,'monotonic_ms':101});os.utime(p,(time.time()-4,time.time()-4))
            self.assertIsNone(o.read());write(p,{**sample,'snapshot_id':2,'monotonic_ms':101});self.assertIsNotNone(o.read())
            self.assertIn('identity',o.errors);self.assertIn('regression',o.errors);self.assertIn('stale',o.errors)

    def test_cleanup_requires_all_observed_receipts(self):
        r=dict(result=dict(process_exited=True,job_active_process_count_after_wait=0,job_handle_closed=True,input_lease_released=True))
        self.assertTrue(cleanup_verified(r))
        for k in r['result']:
            bad=copy.deepcopy(r);bad['result'].pop(k);self.assertFalse(cleanup_verified(bad))

    def test_sealed_evidence_tamper_and_escape(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);raw=dict(checkpoints=[],captures={});write(root/'raw-evaluation.json',raw)
            manifest=dict(files=[dict(path='raw-evaluation.json',sha256=sha(root/'raw-evaluation.json'))])
            write(root/'evidence-manifest.json',manifest);validate_evidence(raw,root)
            write(root/'raw-evaluation.json',{'tampered':True})
            with self.assertRaises(InfrastructureError):validate_evidence(raw,root)
            manifest['files'][0]['path']='../escape';write(root/'evidence-manifest.json',manifest)
            with self.assertRaises(InfrastructureError):validate_evidence(raw,root)

    def test_d6_missing_is_zero_but_forged_missing_rejected(self):
        manifest=load(ROOT/'d6/reference-manifest.json')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);raw={'captures':{}};p=root/'raw-evaluation.json';write(p,raw)
            data=dict(status='completed',raw_sha256=sha(p),manifest_sha256=sha(ROOT/'d6/reference-manifest.json'),
                prompt_sha256=sha(ROOT/'d6/FIXED_VLM_PROMPT.txt'),model_requested=manifest['model_requested'],rounds=[])
            for n in (1,2,3):data['rounds'].append(dict(number=n,states=[dict(id=s['id'],status='candidate_missing',criteria=[0]*5,reference_sha256=s['sha256']) for s in manifest['states']]))
            self.assertEqual(aggregate_d6(data,raw,p,root),(0,[0,0,0]))
            different_model=copy.deepcopy(data);different_model['model_requested']='different'
            self.assertEqual(aggregate_d6(different_model,raw,p,root),(0,[0,0,0]))
            for kind in ('nonzero','missing_round','unknown_state','forged_missing','unproven_broken'):
                bad=copy.deepcopy(data);candidate=copy.deepcopy(raw)
                if kind=='nonzero':bad['rounds'][0]['states'][0]['criteria'][0]=1
                elif kind=='missing_round':bad['rounds'].pop()
                elif kind=='unknown_state':bad['rounds'][0]['states'][0]['id']='other'
                elif kind=='forged_missing':
                    write(root/'context.json',{'before':{'provider_ready':True,'game_state':{'phase':'active'}}})
                    candidate['captures'][manifest['states'][0]['candidate_capture']]={'visible':True,'context':'context.json'}
                else:bad['rounds'][0]['states'][0]['status']='candidate_broken'
                with self.assertRaises(InfrastructureError,msg=kind):aggregate_d6(bad,candidate,p,root)

    def test_d6_semantic_capture_is_required(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);capture={'context':'context.json'}
            write(root/'context.json',{'before':{'provider_ready':True,'game_state':{'phase':'active','player':{'attacking':False,'grounded':True}}}})
            self.assertTrue(reached(capture,{'id':'initial'},root));self.assertFalse(reached(capture,{'id':'sword'},root));self.assertFalse(reached(capture,{'id':'airborne'},root))

    def test_navigation_preserves_art_coordinates_across_camera_scale_and_translation(self):
        from evaluate import Evaluation
        e=Evaluation.__new__(Evaluation)
        samples=[]
        for sx,tx,ty in ((.001,0,0),(.0008,.1,.05),(.0011,-.1,-.1)):
            sy=sx*1280/720
            def pos(x,y):return {'x':tx+sx*x,'y':ty+sy*y}
            ledges=[]
            for x,y in ((640,368),(576,320),(640,278)):
                ledges.append(dict(semantic_role='one_way_platform',present=True,normalized_position=pos(x+16,y+3),normalized_bounds=dict(left=tx+sx*x,right=tx+sx*(x+32),top=ty+sy*y,bottom=ty+sy*(y+6))))
            g=dict(player=dict(normalized_position=pos(249,436)),world=dict(visible_targets=ledges))
            self.assertAlmostEqual(e.xy(g)[0],249);self.assertAlmostEqual(e.xy(g)[1],436);samples.append(dict(game_state=g))
        self.assertAlmostEqual(e.position_span(samples),0)

    def test_portable_publication_redacts_without_overwriting_original(self):
        from publish_evidence import publish
        with tempfile.TemporaryDirectory() as d:
            source=Path(d)/'source';destination=Path(d)/'published'
            write(source/'raw-evaluation.json',dict(status='collected',run_id='test',candidate_identity_sha256='0'*64,captures={}))
            write(source/'receipts/1.json',{'project_path':str(source/'work/project'), 'other':r'Q:\private\session','schema_url':'https://json-schema.org/draft/2020-12/schema'})
            before=sha(source/'receipts/1.json');write(source/'captures/test.context.json',{'receipt_sha256':before})
            write(source/'work/generated.json',{'should_not_publish':True})
            publish(source,destination)
            self.assertEqual(sha(source/'receipts/1.json'),before);self.assertFalse((destination/'work').exists())
            self.assertNotIn('Q:',(destination/'receipts/1.json').read_text(encoding='utf-8'))
            self.assertEqual(load(destination/'receipts/1.json')['schema_url'],'https://json-schema.org/draft/2020-12/schema')
            self.assertEqual(load(destination/'captures/test.context.json')['receipt_sha256'],sha(destination/'receipts/1.json'))
            with self.assertRaises(InfrastructureError):publish(source,destination)

    def test_reopen_nested_forced_cleanup_is_verified(self):
        nested=dict(process_exited=True,job_active_process_count_after_wait=0,job_handle_closed=True,input_lease_released=True)
        self.assertTrue(cleanup_verified(dict(result=nested)))

if __name__=='__main__':unittest.main(verbosity=2)
