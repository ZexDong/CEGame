# Runtime presentation review

Revision `nightsky-runtime-review-3.1.0` reviews contemporaneous normal-input capture
sequences, input receipts and paired public state snapshots. D1-D5 never use a
reference-image comparison or a separate VLM numerical scoring call. Record the
actual reviewer: a human review uses `human_normal_input_capture_review`; the
agent-based evidence review uses `runtime_evidence_audit` and
`reviewer.kind=agent_runtime_evidence_audit`. It is not human approval or sign-off.
Use `score.py --template` to create the evidence-bound review record. A missing
review is an incomplete evaluation, never a candidate zero or a passing default.

Review all 17 IDs once. A pass requires hashed evidence from this run, a concrete
observation, and every listed element. If the candidate cannot produce a required
view, record the direct candidate failure and fail that check. Independent visible
content may pass even when a different Dashboard field is malformed.

| ID | Inspect |
|---|---|
| D2-01 | Initial view: bounded side-view arena, readable floor, exactly two visible fighters, direct entry and controls. |
| D2-02 through D2-07 | Match each collected movement, jump, strike, bolt, pulse and guard state to its visible action. State strings alone cannot establish the presence of invisible gameplay. These gates cannot override a failed automatic rule. |
| D3-01 | Check rendered facing at entry, walking in both directions and release, as well as the existing bounds/release/collision assertions. The reported `facing` string alone is insufficient. |
| D4-01 | A visible playable arena must exist at fresh entry; HUD-only state changes cannot establish direct playable entry. |
| D2-10 | Required HUD and feedback actually appear across initial, whiff, cooldown, bolt-hit, blocked, pulse-hit and both terminal captures. This checks presence only. |
| D2-11 | Both visible articulated fighter bodies are the supplied Manny model; player/rival colors are distinct. A hidden imported model earns no credit. |
| D2-12 | Watch pairs of idle, walk-away, walk-toward, airborne/landing, strike, bolt-cast, guard and hit captures. Verify recognizable supplied motions for all eight public roles. Use import provenance/binding inspection only as corroboration; files alone never pass. |
| D5-01 | At 1280x720 read the exact controls, labels, both numeric health values and proportional bars, and bolt status. Check text against same-time state. |
| D5-02 | Position visibly follows movement input; jump leaves the floor and lands; release recovers idle. Reject static poses and state-only motion. |
| D5-03 | Strike, traveling bolt, hit, WHIFF and COOLDOWN are visible and match their input/state transitions. Use context before/after snapshots; reject a capture outside the claimed state. |
| D5-04 | Warning covers the telegraph, held guard is visibly distinct, pulse impact produces a guard flash/BLOCKED or an appropriate hit reaction. |
| D5-05 | PLAYER WINS and RIVAL WINS agree with final health; banner persists through terminal-lock evidence; Restart/Reopen visibly restore fresh values and idle poses. |

All short-lived text must remain visible for 0.30-1.25 seconds unless replaced by a
later resolution, as specified in INTERFACE-02. Inspect sampled state times and
capture contexts. Do not infer readability or actual clip playback from a boolean.
If evidence acquisition itself misses the relevant interval, report an evaluator
evidence gap and repair acquisition; do not guess a verdict.

`scripts/review_contract.py` is the exact capture-set validator. Passing items need
every required state capture and its matching context, input receipts, state samples
and concrete observations. Failed items still need relevant capture/context and
causal evidence. Candidate-caused failure to reach a required view can fail the
affected item; an unexplained acquisition gap cannot. Blanket approval records and
initial-frame-only action reviews are rejected. The 36 checkpoints, their owners,
public requirements and dimension maxima are unchanged.

## Required clause observations in revision 3.1

`review_contract.SUBCLAUSES` expands the grouped content/animation/feedback entries
without adding score owners. Passing D2-01, D2-12, D5-03, D5-04 and D5-05 must include
every named `clause_observations` entry, an explicit observation and its own relevant
indexed evidence paths. In particular, verify the two-fighter-width initial spacing,
each of the eight animation roles (hitstun on both fighters), full warning visibility,
all displayed nonterminal text lifetimes or valid event replacements, and the 500 ms
result-banner deadline. A generic statement that "animations/feedback look correct"
cannot fill these fields. Missing acquisition remains incomplete, never an assumed pass.

The automated boundary gate runs after this review and after legacy reconciliation.
Review approval cannot override a failed continuous-input or timing assertion. Use a review bound to the current collection and contract revision.
