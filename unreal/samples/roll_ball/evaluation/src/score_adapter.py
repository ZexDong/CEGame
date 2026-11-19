"""Convert native checkpoint observations to the shared result schema."""
from pathlib import Path
import json, math, re
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
   else:entry.update(status='inconclusive_evaluator',reason='Native review or observation is incomplete. '+entry['reason'])
  elif infrastructure:entry.update(status='inconclusive_evaluator',reason='Infrastructure failure prevented this observation.',evidence=['evidence/entry.json'])
  checks.append(entry)
 # Only a successful native finalizer can validate visual responses and their candidate/reference bindings.
 receipt=output/'evidence/finalize.json';receipt_data=load(receipt) if receipt.is_file() else {}
 finalized=receipt_data.get('returncode') in [0,1,2] and any(isinstance(d,dict) and d.get('status') in ['diagnostic_complete','completed','complete'] and p.stat().st_mtime_ns>=receipt_data.get('started_ns',10**30) for p,d in documents)
 if finalized:
  visual=[];paths=[output/'native/d6/result.json',output/'native/d6-run.json',output/'native/d6/aggregation.json',output/'native/d6-result.json',output/'native/d6/parser-and-aggregation.json']
  args=receipt_data.get('command',[])
  for flag in ['--d6','-D6RunPath']:
   if flag in args:
    p=Path(args[args.index(flag)+1]).resolve()
    if p.is_relative_to(output.resolve()):paths.append(p)
  data_sources=list(documents)
  for p in paths:
   if p.is_file():
    data_sources.append((p,load(p)))
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
  for p,data in data_sources:
   for state in state_records(data):
    key=state.get('id',state.get('state_id',state.get('state')));criteria=state.get('criteria')
    score=state.get('score',state.get('total'))
    if score is None and isinstance(criteria,list):score=sum(criteria)
    if type(score) in [int,float] and math.isfinite(score) and 0<=score<=10:unique[(key,state.get('round'))]=(key,score,p)
  visual=list(unique.values())
  for c in checks:
   if c['dimension']!='D6':continue
   pairs=[(s,p) for key,s,p in visual if key==c['id'].removeprefix('D6-')]
   if len(pairs)==3:
    value=round(c['max_score']*sum(s for s,_ in pairs)/30,6)
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
  'extensions':{'native_finalizer_completed':finalized,'coverage_note':'Coverage history is informational. A final score requires a fresh native finalizer and all six observed dimensions; the native visual protocol is unchanged.'}}
