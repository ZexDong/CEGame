"""Host-only contract tests; no altered game or alternative reference project."""
import copy,json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import d6,score,support
from cases import NORMAL,FIXTURES,melee_damage_events,melee_damage_intervals
from catalog import CHECKS
from spec import REQUIREMENTS,ENEMIES,TOWERS,WAVES

VALID='\n'.join(label+':1.5/2' for label in d6.LABELS)+'\nTotal:7.5/10\nReason:Visible objects are complete; shadows are heavy.\n'

class DialogueTests(unittest.TestCase):
    def test_canonical_components(self):self.assertEqual(d6.parse(VALID)['total'],7.5)
    def test_reason_requires_visible_evidence_text(self):
        for reason in ('', '   '):
            invalid=VALID.rsplit('Reason:',1)[0]+'Reason:'+reason
            with self.assertRaises(ValueError):d6.parse(invalid)
    def test_wrong_total(self):
        with self.assertRaises(ValueError):d6.parse(VALID.replace('7.5/10','8/10'))
    def test_duplicate_component(self):
        with self.assertRaises(ValueError):d6.parse(VALID+VALID.splitlines()[0])
    def test_forbidden_increment(self):
        with self.assertRaises(ValueError):d6.parse(VALID.replace('1.5/2','1.7/2',1))
    def test_unexpected_prose(self):
        with self.assertRaises(ValueError):d6.parse(VALID+'Extra text\n')

