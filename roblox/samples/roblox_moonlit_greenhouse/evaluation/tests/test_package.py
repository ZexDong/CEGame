from pathlib import Path
import json,unittest,importlib.util
E=Path(__file__).resolve().parents[1]
class PackageTests(unittest.TestCase):
 def test_structure(self):
  self.assertEqual({p.name for p in E.iterdir() if p.name!='__pycache__'},{'d6','output-template','src','tests','coverage.json','evaluate.py','requirements.txt','rules.json','score.schema.json','validate_score.py'})
 def test_output_example(self):
  spec=importlib.util.spec_from_file_location('template',E/'validate_score.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  d=json.loads((E/'output-template/score.json').read_text(encoding='utf-8'));m.validate(d)
  with self.assertRaises(ValueError):m.validate(d,require_final=True)
if __name__=='__main__':unittest.main()
