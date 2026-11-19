"""Resolve explicit collection gaps using bound source and runtime evidence.

Collected evidence is immutable. Source review cannot override a runtime
failure and applies the same predicates to every candidate.
"""
from runtime import ROOT, TASK, load, sha, InfrastructureError
from source_review import project_rows

REVISION = 'nightsky-observation-source-review-1'
PATH = 'observation-source-review.json'

def apply(actual, raw, root, source):
    from coverage_gate import apply_boundary_gate
    if not (root/PATH).exists():
        return apply_boundary_gate(actual, raw, root, source)
    report = load(root/'states/boundary-coverage.json')
    catalog = load(ROOT/'catalog/boundary-coverage.json')
    expected = {c['id']: c for c in catalog['checks']}
    if report.get('revision') != catalog['revision'] or set(report.get('checks', {})) != set(expected):
        raise InfrastructureError('BOUNDARY_COVERAGE_CONTRACT_MISMATCH')
    review = load(root/PATH)
    if (review.get('revision') != REVISION or review.get('status') != 'completed'
            or review.get('method') != 'manual_source_control_flow_review'
            or not review.get('reviewer') or not review.get('authorization')
            or review.get('raw_sha256') != sha(root/'raw-evaluation.json')
            or review.get('candidate_identity_sha256') != raw['candidate_identity_sha256']
            or review.get('input_gdd_sha256') != sha(TASK/'input/GDD.md')):
        raise InfrastructureError('OBSERVATION_SOURCE_REVIEW_BINDING_INVALID')
    gaps = {key for key, item in report['checks'].items()
            if item['verdict'] == 'gap' and key != 'simultaneous_draw'}
    if set(review.get('checks', {})) != gaps:
        raise InfrastructureError('OBSERVATION_SOURCE_REVIEW_SCOPE_INVALID')
    snapshot_path = 'states/presentation-source.json'
    if raw['evidence_sha256'].get(snapshot_path) != sha(root/snapshot_path):
        raise InfrastructureError('OBSERVATION_SOURCE_SNAPSHOT_CHANGED')
    snapshot = load(root/snapshot_path)
    manifest = load(root/'candidate-manifest.json')
    rows = {r['path']: r for r in manifest['files']}
    if snapshot.get('candidate_identity_sha256') != raw['candidate_identity_sha256']:
        raise InfrastructureError('OBSERVATION_SOURCE_CANDIDATE_CHANGED')
    import hashlib
    for key in gaps:
        item = review['checks'][key]
        if (item.get('verdict') not in ('pass', 'fail') or not item.get('reason')
                or not item.get('call_path') or not item.get('limitations')
                or not item.get('source_citations') or not item.get('runtime_evidence')
                or any(p not in raw['evidence_sha256'] for p in item['runtime_evidence'])):
            raise InfrastructureError('OBSERVATION_SOURCE_REASONING_REQUIRED:'+key)
        for citation in item['source_citations']:
            path = citation['path']; embedded = snapshot['files'].get(path)
            if (not embedded or path not in rows
                    or hashlib.sha256(embedded['content'].encode('utf-8')).hexdigest() != rows[path]['sha256']
                    or embedded['sha256'] != rows[path]['sha256']
                    or not 1 <= citation['start'] <= citation['end'] <= len(embedded['content'].splitlines())):
                raise InfrastructureError('OBSERVATION_SOURCE_CITATION_INVALID:'+key)
        report['checks'][key] = dict(owner=expected[key]['owner'], verdict=item['verdict'],
            reason='SOURCE_CORROBORATED_OBSERVATION:'+item['reason'],
            evidence=item['runtime_evidence']+[snapshot_path, PATH])
    raw['evidence_sha256'][PATH] = sha(root/PATH)
    # Same catalog, owners, negative propagation and source-DRAW rule as 3.1.1.
    for key, item in report['checks'].items():
        owner = expected[key]['owner']
        if item.get('owner') != owner or item.get('verdict') not in ('pass','fail','unreachable','gap'):
            raise InfrastructureError('BOUNDARY_VERDICT_INVALID:'+key)
        if item['verdict'] == 'gap':
            if key != 'simultaneous_draw' or not source:
                raise InfrastructureError('GDD_COVERAGE_INCOMPLETE:'+key)
            item = dict(source['checks'][key], reason='SOURCE_CONTROL_FLOW:'+source['checks'][key]['call_path'],
                        evidence=['states/source-review.json'])
        if not item.get('evidence') or any(p not in raw['evidence_sha256'] for p in item['evidence']):
            raise InfrastructureError('BOUNDARY_EVIDENCE_MISSING:'+key)
        if item['verdict'] != 'pass':
            actual[owner].update(verdict='fail', reason='GDD_BOUNDARY_FAILED:'+key+':'+item['reason'],
                evidence=list(dict.fromkeys(actual[owner]['evidence']+item['evidence'])))
    if source:
        for key, item in source['checks'].items():
            owner = item['owner']
            actual[owner]['evidence'] = list(dict.fromkeys(actual[owner]['evidence']+['states/source-review.json']))
            if item['verdict'] == 'fail':
                actual[owner].update(verdict='fail', reason='GDD_SOURCE_FAILED:'+key+':'+item['call_path'])
