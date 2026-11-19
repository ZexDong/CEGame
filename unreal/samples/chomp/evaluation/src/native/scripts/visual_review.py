"""D2/D5 rendered-evidence gate, distinct from comparative D6 aesthetics.

Deterministic pixels/OCR and native renderer evidence bind each finding to
capture hashes. This module performs no VLM or reference-image comparison.
"""
from common import *

def apply(root,raw,catalog):
    root=Path(root);needed={c['id'] for c in catalog['checks'] if c['dimension'] in ['D2','D5'] and raw['checkpoints'][c['id']]['verdict']=='pass'}
    if not needed:return raw
    path=root/'rendered-review.json'
    if not path.exists():raise InfrastructureError('RENDERED_REVIEW_PENDING')
    review=load(path)
    if review.get('candidate_identity')!=raw['candidate']['sha256']:raise InfrastructureError('RENDERED_REVIEW_IDENTITY')
    if not needed<=set(review.get('checks',{})):raise InfrastructureError('RENDERED_REVIEW_INCOMPLETE')
    for id in needed:
        item=review['checks'][id]
        if item.get('verdict') not in ['pass','fail'] or not item.get('reason') or not item.get('captures'):raise InfrastructureError('RENDERED_REVIEW_INVALID:'+id)
        for capture in item['captures']:
            image=(root/capture['path']).resolve()
            if not image.is_relative_to(root.resolve()) or sha(image)!=capture['sha256']:raise InfrastructureError('RENDERED_REVIEW_CAPTURE_CHANGED')
        raw['checkpoints'][id]['rendered_review']=item
        if item['verdict']=='fail':raw['checkpoints'][id].update(verdict='fail',reason=item['reason'],attribution='candidate')
    return raw
