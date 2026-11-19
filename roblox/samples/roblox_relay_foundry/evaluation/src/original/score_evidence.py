"""Compute D1-D5 from auditable checkpoints; D6 remains a separate visual stage."""
import argparse,json
from pathlib import Path
DIMENSIONS={
 'D1':(10,'static_checks',['package_integrity','qa_source_isolation','engine_open_smoke']),
 'D2':(30,'checks',['d2.required_world_and_hud','d2.all_three_orders_usable','d2.purge_and_exit_content']),
 'D3':(20,'checks',['d3.mode_cycle_no_core_change','d3.wrong_phase_fault_and_purge','d3.wrong_mode_fault_and_purge','d3.physical_gate_and_completion_condition']),
 'D4':(20,'checks',['d4.complete_success_flow','d4.checkpoint_death_preserves_run','d4.restart_in_progress','d4.restart_after_completion']),
 'D5':(10,'checks',['d5.hud_state_sync','d5.visible_error_and_success_feedback']),
}
def main():
 p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();e=json.loads(a.evidence.read_text(encoding='utf-8'))
 dimensions={};incomplete=[]
 for dim,(maximum,section,ids) in DIMENSIONS.items():
  values=e.get(section,{})
  verdicts={i:values.get(i,{'status':'not_run','detail':'checkpoint absent from evidence'}) for i in ids}
  incomplete += [i for i,v in verdicts.items() if v.get('status') in ('inconclusive','not_run')]
  passed=sum(v.get('status')=='pass' for v in verdicts.values())
  dimensions[dim]={'score':round(maximum*passed/len(ids),1),'max_score':maximum,'passed':passed,'total':len(ids),'checkpoints':verdicts}
 invalid=e.get('runner_status')!='completed' or bool(incomplete)
 subtotal=round(sum(x['score'] for x in dimensions.values()),1)
 result={'candidate_qa_sha256':e.get('candidate_qa_sha256'),'official_score':None,'d1_d5_subtotal':None if invalid else subtotal,'d6_score':None,'score_status':'invalid_controller_run' if invalid else 'requires_d6_visual_stage','reason':'Controller/static prerequisites are incomplete; INCONCLUSIVE/NOT_RUN cannot become candidate deductions.' if invalid else 'D1-D5 complete. D6 requires fixed reference/candidate visual states evaluated for three rounds before Overall is official.','dimensions':dimensions,'inconclusive_checkpoints':incomplete,'policy':e.get('policy',{})}
 a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'score_status':result['score_status'],'official_score':None,'d1_d5_subtotal':result['d1_d5_subtotal'],'inconclusive':len(incomplete)},ensure_ascii=False),flush=True)
if __name__=='__main__':main()
