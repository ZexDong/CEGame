"""Independent normal-input cases using only the published read-only state contract."""
import math
from contextlib import contextmanager
from runtime import load, CandidateError, InfrastructureError


def field(g, path, default=None):
    for key in path.split('.'):
        if not isinstance(g, dict) or key not in g:
            return default
        g = g[key]
    return g


def game(snapshot):
    return snapshot.get('game_state') or {} if snapshot else {}


def number(g, path, default=math.nan):
    value = field(g, path)
    return value if type(value) in (int, float) and math.isfinite(value) else default


def fresh(g):
    return (field(g, 'phase') == 'active'
            and number(g, 'player.health') == number(g, 'rival.health') == 100
            and field(g, 'player.grounded') is True
            and field(g, 'player.action_state') == field(g, 'rival.action_state') == 'idle'
            and field(g, 'combat.bolt_ready') is True
            and number(g, 'combat.active_player_projectiles') == 0
            and field(g, 'combat.telegraph_active') is False
            and field(g, 'feedback.result_text') == field(g, 'feedback.status_text') == '')


def span(samples, path):
    values = [number(game(s), path) for s in samples]
    return max(values) - min(values) if values and all(math.isfinite(v) for v in values) else math.inf


class AtomicCases:
    """Each case has its own process. R is only used when R itself is under test."""

    @contextmanager
    def held(self, key):
        self.p.call('down', key=key)
        try:
            yield
        finally:
            self.p.call('up', key=key)

    def samples(self, name):
        return load(self.root / 'states' / (name + '.json'))['samples']

    def check(self, checkpoint, passed, reason, *names):
        self.mark(checkpoint, bool(passed), reason, *['states/' + n + '.json' for n in names])

    def active(self, name):
        state = self.wait(name, lambda g: field(g, 'phase') == 'active', 2, 2)
        if not state:
            raise CandidateError('ACTIVE_STATE_UNREACHABLE:' + name)
        return state

    def motion(self):
        start = self.o.last
        x = number(game(start), 'player.normalized_position.x')
        with self.held('A'):
            away = self.wait('moving-away', lambda g: number(g, 'player.normalized_position.x') < x - 1/1280, 4, 2)
            self.cap('walk-away')
            wall = self.boundary('left-boundary')
            self.cap('walk-away-later')
        released = self.o.window('released', .65)
        self.cap('idle-after-move')
        x = number(game(self.o.last), 'player.normalized_position.x')
        with self.held('D'):
            toward = self.wait('moving-toward', lambda g: number(g, 'player.normalized_position.x') > x + 1/1280, 4, 2)
            self.cap('walk-toward')
            collision = self.boundary('rival-boundary')
            self.cap('walk-toward-later')
        basic = bool(away and toward)
        self.check('D2-02', basic, 'MOVEMENT_BASIC_USE', 'moving-away', 'moving-toward')
        all_samples = wall + released + collision
        bounded = bool(wall and collision) and all(
            0 <= number(game(s), 'player.normalized_position.x') < number(game(s), 'rival.normalized_position.x') <= 1
            and field(game(s), 'player.facing') == 'right' for s in all_samples)
        self.check('D3-01', basic and bounded and len(released) >= 2
                   and span(released, 'player.normalized_position.x') < .003,
                   'MOVEMENT_BOUNDS_RELEASE_FACING_COLLISION', 'left-boundary', 'released', 'rival-boundary')

    def jump_control(self):
        self.press('W')
        air = self.wait('control-airborne', lambda g: field(g, 'player.grounded') is False, 2)
        land = self.wait('control-landed', lambda g: field(g, 'player.grounded') is True, 4, 2) if air else None
        self.facts['jump_control'] = {'air': air, 'land': land, 'samples': self.samples('control-landed') if air else []}
        self.check('D2-03', air and land, 'JUMP_BASIC_USE', 'control-airborne', *(['control-landed'] if air else []))

    def jump_rejection(self):
        self.press('W')
        air = self.wait('airborne', lambda g: field(g, 'player.grounded') is False, 2)
        if not air:
            self.check('D3-02', False, 'GROUNDED_JUMP_NOT_OBSERVED', 'airborne')
            return
        self.cap('airborne')
        before = self.o.window('jump-before-second', .08)
        self.press('W')
        arc = self.o.window('jump-arc', .18)
        self.cap('airborne-later')
        land = self.wait('landed', lambda g: field(g, 'player.grounded') is True, 4, 2)
        self.cap('landed')
        control = self.facts.get('jump_control', {})
        control_samples = control.get('samples', [])
        challenged = before + arc + self.samples('landed')
        peak = lambda samples: min((number(game(s), 'player.normalized_position.y') for s in samples), default=math.nan)
        duration = lambda first, last: number(game(last), 'combat.round_time_ms') - number(game(first), 'combat.round_time_ms')
        good = (air and land and control.get('air') and control.get('land') and before and arc
                and peak(challenged) >= peak(control_samples) - .006
                and duration(air, land) <= duration(control['air'], control['land']) + 150)
        self.check('D3-02', good, 'AIRBORNE_INPUT_PRESERVES_CONTROL_ARC', 'control-airborne', 'control-landed',
                   'airborne', 'jump-before-second', 'jump-arc', 'landed')

    def whiff(self):
        initial = game(self.o.last)
        self.press('J')
        miss = self.wait('whiff', lambda g: field(g, 'combat.last_resolution') == 'player_strike_whiff', 2)
        self.cap('whiff')
        stable = self.o.window('whiff-visible', .35)
        self.cap('whiff-later')
        self.facts['whiff'] = bool(miss and stable) and all(
            number(game(s), 'rival.health') == number(initial, 'rival.health')
            and number(game(s), 'combat.active_player_projectiles') == 0
            and field(game(s), 'feedback.hit_feedback_visible') is False for s in [miss] + stable)
        self.facts['strike_available'] = bool(miss)

    def bolt(self):
        initial = game(self.o.last)
        self.press('K')
        bolt = self.wait('bolt-active', lambda g: number(g, 'combat.active_player_projectiles') > 0, 2)
        self.cap('bolt-cast')
        self.press('K')
        rejected = self.wait('rejected', lambda g: field(g, 'combat.last_resolution') == 'bolt_cooldown_rejected', 1)
        self.cap('cooldown')
        self.press('K')
        repeat = self.o.window('rejected-repeat', .35)
        hit = self.wait('bolt-hit', lambda g: number(g, 'rival.health') < number(initial, 'rival.health'), 4)
        self.cap('bolt-hit')
        self.o.window('bolt-hit-visible', .1)
        self.cap('bolt-hit-later')
        ready = self.wait('bolt-ready', lambda g: field(g, 'combat.bolt_ready') is True, 3, 2)
        stable = self.o.window('bolt-resolved-stable', .35)
        self.check('D2-05', bolt and rejected and ready, 'BOLT_AND_READINESS_AVAILABLE', 'bolt-active', 'rejected', 'bolt-ready')
        bg, rg = game(bolt), game(rejected)
        # Use an observed deadline, including the remaining cooldown at the first sample.
        deadline = number(bg, 'combat.round_time_ms') + number(bg, 'combat.bolt_cooldown_remaining_ms')
        rejection_deadline = number(rg, 'combat.round_time_ms') + number(rg, 'combat.bolt_cooldown_remaining_ms')
        seq = [s for name in ('bolt-active', 'rejected', 'rejected-repeat', 'bolt-hit', 'bolt-ready', 'bolt-resolved-stable') for s in self.samples(name)]
        first_time = number(initial, 'combat.round_time_ms')
        good = (bolt and hit and ready and stable
                and 900 <= deadline - first_time <= 1150
                and number(game(ready), 'combat.round_time_ms') >= deadline - 60
                and all(number(game(s), 'combat.active_player_projectiles') <= 1 for s in seq)
                and all(number(game(s), 'rival.health') == max(0, number(initial, 'rival.health') - 15)
                        and number(game(s), 'combat.active_player_projectiles') == 0 for s in [hit] + stable))
        self.check('D3-04', good, 'BOLT_DAMAGE_REMOVAL_AND_ONE_SECOND_COOLDOWN', 'bolt-active', 'bolt-hit', 'bolt-ready', 'bolt-resolved-stable')
        self.facts['bolt_rejection'] = bool(bolt and rejected and repeat) and abs(rejection_deadline - deadline) <= 60 and all(
            number(game(s), 'combat.active_player_projectiles') <= 1 for s in repeat)

    def approach(self, name):
        with self.held('D'):
            reached = self.boundary(name)
        if not reached:
            raise CandidateError('CLOSE_RANGE_UNREACHABLE:' + name)
        return self.o.last

    def strike(self):
        close = self.approach('approach')
        self.cap('close-range')
        health = number(game(close), 'rival.health')
        self.press('J')
        self.cap('strike-action')
        hit = self.wait('strike-hit', lambda g: number(g, 'rival.health') < health, 2)
        self.cap('strike-hit')
        ended = self.wait('strike-ended', lambda g: field(g, 'player.action_state') in ('idle', 'moving'), 3, 2)
        stable = self.o.window('strike-stable', .35)
        self.facts['strike_hit'] = bool(hit and ended and stable) and all(number(game(s), 'rival.health') == max(0, health - 25) for s in [hit] + stable)
        self.facts['strike_available'] = self.facts.get('strike_available', False) or bool(hit)

    def pulse(self):
        initial = game(self.o.last)
        tele = self.wait('telegraph-1', lambda g: field(g, 'combat.telegraph_active') is True, 4)
        self.cap('telegraph')
        hit = self.wait('pulse-hit', lambda g: number(g, 'player.health') < number(initial, 'player.health'), 2)
        self.cap('pulse-hit')
        self.o.window('pulse-hit-motion', .1)
        self.cap('pulse-hit-later')
        next_tele = self.wait('telegraph-2', lambda g: field(g, 'combat.telegraph_active') is True, 4)
        next_hit = self.wait('pulse-hit-2', lambda g: number(g, 'player.health') < number(game(hit), 'player.health'), 2)
        self.check('D2-06', tele and hit, 'RIVAL_WARNING_AND_PULSE_AVAILABLE', 'telegraph-1', 'pulse-hit')
        clock = lambda s: number(game(s), 'combat.round_time_ms')
        seq = self.samples('pulse-hit')
        no_early = all(number(game(s), 'player.health') == number(initial, 'player.health') for s in seq[:-1])
        stationary = self.samples('telegraph-1') + seq + self.samples('telegraph-2') + self.samples('pulse-hit-2')
        good = (tele and hit and next_tele and next_hit and no_early
                and 2850 <= clock(tele) <= 3150 and 650 <= clock(hit) - clock(tele) <= 850
                and 2850 <= clock(next_tele) - clock(hit) <= 3150 and 650 <= clock(next_hit) - clock(next_tele) <= 850
                and number(game(hit), 'player.health') == number(initial, 'player.health') - 20
                and number(game(next_hit), 'player.health') == number(initial, 'player.health') - 40
                and span(stationary, 'rival.normalized_position.x') < .003)
        self.check('D3-06', good, 'RIVAL_EXACT_DAMAGE_CADENCE_AND_STATIONARY_POSITION',
                   'telegraph-1', 'pulse-hit', 'telegraph-2', 'pulse-hit-2')

    def guard(self):
        initial = game(self.o.last)
        with self.held('S'):
            pose = self.wait('guard-pose', lambda g: field(g, 'player.action_state') == 'blocking', 1)
            self.cap('guard')
            self.o.window('guard-motion', .08)
            self.cap('guard-later')
            blocked = self.wait('blocked', lambda g: field(g, 'combat.last_resolution') == 'rival_pulse_blocked', 5)
            self.cap('blocked')
            tele = self.wait('guard-telegraph-2', lambda g: field(g, 'combat.telegraph_active') is True, 4)
            blocked2 = self.wait('blocked-2', lambda g: field(g, 'combat.telegraph_active') is False, 2) if tele else None
        released = self.wait('guard-released', lambda g: field(g, 'player.action_state') == 'idle', 1, 2)
        pulse = self.wait('guard-released-hit', lambda g: number(g, 'player.health') < number(initial, 'player.health'), 5)
        with self.held('S'):
            late = self.o.window('late-block', .6)
        self.check('D2-07', pose and blocked, 'HELD_GUARD_AVAILABLE', 'guard-pose', 'blocked')
        good = (blocked and blocked2 and released and pulse and late
                and all(number(game(s), 'player.health') == number(initial, 'player.health')
                        and number(game(s), 'rival.health') == number(initial, 'rival.health')
                        and number(game(s), 'combat.active_player_projectiles') == 0 for s in (blocked, blocked2))
                and all(number(game(s), 'player.health') == number(game(pulse), 'player.health') for s in late))
        seq = [s for n in ('guard-pose', 'blocked', 'guard-telegraph-2', 'guard-released', 'late-block') for s in self.samples(n)]
        good = good and span(seq, 'player.normalized_position.x') < .003
        self.check('D3-07', good, 'GUARD_REPEATED_PULSES_RELEASE_AND_LATE_INPUT', 'blocked', 'guard-released', 'guard-released-hit', 'late-block')

    def terminal_lock(self, terminal, name):
        for key in ('A', 'D', 'W', 'J', 'K', 'S'):
            self.press(key)
        seq = self.o.window(name + '-lock', 3.7)
        before = game(terminal)
        paths = ('phase', 'player.health', 'rival.health', 'feedback.result_text',
                 'world.object_counts.player_fighters', 'world.object_counts.rival_fighters')
        good = bool(seq) and all(all(field(game(s), p) == field(before, p) for p in paths)
            and number(game(s), 'combat.active_player_projectiles') == 0
            and field(game(s), 'combat.telegraph_active') is False
            and field(game(s), 'player.action_state') not in ('blocking', 'light_attack', 'energy_attack', 'airborne', 'moving') for s in seq)
        good = good and span([terminal] + seq, 'player.normalized_position.x') < .003 and span([terminal] + seq, 'player.normalized_position.y') < .003
        self.facts[name + '_lock'] = bool(good)
        self.cap(name + '-stable')
        reset = self.restart(name + '-restart')
        self.facts[name + '_restart'] = bool(reset)

    def player_win(self):
        self.approach('win-approach')
        # Bounded adaptive input: stop on observed KO, not a reference hit count.
        while True:
            ready = self.wait('win-ready-' + str(self.p.action_count), lambda g: field(g, 'phase') != 'active'
                              or field(g, 'player.action_state') in ('idle', 'moving'), 3)
            if not ready:
                raise CandidateError('WIN_ACTION_NEVER_READY')
            if field(game(ready), 'phase') != 'active':
                break
            if self.p.action_count >= 16:
                raise CandidateError('PLAYER_WIN_ACTION_BUDGET_EXHAUSTED')
            health = number(game(ready), 'rival.health')
            self.press('J')
            self.wait('win-impact-' + str(self.p.action_count), lambda g: number(g, 'rival.health') < health, 2)
        win = self.wait('player-win', lambda g: field(g, 'phase') == 'player_won', 2, 2)
        self.check('D4-02', win, 'ENTRY_TO_PLAYER_WIN', 'player-win')
        self.facts['win'] = win
        if win:
            self.cap('player-win')
            self.terminal_lock(win, 'player-win')

    def rival_win(self):
        loss = self.wait('rival-win', lambda g: field(g, 'phase') == 'rival_won', 20, 2)
        self.check('D4-03', loss, 'ENTRY_TO_RIVAL_WIN', 'rival-win')
        self.facts['loss'] = loss
        if loss:
            self.cap('rival-win')
            self.terminal_lock(loss, 'rival-win')

    def restart_case(self):
        self.press('K')
        self.press('W')
        with self.held('S'):
            dirty = self.wait('restart-dirty', lambda g: number(g, 'combat.active_player_projectiles') > 0
                              or field(g, 'player.grounded') is False, 1)
            reset = self.restart('restart-in-flight')
            clean = self.o.window('restart-old-event-window', .9)
        self.cap('restart')
        repeat = self.restart('repeat-restart')
        tele = self.wait('restart-telegraph', lambda g: field(g, 'combat.telegraph_active') is True, 4)
        self.restart('restart-from-telegraph')
        safe = self.o.window('cancelled-pulse', 1)
        cadence = self.wait('fresh-cadence', lambda g: field(g, 'combat.telegraph_active') is True, 3)
        self.facts['restart_available'] = bool(reset and repeat)
        self.facts['restart_rule'] = bool(dirty and reset and repeat and tele and clean and safe and cadence) and all(fresh(game(s)) for s in clean + safe) and 2850 <= number(game(cadence), 'combat.round_time_ms') <= 3150

    def reopen_case(self):
        initial = self.o.last
        self.press('K')
        progressed = self.wait('pre-reopen-progress', lambda g: number(g, 'rival.health') < number(game(initial), 'rival.health'), 4)
        old = self.o.last
        self.p.call('reopen')
        self.o.bind(self.p.session)
        opened = self.wait('reopened', lambda g: field(g, 'phase') == 'active', 2, 2)
        self.cap('reopened')
        self.facts['reopen_available'] = bool(opened and old and opened['process_token'] != old['process_token'])
        same_positions = all(abs(number(game(opened), p) - number(game(initial), p)) < .003 for p in ('player.normalized_position.x', 'rival.normalized_position.x'))
        self.check('D4-05', progressed and self.facts['reopen_available'] and fresh(game(opened)) and same_positions
                   and opened['round_id'] != old['round_id'], 'REOPEN_CLEARS_PROGRESS_WITH_NEW_PROCESS', 'pre-reopen-progress', 'reopened')

    def aggregate_rules(self):
        self.check('D2-04', self.facts.get('strike_available'), 'STRIKE_BASIC_HIT_OR_MISS', *self.available_states('whiff', 'strike-hit'))
        self.check('D3-03', self.facts.get('whiff') and self.facts.get('strike_hit'), 'STRIKE_EXACT_SINGLE_HIT_AND_ZERO_MISS', *self.available_states('whiff', 'strike-hit', 'strike-stable'))
        self.check('D3-05', self.facts.get('whiff') and self.facts.get('bolt_rejection'), 'WHIFF_AND_REJECTION_NO_EXTRA_EFFECT', *self.available_states('whiff', 'rejected', 'rejected-repeat'))
        win, loss = self.facts.get('win'), self.facts.get('loss')
        self.check('D2-08', win and loss, 'BOTH_OUTCOMES_AVAILABLE', *self.available_states('player-win', 'rival-win'))
        w, l = game(win), game(loss)
        self.check('D3-09', win and loss and number(w, 'rival.health') == 0 and number(w, 'player.health') > 0
                   and number(l, 'player.health') == 0 and number(l, 'rival.health') > 0
                   and field(w, 'feedback.result_text') == 'PLAYER WINS' and field(l, 'feedback.result_text') == 'RIVAL WINS',
                   'KO_HEALTH_AND_BANNER', *self.available_states('player-win', 'rival-win'))
        self.check('D3-10', self.facts.get('player-win_lock') and self.facts.get('rival-win_lock'), 'BOTH_TERMINALS_REJECT_INPUT_AND_OLD_CADENCE', *self.available_states('player-win-lock', 'rival-win-lock'))
        self.check('D2-09', self.facts.get('restart_available') and self.facts.get('reopen_available'), 'RESTART_AND_REOPEN_AVAILABLE', *self.available_states('restart-in-flight', 'reopened'))
        self.check('D4-04', self.facts.get('restart_rule') and self.facts.get('player-win_restart') and self.facts.get('rival-win_restart'), 'ACTIVE_AND_TERMINAL_RESTART_CLEAR_STATE', *self.available_states('restart-in-flight', 'repeat-restart', 'cancelled-pulse', 'player-win-restart', 'rival-win-restart'))

    def available_states(self, *names):
        return [n for n in names if (self.root / 'states' / (n + '.json')).is_file()]

    def visual_initial(self):
        self.captures['d6-initial'] = self.p.capture('d6-initial')
        self.captures['d6-initial']['state_reached'] = True

    def visual_close(self):
        self.approach('d6-approach')
        self.captures['d6-close'] = self.p.capture('d6-close')
        self.captures['d6-close']['state_reached'] = True

    def visual_jump(self):
        self.press('W')
        air = self.wait('d6-airborne', lambda g: field(g, 'player.grounded') is False, 2)
        if not air:
            raise CandidateError('D6_JUMP_UNREACHABLE')
        self.captures['d6-jump'] = self.p.capture('d6-jump')
        self.captures['d6-jump']['state_reached'] = True
