"""Meaningful scorer/graph/attribution unit checks; no fabricated game versions."""
from pathlib import Path
import sys,unittest,json,tempfile
EV=Path(__file__).resolve().parents[1];sys.path.insert(0,str(EV/'scripts'))
from score import parse_response,finalize
from semantics import graph_valid,locks_valid
from prepare import source_signature,select_adapter,InfrastructureError,private_extension_build_error
from runtime import completed_exit_cleanup
class Contracts(unittest.TestCase):
    def test_linker_fault_is_not_candidate_compile_failure(self):
        self.assertTrue(private_extension_build_error('PrivateAdapter.cpp.obj : error LNK2019: unresolved protected function'))
        self.assertFalse(private_extension_build_error('BoneMazeGameMode.cpp(20): error C2065: bad candidate variable'))
    def test_dead_candidate_cleanup_requires_positive_host_receipt(self):
        receipt={'status':'executor_fault','fault':{'code':'target_exited_before_stop'},'result':{'process_exited':True,'job_handle_closed':True,'input_lease_released':True,'job_active_process_count_after_wait':0,'input_cleanup':{'all_released':True}}}
        fixed=completed_exit_cleanup(receipt)
        self.assertTrue(fixed['unexpected_candidate_exit']);self.assertFalse(fixed['expected_player_quit'])
        self.assertFalse(completed_exit_cleanup(receipt,True)['unexpected_candidate_exit'])
        receipt['result']['input_cleanup']['all_released']=False
        self.assertIsNone(completed_exit_cleanup(receipt))
    def test_adapter_normalizes_archive_endings_but_rejects_added_source(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'Source').mkdir();p=root/'Source/sample.cpp';p.write_bytes(b'first\nsecond\n');signature=source_signature(root)
            p.write_bytes(b'first\r\nsecond\r\n');self.assertEqual(signature,source_signature(root))
            self.assertEqual(select_adapter(root,{'sample':{'source_files':signature}})[0],'sample')
            (root/'Source/extra.cpp').write_text('extra')
            with self.assertRaises(InfrastructureError):select_adapter(root,{'sample':{'source_files':signature}})
    def test_coverage_and_ownership(self):
        catalog=json.loads((EV/'checkpoint-catalog.json').read_text());rows=catalog['checkpoints'];ids=[r['id'] for r in rows]
        self.assertEqual(len(ids),len(set(ids)))
        coverage=json.loads((EV/'requirement-coverage.json').read_text())
        self.assertEqual(66,len(coverage['requirements']));self.assertFalse(coverage['unmapped_requirements'])
        self.assertTrue(all(r['requirements'] and r['score_owner']==r['id'] for r in rows))
        self.assertTrue(all(r['stage']==('static' if r['dimension']=='D1' else 'dynamic') for r in rows))
    def test_budget_invariant(self):
        b=json.loads((EV/'budget.json').read_text());self.assertGreaterEqual(b['session_watchdog_seconds'],b['declared_serial_worst_case_seconds']+b['headroom_seconds'])
    def test_d6_rejects_invalid_increment_and_total(self):
        good='Scene completeness and asset assembly:1.5/2\nComposition and layout:2/2\nScale, hierarchy, and clarity:1/2\nStyle and color consistency:1.5/2\nOverall polish:2/2\nTotal:8/10\nReason:Characters and background are complete; composition is clear.'
        self.assertEqual(parse_response(good)['total'],8)
        for bad in [good.replace('Total:8','Total:9'),good.replace('1.5/2','1.2/2',1),good+'\nextra']:
            with self.assertRaises(ValueError):parse_response(bad)
    def test_infrastructure_never_publishes_zero(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/'run-invalid.json').write_text('{}')
            with self.assertRaises(ValueError):finalize(Path(d))
    def test_incomplete_authoring_never_scores(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/'run-binding.json').write_text('{"authoring_subset":true}')
            with self.assertRaises(ValueError):finalize(Path(d))
if __name__=='__main__':unittest.main()
