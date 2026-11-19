"""Evidence-bound manual source review for two explicitly authorized observation gaps.

This validates a review receipt; it does not infer correctness from source keywords.
"""
import hashlib
import json
from pathlib import PurePosixPath
from runtime import TASK, load, sha, InfrastructureError

REVISION = 'nightsky-source-review-3.1.1'
OWNERS = {'simultaneous_draw': 'D3-09', 'missed_bolt_cleanup': 'D3-04'}
REVIEW_PATH = 'states/source-review.json'


def rows_digest(rows):
    return hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def project_rows(manifest):
    """Allow the same project packaged directly or inside an input manifest root."""
    rows = manifest['files']
    descriptors = [r['path'] for r in rows if r['path'].endswith('.uproject')]
    if len(descriptors) != 1:
        raise InfrastructureError('SOURCE_REVIEW_PROJECT_AMBIGUOUS')
    prefix = descriptors[0].rsplit('/', 1)[0]+'/' if '/' in descriptors[0] else ''
    return sorted([dict(r, path=r['path'][len(prefix):]) for r in rows
                   if r['path'].startswith(prefix)], key=lambda r: r['path'])


def validate(review, manifest):
    if (review.get('revision') != REVISION or review.get('method') != 'manual_source_control_flow_review'
            or review.get('status') != 'completed'):
        raise InfrastructureError('SOURCE_REVIEW_CONTRACT_MISMATCH')
    if review.get('input_gdd_sha256') != sha(TASK/'input/GDD.md'):
        raise InfrastructureError('SOURCE_REVIEW_GDD_CHANGED')
    if not review.get('reviewer', {}).get('identity') or not review.get('authorization'):
        raise InfrastructureError('SOURCE_REVIEW_PROVENANCE_REQUIRED')
    rows = project_rows(manifest)
    if review.get('project_identity_sha256') != rows_digest(rows):
        raise InfrastructureError('SOURCE_REVIEW_CANDIDATE_CHANGED')
    indexed = {r['path']: r for r in rows}
    files = review.get('files', {})
    for path, item in files.items():
        p = PurePosixPath(path)
        if p.is_absolute() or '..' in p.parts or p.parts[0] != 'Source':
            raise InfrastructureError('SOURCE_REVIEW_FILE_SCOPE')
        data = item['content'].encode('utf-8')
        digest = hashlib.sha256(data).hexdigest()
        if (digest != item.get('sha256') or path not in indexed
                or indexed[path]['sha256'] != digest or indexed[path]['size'] != len(data)):
            raise InfrastructureError('SOURCE_REVIEW_FILE_CHANGED:'+path)
    if set(review.get('checks', {})) != set(OWNERS):
        raise InfrastructureError('SOURCE_REVIEW_CLAUSE_SCOPE')
    for key, item in review['checks'].items():
        if item.get('owner') != OWNERS[key] or item.get('verdict') not in ('pass', 'fail'):
            raise InfrastructureError('SOURCE_REVIEW_VERDICT_INVALID:'+key)
        if any(not item.get(k) for k in ('call_path', 'reachability', 'limitations', 'evidence')):
            raise InfrastructureError('SOURCE_REVIEW_REASONING_REQUIRED:'+key)
        for ref in item['evidence']:
            source = files.get(ref.get('path'))
            start, end = ref.get('start'), ref.get('end')
            if (source is None or type(start) is not int or type(end) is not int
                    or not 1 <= start <= end <= len(source['content'].splitlines())):
                raise InfrastructureError('SOURCE_REVIEW_CITATION_INVALID:'+key)
    return review


def load_run_review(raw, root):
    if REVIEW_PATH not in raw['evidence_sha256']:
        raise InfrastructureError('SOURCE_REVIEW_REQUIRED')
    if sha(root/REVIEW_PATH) != raw['evidence_sha256'][REVIEW_PATH]:
        raise InfrastructureError('SOURCE_REVIEW_RECEIPT_CHANGED')
    manifest = load(root/'candidate-manifest.json')
    if (manifest.get('sha256') != raw['candidate_identity_sha256']
            or rows_digest(manifest['files']) != manifest['sha256']):
        raise InfrastructureError('SOURCE_REVIEW_MANIFEST_CHANGED')
    return validate(load(root/REVIEW_PATH), manifest)
