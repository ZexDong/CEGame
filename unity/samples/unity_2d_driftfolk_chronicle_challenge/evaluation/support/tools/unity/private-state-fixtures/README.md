# Evaluator State Preparation

Inject this support only into evaluation copies after generation. Keep it outside generation input, the GDD, public contracts, and manual-play packages.

PreparedStateSession enforces Preparing -> Ready -> Acting -> Closed. Only Preparing may invoke existing initialization, scene loading, or legal precondition writes. Verify setup through engine objects, rendered output, or independent events, close write access, then assess normal player input. Setup timeout or failed preconditions are evaluator faults, not automatic candidate zeros.

Do not create missing levels, add gameplay logic, or write the tested victory/damage outcome. In-level checks may prepare later levels; transition checks start before the preceding exit and let the candidate perform the transition. Observe respawn, restart, and cleanup after actual actions; fixture cleanup must not conceal defects.

This class checks adapter lifecycle rather than providing a permission sandbox. Bind and calibrate adapter source, candidate identity, allowed writes, and independent evidence. Candidate implementations may require separate adapters; the setup protocol, write boundary, and verdict process are shared.

The scoring backend verifies leaf checks, raw evidence, complete assertions, and matching evaluator bindings. This setup helper cannot award points.
