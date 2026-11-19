# D6 visual evaluation contract

Revision `nightsky-visual-3.2.0` applies the task-specific
[visual rubric](VISUAL_RUBRIC_3_2.md). It replaces only the base guide D6 prompt.
`protocol.json` binds the base repository scoring guide, task rubric and fixed prompt by
SHA-256. The scorer verifies both before evaluating any state, including zero fallbacks.
The reference manifest fixes three representative original-source states: initial duel,
close-range duel and jump takeoff. Source receipts and native frames establish provenance.
The complete reference client frame is uniformly resized to 1280×720 without overlays.

After all dynamic cases, the collector uses a clean process for each candidate state.
No success journey, guard implementation, precise damage value or Restart is a prerequisite
for these visual captures. State acquisition uses public observation and normal input.

Each comparison sends reference first and candidate second, using the versioned task-specific
prompt with only its state label substituted. Compare all states in three complete rounds
under one configured provider/model/version/parameter set. The returned model identity
must remain constant. Different configurations cannot be pooled. No supplier/model list
is imposed; the configured endpoint must support image inputs and the fixed text response.

Save each request's round/state, exact prompt, ordered image hashes, configured parameters
and configuration hash. Save the raw response and parser receipt. The first accepted
two-image response is the capability receipt. Credentials remain in an environment variable.
The endpoint is represented by a hash in evidence; timeout and image detail are recorded.

The parser accepts exactly five task-specific criteria in their original order, each in
{0, 0.5, 1, 1.5, 2}, an exact sum and a nonempty reason. The scorer reparses every response,
checks all hashes/configuration bindings and rejects reuse of one round's request as another.
Each round is the arithmetic mean of all state totals. D6 is the mean of those three
unrounded means. Report the final value and three round means to one decimal.

Candidate-attributable unreachable states and black frames score zero in every round,
with the direct cause retained. Severe breakage or incomparable imagery can be recorded
in a hash-bound `human_capture_review` naming the exact candidate image, status
`candidate_broken` or `candidate_incomparable`, and concrete reason; attach its relative
path/hash as the capture's `visual_failure_review` and include it in the raw evidence index
before running D6. These states also score zero. No low-scoring state is removed.

Loss or modification of a previously collected image is an evidence fault, not candidate
missing imagery. A missing capture without a recorded candidate cause, capture-tool error,
API timeout, invalid response or model/configuration drift invalidates D6 and prevents
score publication. All-candidate-zero runs need no VLM service and still retain all three
state records in all three rounds.
