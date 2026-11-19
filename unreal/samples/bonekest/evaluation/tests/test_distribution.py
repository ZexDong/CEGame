"""Small distribution and attribution tests, not game coverage qualification."""
import importlib.util, json, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('distribution_adapter',ROOT/'src/score_adapter.py')
adapter=importlib.util.module_from_spec(spec);spec.loader.exec_module(adapter)
class DistributionTests(unittest.TestCase):
 def test_actual_rule_weights_and_requirement_mapping(self):
  rules=json.loads((ROOT/'rules.json').read_text(encoding='utf-8'))['checks']
  self.assertEqual(len({r['id'] for r in rules}),len(rules))
  for d,m in adapter.MAXIMA.items():self.assertAlmostEqual(sum(c['max_score'] for c in rules if c['dimension']==d),m,places=6)
  self.assertTrue(all(c['requirement_ids'] for c in rules))
 def test_unreachable_is_not_silently_zero(self):
  meta=json.loads((ROOT.parent/'sample.json').read_text(encoding='utf-8'));rule=json.loads((ROOT/'rules.json').read_text(encoding='utf-8'))['checks'][0]
  with tempfile.TemporaryDirectory() as name:
   out=Path(name);(out/'native').mkdir();(out/'evidence').mkdir();(out/'evidence/entry.json').write_text('{}')
   (out/'native/checks.json').write_text(json.dumps({rule['id']:{'verdict':'unreachable','reason':'precondition unavailable'}}))
   result=adapter.convert_result(ROOT,out,meta,'Incomplete fixture binding')
   c=next(c for c in result['checks'] if c['id']==rule['id'])
   self.assertEqual(c['status'],'inconclusive_evaluator');self.assertIsNone(c['score']);self.assertIsNone(result['final_score'])
 def test_observed_dimension_survives_unrelated_infrastructure_fault(self):
  meta=json.loads((ROOT.parent/'sample.json').read_text(encoding='utf-8'));rules=json.loads((ROOT/'rules.json').read_text(encoding='utf-8'))['checks']
  with tempfile.TemporaryDirectory() as name:
   out=Path(name);(out/'native').mkdir();(out/'evidence').mkdir();(out/'evidence/entry.json').write_text('{}')
   (out/'native/checks.json').write_text(json.dumps({r['id']:{'verdict':'pass','reason':'observed'} for r in rules if r['dimension']=='D1'}))
   result=adapter.convert_result(ROOT,out,meta,'Provider unavailable',infrastructure=True)
   self.assertEqual(result['dimensions']['D1']['score'],10);self.assertEqual(result['classification'],'infrastructure_failure');self.assertIsNone(result['final_score'])
 def test_powershell_checkpoint_ids_and_run_faults_are_preserved(self):
  meta=json.loads((ROOT.parent/'sample.json').read_text(encoding='utf-8'));rule=json.loads((ROOT/'rules.json').read_text(encoding='utf-8'))['checks'][0]
  with tempfile.TemporaryDirectory() as name:
   out=Path(name);(out/'native').mkdir();(out/'evidence').mkdir();(out/'evidence/entry.json').write_text('{}')
   (out/'native/verdicts.json').write_text(json.dumps({'run_status':'run_invalid','checkpoints':[{'checkpoint_id':rule['id'],'verdict':'fail','detail':'Observed descriptor failure'}]}))
   result=adapter.convert_result(ROOT,out,meta,'Native provider fault')
   self.assertEqual(result['classification'],'infrastructure_failure')
   check=next(c for c in result['checks'] if c['id']==rule['id']);self.assertEqual(check['score'],0)
if __name__=='__main__':unittest.main()
