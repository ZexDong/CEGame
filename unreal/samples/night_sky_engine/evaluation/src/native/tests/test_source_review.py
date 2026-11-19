"""Reject stale, tampered, out-of-scope and overbroad source-review receipts."""
import copy
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from runtime import ROOT, TASK, sha, load, write, InfrastructureError
from source_review import REVISION, OWNERS, REVIEW_PATH, rows_digest, validate, load_run_review
from coverage_gate import apply_boundary_gate


def fixture():
    content = 'void ResolveRound();\n'
    path = 'Source/Game.cpp'
    digest = hashlib.sha256(content.encode()).hexdigest()
    rows = [dict(path='Game.uproject',size=2,sha256='a'*64),
            dict(path=path,size=len(content),sha256=digest)]
    manifest = dict(files=rows,sha256=rows_digest(rows))
    review = dict(revision=REVISION,method='manual_source_control_flow_review',status='completed',
        reviewer={'identity':'test'},authorization='explicit source audit',input_gdd_sha256=sha(TASK/'input/GDD.md'),
        project_identity_sha256=rows_digest(rows),files={path:dict(content=content,sha256=digest)},
        checks={k:dict(owner=o,verdict='pass',call_path='Reviewed the complete call chain.',
            reachability='Conditional premise.',limitations='No runtime witness.',
            evidence=[dict(path=path,start=1,end=1)]) for k,o in OWNERS.items()})
    return review, manifest


class SourceReview(unittest.TestCase):
    def test_changed_candidate_and_changed_source_are_rejected(self):
        review, manifest = fixture()
        validate(review,manifest)
        changed=copy.deepcopy(manifest);changed['files'][0]['sha256']='b'*64
        with self.assertRaisesRegex(InfrastructureError,'CANDIDATE_CHANGED'):
            validate(review,changed)
        review['files']['Source/Game.cpp']['content']+='void Different();'
        with self.assertRaisesRegex(InfrastructureError,'FILE_CHANGED'):
            validate(review,manifest)

    def test_wrapper_normalization_does_not_ignore_project_changes(self):
        review, manifest = fixture()
        wrapper=copy.deepcopy(manifest)
        for r in wrapper['files']:r['path']='project/'+r['path']
        wrapper['files'].append(dict(path='GDD.md',size=1,sha256='c'*64))
        validate(review,wrapper)
        wrapper['files'].append(dict(path='project/Config/DefaultEngine.ini',size=1,sha256='d'*64))
        with self.assertRaisesRegex(InfrastructureError,'CANDIDATE_CHANGED'):
            validate(review,wrapper)

    def test_missing_reasoning_invalid_citations_and_extra_clauses_are_rejected(self):
        for mutation in ('reason','citation','scope','verdict','gdd'):
            review,manifest=fixture()
            if mutation=='reason':review['checks']['simultaneous_draw']['call_path']=''
            if mutation=='citation':review['checks']['simultaneous_draw']['evidence'][0]['end']=50
            if mutation=='scope':review['checks']['visual_quality']=review['checks']['simultaneous_draw']
            if mutation=='verdict':review['checks']['simultaneous_draw']['verdict']='unknown'
            if mutation=='gdd':review['input_gdd_sha256']='0'*64
            with self.subTest(mutation=mutation),self.assertRaises(InfrastructureError):validate(review,manifest)

    def test_run_requires_receipt_and_rejects_receipt_tampering(self):
        review,manifest=fixture()
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);write(root/'candidate-manifest.json',manifest)
            raw=dict(candidate_identity_sha256=manifest['sha256'],evidence_sha256={})
            with self.assertRaisesRegex(InfrastructureError,'SOURCE_REVIEW_REQUIRED'):load_run_review(raw,root)
            write(root/REVIEW_PATH,review);raw['evidence_sha256'][REVIEW_PATH]=sha(root/REVIEW_PATH)
            load_run_review(raw,root)
            review['checks']['simultaneous_draw']['verdict']='fail';write(root/REVIEW_PATH,review)
            with self.assertRaisesRegex(InfrastructureError,'RECEIPT_CHANGED'):load_run_review(raw,root)

    def test_source_resolves_only_draw_gap_and_never_repairs_runtime_failures(self):
        review,_=fixture();catalog=load(ROOT/'catalog/boundary-coverage.json')
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);path='states/boundary-coverage.json'
            checks={c['id']:dict(owner=c['owner'],verdict='pass',reason='runtime',evidence=['trace.json']) for c in catalog['checks']}
            checks['simultaneous_draw']['verdict']='gap'
            raw=dict(captures={'initial':{}},faults=[],evidence_sha256={path:'hash','trace.json':'hash',REVIEW_PATH:'hash'})
            actual={c['owner']:dict(verdict='pass',reason='runtime',evidence=[]) for c in catalog['checks']}
            actual['D3-04']['verdict']='fail'
            write(root/path,dict(revision=catalog['revision'],checks=checks))
            apply_boundary_gate(actual,raw,root,review)
            self.assertEqual(actual['D3-09']['verdict'],'pass')
            self.assertEqual(actual['D3-04']['verdict'],'fail')
            review['checks']['simultaneous_draw']['verdict']='fail'
            apply_boundary_gate(actual,raw,root,review)
            self.assertEqual(actual['D3-09']['verdict'],'fail')
            checks['guard_movement']['verdict']='gap'
            write(root/path,dict(revision=catalog['revision'],checks=checks))
            with self.assertRaisesRegex(InfrastructureError,'GDD_COVERAGE_INCOMPLETE:guard_movement'):
                apply_boundary_gate(actual,raw,root,review)


if __name__=='__main__':unittest.main()
