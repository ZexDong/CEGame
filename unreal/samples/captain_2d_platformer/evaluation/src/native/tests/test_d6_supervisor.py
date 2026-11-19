"""Exercise D6 process races with real local children; never call a VLM or UE."""
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from runtime import ROOT, TASK, InfrastructureError, load, write, sha, code_identity
from seal_evidence import seal
from run_d6 import control_root, final_state, supervise


class D6SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.run = self.root / 'run'
        self.raw = self.run / 'raw-evaluation.json'
        self.output = self.run / 'd6-result.json'
        catalog = load(ROOT / 'scoring-catalog.json')
        write(self.run / 'journeys.json', [])
        write(self.raw, dict(run_id='run', status='collected', fault=None,
            cleanup_confirmed=True, catalog_sha256=sha(ROOT / 'scoring-catalog.json'),
            gdd_sha256=sha(TASK / 'input/GDD.md'), runtime_identity=code_identity(),
            candidate_identity_sha256='0' * 64, captures={},
            checkpoints=[dict(id=c['id'], dimension=c['dimension'], verdict='unreachable',
                reason='CANDIDATE_MISSING', attribution='candidate', evidence=['journeys.json'])
                for c in catalog['checkpoints']]))
        seal(self.run)
        manifest = load(ROOT / 'd6/reference-manifest.json')
        self.result = dict(status='completed', raw_sha256=sha(self.raw),
            manifest_sha256=sha(ROOT / 'd6/reference-manifest.json'),
            prompt_sha256=sha(ROOT / 'd6/FIXED_VLM_PROMPT.txt'),
            model_requested=manifest['model_requested'], rounds=[dict(number=n,
                states=[dict(id=s['id'], status='candidate_missing', criteria=[0]*5,
                             reference_sha256=s['sha256']) for s in manifest['states']])
                for n in (1, 2, 3)])
        write(self.root / 'fixture.json', self.result)

    def command(self, body):
        script = self.root / 'child.py'
        script.write_text('import json,sys,time\nfrom pathlib import Path\n'
            'output=Path(sys.argv[1])\n'
            'result=json.loads(Path(sys.argv[2]).read_text())\n'
            'def save():\n'
            '    output.write_text(json.dumps(result),encoding="utf-8")\n' + body,
            encoding='utf-8')
        return [sys.executable, str(script), str(self.output), str(self.root / 'fixture.json')]

    def receipt(self):
        return load(control_root(self.output) / 'd6-run.json')

    def test_round_one_and_console_yield_do_not_end_wait(self):
        command = self.command('print("D6 round 1 done",flush=True)\n'
            '(output.parent/"round-one").touch()\ntime.sleep(.8)\nsave()\n')
        results = []
        worker = threading.Thread(target=lambda: results.append(supervise(command, self.raw, self.output, 5)))
        worker.start()
        try:
            deadline = time.monotonic() + 3
            while not (self.run / 'round-one').exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue((self.run / 'round-one').exists())
            self.assertTrue(worker.is_alive())
            self.assertFalse(self.output.exists())
            self.assertEqual(self.receipt()['status'], 'running')
        finally:
            worker.join(6)
        self.assertEqual(results, [0])
        self.assertEqual(self.receipt()['d6_exit_code'], 0)
        self.assertEqual(self.receipt()['status'], 'completed')
        self.assertFalse(self.receipt()['score_publication_allowed'])

    def test_complete_file_never_hides_nonzero_exit(self):
        self.assertEqual(supervise(self.command('save()\nsys.exit(7)\n'), self.raw, self.output, 5), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'D6_PROCESS_EXIT_NONZERO')
        self.assertEqual(self.receipt()['d6_exit_code'], 7)

    def test_missing_result_keeps_log_and_actual_exit(self):
        command = self.command('print("last D6 diagnostic",file=sys.stderr)\n')
        self.assertEqual(supervise(command, self.raw, self.output, 5), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'D6_FINAL_REPORT_MISSING')
        self.assertIn('last D6 diagnostic', (control_root(self.output) / 'd6.log').read_text())

    def test_partial_rounds_never_count_as_complete(self):
        command = self.command('result["rounds"]=result["rounds"][:1]\nsave()\n')
        self.assertEqual(supervise(command, self.raw, self.output, 5), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'D6_ROUNDS_INVALID')

    def test_wrong_raw_binding_never_counts_as_complete(self):
        command = self.command('result["raw_sha256"]="f"*64\nsave()\n')
        self.assertEqual(supervise(command, self.raw, self.output, 5), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'D6_INVALID_OR_WRONG_RUN')

    def test_closed_terminal_does_not_drop_child_output_or_result(self):
        command = self.command('print("x"*200000)\nsave()\n')
        with patch('builtins.print', side_effect=BrokenPipeError):
            self.assertEqual(supervise(command, self.raw, self.output, 5), 0)
        self.assertGreater((control_root(self.output) / 'd6.log').stat().st_size, 200000)

    def test_deadline_terminates_owned_child_and_keeps_no_score(self):
        self.assertEqual(supervise(self.command('time.sleep(10)\n'), self.raw, self.output, .3), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'D6_SUPERVISOR_DEADLINE_EXCEEDED')
        self.assertIsNotNone(self.receipt()['d6_exit_code'])

    def test_existing_result_and_control_directory_never_overwritten(self):
        self.output.touch()
        with self.assertRaises(InfrastructureError):
            supervise([], self.raw, self.output, 5)
        self.output.unlink()
        control_root(self.output).mkdir()
        with self.assertRaises(InfrastructureError):
            supervise([], self.raw, self.output, 5)

    def test_malformed_and_invalid_reports_remain_incomplete(self):
        for body in ('null', '{', '[]'):
            self.output.write_text(body)
            self.assertEqual(final_state(self.raw, self.output, 0)[1], 'D6_FINAL_REPORT_MALFORMED')
        write(self.output, dict(status='invalid', fault=dict(code='VLM_HTTP_500')))
        self.assertEqual(final_state(self.raw, self.output, 0)[1], 'D6_FINAL_REPORT_INCOMPLETE')

    def test_receipt_tampering_is_caught_by_canonical_validator(self):
        write(self.run / 'journeys.json', ['modified'])
        write(self.output, self.result)
        self.assertEqual(final_state(self.raw, self.output, 0)[1], 'EVIDENCE_HASH_MISMATCH:journeys.json')


if __name__ == '__main__':
    unittest.main(verbosity=2)
