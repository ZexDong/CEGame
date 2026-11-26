"""Convert native checkpoint observations to the shared result schema."""
from pathlib import Path
import json, math, re
from statistics import median
MAXIMA=dict(D1=10,D2=30,D3=20,D4=20,D5=10,D6=10)
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def collect_rows(run):
 rows={};documents=[];fault=False
 candidates=['collected-checks.json','checks.json','verdicts.json','checkpoint-verdicts.json','static/static.json','raw-evaluation.json','collection.json','collection/collection.json','native-summary.json','score.json','result.json','scored-checkpoints.json']
 for name in candidates:
  path=run/name
  if not path.is_file():continue
  try:data=load(path)
  except (ValueError,OSError):continue
  documents.append((path,data))
  if isinstance(data,dict):
   if data.get('status',data.get('run_status')) in ['run_invalid','invalid','infrastructure_failure']:fault=True
   if data.get('faults') and any(x.get('domain',x.get('attribution')) in ['infrastructure','evaluator','host','evaluator_or_host'] for x in data['faults'] if isinstance(x,dict)):fault=True
   content=data.get('checks',data.get('checkpoints',data.get('verdicts',data if name in ['checks.json','scored-checkpoints.json'] else {})))
  else:content=data
  if isinstance(content,dict):content=[{'id':key,**value} for key,value in content.items() if isinstance(value,dict)]
  if isinstance(content,list):
   for item in content:
    if isinstance(item,dict) and item.get('id',item.get('checkpoint_id')):rows[item.get('id',item.get('checkpoint_id'))]=(item,path)
 return rows,documents,fault

def evidence_paths(value,base,output):
 found=[]
 if isinstance(value,str):
  try:
   path=(base/value).resolve()
   if path.is_relative_to(output.resolve()) and path.is_file():found.append(path.relative_to(output.resolve()).as_posix())
  except (OSError,ValueError):pass
 elif isinstance(value,dict):
  for v in value.values():found.extend(evidence_paths(v,base,output))
 elif isinstance(value,list):
  for v in value:found.extend(evidence_paths(v,base,output))
 return sorted(set(found))

def _extract_outcome_observations(summary, rel_path):
 obs = {}
 if not isinstance(summary, dict):
  return obs
 explicit = summary.get('outcome_observations')
 if isinstance(explicit, dict):
  for k, v in explicit.items():
   if k in ('journey', 'lifecycle', 'critical') and isinstance(v, dict):
    obs[k] = v
 raw = summary.get('checkpoints', summary.get('verdicts'))
 rows = []
 if isinstance(raw, dict):
  rows = [{'id': str(k), **v} for k, v in raw.items() if isinstance(v, dict)]
 elif isinstance(raw, list):
  rows = [v for v in raw if isinstance(v, dict) and v.get('id', v.get('checkpoint_id'))]

 def _bit(row):
  if row.get('machine_verdict') == 'review' or row.get('verdict') == 'review':
   return None
  v = row.get('verdict', row.get('status'))
  s = str(v or '').strip().lower()
  if s == 'pass':
   return 1
  if s in ('fail', 'blocked_by_candidate'):
   return 0
  return None

 if 'journey' not in obs:
  j_rows = [r for r in rows if str(r.get('id', r.get('checkpoint_id', ''))).lower() in ('d4-journey', 'd4-01', 'flow')
            or any(t in str(r.get('id', r.get('checkpoint_id', ''))).lower() for t in ('journey', 'complete_success', 'end_to_end'))]
  if j_rows:
   bits = [_bit(r) for r in j_rows]
   if 0 in bits:
    obs['journey'] = {'value': 0, 'evidence': [rel_path]}
   elif all(b == 1 for b in bits):
    obs['journey'] = {'value': 1, 'evidence': [rel_path]}
 if 'lifecycle' not in obs:
  l_rows = [r for r in rows if any(t in str(r.get('id', r.get('checkpoint_id', ''))).lower() for t in ('restart', 'reopen', 'reset'))]
  if l_rows:
   bits = [_bit(r) for r in l_rows]
   if 0 in bits:
    obs['lifecycle'] = {'value': 0, 'evidence': [rel_path]}
   elif all(b == 1 for b in bits):
    obs['lifecycle'] = {'value': 1, 'evidence': [rel_path]}
 return obs

