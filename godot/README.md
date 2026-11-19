# Godot

Eight tasks share input/, evaluation/, and sample.json. Supply input/ only during
generation. sample.json.input indexes the design, tools, assets, starter project,
and read-only state interface.

Requirements: Python 3.10+ and Godot 4.x; see sample.json for the task version.
Set GODOT_EXE or pass --godot to select the console executable.
Evaluation runs in an isolated project copy.

Run from a sample directory:

```text
python -B evaluation/evaluate.py --project "<absolute-project>" --output "<new-absolute-output>" --godot "<godot-executable>"
python -B evaluation/evaluate.py --phase finalize --output "<same-output>" --review "<completed-review.json>"
python -B evaluation/validate_score.py --score "<same-output>/score.json" --check-evidence
```

Exit codes: 3 awaits review, 2 indicates an environment or package error, and 0
indicates completion of all six dimensions.
The collection directory must be outside the distribution and submitted project.
Use --trajectory to select a trajectory. --interactive-seconds 120 collects
normal manual play; --timeout must exceed the collection duration.
Automatic trajectories collect public-input evidence. Reviewers verify complete
gameplay, boundaries, terminal states, and restart requirements against evidence.
--headless is diagnostic and does not produce D6 image evidence.

The evaluator sends Godot input events and reads the public dashboard's capture()
snapshots. It does not write game state through that interface.
Each trajectory starts independently; reopen creates a new process.
D1 uses current import, startup, log, and interface observations.
D2-D5 require review against the requirement lists in rules.json.
D6 reviews actual screenshots against the public design and assets using the
fixed prompt; see evaluation/d6/protocol.json for its comparison scope.

Collection creates review-template.json in the result directory. Fill in reviewer
and each requirement's verdict, reason, and evidence. Evidence paths are relative
to the result directory and may include # locators.
Requirement verdicts are pass, fail, or inconclusive. The aggregate checkpoint
verdict is pass, fail, partial, or inconclusive.
References must point to trajectories and screenshots sealed by this collection;
D6 requires PNG evidence. Pass the completed review using --review.
The evaluator verifies collection hashes, input/evaluator bindings, and coverage
before aggregation. Missing evidence leaves dimensions and the total null.

D1-D6 maxima are 10/30/20/20/10/10. Checkpoints have equal weights within each
dimension; checkpoint credit follows the proportion of passed requirements.
Results follow score.schema.json. output-template/score.json is an unexecuted
null-valued structure. See THIRD_PARTY_NOTICES.md and bundled input licenses.

| sample_id | Title |
|---|---|
| CervantesTactics | Cervantes Tactics - Chapter 1 |
| FourShot | Four Shot - Five Stage Challenge |
| MataroDrive | Motaro Drive - Procedural Reconstruction |
| OpenRPG | Open RPG - Forest Reconstruction |
| OpenRTS | Open RTS - Economy Production |
| RougelikeTD | Roguelike TD - Twelve Wave |
| SpaceInvaders | Space Invaders - First Level |
| TowerDefense | Ape Tower Defense - Grassland |
