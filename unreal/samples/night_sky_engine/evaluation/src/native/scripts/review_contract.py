"""Runtime presentation evidence gates; no reference-image or numerical VLM scoring."""
from runtime import load, inside, sha, InfrastructureError

REVISION = 'nightsky-runtime-review-3.1.0'
# These are mandatory observations within existing score owners, not extra points.
SUBCLAUSES = {
    'D2-01': ('initial_two_fighter_widths', 'same_readable_floor', 'visible_arena_bounds'),
    'D2-12': ('stand_idle', 'fwalk_toward', 'bwalk_away', 'jump_airborne',
              '5a_strike', 'fireball_cast', 'standblock_guard', 'hitstun_both_fighters'),
    'D5-03': ('damage_flash_or_reaction', 'travelling_projectile', 'truthful_whiff',
              'truthful_cooldown', 'all_nonterminal_text_lifetimes_or_valid_replacements'),
    'D5-04': ('warning_entire_telegraph', 'held_block_pose', 'guard_flash_and_blocked',
              'unblocked_player_hit_reaction'),
    'D5-05': ('health_consistent_banners', 'banner_within_500ms_of_decisive_damage',
              'persistent_result', 'clean_restart_view', 'clean_reopen_view'),
}
# These supplement existing checkpoints, without adding checkpoints or points.
CAPTURES = {
    'D2-01': ['initial'],
    'D2-02': ['walk-away', 'walk-toward'],
    'D2-03': ['airborne', 'landed'],
    'D2-04': ['strike-action', 'strike-hit', 'whiff'],
    'D2-05': ['bolt-cast', 'cooldown', 'bolt-hit'],
    'D2-06': ['telegraph', 'pulse-hit'],
    'D2-07': ['guard', 'blocked'],
    'D2-10': ['initial', 'whiff', 'cooldown', 'bolt-hit', 'blocked', 'pulse-hit', 'player-win', 'rival-win'],
    'D2-11': ['initial', 'walk-toward', 'strike-hit', 'reopened'],
    'D2-12': ['initial', 'idle-after-move', 'walk-away', 'walk-away-later', 'walk-toward',
              'walk-toward-later', 'airborne', 'airborne-later', 'landed', 'strike-action',
              'strike-hit', 'bolt-cast', 'guard', 'guard-later', 'pulse-hit', 'pulse-hit-later'],
    'D3-01': ['initial', 'walk-away', 'walk-toward', 'idle-after-move'],
    'D4-01': ['initial'],
    'D5-01': ['initial', 'bolt-cast', 'bolt-hit', 'reopened'],
    'D5-02': ['walk-away', 'walk-toward', 'airborne', 'airborne-later', 'landed', 'idle-after-move'],
    'D5-03': ['strike-action', 'strike-hit', 'bolt-cast', 'bolt-hit', 'whiff', 'whiff-later', 'cooldown'],
    'D5-04': ['telegraph', 'guard', 'guard-later', 'blocked', 'pulse-hit', 'pulse-hit-later'],
    'D5-05': ['player-win', 'player-win-stable', 'rival-win', 'rival-win-stable', 'restart', 'reopened'],
}
GATED_IDS = {'D2-02', 'D2-03', 'D2-04', 'D2-05', 'D2-06', 'D2-07', 'D3-01', 'D4-01'}


def validate_review(review, raw, root):
    if review.get('method') == 'candidate_unreachable_evidence':
        return
    if review.get('review_revision') != REVISION:
        raise InfrastructureError('RUNTIME_REVIEW_REVISION_REQUIRED')
    reviewer = review.get('reviewer', {})
    if reviewer.get('kind') not in ('human', 'agent_runtime_evidence_audit') or not reviewer.get('identity'):
        raise InfrastructureError('RUNTIME_REVIEWER_PROVENANCE_REQUIRED')
    if review.get('review_authority') or review.get('blanket_approval') is not False:
        raise InfrastructureError('BLANKET_REVIEW_APPROVAL_REJECTED')
    if review.get('method') == 'human_normal_input_capture_review' and reviewer['kind'] != 'human':
        raise InfrastructureError('FALSE_HUMAN_REVIEW_PROVENANCE')
    for checkpoint, item in review['checks'].items():
        if item.get('pass') and checkpoint in SUBCLAUSES:
            clauses = item.get('clause_observations', {})
            if set(clauses) != set(SUBCLAUSES[checkpoint]):
                raise InfrastructureError('REVIEW_CLAUSE_COVERAGE_REQUIRED:' + checkpoint)
            parent_paths = {e['path'] for e in item.get('evidence', [])}
            for clause, observed in clauses.items():
                if (observed.get('pass') is not True or not observed.get('observation', '').strip()
                    or not observed.get('evidence') or any(e not in parent_paths for e in observed['evidence'])):
                    raise InfrastructureError('REVIEW_CLAUSE_EVIDENCE_REQUIRED:' + checkpoint + ':' + clause)
        paths = {e['path'] for e in item.get('evidence', [])}
        available = [raw['captures'][name] for name in CAPTURES[checkpoint] if name in raw['captures']]
        linked = [c for c in available if c['path'] in paths and c['context'] in paths]
        if not linked:
            raise InfrastructureError('REVIEW_REQUIRES_MATCHED_CAPTURE_CONTEXT:' + checkpoint)
        if item.get('pass') and (len(available) != len(CAPTURES[checkpoint]) or len(linked) != len(available)):
            raise InfrastructureError('REVIEW_MISSING_REQUIRED_STATE:' + checkpoint)
        if not any('/states/' in '/' + p for p in paths) or not any('/receipts/' in '/' + p for p in paths):
            raise InfrastructureError('REVIEW_REQUIRES_INPUT_AND_STATE:' + checkpoint)
        if not isinstance(item.get('observations'), list) or not item['observations'] or not all(isinstance(s, str) and s.strip() for s in item['observations']):
            raise InfrastructureError('REVIEW_CONCRETE_OBSERVATIONS_REQUIRED:' + checkpoint)
        # Validate the capture receipt linkage, not just an arbitrary attached PNG.
        indexed_hashes = {v for p, v in raw['evidence_sha256'].items() if '/receipts/' in '/' + p}
        for capture in linked:
            context = load(inside(root, capture['context']))
            if context.get('receipt_sha256') not in indexed_hashes:
                raise InfrastructureError('REVIEW_CAPTURE_RECEIPT_MISSING:' + checkpoint)


def apply_verdict(actual, checkpoint, item):
    """A presentation pass must never repair a failed mechanical prerequisite."""
    row = actual[checkpoint]
    if checkpoint in GATED_IDS and row['verdict'] != 'pass' and item['pass']:
        return
    mechanical_evidence = row['evidence'] if checkpoint in GATED_IDS else []
    row.update(verdict='pass' if item['pass'] else 'fail', reason=item['reason'],
               evidence=list(dict.fromkeys(mechanical_evidence + [e['path'] for e in item['evidence']])))
