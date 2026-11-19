"""Counterexample state traces, not deliberate-error game implementations."""
import copy
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from coverage_assertions import terminal_unchanged, guard_stationary, feedback_interval, draw_result
from coverage_gate import apply_boundary_gate
from runtime import ROOT, load, write, InfrastructureError


def snapshot(t=0, text='', phase='active'):
    return {'snapshot_id':t+1, 'monotonic_ms':t, 'round_id':'round-0','process_id':7,'process_token':'process-0','game_state':{
        'phase':phase,
        'player':{'health':100,'action_state':'blocking','normalized_position':{'x':.2,'y':.8}},
        'rival':{'health':100,'normalized_position':{'x':.7,'y':.8}},
        'feedback':{'status_text':text,'result_text':''},
        'combat':{'round_time_ms':t,'active_player_projectiles':0,'telegraph_active':False},
        'world':{'object_counts':{'player_fighters':1,'rival_fighters':1}}}}


class Coverage(unittest.TestCase):
    def test_review_form_exposes_each_required_clip_observation(self):
        from make_review import main
        from review_contract import SUBCLAUSES
        from test_evaluator import Contracts
        from runtime import sha
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);raw=Contracts().raw()
            write(root/'fixture.json',{'fixture':True})
            raw.update(run_id='fixture',candidate_identity_sha256='0'*64,captures={},
                       evidence_sha256={'fixture.json':sha(root/'fixture.json')})
            write(root/'raw.json',raw)
            main(root/'raw.json',root/'review.html')
            form=(root/'review.html').read_text(encoding='utf-8')
            review=load(root/'semantic-review.json')
            for key in SUBCLAUSES['D2-12']:
                self.assertIn('id="c-D2-12-'+key+'"',form)
                self.assertIn('id="e-D2-12-'+key+'"',form)
                self.assertIsNone(review['checks']['D2-12']['clause_observations'][key]['pass'])

    def test_animation_import_statement_cannot_approve_eight_clip_roles(self):
        from review_contract import validate_review, REVISION
        review=dict(review_revision=REVISION,reviewer={'kind':'human','identity':'fixture'},
                    method='human_normal_input_capture_review',blanket_approval=False,
                    checks={'D2-12':{'pass':True,'observations':['All files imported'],'evidence':[]}})
        with self.assertRaisesRegex(InfrastructureError,'REVIEW_CLAUSE_COVERAGE_REQUIRED:D2-12'):
            validate_review(review,{},Path('.'))

    def test_feedback_replacement_cannot_excuse_an_overlong_old_message(self):
        seq=[snapshot(0),snapshot(50,'WHIFF'),snapshot(1500,'WHIFF'),snapshot(1550,'HIT 15')]
        self.assertEqual(feedback_interval(seq,'WHIFF')[0],'fail')
        seq=[snapshot(0),snapshot(50,'WHIFF'),snapshot(100,'WHIFF'),snapshot(150,'HIT 15')]
        self.assertEqual(feedback_interval(seq,'WHIFF')[0],'replaced')

    def test_total_runtime_budget_covers_every_declared_case(self):
        cases=load(ROOT/'catalog/trajectories.json')['trajectories']
        budget=load(ROOT/'contracts/budget.json')
        self.assertGreaterEqual(budget['local_wait_budget_seconds'],sum(c['max_wait_seconds']+2 for c in cases)+2)
        self.assertGreaterEqual(budget['max_start_rpcs'],len(cases)+3)
        draw=next(c for c in cases if c['id']=='draw-probe')
        self.assertGreaterEqual(draw['max_wait_seconds'],5+3*(3+2)+17+4+1+2)

    def test_guard_detects_motion_even_when_it_returns_to_start(self):
        initial=snapshot(); transient=snapshot(100)
        transient['game_state']['player']['normalized_position']['x']=.3
        self.assertTrue(guard_stationary([snapshot(100),snapshot(200)],initial))
        self.assertFalse(guard_stationary([transient,snapshot(200)],initial))
        self.assertFalse(guard_stationary([],initial))

    def test_terminal_detects_transient_attack_and_rival_motion(self):
        initial=snapshot(phase='player_won');initial['game_state']['player']['action_state']='idle'
        for mutation in ('attack','player_x','rival_x','rival_y','projectile','damage','banner'):
            bad=copy.deepcopy(initial)
            if mutation=='attack':bad['game_state']['player']['action_state']='light_attack'
            if mutation in ('player_x','rival_x','rival_y'):
                who,axis=mutation.split('_');bad['game_state'][who]['normalized_position'][axis]+=.1
            if mutation=='projectile':bad['game_state']['combat']['active_player_projectiles']=1
            if mutation=='damage':bad['game_state']['player']['health']=80
            if mutation=='banner':bad['game_state']['feedback']['result_text']='RIVAL WINS'
            with self.subTest(mutation=mutation):
                self.assertFalse(terminal_unchanged([bad,initial],initial))
        self.assertTrue(terminal_unchanged([initial],initial))

    def test_terminal_rejects_missing_health_and_hidden_new_round(self):
        initial=snapshot(phase='player_won');bad=copy.deepcopy(initial)
        bad['round_id']='round-1'
        self.assertFalse(terminal_unchanged([bad],initial))
        del initial['game_state']['player']['health']
        self.assertFalse(terminal_unchanged([initial],initial))

    def test_feedback_exact_bounds_and_uncertain_sampling(self):
        for times,expected in (([0,50,400,750],'pass'),([0,50,100,150],'fail'),
                               ([0,50,1500,1550],'fail'),([0,250,500,750],'gap')):
            seq=[snapshot(t,'WHIFF' if i in (1,2) else '') for i,t in enumerate(times)]
            self.assertEqual(feedback_interval(seq,'WHIFF')[0],expected)
        self.assertEqual(feedback_interval([snapshot(0),snapshot(500)],'WHIFF')[0],'gap')

    def test_draw_setup_failure_cannot_be_candidate_failure(self):
        before=snapshot();after=snapshot(100)
        after['game_state']['rival']['health']=0
        self.assertEqual(draw_result(before,after),'setup_gap')
        after['game_state']['player']['health']=0
        self.assertEqual(draw_result(before,after),'fail')
        after['game_state'].update(phase='draw')
        after['game_state']['feedback']['result_text']='DRAW'
        self.assertEqual(draw_result(before,after),'pass')

    def test_missing_boundary_evidence_blocks_publication(self):
        with self.assertRaisesRegex(InfrastructureError,'BOUNDARY_COVERAGE_REQUIRED'):
            apply_boundary_gate({},dict(captures={'initial':{}},faults=[],evidence_sha256={}),Path('.'))

    def test_gap_is_not_zero_and_failure_cannot_be_repaired_by_presentation(self):
        catalog=load(ROOT/'catalog/boundary-coverage.json')
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);path='states/boundary-coverage.json'
            checks={c['id']:dict(owner=c['owner'],verdict='pass',reason='trace',evidence=['states/trace.json']) for c in catalog['checks']}
            actual={c['owner']:dict(verdict='pass',reason='presentation accepted',evidence=[]) for c in catalog['checks']}
            raw=dict(captures={'initial':{}},faults=[],evidence_sha256={path:'hash','states/trace.json':'hash'})
            checks['guard_movement']['verdict']='fail'
            write(root/path,dict(revision=catalog['revision'],checks=checks))
            apply_boundary_gate(actual,raw,root)
            self.assertEqual(actual['D3-07']['verdict'],'fail')
            checks['simultaneous_draw']['verdict']='gap'
            write(root/path,dict(revision=catalog['revision'],checks=checks))
            with self.assertRaisesRegex(InfrastructureError,'GDD_COVERAGE_INCOMPLETE:simultaneous_draw'):
                apply_boundary_gate(actual,raw,root)

    def test_every_supplement_has_public_owner_and_bounded_case(self):
        catalog=load(ROOT/'catalog/checkpoints.json')['checkpoints']
        owners={c['id']:c for c in catalog}
        cases={c['id']:c for c in load(ROOT/'catalog/trajectories.json')['trajectories']}
        for c in load(ROOT/'catalog/boundary-coverage.json')['checks']:
            self.assertIn(c['requirement_id'],owners[c['owner']]['source_ids'])
            self.assertIn(c['owner'],cases[c['case_id']]['checkpoint_ids'])


if __name__=='__main__':unittest.main()
