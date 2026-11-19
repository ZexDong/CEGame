"""Recollect bolt checks with timed normal inputs and bound candidate evidence."""
import argparse,shutil,time
from pathlib import Path
from evaluate import Evaluation
from runtime import ROOT,Player,Observer,load,write,sha,code_identity,InfrastructureError
from atomic import game,field,number

class BoltRepair(Evaluation):
    def bolt(self):
        initial=game(self.o.last)
        self.press('K')
        bolt=self.wait('bolt-active',lambda g:number(g,'combat.active_player_projectiles')>0,2)
        self.cap('bolt-cast')
        deadline=number(game(bolt),'combat.round_time_ms')+number(game(bolt),'combat.bolt_cooldown_remaining_ms')
        # Send both challenges while the original cooldown is active. Waiting for
        # a transient last_resolution first can accidentally authorize a new shot.
        for _ in range(2):
            now=load(self.root/'state/duel-state.json')
            if number(game(now),'combat.round_time_ms')+250>=deadline:
                raise InfrastructureError('BOLT_REPAIR_REJECTION_WINDOW_MISSED')
            self.press('K')
        rejected=self.wait('rejected',lambda g:field(g,'combat.last_resolution')=='bolt_cooldown_rejected'
            or field(g,'feedback.status_text')=='COOLDOWN',1)
        self.cap('cooldown')
        repeat=self.o.window('rejected-repeat',.35)
        hit=self.wait('bolt-hit',lambda g:number(g,'rival.health')<number(initial,'rival.health'),4)
        self.cap('bolt-hit')
        ready=self.wait('bolt-ready',lambda g:field(g,'combat.bolt_ready') is True,3,2)
        stable=self.o.window('bolt-resolved-stable',.35)
        self.check('D2-05',bolt and rejected and ready,'BOLT_AND_READINESS_AVAILABLE','bolt-active','rejected','bolt-ready')
        rejection_deadline=number(game(rejected),'combat.round_time_ms')+number(game(rejected),'combat.bolt_cooldown_remaining_ms')
        seq=[s for name in ('bolt-active','rejected','rejected-repeat','bolt-hit','bolt-ready','bolt-resolved-stable') for s in self.samples(name)]
        good=(bolt and hit and ready and stable and 900<=deadline-number(initial,'combat.round_time_ms')<=1150
            and number(game(ready),'combat.round_time_ms')>=deadline-60
            and all(number(game(s),'combat.active_player_projectiles')<=1 for s in seq)
            and all(number(game(s),'rival.health')==max(0,number(initial,'rival.health')-15)
                and number(game(s),'combat.active_player_projectiles')==0 for s in [hit]+stable))
        self.check('D3-04',good,'BOLT_DAMAGE_REMOVAL_AND_ONE_SECOND_COOLDOWN','bolt-active','bolt-hit','bolt-ready','bolt-resolved-stable')
        no_extra=bool(bolt and rejected and repeat) and abs(rejection_deadline-deadline)<=60 and all(number(game(s),'combat.active_player_projectiles')<=1 for s in repeat)
        self.check('D3-05',self.facts.get('whiff') and no_extra,'WHIFF_AND_REJECTION_NO_EXTRA_EFFECT','whiff','rejected','rejected-repeat')

def main():
    p=argparse.ArgumentParser();p.add_argument('--source-run',type=Path,required=True)
    p.add_argument('--evidence',type=Path,required=True);p.add_argument('--engine',type=Path,required=True);p.add_argument('--pwsh',type=Path,required=True)
    a=p.parse_args();raw=load(a.evidence/'raw-evaluation.json');target=a.evidence/'bolt-repair'
    if target.exists():raise InfrastructureError('REPAIR_OUTPUT_EXISTS')
    # The existing compiled evaluation copy is reused only after its source and
    # content bytes match the input-bound candidate manifest.
    for row in load(a.source_run/'candidate-manifest.json')['files']:
        if row['path'].startswith('project/'):
            path=a.source_run/row['path']
            if not path.is_file() or sha(path)!=row['sha256']:raise InfrastructureError('REPAIR_PROJECT_CHANGED')
    target.mkdir()
    args=argparse.Namespace(output=target,engine=a.engine,pwsh=a.pwsh)
    runner=BoltRepair(args);runner.project=next((a.source_run/'project').glob('*.uproject'))
    runner.facts['whiff']=raw['facts'].get('whiff')
    write(target/'states/whiff.json',load(a.evidence/'states/whiff.json'))
    runner.budget.arm();runner.p=Player(a.pwsh,target,runner.budget)
    runner.o=Observer(target,{'process_id':0,'process_token':'unbound'},runner.budget)
    try:runner.isolated(next(c for c in runner.cases if c['id']=='bolt'))
    finally:
        runner.p.close();runner.budget.close()
    index={p.relative_to(a.evidence).as_posix():sha(p) for d in ('receipts','states','captures','cases') for p in (target/d).glob('*') if p.is_file()}
    ids=('D2-05','D3-04','D3-05')
    checks=[]
    for key in ids:
        c=runner.verdicts[key];c['evidence']=['bolt-repair/'+e for e in c['evidence']];checks.append(c)
    write(a.evidence/'checkpoint-repair.json',{'source_raw_sha256':sha(a.evidence/'raw-evaluation.json'),
        'candidate_identity_sha256':raw['candidate_identity_sha256'],'collector_identity':code_identity(),
        'adapter':'scripts/repair_bolt.py','adapter_sha256':sha(Path(__file__)),
        'reason':'Independently repeat only the bolt checks with normal inputs inside the cooldown window; preserve candidate and source-run bindings.',
        'checkpoints':checks,'faults':runner.faults,'evidence_sha256':index})
    print(a.evidence/'checkpoint-repair.json')

if __name__=='__main__':main()