class CoverageTests(unittest.TestCase):
    def test_visual_pass_cannot_be_inferred_from_source_object_creation(self):
        required=support.load(support.TASK/'evaluator/rendered-review-criteria.json')['checks']['weapons_content']
        review={'verdict':'pass','criteria':{k:{'verdict':'pass','basis':'source','facts':'Object is created','evidence':['source.cpp']} for k in required}}
        self.assertEqual(len(score.visual_review_errors('weapons_content',review)),len(required))
    def test_partial_context_review_cannot_pass(self):
        review={'verdict':'pass','criteria':{'detail_type_level_health_refund':{'verdict':'pass','basis':'rendered','facts':'Details visible','evidence':['details.png']}}}
        self.assertTrue(any('tower_damage_cooldown_range' in s for s in score.visual_review_errors('ui_context',review)))
        self.assertTrue(any('selected_tower_range_ring' in s for s in score.visual_review_errors('ui_context',review)))
    def test_complete_rendered_projectile_review_is_accepted(self):
        required=support.load(support.TASK/'evaluator/rendered-review-criteria.json')['checks']['weapons_content']
        review={'verdict':'pass','evidence':['flight.png'],'criteria':{k:{'verdict':'pass','basis':'rendered','facts':'Observed in frame','evidence':['flight.png']} for k in required}}
        self.assertEqual(score.visual_review_errors('weapons_content',review),[])
        review['criteria']['arrow_visible']['evidence']=['unverified.png']
        self.assertTrue(score.visual_review_errors('weapons_content',review))
    def test_new_evidence_does_not_add_weighted_checkpoints(self):
        self.assertEqual(len(CHECKS),69)
        self.assertEqual({d:sum(c['dimension']==d for c in CHECKS.values()) for d in ['D1','D2','D3','D4','D5']},
                         {'D1':5,'D2':16,'D3':31,'D4':10,'D5':7})
    def test_melee_damage_bounds_unknown_regeneration_order_at_health_cap(self):
        def row(t,h):return {'phase':'combat','simulation_seconds':t,'slots':{'crystal_health':h,'crystal_max_health':500}}
        _,low,high=melee_damage_intervals([row(100,500),row(100.025,495.04)])[0]
        self.assertLess(low,5);self.assertGreater(high,5)
        self.assertFalse(low-.001<=4<=high+.001)
        self.assertFalse(low-.001<=6<=high+.001)
        _,low,high=melee_damage_intervals([row(100,450),row(100.1,445.2)])[0]
        self.assertAlmostEqual(low,5);self.assertAlmostEqual(high,5)
    def test_melee_damage_includes_first_hit_after_paused_baseline(self):
        rows=[{'phase':'paused','simulation_seconds':100,'slots':{'crystal_health':300,'crystal_max_health':500}},
              {'phase':'combat','simulation_seconds':100.025,'slots':{'crystal_health':295.05,'crystal_max_health':500}},
              {'phase':'combat','simulation_seconds':100.125,'slots':{'crystal_health':295.25,'crystal_max_health':500}}]
        events=melee_damage_events(rows)
        self.assertEqual(len(events),1)
        self.assertAlmostEqual(events[0][1],5)
    def test_melee_damage_uses_actual_sample_interval_and_health_clamp(self):
        def row(t,h):return {'phase':'combat','simulation_seconds':t,'slots':{'crystal_health':h,'crystal_max_health':500}}
        self.assertAlmostEqual(melee_damage_events([row(10,450),row(10.105,445.21)])[0][1],5)
        self.assertAlmostEqual(melee_damage_events([row(10,500),row(10.105,495)])[0][1],5)
    def test_inspect_uses_public_entity_cell_when_inspect_target_is_missing(self):
        cell={'id':'cell','kind':'board_cell','cell':[3,4],'rect':[.2,.3,.01,.01],'visible':True,'interactable':True}
        snapshot={'entities':[{'id':'tower','kind':'archer','cell':[3,4]}],'targets':[cell]}
        self.assertEqual(support.select(snapshot,'inspect',entity_id='tower'),cell)
        cell['interactable']=False
        with self.assertRaises(support.CandidateError):support.select(snapshot,'inspect',entity_id='tower')
    def test_private_fixture_patch_does_not_change_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';source.mkdir();(source/'a.h').write_text('private:')
            mapping={'source_files':{'a.h':support.sha(source/'a.h')},'module_path':'Module',
                'adapter_source':'fixtures/InputMapping.cpp','adapter_sha256':support.sha(support.TASK/'evaluator/fixtures/InputMapping.cpp'),
                'assessment_source_patches':[{'path':'a.h','before':'private:','after':'private: /* assessment friendship */'}]}
            support.write(root/'mapping.json',mapping)
            support.prepare_fixture(source,root/'copy',root/'mapping.json')
            self.assertEqual((source/'a.h').read_text(),'private:')
            self.assertIn('assessment friendship',(root/'copy/a.h').read_text())
    def test_no_unmapped_or_private_source(self):
        self.assertEqual(len(REQUIREMENTS),53)
        self.assertEqual(set(REQUIREMENTS),{r for c in CHECKS.values() for r in c['requirements']})
        self.assertEqual(len(NORMAL+list(FIXTURES)),len(set(NORMAL+list(FIXTURES))))
        for c in CHECKS.values():
            if c['stage']=='dynamic':self.assertTrue(set(c['cases'])<=set(NORMAL+list(FIXTURES)))
            self.assertEqual(c['stage'],'static' if c['dimension']=='D1' else 'dynamic')
    def test_full_public_tables(self):
        self.assertEqual(len(ENEMIES),15);self.assertEqual(len(TOWERS),6);self.assertEqual(set(WAVES),set(range(1,26)))
        self.assertTrue(all(f'contact_{k}_{t}' in FIXTURES for k,t in ENEMIES))
    def test_core_has_no_gold_import(self):
        for filename in ['cases.py','spec.py','score.py']:
            text=(Path(__file__).resolve().parents[1]/'scripts'/filename).read_text()
            self.assertNotIn('gold/project',text)
            self.assertNotIn('StarterGameMode',text)
    def test_fixture_identity_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';source.mkdir();(source/'a.cpp').write_text('candidate')
            support.write(root/'mapping.json',{'source_files':{'a.cpp':'incorrect'}})
            with self.assertRaisesRegex(support.InfrastructureError,'SOURCE_IDENTITY_MISMATCH'):
                support.prepare_fixture(source,root/'copy',root/'mapping.json')
    def test_build_target_is_discovered(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'Source/OtherLayout').mkdir(parents=True)
            (root/'Source/OtherLayout/AlternateEditor.Target.cs').write_text('')
            with patch('support.subprocess.run') as run:
                run.return_value.returncode=0
                support.compile_project(root/'Changed.uproject',root/'engine',root/'build.log')
                self.assertEqual(run.call_args.args[0][1],'AlternateEditor')

