"""Preserve independent gameplay evidence after a proven engine-health bridge fault."""
import argparse,time
from pathlib import Path
import evaluate
from runtime import Player,load,write,sha,InfrastructureError

def has_started_ticking(state, session):
    return (state.get('process_id')==session['process_id']
        and state.get('process_token')==session['process_token']
        and state.get('snapshot_id',0)>1
        and state.get('game_state',{}).get('combat',{}).get('round_time_ms',0)>0)

class PixelFirstPlayer(Player):
    def call(self,op,**kwargs):
        started=time.monotonic()
        if op=='start':kwargs['observer_disabled']=True
        result=super().call(op,**kwargs)
        if op in ('start','reopen'):
            preflight=max((r['elapsed_ms']/1000 for r in result.get('host_preflight_retries',[])),default=0)
            deadline=min(started+self.budget.contract['start_rpc_timeout_seconds'],started+preflight+60)
            # A native window can be stable before Unreal finishes loading the
            # world. Keep that host preparation outside the two-second gameplay
            # entry check, within the existing 60-second startup allowance.
            while time.monotonic()<deadline:
                try:
                    state=load(self.root/'state/duel-state.json')
                    # BeginPlay publishes before first-frame asset preparation.
                    # Require actual world ticking within the same startup cap.
                    if has_started_ticking(state,self.session):
                        break
                except (OSError,ValueError):pass
                self.budget.check();time.sleep(.025)
        return result

def main():
    p=argparse.ArgumentParser()
    for name in ('project','engine','pwsh','output','failed-run'):
        p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--run-id',required=True);p.add_argument('--candidate-id',required=True)
    p.add_argument('--source-review',type=Path,help='Completed source review retained by the standard collector')
    args=p.parse_args();origin=args.failed_run.resolve()
    previous=load(origin/'raw-evaluation.json')
    receipt=load(origin/'receipts/0001-start.json')
    health=load(origin/'state/engine-health.json')
    if receipt.get('fault',{}).get('code','').lower()!='first_frame_state_timeout':
        raise InfrastructureError('OBSERVER_FALLBACK_REQUIRES_PROVEN_BRIDGE_FAILURE')
    if health.get('first_frame') is True or health.get('ready') is not True:
        raise InfrastructureError('OBSERVER_FALLBACK_REQUIRES_MISSING_FIRST_FRAME_FIELD')
    # The executor's documented control mode establishes a stable real window.
    # Published gameplay state, normal inputs and all checkpoints remain unchanged.
    evaluate.Player=PixelFirstPlayer
    code=evaluate.Evaluation(args).run()
    target=args.output.resolve();raw=load(target/'raw-evaluation.json')
    if raw['candidate_identity_sha256']!=previous['candidate_identity_sha256']:
        raise InfrastructureError('OBSERVER_FALLBACK_CANDIDATE_CHANGED')
    provenance={'source_run_id':previous['run_id'],'source_raw_sha256':sha(origin/'raw-evaluation.json'),
        'source_start_receipt':receipt,'engine_health_snapshot':health,
        'reason':'Candidate engine-health snapshot publishes ready but omits first_frame; use the existing window-control mode to preserve independent visible/gameplay checks.',
        'adapter_sha256':sha(Path(__file__)),'candidate_modified':False}
    write(target/'bridge-failure.json',provenance)
    raw['evidence_sha256']['bridge-failure.json']=sha(target/'bridge-failure.json')
    raw['diagnostic_adapter']={'path':'scripts/collect_with_observer_fallback.py','sha256':sha(Path(__file__)),
        'provenance':'bridge-failure.json'}
    for c in raw['checkpoints']:
        if c['checkpoint_id']=='D1-04':
            c.update(verdict='fail',reason='CANDIDATE_ENGINE_HEALTH_FIRST_FRAME_FIELD_MISSING',
                evidence=list(dict.fromkeys(c['evidence']+['bridge-failure.json'])))
    raw['faults'].append({'domain':'candidate','code':'CANDIDATE_ENGINE_HEALTH_FIRST_FRAME_FIELD_MISSING',
        'affected_checkpoint_ids':['D1-04'],'attribution':'Fresh engine-health snapshots from the candidate omit the required first_frame field; independent runtime evidence recovered with documented executor control mode.',
        'evidence':['bridge-failure.json']})
    write(target/'raw-evaluation.json',raw)
    raise SystemExit(code)

if __name__=='__main__':main()
