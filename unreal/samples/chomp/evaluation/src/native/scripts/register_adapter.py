"""Bind a separately authored scaffold adapter after its semantic review."""
from common import *
import argparse
p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--source',required=True);p.add_argument('--module',required=True);p.add_argument('--review',required=True);p.add_argument('--output',required=True);a=p.parse_args()
source=Path(a.source).resolve();output=Path(a.output).resolve();review=load(a.review)
for field in ['semantic_lookup','atomic_validation','no_outcome_calls','public_observer_unchanged','renderer_mapping','art_derivation_mapping']:
    if not review.get(field):raise InfrastructureError('ADAPTER_REVIEW_MISSING:'+field)
if source.parent!=output.parent:raise InfrastructureError('KEEP_ADAPTER_AND_BINDING_TOGETHER')
write(output,{'version':'1.0.0','kind':'candidate','source':source.name,'source_sha256':sha(source),'candidate_identity':identity(Path(a.candidate))['sha256'],'module':a.module,'review':review})
