"""Attribute failed public capabilities only to their frozen dependent leaves."""
from __future__ import annotations
import json
from pathlib import Path

def require(value,message):
    if not value:raise ValueError(message)

def affected_leaves(manifest,dependencies,receipt):
    """Receipts must be hash-bound by the surrounding evidence/scoring pipeline.

    This function grants no PASS and no points. A product-block classification
    needs a published capability and independently executed service evidence.
    """
    require(manifest.get('public_session_required') is True and manifest.get('session_contract_version')=='game-session/v1','session service was not required by this frozen input')
    require('confirmed_failed_capabilities' not in receipt,'additional failures require their own complete evidence receipts')
    records=[receipt]+receipt.get('other_failure_receipts',[])
    for record in records:
        require(record.get('execution_valid') is True and record.get('host_healthy') is True,
                'service request was not reliably executed')
        require(record.get('request_valid_under_public_contract') is True,'invalid author request is not a candidate failure')
        require(record.get('capability') in dependencies['public_capabilities'],'capability is not in the frozen dependency contract')
        require(record.get('status')=='PRODUCT_CONTRACT_FAILURE','not an observed public service failure')
        require(bool(record.get('independent_evidence')),'a service self-report cannot establish its own failure')
    # Each leaf contains alternative sufficient routes. One failed route never
    # blocks a leaf while another registered route remains available.
    failures={record['capability'] for record in records}
    result=[]
    for leaf in dependencies['leaves']:
        routes=leaf['alternative_routes']
        require(routes and all(route for route in routes),'empty dependency route')
        if all(any(part in failures for part in route) for route in routes):
            result.append({'check_id':leaf['check_id'],'status':'BLOCKED_BY_PRODUCT',
                           'attribution':'published_service_not_delivered',
                           'product_block_reason':'; '.join(record['reason'] for record in records if any(record['capability'] in route for route in routes)),
                           'gameplay_failure_observed':False})
    return result

def validate_dependency_contract(contract,all_leaf_ids):
    leaves=contract['leaves'];ids=[x['check_id'] for x in leaves]
    require(len(ids)==len(set(ids)) and set(ids)==set(all_leaf_ids),'dependency graph must bind every leaf exactly once')
    capabilities=set(contract['public_capabilities'])
    for leaf in leaves:
        require(leaf['alternative_routes'] and all(route and set(route)<=capabilities for route in leaf['alternative_routes']),
                'unknown or empty dependency route')
    return True
