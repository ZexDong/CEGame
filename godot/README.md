# Godot

Eight tasks share input/, evaluation/, and sample.json. Supply input/ only during
generation. sample.json.input indexes the design, tools, assets, starter project,
and read-only state interface.

Use Python and a Godot editor compatible with the starter project.
Set GODOT_EXE or pass --godot to select the console executable.
Evaluation runs in an isolated project copy.

Run from a sample directory:

```text
python -B evaluation/evaluate.py --project "<absolute-project>" --output "<new-absolute-output>" --godot "<godot-executable>"
python -B evaluation/evaluate.py --phase finalize --output "<same-output>"
python -B evaluation/validate_score.py --score "<same-output>/score.json" --check-evidence
```

Exit codes: 3 indicates incomplete evidence, 2 indicates an environment or package error, and 0
indicates completion of all six dimensions.
The collection directory must be outside the distribution and submitted project.
Use --trajectory to select a trajectory. Automatic trajectories collect public-input
evidence and dashboard snapshots. --headless is diagnostic and does not produce D6
image evidence.

The evaluator sends Godot input events and reads the public dashboard's capture()
snapshots. It does not write game state through that interface.
Each trajectory starts independently; reopen creates a new process.
D1 uses current import, startup, log, and interface observations.
D2-D5 count the authored conditions resolved during collection. Unresolved checks
keep a null score. `--phase finalize` verifies and reuses the sealed collection.

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
