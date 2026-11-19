"""Shared visual protocol validation, model configuration and candidate attribution."""
import hashlib
import json
import re
from urllib.parse import urlsplit
from PIL import Image, ImageStat
from runtime import ROOT, REPO, load, sha, inside, InfrastructureError


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def protocol():
    p = load(ROOT/'d6/protocol.json')
    m = load(ROOT/'d6/d6-reference-manifest.json')
    guide = REPO/p['scoring_guide']
    if sha(guide) != p['scoring_guide_sha256']:
        raise InfrastructureError('D6_CANONICAL_GUIDE_CHANGED')
    if p.get('revision') != 'nightsky-visual-3.2.0' or p.get('scope') != 'NightSkyEngine':
        raise InfrastructureError('D6_TASK_RUBRIC_REQUIRED')
    rubric = inside(ROOT/'d6', p['rubric'])
    if sha(rubric) != p['rubric_sha256']:
        raise InfrastructureError('D6_TASK_RUBRIC_CHANGED')
    prompt = re.search(r'```text\n(.*?)\n```', rubric.read_text(encoding='utf-8'), re.S)[1]
    expected = prompt+'\n'
    if (ROOT/'d6/FIXED_VLM_PROMPT.txt').read_text(encoding='utf-8') != expected or sha(ROOT/'d6/FIXED_VLM_PROMPT.txt') != p['prompt_sha256']:
        raise InfrastructureError('D6_CANONICAL_PROMPT_CHANGED')
    if (m.get('protocol') != p['revision'] or m.get('prompt_sha256') != p['prompt_sha256']
        or m.get('scoring_guide_sha256') != p['scoring_guide_sha256']
        or m.get('rubric_sha256') != p['rubric_sha256']):
        raise InfrastructureError('D6_MANIFEST_PROTOCOL_MISMATCH')
    if not 3 <= len(m['states']) <= 5 or len({s['id'] for s in m['states']}) != len(m['states']) or m['vlm_rounds'] != 3 or p['rounds'] != 3 or p['state_weighting'] != 'equal':
        raise InfrastructureError('D6_PROTOCOL_INVALID')
    for s in m['states']:
        path = inside(ROOT/'d6', s['reference'])
        if not path.is_file() or sha(path) != s['sha256']:
            raise InfrastructureError('D6_REFERENCE_CHANGED')
        with Image.open(path) as im:
            if list(im.size) != m['delivered_size']:
                raise InfrastructureError('D6_REFERENCE_SIZE_INVALID')
    return m


def configured(config):
    for key in ('provider','model','model_version','base_url'):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise InfrastructureError('VLM_CONFIGURATION_REQUIRED:'+key)
    url = urlsplit(config['base_url'])
    if not url.hostname or url.username or url.password or url.query or url.fragment:
        raise InfrastructureError('VLM_ENDPOINT_INVALID')
    allow_http = config.get('allow_configured_http', False)
    if type(allow_http) is not bool:
        raise InfrastructureError('VLM_TRANSPORT_POLICY_INVALID')
    if url.scheme != 'https' and not (url.scheme == 'http' and (url.hostname in ('localhost','127.0.0.1','::1') or allow_http)):
        raise InfrastructureError('VLM_ENDPOINT_REQUIRES_TLS')
    params = config.get('parameters', {})
    if not isinstance(params, dict) or set(params) & {'messages','model','stream','api_key','authorization'}:
        raise InfrastructureError('VLM_PARAMETERS_INVALID')
    timeout = config.get('timeout_seconds', 180)
    detail = config.get('image_detail', 'high')
    if type(timeout) not in (int,float) or not 1 <= timeout <= 600 or detail not in ('auto','low','high'):
        raise InfrastructureError('VLM_CALL_SETTINGS_INVALID')
    result = {key:config[key] for key in ('provider','model','model_version')}
    result.update(parameters=params, timeout_seconds=timeout, image_detail=detail,
                  endpoint_sha256=hashlib.sha256(config['base_url'].rstrip('/').encode()).hexdigest())
    if allow_http:
        result['transport_policy'] = 'explicit_existing_provider_http'
    digest(result)
    return result


def candidate_status(raw, root, state):
    c = raw['captures'].get(state['candidate_capture'])
    if not c or c.get('state_reached') is False:
        faults = [f for f in raw['faults'] if f.get('domain') == 'candidate' and f.get('case_id') in (None,state['capture_case'])]
        if not faults:
            raise InfrastructureError('D6_CAPTURE_GAP_WITHOUT_CANDIDATE_CAUSE:'+state['id'])
        return 'candidate_missing', faults[0]['code'], c
    path = inside(root,c['path'])
    if not path.is_file() or sha(path) != c['sha256']:
        raise InfrastructureError('D6_CANDIDATE_IMAGE_CHANGED')
    with Image.open(path) as im:
        stat = ImageStat.Stat(im.convert('RGB'))
        if im.size != (c['width'],c['height']):
            raise InfrastructureError('D6_CAPTURE_SIZE_CHANGED')
        visible = max(stat.mean)>3 and max(stat.stddev)>2
    if visible != c['visible']:
        raise InfrastructureError('D6_CAPTURE_VISIBILITY_CHANGED')
    if not visible:
        return 'candidate_black','CANDIDATE_BLACK_FRAME',c
    ref = c.get('visual_failure_review')
    if ref:
        path = inside(root,ref['path'])
        if raw['evidence_sha256'].get(ref['path']) != ref['sha256'] or sha(path) != ref['sha256']:
            raise InfrastructureError('D6_CAPTURE_REVIEW_CHANGED')
        review = load(path)
        if (review.get('method') not in ('human_capture_review','runtime_evidence_audit') or review.get('candidate_sha256') != c['sha256']
            or review.get('status') not in ('candidate_broken','candidate_incomparable') or not review.get('reason')):
            raise InfrastructureError('D6_CAPTURE_REVIEW_INVALID')
        if review['method']=='runtime_evidence_audit':
            if (review.get('reviewer',{}).get('kind')!='agent_runtime_evidence_audit'
                or not review.get('reviewer',{}).get('identity') or not review.get('observations')):
                raise InfrastructureError('D6_CAPTURE_REVIEW_PROVENANCE_REQUIRED')
        return review['status'],review['reason'],c
    return 'compared','',c