def convert_result(evaluation,output,meta,reason,infrastructure=False):
 evaluation=Path(evaluation);output=Path(output);rules=load(evaluation/'rules.json')['checks']
 native_rows,documents,native_fault=collect_rows(output/'native');infrastructure=infrastructure or native_fault
 checks=[]
 for rule in rules:
  entry={'id':rule['id'],'requirement_ids':list(dict.fromkeys(rule['requirement_ids'])),'dimension':rule['dimension'],'max_score':rule['max_score'],'score':None,'status':'not_run','reason':'No native observation for this checkpoint.','blocked_by':[],'evidence':[]}
  if rule['id'] in native_rows and rule['dimension']!='D6':
   row,path=native_rows[rule['id']];ev=evidence_paths(row.get('evidence',row.get('evidence_paths',[])),path.parent,output)
   # Keep the checkpoint record alongside its referenced runtime evidence.
   ev=sorted(set(ev+[path.relative_to(output).as_posix()]));verdict=row.get('verdict',row.get('status'))
   entry['reason']=str(row.get('reason',row.get('reason_code',row.get('detail','Native checkpoint observation'))))
   entry['evidence']=ev
   if verdict=='pass':entry.update(status='pass',score=entry['max_score'])
   elif verdict=='fail':entry.update(status='fail',score=0,reason=entry['reason'] or 'Native observation failed.')
   elif verdict in ['unreachable','blocked_by_candidate']:
    # Blocked checkpoints require an evidenced checkpoint dependency.
    entry.update(status='inconclusive_evaluator',reason='Native unreachable verdict lacks a frozen, evidenced blocked_by checkpoint dependency; diagnostic zero is not promoted. '+entry['reason'])
   else:entry.update(status='inconclusive_evaluator',reason='Native checkpoint observation is incomplete. '+entry['reason'])
  elif infrastructure:entry.update(status='inconclusive_evaluator',reason='Infrastructure failure prevented this observation.',evidence=['evidence/entry.json'])
  checks.append(entry)
 # Only a successful native finalizer can validate visual responses and their candidate/reference bindings.
 receipt=output/'evidence/finalize.json';receipt_data=load(receipt) if receipt.is_file() else {}
 summary_path = output / 'native/native-summary.json'
 started = receipt_data.get('started_ns')
 summary = load(summary_path) if summary_path.is_file() else {}
 finalized = (not infrastructure and type(started) is int and started >= 0
              and receipt_data.get('returncode') in (0,) and summary_path.is_file()
              and summary_path.stat().st_mtime_ns >= started and isinstance(summary, dict)
              and summary.get('status', summary.get('evaluation_status')) in
              ('diagnostic_complete', 'diagnostic_completed', 'completed', 'complete'))
 if finalized:
  def state_records(data):
   if not isinstance(data,dict):return []
   records=[]
   for key in ['records','reviews','d6_results','items']:
    if isinstance(data.get(key),list):records.extend(x for x in data[key] if isinstance(x,dict) and 'round' in x)
   for rnd in data.get('rounds',[]):
    if isinstance(rnd,dict):records.extend({'round':rnd.get('round',rnd.get('number')),**state} for state in rnd.get('states',[]) if isinstance(state,dict))
   if isinstance(data.get('dimensions'),dict):records.extend(state_records(data['dimensions'].get('D6')))
   return records
  unique={}
  ambiguous = set()
  for state in state_records(summary):
   key = state.get('id', state.get('state_id', state.get('state')))
   number = state.get('round')
   if not isinstance(key, str) or type(number) is not int or number not in (1, 2, 3):
    continue
   score = state.get('score', state.get('total'))
   criteria = state.get('criteria')
   if score is None and isinstance(criteria, list) and all(type(v) in (int, float) for v in criteria):
    score = sum(criteria)
   if type(score) not in (int, float) or not math.isfinite(score) or not 0 <= score <= 10:
    continue
   if (key, number) in unique:
    ambiguous.add(key)
   unique[key, number] = (key, score, summary_path)
  visual = [item for item in unique.values() if item[0] not in ambiguous]
  for c in checks:
   if c['dimension']!='D6':continue
   pairs=[(s,p) for key,s,p in visual if key==c['id'].removeprefix('D6-')]
   if len(pairs)==3:
    value=round(c['max_score'] * median(s for s,_ in pairs) / 10, 6)
    c.update(score=value,status='pass' if value==c['max_score'] else 'fail' if value==0 else 'partial',reason='Native finalizer validated the fixed visual state in three rounds.',evidence=sorted({p.relative_to(output).as_posix() for _,p in pairs}|{'evidence/finalize.json'}))
 dimensions={}
 for d,m in MAXIMA.items():
  subset=[c for c in checks if c['dimension']==d];complete=all(c['score'] is not None for c in subset)
  dimensions[d]={'score':round(sum(c['score'] for c in subset),6) if complete else None,'max_score':m,'status':'complete' if complete else 'invalid' if infrastructure else 'incomplete','evidence':sorted({p for c in subset for p in c['evidence']})}
 complete=finalized and not infrastructure and all(d['status']=='complete' for d in dimensions.values())
 return {'schema_version':'2.1','sample_id':meta['sample_id'],'sample_version':meta['sample_version'],'evaluator_version':meta['evaluation']['version'],
  'run_id':re.sub('[^A-Za-z0-9_.:-]','_',output.name) if re.match('[A-Za-z0-9]',output.name) else 'run-'+re.sub('[^A-Za-z0-9_.:-]','_',output.name),
  'evaluation_valid':complete,'classification':'scored' if complete else 'infrastructure_failure' if infrastructure else 'incomplete','coverage_status':'not_reviewed','reason':reason,
  'dimensions':dimensions,'checks':checks,'coverage_evidence':[],'final_score':round(sum(d['score'] for d in dimensions.values()),6) if complete else None,'max_score':100,
  'extensions':{**({'outcome_observations':_extract_outcome_observations(summary, 'native/native-summary.json')} if finalized and not infrastructure and _extract_outcome_observations(summary, 'native/native-summary.json') else {}), 'native_finalizer_completed':finalized,'coverage_note':'Coverage history is informational. A final score requires a fresh native finalizer and all six observed dimensions; the native visual protocol is unchanged.'}}
