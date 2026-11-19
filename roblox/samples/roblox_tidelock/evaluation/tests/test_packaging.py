from pathlib import Path
import hashlib, importlib.util, json, unittest

E=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('template_validator',E/'validate_score.py')
v=importlib.util.module_from_spec(spec); spec.loader.exec_module(v)

class PackagingTests(unittest.TestCase):
    def test_exact_template_top_level(self):
        expected={'d6','output-template','src','tests','coverage.json','evaluate.py','requirements.txt','rules.json','score.schema.json','validate_score.py'}
        self.assertEqual({p.name for p in E.iterdir() if p.name!='__pycache__'},expected)
    def test_unexecuted_output_is_valid_but_not_final(self):
        d=json.loads((E/'output-template/score.json').read_text(encoding='utf-8'))
        v.validate(d)
        with self.assertRaises(ValueError): v.validate(d,require_final=True)
    def test_prompt_is_recovered_original(self):
        protocol=json.loads((E/'d6/protocol.json').read_text(encoding='utf-8'))
        self.assertEqual(hashlib.sha256((E/'d6/prompt.txt').read_bytes()).hexdigest(),protocol['original_prompt_sha256'])
        self.assertEqual(len(protocol['five_visual_aspects']),5)

if __name__=='__main__': unittest.main()
