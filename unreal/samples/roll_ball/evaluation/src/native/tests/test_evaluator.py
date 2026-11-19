import json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
from runtime import interval_verdict
from evidence import InvalidEvidence,resolve,read,check_collection,ROOT
from navigation import route

class ContractTests(unittest.TestCase):
    def test_timing_boundary_is_review(self):
        self.assertEqual(interval_verdict(.74,.80,.75,2),'review')
        self.assertEqual(interval_verdict(.80,1.2,.75,2),'pass')
        self.assertEqual(interval_verdict(.1,.7,.75,2),'fail')
    def test_public_route_avoids_traps(self):
        path=route((0,0),(9,9))
        self.assertTrue(path)
        self.assertNotIn((1,1),[cell for cell,key in path])
    def test_evidence_path_escape_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); (root/'ok').write_text('x')
            with self.assertRaises(InvalidEvidence): resolve(root,'../outside')
            with self.assertRaises(InvalidEvidence): resolve(root,'C:/outside')
    def test_duplicate_and_nonfinite_json_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'bad.json';p.write_text('{"x":1,"x":2}')
            with self.assertRaises(InvalidEvidence): read(p)
            p.write_text('{"x":NaN}')
            with self.assertRaises(InvalidEvidence): read(p)
    def test_collection_binding_and_case_path_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t); run=root/'run'; run.mkdir()
            bad=root/'bad.json'
            bad.write_text('{"version":"4.0.0","catalog_sha256":"bad","cases":[],"faults":[]}')
            with self.assertRaises(InvalidEvidence): check_collection(bad)
            bad.write_text('{"version":"4.0.0","catalog_sha256":"'+__import__('hashlib').sha256((ROOT/'catalog/checkpoints.json').read_bytes()).hexdigest()+'","cases":[{"id":"..","findings":{}}],"faults":[]}')
            with self.assertRaises(InvalidEvidence): check_collection(bad)

if __name__=='__main__': unittest.main()
