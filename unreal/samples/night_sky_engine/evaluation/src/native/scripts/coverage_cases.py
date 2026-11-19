"""Version 3.1 normal-input coverage extensions; never writes candidate state."""
import threading
import time
from contextlib import contextmanager
from atomic import AtomicCases, game, field, number, fresh, span
from coverage_assertions import guard_stationary, terminal_unchanged, feedback_interval, draw_result
from runtime import Observer, CandidateError, InfrastructureError, write, load


class CoverageCases(AtomicCases):
    def boundary_result(self, key, owner, passed, reason, *names, gap=False):
        self.facts.setdefault('boundary_checks', {})[key] = {
            'owner': owner, 'verdict': 'gap' if gap else 'pass' if passed else 'fail',
            'reason': reason, 'evidence': ['states/'+n+'.json' for n in names]}

    @contextmanager
    def trace(self, name):
        """Observe during input and capture RPCs, including down/up transitions."""
        observer = Observer(self.root, self.p.session)
        samples = []
        stopped = threading.Event()
        errors = []
        def collect():
            try:
                while not stopped.is_set():
                    s = observer.read()
                    if s:
                        samples.append(s)
                    stopped.wait(.005)
            except Exception as e:
                errors.append(type(e).__name__)
        thread = threading.Thread(target=collect, daemon=True)
        thread.start()
        try:
            yield samples
        finally:
            stopped.set(); thread.join(timeout=2)
            write(self.root/'states'/(name+'.json'), {'samples': samples,
                  'continuous_during_rpc': True, 'errors': errors + observer.errors})
            if thread.is_alive() or errors:
                raise InfrastructureError('CONTINUOUS_TRACE_FAILED:'+name)

    def guard_movement(self):
        # A and D while S remains down are the actual forbidden-input challenge.
        with self.held('S'):
            before = self.wait('guard-conflict-ready', lambda g: field(g, 'player.action_state') == 'blocking', 1)
            if not before:
                raise CandidateError('GUARD_PRECONDITION_UNREACHABLE')
            with self.trace('guard-conflict-trace') as seq:
                for key in ('A', 'D'):
                    with self.held(key):
                        self.o.window('guard-conflict-'+key, .4)
                        self.cap('guard-conflict-'+key)
                self.o.window('guard-conflict-held', .35)
            good = guard_stationary(seq, before)
        released = self.wait('guard-conflict-release', lambda g: field(g, 'player.action_state') != 'blocking', 1)
        self.boundary_result('guard_movement', 'D3-07', good and released,
                             'HELD_GUARD_REJECTS_BOTH_MOVEMENT_INPUTS', 'guard-conflict-trace', 'guard-conflict-release')

    def terminal_lock(self, terminal, name):
        # A late stable frame must not erase a forbidden transient response.
        good = True
        names = []
        for key in ('A', 'D', 'W', 'J', 'K', 'S'):
            trace_name = name+'-challenge-'+key
            with self.trace(trace_name) as seq:
                with self.held(key):
                    self.o.window(trace_name+'-held', .35)
                self.o.window(trace_name+'-released', .30)
            good = good and terminal_unchanged(seq, terminal)
            names.append(trace_name)
        seq = self.o.window(name+'-lock', 3.7)
        good = good and terminal_unchanged(seq, terminal)
        self.facts[name+'_lock'] = bool(good)
        self.boundary_result(name+'_input_lock', 'D3-10', good,
                             'EACH_TERMINAL_INPUT_OBSERVED_DURING_HOLD_AND_RELEASE', *names, name+'-lock')
        self.cap(name+'-stable')
        reset = self.restart(name+'-restart')
        self.facts[name+'_restart'] = bool(reset)

    def repeated_jump(self):
        durations = []
        grounded = []
        for attempt in range(2):
            self.press('W')
            air = self.wait('repeat-jump-air-'+str(attempt), lambda g: field(g, 'player.grounded') is False, 2)
            land = self.wait('repeat-jump-land-'+str(attempt), lambda g: field(g, 'player.grounded') is True, 4, 2)
            if not air or not land:
                raise CandidateError('REPEATED_GROUNDED_JUMP_UNREACHABLE')
            grounded.append(land)
            durations.append(number(game(land), 'combat.round_time_ms')-number(game(air), 'combat.round_time_ms'))
        self.cap('repeat-jump-landed')
        self.boundary_result('repeated_jump', 'D3-02',
                             span(grounded, 'player.normalized_position.y') < .003,
                             'LATER_GROUNDED_JUMP_RETURNS_TO_SAME_FLOOR',
                             'repeat-jump-air-0', 'repeat-jump-land-0', 'repeat-jump-air-1', 'repeat-jump-land-1')

    def feedback_whiff(self):
        with self.trace('feedback-whiff-duration') as seq:
            self.o.window('feedback-whiff-before', .30)
            self.press('J')
            self.o.window('feedback-whiff-after', 1.9)
        verdict, interval = feedback_interval(seq, 'WHIFF')
        self.cap('feedback-whiff-cleared')
        self.boundary_result('whiff_duration', 'D5-03', verdict == 'pass',
                             'WHIFF_DURATION_BOUNDS:'+str(interval), 'feedback-whiff-duration',
                             gap=verdict in ('gap', 'replaced'))

    def mixed_damage(self):
        # Five bolts leave 25 HP. One more leaves 10; J must clamp the last hit to 0.
        self.approach('mixed-close')
        start = game(self.o.last)
        expected = number(start, 'rival.health')
        names = []
        good = True
        for attempt in range(6):
            ready_name = 'mixed-ready-'+str(attempt)
            ready = self.wait(ready_name, lambda g: field(g, 'combat.bolt_ready') is True
                              and field(g, 'player.action_state') in ('idle', 'moving'), 3)
            if not ready:
                raise CandidateError('BOLT_REFIRE_PRECONDITION_UNREACHABLE')
            self.press('K'); expected -= 15
            name = 'mixed-hit-'+str(attempt)
            hit = self.wait(name, lambda g: number(g, 'rival.health') <= expected, 2)
            names.extend((ready_name, name))
            good = good and bool(hit) and number(game(hit), 'rival.health') == expected
            if not hit:
                break
        ready = self.wait('mixed-strike-ready', lambda g: field(g, 'player.action_state') in ('idle', 'moving'), 3)
        self.press('J')
        terminal = self.wait('mixed-overkill', lambda g: field(g, 'phase') != 'active', 2)
        self.cap('mixed-overkill')
        self.boundary_result('bolt_refire', 'D3-04', good,
                             'SIX_READY_BOLTS_DAMAGE_ONCE_AND_REMOVE_BEFORE_REFIRE', *names)
        self.boundary_result('strike_overkill', 'D3-03', ready and good and terminal
                             and number(game(terminal), 'rival.health') == 0
                             and field(game(terminal), 'phase') == 'player_won',
                             'TEN_HP_RIVAL_CLAMPS_TO_ZERO_ON_25_DAMAGE', *names, 'mixed-overkill')

    def restart_movement(self):
        initial = self.o.last
        names = []
        for key in ('A', 'D'):
            name = 'restart-held-'+key
            with self.held(key):
                moved = self.wait(name+'-dirty', lambda g:
                                  abs(number(g, 'player.normalized_position.x')
                                      - number(game(initial), 'player.normalized_position.x')) > .01, 2)
                reset = self.restart(name)
                samples = self.o.window(name+'-stable', .6)
            names.extend((name+'-dirty', name, name+'-stable'))
            good = bool(moved and reset and samples) and all(fresh(game(s)) for s in samples)
            good = good and span([reset]+samples, 'player.normalized_position.x') < .003
            self.boundary_result('restart_held_'+key, 'D4-04', good,
                                 'RESTART_CLEARS_HELD_DIRECTION_AND_RESIDUAL_MOTION', *names)
        self.cap('restart-held-clean')

    def restart_strike(self):
        self.approach('cancel-strike-close')
        with self.trace('cancel-strike-trace') as seq:
            self.press('J')
            pending = self.wait('cancel-strike-pending', lambda g:
                                field(g, 'player.action_state') == 'light_attack', .3)
            reset = self.restart('cancel-strike-reset')
            safe = self.o.window('cancel-strike-old-deadline', 1.3)
        self.cap('cancel-strike-clean')
        self.boundary_result('restart_strike', 'D4-04', reset and safe and all(fresh(game(s)) for s in safe),
                             'RESTART_CANCELS_COMMITTED_STRIKE_AND_OLD_DAMAGE',
                             'cancel-strike-pending', 'cancel-strike-trace', 'cancel-strike-old-deadline',
                             gap=not pending)

    def reopen_terminal(self):
        initial = self.o.last
        loss = self.wait('reopen-terminal-loss', lambda g: field(g, 'phase') == 'rival_won', 20, 2)
        if not loss:
            raise CandidateError('TERMINAL_REOPEN_PRECONDITION_UNREACHABLE')
        self.cap('reopen-terminal-before')
        self.p.call('reopen'); self.o.bind(self.p.session)
        opened = self.wait('reopen-terminal-fresh', fresh, 2, 2)
        self.cap('reopen-terminal-after')
        good = opened and opened['process_token'] != loss['process_token'] and opened['round_id'] != loss['round_id']
        good = good and all(abs(number(game(opened), who+'.normalized_position.'+axis)
                               - number(game(initial), who+'.normalized_position.'+axis)) < .003
                            for who in ('player','rival') for axis in ('x','y'))
        self.boundary_result('reopen_terminal', 'D4-05', good,
                             'TERMINAL_PROGRESS_NOT_RESTORED_IN_NEW_PROCESS', 'reopen-terminal-loss','reopen-terminal-fresh')

    def bolt_overkill(self):
        self.approach('overkill-bolt-close')
        for n in range(3):
            self.wait('overkill-strike-ready-'+str(n),lambda g: field(g,'player.action_state') in ('idle','moving'),3)
            self.press('J')
            hit=self.wait('overkill-strike-hit-'+str(n),lambda g: number(g,'rival.health') <= 100-25*(n+1),2)
            if not hit or number(game(hit),'rival.health') != 100-25*(n+1):
                raise CandidateError('BOLT_OVERKILL_SETUP_DAMAGE_INVALID')
        for n in range(2):
            ready=self.wait('overkill-bolt-ready-'+str(n),lambda g: field(g,'combat.bolt_ready') is True
                            and field(g,'player.action_state') in ('idle','moving'),3)
            if not ready:
                raise CandidateError('BOLT_OVERKILL_NOT_READY')
            self.press('K')
            hit=self.wait('overkill-bolt-hit-'+str(n),lambda g: number(g,'rival.health') <= max(0,25-15*(n+1)),2)
            if not hit:
                raise CandidateError('BOLT_OVERKILL_NO_HIT')
        stable=self.o.window('overkill-bolt-stable',.6)
        self.cap('overkill-bolt-result')
        self.boundary_result('bolt_overkill','D3-04',stable and all(number(game(s),'rival.health')==0
                             and field(game(s),'phase')=='player_won'
                             and number(game(s),'combat.active_player_projectiles')==0 for s in stable),
                             'TEN_HP_RIVAL_CLAMPS_TO_ZERO_ON_15_DAMAGE','overkill-bolt-hit-0','overkill-bolt-hit-1','overkill-bolt-stable')

    def feedback_guard(self):
        with self.held('S'):
            tele=self.wait('feedback-guard-telegraph',lambda g:field(g,'combat.telegraph_active') is True,4)
            if not tele:
                raise CandidateError('GUARD_FEEDBACK_PRECONDITION_UNREACHABLE')
            with self.trace('feedback-guard-duration') as seq:
                self.o.window('feedback-guard-through-impact',2.2)
        verdict,interval=feedback_interval(seq,'BLOCKED')
        self.boundary_result('guard_duration','D5-04',verdict=='pass',
                             'BLOCKED_DURATION_BOUNDS:'+str(interval),'feedback-guard-duration',gap=verdict in ('gap','replaced'))

    def bolt_rejection_trace(self):
        initial=self.o.last
        with self.trace('bolt-rejection-continuous') as seq:
            self.o.window('bolt-rejection-before',.3)
            self.press('K')
            bolt=self.wait('bolt-rejection-first',lambda g:number(g,'combat.active_player_projectiles')==1,1)
            if not bolt:
                raise CandidateError('BOLT_REJECTION_PRECONDITION_UNREACHABLE')
            deadline=number(game(bolt),'combat.round_time_ms')+number(game(bolt),'combat.bolt_cooldown_remaining_ms')
            for n in range(2):
                current=game(load(self.root/'state/duel-state.json'))
                if field(current,'combat.bolt_ready') is True:
                    raise InfrastructureError('REJECTION_ACQUISITION_MISSED_COOLDOWN')
                self.press('K')
            self.cap('bolt-rejection-feedback')
            self.o.window('bolt-rejection-after',1.5)
        before_hp=number(game(initial),'rival.health')
        cooldown_samples=[s for s in seq if number(game(s),'combat.bolt_cooldown_remaining_ms')>0]
        good=bool(cooldown_samples) and all(abs(number(game(s),'combat.round_time_ms')+
                       number(game(s),'combat.bolt_cooldown_remaining_ms')-deadline)<=60 for s in cooldown_samples)
        good=good and all(number(game(s),'combat.active_player_projectiles') in (0,1)
                         and number(game(s),'player.health')==number(game(initial),'player.health')
                         and number(game(s),'rival.health') in (before_hp,before_hp-15) for s in seq)
        # Reject false rival hit feedback before the legitimate bolt damage.
        good=good and all(not field(game(s),'feedback.hit_feedback_visible') for s in seq
                         if number(game(s),'rival.health')==before_hp)
        self.boundary_result('rejection_side_effects','D3-05',good,
                             'REPEATED_REJECTION_PRESERVES_DEADLINE_HP_COUNTS_AND_REACTIONS','bolt-rejection-continuous')
        verdict,interval=feedback_interval(seq,'COOLDOWN')
        self.boundary_result('cooldown_duration','D5-03',verdict in ('pass','replaced'),
                             'COOLDOWN_DURATION_OR_LEGITIMATE_REPLACEMENT:'+str(interval),'bolt-rejection-continuous',gap=verdict=='gap')

    def draw_probe(self):
        """Bounded scheduling probe; lack of synchronization is never a candidate zero.

        Public snapshots do not expose frame IDs or pending-impact deadlines. Even a
        double-zero snapshot alone cannot prove both impacts belonged to ONE update.
        Save useful diagnostic evidence, but require an independent frame witness to
        award the simultaneous-update clause. No private candidate member is read.
        """
        self.approach('draw-close')
        latencies = []
        for n in range(3):
            ready = self.wait('draw-strike-ready-'+str(n), lambda g:
                              field(g, 'player.action_state') in ('idle', 'moving'), 3)
            if not ready:
                raise CandidateError('DRAW_SETUP_STRIKE_UNAVAILABLE')
            hp = number(game(ready), 'rival.health')
            self.press('J')
            hit = self.wait('draw-strike-hit-'+str(n), lambda g: number(g, 'rival.health') < hp, 2)
            if not hit or number(game(hit), 'rival.health') != hp-25:
                raise CandidateError('DRAW_SETUP_DAMAGE_INVALID')
            latencies.append(number(game(hit), 'combat.round_time_ms')-number(game(ready), 'combat.round_time_ms'))
        low = self.wait('draw-player-low', lambda g: number(g, 'player.health') <= 20, 17)
        if not low or number(game(low), 'player.health') != 20:
            raise CandidateError('DRAW_SETUP_PLAYER_HEALTH_UNREACHABLE')
        tele = self.wait('draw-final-telegraph', lambda g: field(g, 'combat.telegraph_active') is True, 4)
        if not tele:
            raise CandidateError('DRAW_SETUP_TELEGRAPH_UNREACHABLE')
        lead = sorted(latencies)[1]
        ready = self.wait('draw-input-window', lambda g:
                          number(g, 'combat.telegraph_remaining_ms') <= lead, 1)
        with self.trace('draw-decisive-trace') as seq:
            self.press('J')
            result = self.wait('draw-result', lambda g: field(g, 'phase') != 'active', 2)
            self.cap('draw-result')
        verdict = draw_result(ready, result)
        self.boundary_result('simultaneous_draw', 'D3-09', False,
                             'FRAME_CAUSALITY_WITNESS_UNAVAILABLE; observed='+verdict,
                             'draw-input-window', 'draw-decisive-trace', 'draw-result', gap=True)
