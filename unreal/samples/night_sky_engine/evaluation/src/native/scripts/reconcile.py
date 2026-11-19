"""Reconcile proven collector false negatives using already-bound public evidence."""
import math
from runtime import ROOT,load,sha,inside,code_identity,InfrastructureError
from atomic import game, field, number, span, fresh


def reconcile(actual, raw, root):
    corrections=[]
    def samples(name):
        path='states/'+name+'.json'
        return load(root/path)['samples'] if path in raw['evidence_sha256'] else []
    def correct(key, reason, names):
        prior=dict(actual[key])
        evidence=['states/'+n+'.json' for n in names]
        actual[key].update(verdict='pass',reason=reason,evidence=evidence)
        corrections.append({'checkpoint_id':key,'prior_verdict':prior['verdict'],
            'prior_reason':prior['reason'],'reason':reason,'evidence':evidence,
            'attribution':'evaluator_observation_or_predicate'})

    # An empty 80/180 ms subwindow is legal at the public 250 ms cadence.
    # The surrounding matched jump/landing states still establish the control
    # and challenged arcs; do not convert an acquisition gap into candidate failure.
    key='D3-02'
    if actual[key]['verdict']=='fail' and actual[key]['reason']=='AIRBORNE_INPUT_PRESERVES_CONTROL_ARC':
        names=['control-airborne','control-landed','airborne','jump-before-second','jump-arc','landed']
        ca,cl,air,before,arc,land=[samples(n) for n in names]
        if ca and cl and air and land and (not before or not arc):
            peak=lambda seq:min(number(game(s),'player.normalized_position.y') for s in seq)
            duration=lambda first,last:number(game(last),'combat.round_time_ms')-number(game(first),'combat.round_time_ms')
            matched=(field(game(ca[-1]),'player.grounded') is False and field(game(air[-1]),'player.grounded') is False
                and field(game(cl[-1]),'player.grounded') is True and field(game(land[-1]),'player.grounded') is True)
            challenged=before+arc+land
            # Capture RPCs can consume a grounded publication before the named
            # landing wait starts. Compare the first observed stable landing in
            # each continuous trace, not the delayed end of that wait.
            def landing_confirmation(seq):
                for prior, current in zip(seq, seq[1:]):
                    if (field(game(prior),'player.grounded') is True
                        and field(game(current),'player.grounded') is True):
                        return current
                return seq[-1]
            if (matched and peak(challenged)>=peak(cl)-.006
                and duration(air[-1],landing_confirmation(challenged))
                    <=duration(ca[-1],landing_confirmation(cl))+150):
                correct(key,'CONTROL_AND_CHALLENGED_ARCS_MATCH_DESPITE_SUBCADENCE_WINDOW',names)

    # TERMINAL-02 permits holding a win/loss pose. A pre-existing action label
    # frozen at KO does not demonstrate a new terminal attack or input response.
    key='D3-10'
    if actual[key]['verdict']=='fail' and actual[key]['reason']=='BOTH_TERMINALS_REJECT_INPUT_AND_OLD_CADENCE':
        stable=True;names=[]
        for name in ('player-win','rival-win'):
            initial=samples(name);seq=samples(name+'-lock');names.extend((name,name+'-lock'))
            if not initial or not seq:stable=False;break
            terminal=initial[-1];before=game(terminal)
            fields=('phase','player.health','rival.health','feedback.result_text',
                'world.object_counts.player_fighters','world.object_counts.rival_fighters')
            committed={'blocking','light_attack','energy_attack','airborne','moving'}
            stable=stable and all(all(field(game(s),p)==field(before,p) for p in fields)
                and number(game(s),'combat.active_player_projectiles')==0
                and field(game(s),'combat.telegraph_active') is False
                and (field(game(s),'player.action_state') not in committed
                     or field(game(s),'player.action_state')==field(before,'player.action_state')) for s in seq)
            stable=stable and all(span([terminal]+seq,p)<.003 for p in ('player.normalized_position.x','player.normalized_position.y'))
            # Round gameplay time may legitimately freeze at the result. Use
            # the observer's monotonic clock for the terminal waiting interval.
            stable=stable and seq[-1].get('monotonic_ms',math.nan)-terminal.get('monotonic_ms',math.nan)>=3500
        if stable:correct(key,'TERMINAL_INPUTS_HAVE_NO_EFFECT_EXISTING_POSE_LABEL_IS_STABLE',names)
    key='D4-04'
    if key in actual and actual[key]['verdict']=='fail' and actual[key]['reason']=='ACTIVE_AND_TERMINAL_RESTART_CLEAR_STATE':
        names=['restart-dirty','restart-in-flight','repeat-restart','restart-telegraph','restart-from-telegraph',
               'restart-old-event-window','cancelled-pulse','fresh-cadence','player-win-restart','rival-win-restart']
        data={n:samples(n) for n in names}
        facts=raw.get('facts',{})
        if all(data.values()) and all(facts.get(n) for n in ('restart_available','player-win_restart','rival-win_restart')):
            cadence=game(data['fresh-cadence'][-1])
            onset=number(cadence,'combat.round_time_ms')+number(cadence,'combat.telegraph_remaining_ms')-750
            clean=data['restart-old-event-window']+data['cancelled-pulse']
            resets=[data[n][-1] for n in ('restart-in-flight','repeat-restart','restart-from-telegraph','player-win-restart','rival-win-restart')]
            dirty=any(number(game(s),'combat.active_player_projectiles')>0 or field(game(s),'player.grounded') is False for s in data['restart-dirty'])
            if dirty and field(cadence,'combat.telegraph_active') is True and 2850<=onset<=3150 and all(fresh(game(s)) for s in clean+resets):
                correct(key,'RESTART_CLEAN_WITH_CADENCE_ONSET_FROM_REMAINING_TIMER',names)

    for manifest,prefix,adapter,allowed in (
        ('checkpoint-repair.json','bolt-repair/','scripts/repair_bolt.py',{'D2-05','D3-04','D3-05'}),):
        repair_path=root/manifest
        if not repair_path.exists():continue
        repair=load(repair_path)
        if (repair.get('source_raw_sha256')!=sha(root/'raw-evaluation.json')
            or repair.get('candidate_identity_sha256')!=raw.get('candidate_identity_sha256')
            or repair.get('collector_identity')!=code_identity()
            or repair.get('adapter')!=adapter
            or repair.get('adapter_sha256')!=sha(ROOT/adapter)):
            raise InfrastructureError('CHECKPOINT_REPAIR_IDENTITY_MISMATCH')
        index=repair.get('evidence_sha256',{})
        if not index:raise InfrastructureError('CHECKPOINT_REPAIR_EVIDENCE_MISSING')
        for path,digest in index.items():
            if not path.startswith(prefix) or sha(inside(root,path))!=digest:
                raise InfrastructureError('CHECKPOINT_REPAIR_EVIDENCE_CHANGED')
        rows=repair.get('checkpoints',[])
        if len(rows)!=len(allowed) or {c['checkpoint_id'] for c in rows}!=allowed:
            raise InfrastructureError('CHECKPOINT_REPAIR_SCOPE_INVALID')
        for c in rows:
            key=c['checkpoint_id'];prior=dict(actual[key])
            if c['dimension']!=prior['dimension'] or c['verdict'] not in ('pass','fail','unreachable') or not c['evidence'] or any(e not in index for e in c['evidence']):
                raise InfrastructureError('CHECKPOINT_REPAIR_VERDICT_INVALID')
            actual[key].update(c)
            corrections.append({'checkpoint_id':key,'prior_verdict':prior['verdict'],'prior_reason':prior['reason'],
                'verdict':c['verdict'],'reason':c['reason'],'evidence':c['evidence'],
                'repair_manifest_sha256':sha(repair_path),'attribution':'evaluator_action_timing_recollected'})
        raw['evidence_sha256'].update(index)
        raw['evidence_sha256'][manifest]=sha(repair_path)
        raw['faults'].extend(repair.get('faults',[]))
    return corrections