def request_receipt(state,capture,config,roundno):
    prompt = (ROOT/'d6/FIXED_VLM_PROMPT.txt').read_text(encoding='utf-8').replace('{{CURRENT_STATE_LABEL}}',state['label'])
    return {'round':roundno,'state_id':state['id'],'model_config_sha256':digest(config),
            'model':config['model'],'parameters':config['parameters'],'image_detail':config['image_detail'],
            'prompt':prompt,'image_order':['reference','candidate'],'reference_sha256':state['sha256'],'candidate_sha256':capture['sha256']}


def validate_result(d6,raw,root):
    from d6 import parse
    m = protocol()
    for key,path in (('manifest_sha256','d6-reference-manifest.json'),('prompt_sha256','FIXED_VLM_PROMPT.txt'),('protocol_sha256','protocol.json')):
        if d6.get(key) != sha(ROOT/'d6'/path):
            raise InfrastructureError('D6_CONTRACT_CHANGED:'+key)
    if d6.get('schema_version') != '3.0.0' or d6.get('status') != 'completed':
        raise InfrastructureError('D6_INCOMPLETE')
    rounds = d6.get('rounds',[])
    if [r['number'] for r in rounds] != [1,2,3]:
        raise InfrastructureError('D6_REQUIRES_THREE_ROUNDS')
    config = d6.get('model_config',{})
    if d6.get('model_config_sha256') != digest(config):
        raise InfrastructureError('D6_CONFIGURATION_CHANGED')
    means=[];compared=[];used=set()
    for r in rounds:
        if [s['id'] for s in r['states']] != [s['id'] for s in m['states']]:
            raise InfrastructureError('D6_STATE_SET_MISMATCH')
        values=[]
        for entry,state in zip(r['states'],m['states']):
            criteria=entry['criteria']
            if len(criteria)!=5 or any(type(v) not in (int,float) or v not in (0,.5,1,1.5,2) for v in criteria):
                raise InfrastructureError('D6_CRITERIA_INVALID')
            status,reason,capture=candidate_status(raw,root,state)
            if (entry['status']!=status or entry['reference_sha256']!=state['sha256']
                or entry['candidate_sha256']!=(capture['sha256'] if capture else None)):
                raise InfrastructureError('D6_PAIR_IDENTITY_OR_STATUS_CHANGED')
            if status!='compared':
                if any(criteria) or entry['reason']!=reason:
                    raise InfrastructureError('D6_ZERO_FALLBACK_INVALID')
            else:
                if any(k not in config for k in ('provider','model','model_version','parameters','image_detail','endpoint_sha256','timeout_seconds')):
                    raise InfrastructureError('D6_MODEL_METADATA_MISSING')
                artifacts={}
                for key in ('request','response','parser'):
                    ref=entry[key];path=inside(root,ref['path'])
                    if not path.is_file() or sha(path)!=ref['sha256']:
                        raise InfrastructureError('D6_RAW_EVIDENCE_CHANGED')
                    artifacts[key]=load(path)
                if artifacts['request']!=request_receipt(state,capture,config,r['number']):
                    raise InfrastructureError('D6_REQUEST_BINDING_INVALID')
                pair=(entry['request']['path'],entry['response']['path'])
                if pair in used:raise InfrastructureError('D6_ROUND_EVIDENCE_REUSED')
                used.add(pair)
                response=artifacts['response']
                if not d6.get('model_returned') or response.get('model')!=d6['model_returned']:
                    raise InfrastructureError('D6_MODEL_IDENTITY_INVALID')
                values_parsed,reason_parsed=parse(response['choices'][0]['message']['content'])
                if criteria!=values_parsed or entry['reason']!=reason_parsed or artifacts['parser']!={'criteria':values_parsed,'reason':reason_parsed}:
                    raise InfrastructureError('D6_PARSER_OR_CRITERIA_CHANGED')
                compared.append(entry)
            values.append(sum(criteria))
        means.append(sum(values)/len(values))
    if compared:
        expected={'model_config_sha256':digest(config),'returned_model':d6['model_returned'],'two_images_accepted':True,
                  'request':compared[0]['request'],'response':compared[0]['response']}
        if d6.get('capability_receipt')!=expected:
            raise InfrastructureError('D6_CAPABILITY_RECEIPT_INVALID')
    elif config!={'execution':'not_required_all_states_candidate_zero'}:
        raise InfrastructureError('D6_ZERO_CONFIGURATION_INVALID')
    return means
