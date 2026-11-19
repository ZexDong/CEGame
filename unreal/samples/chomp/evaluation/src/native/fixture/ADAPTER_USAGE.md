# Private semantic preconditions

Declared preconditions can be prepared in a separate evaluation copy. This package uses the repository `ue-state-fixture-1.0.0` transport
only in a separate assessment copy. The release input and Gold gameplay contain
no fixture reader. Normal Start/Restart and pause are mandatory before setup;
normal P/Resume and directional input trigger the behavior under test.

`adapters/gold.cpp` is the reference-specific mapping. `adapters/untouched.cpp`
probes the inert starter and explicitly refuses gameplay setup. Candidate
adapters must be separately authored and reviewed for their candidate identity;
the Gold mapping must never be guessed or imposed on a scaffold implementation.
An unavailable mapping is an evaluator authoring fault, not candidate failure.

The adapter may set whitelisted public preconditions: legal actor positions,
direction/edge progress, pre-existing score/lives/extra-life progress, remaining
pickups, the four ghost roles and their travel states, active time and remaining
timers, capture chain and spent fruit opportunities. It must validate the whole
request before writing. It cannot set a result phase, call any tested outcome,
write a verdict, or alter the read-only observation transport. Refreshing visual
transforms/pickup meshes after setup is allowed; executing game rules is not.

Each setup retains authorization, nonce/sequence, source identity, before/after
native receipt, consecutive public snapshots, a client capture and a cleanup
receipt. Setup acceptance checks the actual fields before normal input resumes.
Every case starts a new run via a visible control. Persistence cases use a new
process and the same isolated user directory. This is the task's audited reset
contract for reusing a process; unrelated cases do not inherit run state.

To adapt a returned scaffold, supply a new C++ mapping that implements the three
StateFixture functions, bind its source hash and reviewed candidate identity in
an adapter JSON, and stage it only in an assessment copy. Actor lookup must start
from an engine role or semantic identity. All scoring predicates remain in the
task script and consume public observations; no Gold source or symbols occur
there. Probe and setup disagreement invalidate the affected authoring run.
