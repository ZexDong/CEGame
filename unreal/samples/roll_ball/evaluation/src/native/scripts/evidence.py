"""Shared private evidence validation for the RollBall v4 collection format.

This module validates hashes, JSON and image transport only.  It deliberately
does not inspect candidate classes or infer gameplay from source text.
"""
from pathlib import Path
import hashlib, json, math, re
from PIL import Image, ImageStat
ROOT = Path(__file__).resolve().parents[1]
class InvalidEvidence(ValueError): pass

def read(path):
    def unique(pairs):
        out={}
        for k,v in pairs:
            if k in out: raise InvalidEvidence('DUPLICATE_JSON_KEY:'+k)
            out[k]=v
        return out
    def finite_float(value):
        n=float(value)
        if not math.isfinite(n):raise InvalidEvidence('NONFINITE_JSON')
        return n
    return json.loads(Path(path).read_text(encoding='utf-8-sig'),object_pairs_hook=unique,parse_float=finite_float,parse_constant=lambda s: (_ for _ in ()).throw(InvalidEvidence('NONFINITE_JSON')))

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(path,value): Path(path).write_bytes((json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode('utf-8'))
def resolve(root,relative):
    root=Path(root).resolve();p=Path(relative)
    if p.is_absolute() or ':' in relative or '\\' in relative or '..' in p.parts: raise InvalidEvidence('EVIDENCE_PATH_ESCAPE')
    target=root/p
    if any(x.is_symlink() or (hasattr(x,'is_junction') and x.is_junction()) for x in [target,*target.parents] if x!=root and root in x.parents): raise InvalidEvidence('EVIDENCE_REPARSE_POINT')
    if not target.resolve().is_relative_to(root):raise InvalidEvidence('EVIDENCE_PATH_ESCAPE')
    return target

def verified(root,relative,digest):
    path=resolve(root,relative)
    if not path.is_file() or sha(path)!=digest:raise InvalidEvidence('EVIDENCE_HASH_MISMATCH:'+relative)
    return path

def image_info(path):
    try:
        with Image.open(path) as image:
            image.load();rgb=image.convert('RGB');small=rgb.resize((96,54));stat=ImageStat.Stat(small)
            return image.size, max(stat.mean)<4 and max(v[1] for v in small.getextrema())<35
    except Exception as e:raise InvalidEvidence('CAPTURE_DECODE_FAILED') from e

def check_collection(path):
    """Validate one isolated collector result and return ``(data, catalog)``.

    A ``review`` finding is retained for a later visual review.  Candidate
    ``unreachable`` findings remain scoreable as zero; infrastructure faults
    invalidate publication instead of being attributed to the candidate.
    """
    path=Path(path).resolve(); data=read(path)
    if not isinstance(data,dict) or data.get('version')!='4.0.0': raise InvalidEvidence('COLLECTION_VERSION')
    if data.get('catalog_sha256')!=sha(ROOT/'catalog/checkpoints.json'): raise InvalidEvidence('COLLECTION_CATALOG_BINDING')
    if not isinstance(data.get('faults'),list): raise InvalidEvidence('COLLECTION_FAULTS_INVALID')
    if data['faults']: raise InvalidEvidence('RUNTIME_INFRASTRUCTURE_FAULT')
    catalog=read(ROOT/'catalog/checkpoints.json')
    expected={c['id'] for c in catalog['checkpoints']}; seen=set()
    cases=data.get('cases')
    if not isinstance(cases,list) or not cases: raise InvalidEvidence('NO_CASES')
    for case in cases:
        if not isinstance(case,dict): raise InvalidEvidence('CASE_INVALID')
        name=case.get('id')
        if not isinstance(name,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}',name) or name in seen: raise InvalidEvidence('CASE_SET_INVALID')
        seen.add(name)
        if not isinstance(case.get('findings'),dict): raise InvalidEvidence('CASE_FINDINGS_INVALID')
        for cid,row in case['findings'].items():
            if cid not in expected: raise InvalidEvidence('UNKNOWN_CHECKPOINT:'+str(cid))
            if not isinstance(row,dict): raise InvalidEvidence('CHECKPOINT_ROW_INVALID:'+cid)
            if row.get('machine_verdict') not in ('supported','fail','review','unreachable'):
                raise InvalidEvidence('INVALID_MACHINE_VERDICT:'+cid)
        case_root=resolve(path.parent,name)
        if not case_root.is_dir(): raise InvalidEvidence('CASE_DIRECTORY_MISSING:'+name)
        for rel in ('samples.json','receipts.json','observation-errors.json'):
            p=resolve(path.parent,f'{name}/{rel}')
            if not p.is_file(): raise InvalidEvidence('CASE_ARTIFACT_MISSING:'+name+'/'+rel)
            read(p)
        for key,filename in (('samples_sha256','samples.json'),('receipts_sha256','receipts.json')):
            digest=case.get(key)
            if not isinstance(digest,str) or sha(case_root/filename)!=digest: raise InvalidEvidence('CASE_ARTIFACT_HASH_MISMATCH:'+name+'/'+filename)
        for cap in case.get('captures',[]):
            rel=cap.get('path'); digest=cap.get('sha256')
            if not isinstance(rel,str) or not isinstance(digest,str): raise InvalidEvidence('CAPTURE_DESCRIPTOR_INVALID')
            verified(case_root,rel,digest); image_info(case_root/rel)
            if not isinstance(cap.get('receipt_index'),int): raise InvalidEvidence('CAPTURE_RECEIPT_BINDING_MISSING')
    return data,catalog

def check_raw(path):
    """Compatibility alias; old v3 reports are intentionally rejected."""
    return check_collection(path)

def rounded(n):return math.floor(n*10+0.500000001)/10
