"""Require clause evidence before a legacy checkpoint can retain full credit."""
from runtime import ROOT, load, write, InfrastructureError


def collect_boundary_report(runner):
    checks = runner.facts.get('boundary_checks', {})
    catalog = load(ROOT/'catalog/boundary-coverage.json')
    for item in catalog['checks']:
        if item['id'] not in checks:
            failed = next((j for j in runner.journeys if j['id'] == item['case_id']
                           and j['status'] == 'candidate_failure'), None)
            startup_failure = next((f for f in runner.faults if f['domain'] == 'candidate'
                                    and not f.get('case_id')), None) if not runner.journeys else None
            checks[item['id']] = dict(owner=item['owner'],
                verdict='unreachable' if failed or startup_failure else 'gap',
                reason=failed['reason'] if failed else startup_failure['code'] if startup_failure else 'BOUNDARY_EVIDENCE_NOT_COLLECTED',
                evidence=['cases/'+failed['id']+'.json'] if failed else ['candidate-manifest.json'] if startup_failure else [])
    write(runner.root/'states/boundary-coverage.json',
          {'revision': catalog['revision'], 'checks': checks})


def apply_boundary_gate(actual, raw, root, source_review=None):
    # A candidate that never reaches gameplay retains ordinary failure attribution.
    if not raw.get('captures') and any(f.get('domain') == 'candidate' for f in raw['faults']):
        return
    path = 'states/boundary-coverage.json'
    if path not in raw['evidence_sha256']:
        raise InfrastructureError('BOUNDARY_COVERAGE_REQUIRED')
    report = load(root/path); catalog = load(ROOT/'catalog/boundary-coverage.json')
    expected = {c['id']: c for c in catalog['checks']}
    if report.get('revision') != catalog['revision'] or set(report.get('checks', {})) != set(expected):
        raise InfrastructureError('BOUNDARY_COVERAGE_CONTRACT_MISMATCH')
    for key, item in report['checks'].items():
        owner = expected[key]['owner']
        if item.get('owner') != owner or item.get('verdict') not in ('pass','fail','unreachable','gap'):
            raise InfrastructureError('BOUNDARY_VERDICT_INVALID:'+key)
        if item['verdict'] == 'gap':
            if key == 'simultaneous_draw' and source_review:
                # Only the missing witness is replaced. Runtime failures survive.
                from source_review import REVIEW_PATH
                source = source_review['checks'][key]
                item = dict(owner=owner, verdict=source['verdict'],
                            reason='SOURCE_CONTROL_FLOW:'+source['call_path'], evidence=[REVIEW_PATH])
            else:
                raise InfrastructureError('GDD_COVERAGE_INCOMPLETE:'+key+':'+item.get('reason', ''))
        if not item.get('evidence') or any(e not in raw['evidence_sha256'] for e in item['evidence']):
            raise InfrastructureError('BOUNDARY_EVIDENCE_MISSING:'+key)
        if item['verdict'] != 'pass':
            actual[owner].update(verdict='fail', reason='GDD_BOUNDARY_FAILED:'+key+':'+item['reason'],
                                 evidence=list(dict.fromkeys(actual[owner]['evidence']+item['evidence'])))
    if source_review:
        from source_review import REVIEW_PATH
        for key, item in source_review['checks'].items():
            owner = item['owner']
            actual[owner]['evidence'] = list(dict.fromkeys(actual[owner]['evidence']+[REVIEW_PATH]))
            if item['verdict'] == 'fail':
                actual[owner].update(verdict='fail', reason='GDD_SOURCE_FAILED:'+key+':'+item['call_path'])
