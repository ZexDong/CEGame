"""Format regression tests only; no gameplay judgments or model reevaluation."""
from pathlib import Path
import importlib.util
import json
import sys
import tempfile
import unittest

E=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(E/'src'))
from export_v2 import export_result
spec=importlib.util.spec_from_file_location('v2_validator',E/'validate_score.py')
validator=importlib.util.module_from_spec(spec); spec.loader.exec_module(validator)

def fixture():
    return {'schema_version':'tide-lock-score-v1','runner_valid':True,'adjudication_complete':True,
        'official_score':30.2,'unresolved':[],'problems':[],
        'breakdown':[{'dimension':d,'possible':m,'score':s,
            'checkpoints':[{'id':'fixture.'+d,'status':'pass' if s else 'fail','detail':'Synthetic format fixture, not a real run.'}]} 
            for d,m,s in [('D1',10,10),('D2',30,6),('D3',20,0),('D4',20,6.7),('D5',10,4),('D6',10,3.5)]]}

class V2ExportTests(unittest.TestCase):
    def test_original_values_and_total_preserved(self):
        raw=fixture()
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            result=export_result(raw,out,{'requirements':[]})
            validator.validate(result,out,require_final=True,check_evidence=True)
            self.assertEqual(result['final_score'],30.2)
            for row in raw['breakdown']:
                self.assertEqual(result['dimensions'][row['dimension']]['score'],row['score'])
            self.assertEqual(json.loads((out/'evidence/native-score.json').read_text(encoding='utf-8')),raw)
    def test_uncertainty_is_not_changed_into_zero_or_pass(self):
        raw=fixture()
        raw['adjudication_complete']=False; raw['official_score']=None
        raw['unresolved']=['fixture.D3']
        raw['breakdown'][2]['checkpoints'][0]['status']='inconclusive'
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory); result=export_result(raw,out,{'requirements':[]})
            validator.validate(result,out,check_evidence=True)
            self.assertIsNone(result['dimensions']['D3']['score'])
            self.assertIsNone(result['final_score'])
            self.assertEqual(raw['breakdown'][2]['score'],0)
    def test_not_run_example_remains_not_run(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory); result=export_result({},out,{'requirements':[]},not_run=True)
            validator.validate(result,out,check_evidence=True)
            self.assertEqual(result['classification'],'not_run')
            self.assertTrue(all(v['status']=='not_run' for v in result['dimensions'].values()))
    def test_host_failure_is_not_a_candidate_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            result=export_result({},out,{'requirements':[]},infrastructure_error='Synthetic missing-tool fixture.')
            validator.validate(result,out,check_evidence=True)
            self.assertEqual(result['classification'],'infrastructure_failure')
            self.assertIsNone(result['final_score'])

if __name__=='__main__': unittest.main()
