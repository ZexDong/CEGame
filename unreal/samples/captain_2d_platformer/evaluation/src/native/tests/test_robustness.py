"""Lifecycle, malformed-observer and interrupted-output regressions; no game variants."""
import copy
import io
import os
import queue
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock,patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import runtime
from runtime import Player,Observer,load,write,cleanup_verified,CandidateError,InfrastructureError
from evaluate import Evaluation,fresh
from score import valid_raw,score
from d6 import reached

def stopped():
    return dict(process_exited=True,job_active_process_count_after_wait=0,job_handle_closed=True,input_lease_released=True)

def failed_reopen():
    return dict(operation='Reopen',status='executor_fault',fault=dict(code='target_exited_before_stop'),
        result=dict(termination_reason='old_session_stop_failed',stop_result=stopped(),session=None))

class RobustnessTests(unittest.TestCase):
    def test_destroyed_window_watchdog_is_candidate_but_focus_and_release_faults_are_not(self):
        receipt=dict(status='executor_fault',fault=dict(code='input_watchdog_fault_latched',
            details=dict(watchdog_faulted=True,watchdog_fault_code='WINDOW_INVALID',native_error=0)))
        self.assertEqual(runtime.classify(receipt),'candidate')
        for code in ('FOREGROUND_LOST','PROCESS_ID_MISMATCH','INPUT_RELEASE_FAILED'):
            other=copy.deepcopy(receipt);other['fault']['details']['watchdog_fault_code']=code
            self.assertEqual(runtime.classify(other),'infrastructure')
        for key,value in [('watchdog_faulted',False),('native_error',5)]:
            other=copy.deepcopy(receipt);other['fault']['details'][key]=value
            self.assertEqual(runtime.classify(other),'infrastructure')

    def setUp(self):
        self.directory=tempfile.TemporaryDirectory();self.addCleanup(self.directory.cleanup)
        self.root=Path(self.directory.name)

    def evaluation(self):
        engine=self.root/'engine'
        write(engine/'Engine/Build/Build.version',dict(MajorVersion=5,MinorVersion=7,PatchVersion=4,Changelist=51494982))
        return Evaluation(SimpleNamespace(output=self.root/'run',candidate=self.root/'missing',engine=engine,pwsh='unused'))

    def test_nested_cleanup_is_complete_and_does_not_apply_to_new_session(self):
        receipt=failed_reopen();self.assertTrue(cleanup_verified(receipt))
        for key in stopped():
            bad=copy.deepcopy(receipt);bad['result']['stop_result'].pop(key)
            self.assertFalse(cleanup_verified(bad),key)
        for value in (None,False,'0',1):
            bad=copy.deepcopy(receipt);bad['result']['stop_result']['job_active_process_count_after_wait']=value
            self.assertFalse(cleanup_verified(bad),repr(value))
        receipt['status']='ok';self.assertFalse(cleanup_verified(receipt))

    def test_failed_reopen_clears_python_session_before_raising(self):
        p=Player.__new__(Player);p.root=self.root;p.serial=0;p.budget=None
        p.session={'process_id':1};p.had_session=True;p.last_cleanup_receipt=None;p.last_receipt=None
        p.process=SimpleNamespace(stdin=io.StringIO());p.responses=queue.Queue();p.responses.put(failed_reopen())
        with self.assertRaisesRegex(CandidateError,'target_exited_before_stop'):p.call('reopen')
        self.assertIsNone(p.session);self.assertTrue(cleanup_verified(p.last_cleanup_receipt))
        original=p.process.stdin.getvalue();p.call('stop')
        self.assertEqual(p.process.stdin.getvalue(),original,'No second Stop after proven cleanup')

    def test_candidate_exit_preserves_independent_results(self):
        e=self.evaluation();e.root.mkdir();e.mark('D1-02',True,'BUILD_OK','build.json')
        e.p=SimpleNamespace(session=None,last_cleanup_receipt=failed_reopen(),last_receipt=failed_reopen(),had_session=True,close=Mock())
        cleaned,fault=e.cleanup()
        self.assertTrue(cleaned);self.assertIsNone(fault);e.p.close.assert_called_once()
        self.assertEqual(e.verdicts['D1-02']['verdict'],'pass')

    def test_host_close_failure_cannot_be_hidden_by_game_cleanup(self):
        e=self.evaluation();e.p=SimpleNamespace(session=None,last_cleanup_receipt=failed_reopen(),last_receipt=None,had_session=True,
            close=Mock(side_effect=InfrastructureError('PLAYER_HOST_CLEANUP_TIMEOUT')))
        cleaned,fault=e.cleanup();self.assertFalse(cleaned);self.assertIn('PLAYER_HOST_CLEANUP_TIMEOUT',fault['close_error'])

    def test_missing_candidate_still_scores_and_closed_stdout_is_harmless(self):
        e=self.evaluation()
        with patch('builtins.print',side_effect=BrokenPipeError):self.assertEqual(e.run(),0)
        raw=load(e.root/'raw-evaluation.json');catalog=valid_raw(raw)
        self.assertEqual(raw['status'],'collected');self.assertTrue(raw['cleanup_confirmed'])
        self.assertEqual(score(raw,catalog,{},(0,[0,0,0]))['scores']['Overall'],0)

    def test_unexpected_exception_and_cleanup_failure_both_remain_visible(self):
        e=self.evaluation()
        def failed_identity(_):
            self.assertEqual(load(e.root/'raw-evaluation.json')['status'],'running')
            raise IndexError('DRIVER_BUG')
        with patch('evaluate.identity',side_effect=failed_identity),patch.object(e,'cleanup',side_effect=RuntimeError('CLOSE_BUG')):
            self.assertEqual(e.run(),2)
        raw=load(e.root/'raw-evaluation.json')
        self.assertEqual(raw['fault']['exception_type'],'IndexError')
        self.assertEqual(raw['fault']['cleanup_fault']['exception_type'],'RuntimeError')
        with self.assertRaises(InfrastructureError):valid_raw(raw)

    def test_interrupted_run_checkpoint_is_not_scorable(self):
        e=self.evaluation();e.root.mkdir();e.checkpoint()
        with self.assertRaises(InfrastructureError):valid_raw(load(e.root/'raw-evaluation.json'))

    def test_missing_geometry_keeps_initial_pictures_hud_and_values(self):
        e=self.evaluation();e.root.mkdir()
        g=dict(phase='active',player=dict(health=dict(current=100),grounded=True),
            objective=dict(keys_collected=0,key_present=True,exit_state='locked'),
            world=dict(object_counts=dict(player=1,key=1,exit=1,hazard=2,enemy=1,spring=1,one_way_platform=3),
                enemies=[dict(health=dict(current=50))],visible_targets=[]))
        s=dict(game_state=g)
        e.o=SimpleNamespace(last=s,samples=[s],errors=[],schema={})
        e.wait=Mock(return_value=s);e.cap=Mock(return_value={});e.window=Mock(return_value=[s])
        e.isolated('initial',e.initial_state)
        self.assertEqual(e.journeys[0]['reason'],'LEDGES_MISSING_FOR_ROOM_PROJECTION')
        for key in ('D2-01','D3-01','D5-01'):self.assertEqual(e.verdicts[key]['verdict'],'pass',key)
        e.attribute_unreachable();self.assertEqual(e.verdicts['D2-05']['verdict'],'unreachable')
        self.assertTrue(e.cap.called)

    def test_malformed_geometry_and_nullable_enemies_are_candidate_data(self):
        e=self.evaluation()
        for value in (None,{},[None],[]):
            with self.assertRaises(CandidateError):e.projection(dict(world=dict(visible_targets=value)))
        self.assertFalse(fresh(dict(world=dict(enemies=None))))

    def test_independent_restart_does_not_require_unrelated_objects(self):
        e=self.evaluation()
        g=dict(phase='active',player=dict(grounded=True),session=dict(deaths=0))
        before=dict(game_state=g,round_id='old',round_index=1,restart_count=0)
        after=dict(game_state=g,round_id='new',round_index=2,restart_count=1)
        def wait(name,predicate,*args):
            if name.endswith('-before'):return before
            return after if predicate(g) else None
        e.wait=wait;e.press=Mock()
        self.assertIs(e.restart('movement'),after)
        with self.assertRaisesRegex(CandidateError,'RESTART_NOT_CLEAN'):e.restart('full-reset',strict=True)

    def test_independent_restart_tolerates_duplicate_transport_notification(self):
        e=self.evaluation()
        g=dict(phase='active',player=dict(grounded=True),session=dict(deaths=0))
        before=dict(game_state=g,round_id='old',round_index=1,restart_count=0)
        after=dict(game_state=g,round_id='new',round_index=3,restart_count=2)
        def wait(name,predicate,*args):
            if name.endswith('-before'):return before
            return after if predicate(g) else None
        e.wait=wait;e.press=Mock()
        self.assertIs(e.restart('movement'),after)
        self.assertEqual(e.facts['restart_deltas'][0]['delta'],2)
        with self.assertRaisesRegex(CandidateError,'RESTART_NOT_CLEAN'):
            e.restart('full-reset',strict=True)

    def test_navigation_route_has_one_bounded_recovery_attempt(self):
        e=self.evaluation();e.root.mkdir();(e.root/'journeys').mkdir()
        e.o=SimpleNamespace(samples=[],last=None,errors=[])
        route=Mock(side_effect=[CandidateError('SPRING_NO_BOOST'),None])
        e.isolated('traversal',route)
        self.assertEqual(route.call_count,2)
        self.assertEqual(e.journeys[-1]['status'],'completed')
        self.assertEqual(e.journeys[-1]['attempts'],2)
        self.assertEqual(e.facts['route_recoveries'][0]['reason'],'SPRING_NO_BOOST')

    def test_basic_movement_can_preserve_credit_without_platforms(self):
        e=self.evaluation();e.root.mkdir()
        g=dict(player=dict(normalized_position=dict(x=.5)))
        e.o=SimpleNamespace(last=dict(game_state=g),samples=[],errors=[],schema={})
        e.p=SimpleNamespace(call=Mock());e.restart=Mock();e.cap=Mock()
        states=[dict(player=dict(normalized_position=dict(x=.45),facing='left')),
                dict(player=dict(normalized_position=dict(x=.55),facing='right')),
                dict(player=dict(grounded=False)),dict(player=dict(grounded=True))]
        def wait(name,predicate,*args):
            state=states.pop(0);self.assertTrue(predicate(state))
            e.o.last=dict(game_state=state);return e.o.last
        e.wait=wait;e.isolated('movement',e.basic_movement)
        for key in ('D2-02','D5-02'):self.assertEqual(e.verdicts[key]['verdict'],'pass')
        for key in ('D3-02','D3-03'):self.assertEqual(e.verdicts[key]['verdict'],'unreachable')
        self.assertEqual([c for c in e.p.call.call_args_list if c.args==('up',)].__len__(),2)

    def test_absent_enemy_is_candidate_failure_before_combat_indexing(self):
        e=self.evaluation();e.root.mkdir()
        e.o=SimpleNamespace(last=dict(game_state=dict(world=dict(enemies=[]))),samples=[],errors=[],schema={})
        e.restart=Mock();e.isolated('combat',e.combat)
        self.assertEqual(e.journeys[-1]['reason'],'ENEMY_MISSING_FOR_COMBAT')

    def test_nonobject_snapshot_is_rejected_without_observer_crash(self):
        o=Observer(self.root,dict(process_id=1,process_token='token'))
        for bad in ([],None,7):
            write(self.root/'state/game-state.json',bad)
            self.assertIsNone(o.read())
        self.assertIn('invalid_envelope',o.errors)

    def test_old_schema_error_does_not_mask_unrelated_driver_exception(self):
        e=self.evaluation();e.root.mkdir();e.o=SimpleNamespace(last={},schema={'type':'object'},errors=['old error'],samples=[])
        with self.assertRaisesRegex(IndexError,'driver bug'):
            e.isolated('feature',Mock(side_effect=IndexError('driver bug')))

    def test_malformed_d6_context_does_not_invalidate_other_states(self):
        p=self.root/'context.json'
        for context in ([],dict(before=dict(provider_ready=True,game_state=[]))):
            write(p,context);self.assertFalse(reached(dict(context=p.name),dict(id='sword'),self.root))

    def test_real_powershell_host_reopen_does_not_double_stop(self):
        pwsh=os.environ.get('CAPTAIN_TEST_PWSH') or shutil.which('pwsh')
        if not pwsh:self.skipTest('PowerShell 7 not available')
        module=self.root/'engine/unreal-5.7.4/executor/UnrealEvaluationExecutor.psm1'
        module.parent.mkdir(parents=True)
        module.write_text('''
function Start-UnrealEvaluationSession {
    [pscustomobject]@{status='ok';result=[pscustomobject]@{session=[pscustomobject]@{id='fixture'};process_id=123;process_token='fixture'}}
}
function Reopen-UnrealEvaluationSession {
    [pscustomobject]@{operation='Reopen';status='executor_fault';fault=[pscustomobject]@{code='target_exited_before_stop'};
        result=[pscustomobject]@{termination_reason='old_session_stop_failed';stop_result=[pscustomobject]@{
            process_exited=$true;job_active_process_count_after_wait=0;job_handle_closed=$true;input_lease_released=$true}}}
}
function Stop-UnrealEvaluationSession { throw 'Unexpected duplicate Stop reached the executor' }
Export-ModuleMember -Function *
''',encoding='utf-8')
        with patch.object(runtime,'REPO',self.root):p=Player(pwsh,self.root/'run')
        try:
            p.call('start',project='fixture',engine='fixture',root=str(self.root/'run'))
            with self.assertRaises(CandidateError):p.call('reopen')
            self.assertIsNone(p.session)
            # Exercise the PowerShell idempotence guard too, as an older Python
            # client would send this redundant Stop with a stale session.
            p.session={'stale':True}
            with self.assertRaises(CandidateError):p.call('stop')
            self.assertTrue(cleanup_verified(p.last_receipt))
        finally:p.close()

if __name__=='__main__':unittest.main(verbosity=2)
