# Source-assisted observation exceptions — revision 3.1.1

Two clauses use a scoped, diagnostic source review where reliable runtime observation is unavailable. A source review is not evidence that the branch ran. Runtime scoring and checkpoint weights remain unchanged.

Exactly two clauses require a completed manual control-flow review:

| Clause | Existing owner | Required reasoning |
|---|---|---|
| `simultaneous_draw` | D3-09 | Trace every health mutation, damage callback, early terminal return/cancellation, final phase and result assignment. Establish what happens when both lethal impacts are due in the same update. A DRAW enum or branch is insufficient. |
| `missed_bolt_cleanup` | D3-04 | Trace spawning, travel/collision order, arena exit, destruction/visibility and active-projectile bookkeeping. Explicitly establish reachability or a normal-play invariant making the miss branch unreachable. |

A conditional source pass does not assert that an exit branch was executed. Source
passes cannot repair independent runtime failures or certify rendered readability.
DRAW source evidence resolves only the missing same-update witness; it cannot turn
an unrelated acquisition gap into a candidate failure or pass. Source failures force
the existing owner to fail, without adding points or duplicating a deduction.

Receipts use `nightsky-source-review-3.1.1`, identify the reviewer and authorization,
bind the public GDD hash and complete project identity, embed the exact reviewed UTF-8
files with their original SHA-256, and cite line ranges with call-path reasoning,
reachability and limitations. File presence or keyword matching never generates a
verdict. `source_review.py` validates the receipt, not the correctness of its reasoning.
As with semantic review, the evaluator operator must supply a trusted completed review;
candidate-provided self-reviews are not accepted as reviewer authority.

The project identity includes Source, Content, Config and the descriptor; runtime
cache folders use the existing identity exclusions. A project directly supplied as a
`.uproject` and the same project inside an input wrapper have the same review reuse
key. Any changed project file invalidates reuse and requires a fresh review.

Pass `--source-review <review.json>` to `scripts/evaluate.py` when collecting a new
run. It validates the review against the candidate before build and embeds it as
`states/source-review.json` in the run's evidence index. `scripts/score.py` requires
and revalidates it for candidates that reach observable gameplay. A candidate that
fails before any capture keeps the existing failure attribution without a review.
The bounded DRAW probe remains available for diagnostic input evidence; unsuccessful
synchronization is resolved by the source receipt, not relabeled as runtime success.

Every new collection binds its current candidate and evaluator. Source reviews cannot reuse results from a different project or substitute for failed runtime evidence.

The optional [observation source review](observation-source-review.md) resolves collector gaps using candidate-bound source and runtime evidence.
