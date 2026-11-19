"""Score frozen kitchen leaves only after raw NUnit/evidence agreement."""
import argparse, json, math, sys, xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REPO=ROOT.parents[3]
sys.path.insert(0,str(REPO/'tools/maintenance'))
from session_dependency_gate import validate_dependency_contract

def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
def require(x,msg):
 if not x:raise ValueError(msg)

def score(output,project,exits,compile_failure=False):
 rules=read(ROOT/'rules.json');deps=read(ROOT/'session-dependencies.json');leaves={};checks=[];phase_info={};reasons=[]
 for dim,maximum in [('D1',10),('D2',30),('D3',20),('D4',20),('D5',10)]:
  items=rules['dimensions'][dim]['checks'];require(items and rules['dimensions'][dim]['maximum_score']==maximum,'wrong dimension maximum')
  for item in items:
   require(item['id'] not in leaves,'duplicate rule leaf');require(math.isclose(item['weight'],maximum/len(items)),'unequal checkpoint weights')
   leaves[item['id']]={**item,'dimension':dim}
 validate_dependency_contract(deps,leaves)
 dependent={x['check_id']:x for x in deps['leaves']}
 if compile_failure:
  receipt=read(output/'candidate-compile-failure.json');require(receipt['classification']=='candidate_compile_failure' and receipt.get('diagnostics'),'no attributable candidate compile error')
  checks=[dict(id=k,dimension=v['dimension'],weight=v['weight'],status='BLOCKED_BY_PRODUCT',expected='candidate compiles',observed='candidate-owned compiler error',precondition_reached=False,oracle_valid=True,acquisition_status='PRODUCT_BLOCKED',acquisition_route='compile',attribution='product_block',trajectory='candidate_compile_failure',process_id=receipt['baseline']['cli_process_id'],frame=0,setup_writes_after_action=0,product_block_reason='candidate-owned compiler error',blocker_kind='candidate_compile') for k,v in leaves.items()]
 else:
  for phase,contract in rules['phase_contract'].items():
   require(exits[phase]==0,'host/test execution failed: '+phase+' exit='+str(exits[phase]))
   xml=ET.parse(output/(phase+'.xml')).getroot();tests=list(xml.iter('test-case'));names=[x.get('name') for x in tests]
   require(len(tests)==contract['expected_tests'] and len(names)==len(set(names)) and set(names)==set(contract['expected_test_names']),'wrong, missing or duplicate NUnit tests in '+phase)
   require(all(x.get('result')=='Passed' for x in tests),'NUnit producer failed in '+phase)
   doc=read(output/(phase+'-evidence.json'));require(doc['phase']==phase and doc['process_id']>0,'wrong phase or PID')
   rows=doc['checks'];ids=[x['id'] for x in rows]
   require(len(ids)==len(set(ids)) and set(ids)==set(contract['expected_check_ids']),'wrong raw leaf set in '+phase)
   for row in rows:
    require(row['dimension']==leaves[row['id']]['dimension'] and row['weight']==leaves[row['id']]['weight'],'changed leaf identity/weight')
    require(row['status'] in ('PASS','FAIL_OBSERVED','BLOCKED_BY_PRODUCT'),'unresolved evaluator verdict: '+row['id'])
    require(row['process_id']==doc['process_id'] and row['frame']>=0 and row['setup_writes_after_action']==0,'unbound PID/frame or late setup write')
    require(row['oracle_valid'] is True,'invalid oracle')
    name=contract.get('check_test_bindings',{}).get(row['id'],contract['expected_test_names'][0]);case=next(x for x in tests if x.get('name')==name);require(row['trajectory']==case.get('fullname'),'leaf/NUnit test binding differs: '+row['id'])
    if row['status']=='BLOCKED_BY_PRODUCT':
     cap=row.get('failed_capability');routes=dependent[row['id']]['alternative_routes']
     require(cap and all(cap in route for route in routes),'unfrozen or false dependency block '+row['id']+': '+str(cap))
     require(row.get('product_block_reason') and row['precondition_reached'] is False,'missing product blocker evidence')
    else:require(row['precondition_reached'] is True,'unreached behavior cannot be pass/fail')
    if phase!='static':
     fact=read(output/'facts'/(name+'.json'));require(fact['test_id']==name and fact['process_id']==doc['process_id'],'missing current scenario facts')
     require(fact.get('frames') or row['status']=='BLOCKED_BY_PRODUCT','self-reported leaf has no independently acquired frame facts')
   checks+=rows;phase_info[phase]={'process_id':doc['process_id'],'test_count':len(tests),'exit_code':exits[phase]}
  require(phase_info['dynamic']['process_id']!=phase_info['fresh']['process_id'],'Reopen reused a process')
 require(len(checks)==len(leaves),'incomplete automatic leaf output')
 dimensions={dim:{'score':sum(c['weight'] for c in checks if c['dimension']==dim and c['status']=='PASS'),'maximum_score':maximum,'status':'evaluated'} for dim,maximum in [('D1',10),('D2',30),('D3',20),('D4',20),('D5',10)]}
 dimensions['D6']={'score':None,'maximum_score':10,'status':'pending_visual'}
 auto=sum(d['score'] for k,d in dimensions.items() if k!='D6')
 return {'schema_version':4,'evaluator_revision':rules['evaluator_revision'],'evaluator_protocol':rules['evaluator_protocol'],'valid_score':True,'scoring_execution_valid':True,'formal_release_eligible':False,'validation_reasons':[], 'candidate_status':'invalid_game' if compile_failure else 'evaluated','project_path':str(project),'automated_score':auto,'automated_maximum_score':90,'score':None,'maximum_score':100,'score_status':'pending_visual','overall':{'score':None,'maximum_score':100,'status':'pending_visual'},'dimensions':dimensions,'blocked_weight':sum(c['weight'] for c in checks if c['status']=='BLOCKED_BY_PRODUCT'),'interface_blocked_weight':sum(c['weight'] for c in checks if c['status']=='BLOCKED_BY_PRODUCT' and c.get('blocker_kind')=='public_session_contract'),'checks':checks,'phases':phase_info}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--project',type=Path,required=True);p.add_argument('--static-exit',type=int,required=True);p.add_argument('--dynamic-exit',type=int,required=True);p.add_argument('--fresh-exit',type=int,required=True);p.add_argument('--compile-failure',action='store_true');a=p.parse_args()
 try:r=score(a.output,a.project,{'static':a.static_exit,'dynamic':a.dynamic_exit,'fresh':a.fresh_exit},a.compile_failure);code=0
 except Exception as exc:r={'schema_version':4,'valid_score':False,'scoring_execution_valid':False,'score':None,'candidate_status':'evaluator_invalid','validation_reasons':[str(exc)],'checks':[]};code=3
 write(a.output/'score.json',r);print(json.dumps({'valid':r['valid_score'],'errors':r['validation_reasons']}));sys.exit(code)
