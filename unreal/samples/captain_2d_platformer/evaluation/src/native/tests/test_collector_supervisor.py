"""Real child processes exercise checkpoint/exit races without starting Unreal."""
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from runtime import InfrastructureError, load, write
from run_collector import control_root, final_state, supervise


class CollectorSupervisorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / 'test-run'

    def command(self, body):
        script = self.root / 'child.py'
        script.write_text('import json,sys,time\nfrom pathlib import Path\n'
            'root=Path(sys.argv[1])\n'
            'report=dict(run_id=root.name,status="running",fault=None,cleanup_confirmed=False)\n'
            'def save():\n'
            '    temp=root/"raw.tmp"\n'
            '    temp.write_text(json.dumps(report),encoding="utf-8")\n'
            '    temp.replace(root/"raw-evaluation.json")\n' + body, encoding='utf-8')
        return [sys.executable, str(script), str(self.output)]

    def receipt(self):
        return load(control_root(self.output) / 'collector-run.json')

    def test_running_checkpoint_and_target_exit_do_not_end_wait(self):
        command = self.command('save()\n(root/"game-exited").touch()\n'
            'time.sleep(.8)\nreport.update(status="collected",cleanup_confirmed=True)\nsave()\n')
        result = []
        worker = threading.Thread(target=lambda: result.append(supervise(command, self.output, 5)))
        worker.start()
        try:
            deadline = time.monotonic() + 3
            while not (self.output / 'game-exited').exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue((self.output / 'game-exited').exists())
            self.assertEqual(load(self.output / 'raw-evaluation.json')['status'], 'running')
            self.assertTrue(worker.is_alive())
            self.assertEqual(self.receipt()['status'], 'running')
        finally:
            worker.join(timeout=6)
        self.assertEqual(result, [0])
        self.assertEqual(self.receipt()['status'], 'collected')

    def test_exit_with_only_checkpoint_is_incomplete(self):
        self.assertEqual(supervise(self.command('save()\n'), self.output, 5), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'COLLECTOR_EXITED_WITH_RUNNING_CHECKPOINT')
        self.assertEqual(load(self.output / 'raw-evaluation.json')['status'], 'running')

    def test_collected_file_does_not_mask_nonzero_exit(self):
        command = self.command('report.update(status="collected",cleanup_confirmed=True)\nsave()\nsys.exit(7)\n')
        self.assertEqual(supervise(command, self.output, 5), 2)
        self.assertEqual(self.receipt()['collector_exit_code'], 7)
        self.assertEqual(self.receipt()['fault']['code'], 'COLLECTOR_EXIT_NONZERO')

    def test_missing_raw_preserves_stderr_and_exit_code(self):
        command = self.command('print("collector traceback",file=sys.stderr)\nsys.exit(1)\n')
        self.assertEqual(supervise(command, self.output, 5), 2)
        self.assertIn('collector traceback', (control_root(self.output) / 'collector.log').read_text())
        self.assertEqual(self.receipt()['fault']['code'], 'COLLECTOR_FINAL_REPORT_MISSING')

    def test_missing_cleanup_never_counts_as_completion(self):
        self.assertEqual(supervise(self.command('report["status"]="collected"\nsave()\n'), self.output, 5), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'COLLECTOR_CLEANUP_UNVERIFIED')

    def test_timeout_ends_only_owned_child_and_is_not_a_candidate_score(self):
        command = self.command('save()\ntime.sleep(10)\n')
        self.assertEqual(supervise(command, self.output, .3), 2)
        self.assertEqual(self.receipt()['fault']['code'], 'SUPERVISOR_DEADLINE_EXCEEDED')
        self.assertIsNotNone(self.receipt()['collector_exit_code'])
        self.assertFalse(self.receipt()['cleanup_confirmed'])

    def test_closed_terminal_and_large_child_output_preserve_completion(self):
        command = self.command('print("x"*200000)\nreport.update(status="collected",cleanup_confirmed=True)\nsave()\n')
        with patch('builtins.print', side_effect=BrokenPipeError):
            self.assertEqual(supervise(command, self.output, 5), 0)
        self.assertGreater((control_root(self.output) / 'collector.log').stat().st_size, 200000)

    def test_malformed_report_and_wrong_run_cannot_pass(self):
        self.output.mkdir()
        path = self.output / 'raw-evaluation.json'
        for body in ('{}\\n', 'null', '{'):
            path.write_text(body, encoding='utf-8')
            self.assertEqual(final_state(self.output, 0)[1], 'COLLECTOR_FINAL_REPORT_MALFORMED')
        write(path, dict(run_id='another-run',status='collected',cleanup_confirmed=True,fault=None))
        self.assertEqual(final_state(self.output, 0)[1], 'COLLECTOR_RUN_ID_MISMATCH')

    def test_existing_run_is_never_overwritten(self):
        self.output.mkdir()
        with self.assertRaises(InfrastructureError):
            supervise(self.command('raise RuntimeError("must not start")'), self.output, 5)


if __name__ == '__main__':
    unittest.main(verbosity=2)
