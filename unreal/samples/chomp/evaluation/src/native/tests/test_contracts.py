"""Scoring/protocol fault tests use records and images, never broken games."""
import unittest,tempfile,sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from common import *
from d6 import parse,round_decimal,image_fault,aggregate
from score import score
from PIL import Image

class ContractTests(unittest.TestCase):
    def test_coverage_and_unique_ownership(self):
        checks=load(TASK/'evaluator/catalog/checkpoints.json')['checks'];coverage=load(TASK/'evaluator/requirement-coverage.json')['requirements']
        self.assertEqual(len(coverage),58);self.assertEqual(len({c['id'] for c in checks}),len(checks));self.assertTrue(all(c['check_ids'] for c in coverage));self.assertEqual({c['score_owner'] for c in checks},{c['id'] for c in checks})
    def test_budget_covers_repeated_setups(self):
        cases=load(TASK/'evaluator/catalog/cases.json')['cases'];b=load(TASK/'evaluator/contracts/budget.json')
        required=sum(c['max_serial_seconds']+18*c['setup_repetitions'] for c in cases)+280
        self.assertGreaterEqual(b['declared_serial_worst_case_seconds'],required);self.assertGreaterEqual(b['session_watchdog_seconds'],required+600)
    def test_fixed_prompt_and_references(self):
        r=load(TASK/'evaluator/d6/reference-manifest.json');self.assertEqual(r['rounds'],3);self.assertEqual(len(r['states']),3)
        self.assertEqual(sha(TASK/'evaluator/d6/FIXED_PROMPT.txt'),r['prompt_sha256'])
        for s in r['states']:self.assertEqual(sha(TASK/'evaluator/d6'/s['path']),s['sha256'])
    def test_parser_rejects_sum_step_and_extra_line(self):
        from d6 import LABELS
        valid='\n'.join(x+':1.5/2' for x in LABELS)+'\nTotal:7.5/10\nReason:Visible differences.'
        self.assertEqual(parse(valid)['total'],7.5)
        for bad in [valid+'\nextra',valid.replace('7.5/10','8/10'),valid.replace('1.5/2','1.3/2',1),valid.replace('Reason:Visible differences.','Reason:')]:
            with self.assertRaises(InfrastructureError):parse(bad)
        self.assertEqual(round_decimal(7.25),7.3)
    def test_missing_black_wrong_resolution_and_corrupt_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'frame.png';Image.new('RGB',(1280,720),'black').save(p);self.assertEqual(image_fault(p),'D6_CANDIDATE_BLACK_OR_EMPTY_FRAME')
            Image.new('RGB',(300,200),'white').save(p);self.assertEqual(image_fault(p),'D6_CANDIDATE_FRAME_UNUSABLE')
            Image.new('RGB',(720,720),'white').save(p);self.assertEqual(image_fault(p),'D6_CANDIDATE_VIEWPORT_MISMATCH')
            p.write_bytes(b'corrupted evidence')
            with self.assertRaises(InfrastructureError):image_fault(p)
    def test_incomplete_and_invalid_never_publish_scores(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for raw in [{'status':'run_invalid'},{'status':'d6_pending','partial_selection':True},{'status':'d6_pending','checkpoints':{}}]:
                write(root/'raw-evaluation.json',raw)
                with self.assertRaises(InfrastructureError):score(root)
                self.assertFalse((root/'result.json').exists())
    def test_no_gold_symbols_in_scoring_or_cases(self):
        for name in ['cases.py','common.py','score.py','evaluate.py','rendered_checks.py']:
            text=(TASK/'evaluator/scripts'/name).read_text(encoding='utf-8')
            for forbidden in ['AChompGame','ChompGame.h','ChompPresentation','UpperJaw','GhostHeads']:self.assertNotIn(forbidden,text)

if __name__=='__main__':unittest.main(verbosity=2)