class AttributionTests(unittest.TestCase):
    def dialogue_run(self,root):
        protocol=support.load(support.TASK/'evaluator/d6/protocol.json')
        pairs=[{'state':s['id'],'candidate_status':'captured','reference_sha256':s['sha256'],'candidate_sha256':'candidate-image'} for s in protocol['states']]
        support.write(root/'d6/pairs.json',{'protocol_sha256':support.sha(support.TASK/'evaluator/d6/protocol.json'),'pairs':pairs})
        for r in range(1,4):
            for pair in pairs:(root/'d6'/f'response-{r}-{pair["state"]}.txt').write_text(VALID,encoding='utf-8')
        return {'backend':'direct_conversation','model_identity':'recorded-model','same_model_all_rounds':True,
                'prompt_template_sha256':protocol['prompt_sha256'],
                'rated_pairs':{p['state']:{k:p[k] for k in ['reference_sha256','candidate_sha256','candidate_status']}for p in pairs}}
    def test_missing_model_binding_is_infrastructure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.dialogue_run(root)
            with self.assertRaisesRegex(support.InfrastructureError,'MODEL_BINDING_REQUIRED'):d6.aggregate(root)
    def test_template_model_binding_cannot_publish(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);binding=self.dialogue_run(root);binding['model_identity']='RECORD_ACTUAL_MODEL'
            with self.assertRaisesRegex(support.InfrastructureError,'MODEL_BINDING_REQUIRED'):d6.aggregate(root,binding)
    def test_changed_rated_image_cannot_publish(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);binding=self.dialogue_run(root);binding['rated_pairs']['opening']['candidate_sha256']='different-image'
            with self.assertRaisesRegex(support.InfrastructureError,'RATED_IMAGES_OR_PROMPT_CHANGED'):d6.aggregate(root,binding)
    def base(self,status):
        return {'status':status,'partial':False,'static':{},'cases':{},'d6':{},'faults':[],
                'gdd_sha256':support.sha(support.TASK/'input/GDD.md'),
                'scoring_guide_sha256':support.sha(support.REPO/'gamecreate/GAME_INDEPENDENT_SCORING_GUIDE.md')}
    def run_score(self,data):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);support.write(root/'collection.json',data);return score.score(root)
    def test_candidate_missing_is_numeric_zero(self):
        result=self.run_score(self.base('candidate_failed'))
        self.assertEqual(set(result['scores'].values()),{0.0})
    def test_host_fault_never_becomes_candidate_zero(self):
        with self.assertRaises(support.InfrastructureError):self.run_score(self.base('run_invalid'))
    def test_in_progress_never_scores(self):
        with self.assertRaises(support.InfrastructureError):self.run_score(self.base('collecting'))
    def test_missing_author_assertions_block(self):
        with self.assertRaisesRegex(support.InfrastructureError,'EVIDENCE_COMPLETION_REQUIRED'):self.run_score(self.base('collected'))
    def test_development_partial_never_scores(self):
        data=self.base('candidate_failed');data['partial']=True
        with self.assertRaisesRegex(support.InfrastructureError,'PARTIAL'):self.run_score(data)
    def test_malformed_response_is_infrastructure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);protocol=support.load(support.TASK/'evaluator/d6/protocol.json')
            support.write(root/'d6/pairs.json',{'protocol_sha256':support.sha(support.TASK/'evaluator/d6/protocol.json'),'pairs':[{'state':s['id'],'candidate_status':'captured'}for s in protocol['states']]})
            (root/'d6/response-1-opening.txt').write_text('fabricated invalid answer')
            with self.assertRaisesRegex(support.InfrastructureError,'D6_RESPONSE_INVALID'):d6.aggregate(root)
    def test_unknown_d6_status_cannot_be_zero(self):
        data=self.base('collected');data['d6']={'opening':{'status':'infrastructure_failed','reason':'lost'}}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);support.write(root/'collection.json',data)
            with self.assertRaisesRegex(support.InfrastructureError,'UNKNOWN_CAPTURE_STATUS'):d6.prepare(root)
    def test_partial_d6_state_set_cannot_publish(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);support.write(root/'d6/pairs.json',{'protocol_sha256':support.sha(support.TASK/'evaluator/d6/protocol.json'),'pairs':[]})
            with self.assertRaisesRegex(support.InfrastructureError,'STATE_SET_INVALID'):d6.aggregate(root)
    def test_d6_path_escape_is_infrastructure(self):
        data=self.base('collected');data['d6']={'opening':{'status':'captured','path':'../../outside.png','sha256':'wrong'}}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);support.write(root/'collection.json',data)
            with self.assertRaisesRegex(support.InfrastructureError,'PATH_ESCAPE'):d6.prepare(root)

if __name__=='__main__':unittest.main()
