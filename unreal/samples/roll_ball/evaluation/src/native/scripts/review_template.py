"""Create a bound, intentionally incomplete human presentation review."""
import argparse
from pathlib import Path
from evidence import check_collection, sha, write
p=argparse.ArgumentParser();p.add_argument('--collection',required=True);p.add_argument('--output',required=True);a=p.parse_args()
data,catalog=check_collection(a.collection)
# Include only machine-supported/review presentation checkpoints. A reviewer
# must explicitly decide every row and attach a capture hash.
ids=set()
for case in data['cases']:
    ids.update(cid for cid,row in case.get('findings',{}).items() if row.get('machine_verdict') in ('supported','review'))
ids={c['id'] for c in catalog['checkpoints'] if c['id'] in ids and c.get('visible_review_required')}
write(a.output,dict(version='4.0.0',status='draft',reviewer=None,
    collection_sha256=sha(Path(a.collection).resolve()),checks={cid:dict(verdict=None,reason=None,evidence=[]) for cid in sorted(ids)}))
