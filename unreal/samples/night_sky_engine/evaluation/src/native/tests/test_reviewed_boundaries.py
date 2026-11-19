import copy, hashlib, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from runtime import ROOT,TASK,load,write,sha,InfrastructureError
from reviewed_boundaries import apply,REVISION,PATH

class ReviewedBoundaries(unittest.TestCase):
    def test_source_review_cannot_override_non_gap_reopen_failure(self):
        for candidate in ('candidate-one', 'candidate-two'):
            with self.subTest(candidate=candidate),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);raw,review,actual,checks,catalog=self.fixture(root)
                raw['candidate_identity_sha256']=candidate
                review['candidate_identity_sha256']=candidate
                checks['reopen_terminal']['verdict']='fail'
                actual['D4-05'].update(verdict='fail',
                    reason='REOPEN_CLEARS_PROGRESS_WITH_NEW_PROCESS')
                review['checks']['reopen_terminal']=copy.deepcopy(review['checks']['whiff_duration'])
                write(root/'states/boundary-coverage.json',dict(revision=catalog['revision'],checks=checks))
                write(root/PATH,review)
                with self.assertRaisesRegex(InfrastructureError,'OBSERVATION_SOURCE_REVIEW_SCOPE_INVALID'):
                    apply(actual,raw,root,None)
                self.assertEqual(actual['D4-05']['verdict'],'fail')

    def fixture(self,root):
        catalog=load(ROOT/'catalog/boundary-coverage.json')
        checks={c['id']:dict(owner=c['owner'],verdict='pass',reason='runtime',evidence=['trace.json']) for c in catalog['checks']}
        checks['whiff_duration']['verdict']='gap'
        write(root/'states/boundary-coverage.json',dict(revision=catalog['revision'],checks=checks))
        content='void feedback() { timer = 0.7f; }\n';digest=hashlib.sha256(content.encode()).hexdigest()
        path='project/Source/Game.cpp'
        write(root/'candidate-manifest.json',dict(files=[dict(path=path,sha256=digest)]))
        write(root/'states/presentation-source.json',dict(candidate_identity_sha256='candidate',files={path:dict(content=content,sha256=digest)}))
        write(root/'trace.json',{'samples':[1,2,3]});write(root/'raw-evaluation.json',{'identity':'fixture'})
        raw=dict(candidate_identity_sha256='candidate',evidence_sha256={p.relative_to(root).as_posix():sha(p) for p in root.rglob('*') if p.is_file()})
        review=dict(revision=REVISION,status='completed',method='manual_source_control_flow_review',reviewer='test',authorization='test',
            raw_sha256=sha(root/'raw-evaluation.json'),candidate_identity_sha256='candidate',input_gdd_sha256=sha(TASK/'input/GDD.md'),checks={
                'whiff_duration':dict(verdict='pass',reason='bounded timer',call_path='assignment to decrement to HUD',limitations='sample bracketing',
                    source_citations=[dict(path=path,start=1,end=1)],runtime_evidence=['trace.json'])})
        write(root/PATH,review)
        actual={c['owner']:dict(verdict='pass',reason='runtime',evidence=[]) for c in catalog['checks']}
        return raw,review,actual,checks,catalog

    def test_source_gap_pass_cannot_repair_mechanical_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);raw,review,actual,_,_=self.fixture(root)
            actual['D5-03']['verdict']='fail'
            apply(actual,raw,root,None)
            self.assertEqual(actual['D5-03']['verdict'],'fail')

    def test_source_failure_propagates_to_existing_owner(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);raw,review,actual,_,_=self.fixture(root)
            review['checks']['whiff_duration']['verdict']='fail';write(root/PATH,review)
            apply(actual,raw,root,None)
            self.assertEqual(actual['D5-03']['verdict'],'fail')

    def test_non_gap_override_and_stale_or_uncited_review_rejected(self):
        for mutation in ('runtime-fail','extra','stale','citation','source'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);raw,review,actual,checks,catalog=self.fixture(root)
                if mutation=='runtime-fail':
                    checks['whiff_duration']['verdict']='fail';write(root/'states/boundary-coverage.json',dict(revision=catalog['revision'],checks=checks))
                if mutation=='extra':review['checks']['guard_movement']=copy.deepcopy(review['checks']['whiff_duration'])
                if mutation=='stale':review['raw_sha256']='changed'
                if mutation=='citation':review['checks']['whiff_duration']['source_citations'][0]['end']=900
                if mutation=='source':write(root/'states/presentation-source.json',{})
                write(root/PATH,review)
                with self.assertRaises(InfrastructureError):apply(actual,raw,root,None)
