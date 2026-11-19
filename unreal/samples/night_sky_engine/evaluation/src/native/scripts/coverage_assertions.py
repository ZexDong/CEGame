"""GDD boundary predicates. Missing observations are never positive evidence."""
import math
from atomic import field, game, number, span


def unchanged(samples, before, paths):
    return bool(samples) and all(field(game(before), p) is not None for p in paths) and all(field(game(s), p) == field(game(before), p)
                                 for s in samples for p in paths)


def terminal_unchanged(samples, before):
    paths = ('phase', 'player.health', 'rival.health', 'feedback.result_text',
             'world.object_counts.player_fighters', 'world.object_counts.rival_fighters')
    return (unchanged(samples, before, paths)
            and all(before.get(p) is not None and s.get(p) == before[p]
                    for s in samples for p in ('round_id','process_id','process_token'))
            and all(number(game(s), 'combat.active_player_projectiles') == 0
                    and field(game(s), 'combat.telegraph_active') is False
                    and isinstance(field(game(s), 'player.action_state'), str)
                    and (field(game(s), 'player.action_state') not in
                         ('blocking', 'light_attack', 'energy_attack', 'airborne', 'moving')
                         or field(game(s), 'player.action_state') == field(game(before), 'player.action_state'))
                    for s in samples)
            and all(span([before] + samples, who + '.normalized_position.' + axis) < .003
                    for who in ('player', 'rival') for axis in ('x', 'y')))


def guard_stationary(samples, before):
    return (unchanged(samples, before, ('player.health', 'rival.health',
                                      'combat.active_player_projectiles'))
            and all(field(game(s), 'player.action_state') == 'blocking' for s in samples)
            and all(span([before] + samples, 'player.normalized_position.' + axis) < .003
                    for axis in ('x', 'y')))


def feedback_interval(samples, text):
    """Bracket appearance/expiry; only prove durations inside the GDD interval.

    A 250 ms publisher cannot prove a 300 ms minimum using one screenshot.
    Ambiguous intervals are acquisition gaps, not candidate failures or passes.
    """
    active = [i for i, s in enumerate(samples) if field(game(s), 'feedback.status_text') == text]
    if not active or active[0] == 0 or active[-1] == len(samples)-1:
        return 'gap', None
    first, last = active[0], active[-1]
    if active != list(range(first, last+1)):
        return 'fail', 'NONCONTIGUOUS_FEEDBACK'
    clock = lambda i: number(game(samples[i]), 'combat.round_time_ms')
    lower = clock(last)-clock(first)
    upper = clock(last+1)-clock(first-1)
    if not all(math.isfinite(v) for v in (lower, upper)):
        return 'gap', None
    if upper < 300 or lower > 1250:
        if upper < 300 and field(game(samples[last+1]), 'feedback.status_text'):
            return 'replaced', [lower, upper]
        return 'fail', [lower, upper]
    if field(game(samples[last+1]), 'feedback.status_text'):
        return ('replaced' if upper <= 1250 else 'gap'), [lower, upper]
    if lower >= 300 and upper <= 1250:
        return 'pass', [lower, upper]
    return 'gap', [lower, upper]


def draw_result(before, after):
    """Both HP transitions are necessary; a missed synchronization is a setup gap."""
    if not (number(game(before), 'player.health') > 0 and number(game(before), 'rival.health') > 0
            and number(game(after), 'player.health') == number(game(after), 'rival.health') == 0):
        return 'setup_gap'
    return 'pass' if (field(game(after), 'phase') == 'draw'
                       and field(game(after), 'feedback.result_text') == 'DRAW') else 'fail'
