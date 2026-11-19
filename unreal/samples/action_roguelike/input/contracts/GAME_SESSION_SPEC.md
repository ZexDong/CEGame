# Read-Only Task-State Contract

This contract defines evaluator interoperability. It does not add gameplay requirements, expose scores or checkpoints, or authorize gameplay control. `GDD.md` Section 6 remains the sole gameplay acceptance authority.

## Transport

The launcher passes two arguments:

```text
-ActionRoguelikeSnapshotPath=<absolute-snapshot-path>
-ActionRoguelikeEventsPath=<absolute-events-path>
```

Publish the snapshot to the exact first argument value according to `actionroguelike-probe-snapshot.schema.json`, and events to the exact second value according to `actionroguelike-probe-events.schema.json`. Paths are chosen by the launcher for each run and can contain spaces. No basename or directory name is fixed; do not reconstruct them from a project path or search for previous state files. The launcher creates their parent directories inside its run root. The two targets and the engine-health `StatePath` are distinct. Write a sibling temporary file, flush and close it, then atomically replace the target. Never expose an API that mutates Health, Credits, enemies, abilities, timers, results, Restart, or any gameplay outcome.

Publishing these documents does not by itself make their contents trusted scoring evidence. The candidate owns its project and can author any bytes or metadata it emits. Trust can only be assigned after the evaluator independently proves that a protected, evaluator-owned read-only publisher is loaded in the current process and binds the captured bytes to that process and evaluation session. Self-reported `publisher`, `trust`, provenance, hashes, or source references never perform that upgrade.

## Identity and freshness

- Use the launcher process token as the stable process identity.
- Use a new stable round ID for every new round, including Restart.
- Increase snapshot and event sequence numbers monotonically within one process.
- Use a monotonic publisher clock; do not use wall-clock timestamps for ordering.
- Publish one coherent snapshot from one frame or one completed state-update boundary.
- Retain stable entity IDs for the lifetime of an entity within a round.

## Lossless typed-event coverage

The event contract uses a version 2 half-open cursor interval: every batch contains exactly the event sequences in `[cursor_start, cursor_end)`. `head_watermark` equals `cursor_start`, `tail_watermark` equals `cursor_end`, and `dropped_event_count` must remain zero. The first batch in a `stream_epoch` starts at cursor zero with no previous batch. Every later batch links `previous_batch_id` to the immediately preceding batch and starts at that batch's `cursor_end`. A new process or round uses a new epoch.

Schema-valid metadata is still only a claim. The evaluator checks the arithmetic, event sequences, epoch identity, batch linkage, monotonic ordering, drop counter, and watermarks across every captured batch. Missing, inconsistent, reset, or dropped coverage remains unverified and cannot prove that a forbidden event was absent.

## Semantic boundary

Publish current authoritative runtime facts and player-visible feedback facts. Do not publish class names, member names, source paths, absolute paths, host metadata, evaluator names, checkpoint IDs, score data, or private material. Asset binding claims are optional claims; the evaluator independently checks asset bytes and visible correlation before using them.

The `controls` array reports the public normal-player bindings actually active in the candidate. It is not a control API. The evaluator sends those inputs through the public executor.

## Evidence health

Every trusted semantic field includes the schema-required provenance and freshness data. Unavailable facts must be marked unavailable rather than guessed. Runtime logs are auxiliary and cannot replace schema-valid state plus contemporaneous client capture.
