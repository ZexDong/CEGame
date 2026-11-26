# Unity Release

## Scope and structure

11 tasks include input, evaluator source, required rules, and visual references.
All engines share README, LICENSE, FORMAT, catalog, template, and samples.
The template contains empty placeholder files with instructions in its root README.

sample.json.input indexes the tools, assets, starter project, public interfaces, and self-checks for each task.
Supply an independent input copy during generation; access evaluation during assessment.

## Requirements

Install the Unity editor required by the starter project, Unity CLI, and Python.

Run from any sample directory:

```text
python -m pip install -r evaluation/requirements.txt
python -B evaluation/evaluate.py --help
python -B evaluation/validate_score.py --score evaluation/output-template/score.json
```

output-template is unexecuted with null scores.

## Candidate evaluation

Run from the sample directory. Write results to a new directory outside the sample and candidate.

```text
python -B evaluation/evaluate.py --project "<candidate>" --output "<new-output>" --editor "<Unity.exe>" --unity-cli "<pinned-cli.exe>"
python -B evaluation/validate_score.py --score "<result>/score.json" --check-evidence
```

## Native steps and visual protocol

Each evaluator includes its fixed D6 prompt, references, and settings. Python backends support --review-d6 for automated D6 visual evaluation. Supply credentials through environment variables. See evaluation/src/backend for variables, prompts, and native visual steps.

## Results and assets

Results use format 2.1 with D1-D6 maxima of 10/30/20/20/10/10.
A complete total requires evidence for all six dimensions. Missing evidence or infrastructure failures leave the total null.
Write results, logs, screenshot receipts, and model responses outside the distribution.

Assets are organized and adapted for each task. Sources, modifications, and applicable licenses are documented in
THIRD_PARTY_NOTICES.md and license files within input.

## Tasks

| sample_id | Title | Package status |
|---|---|---|
| unity_2d_arrow_escape | Arrow Escape | packaged |
| unity_2d_brick_n_balls_challenge | Brick'n'Balls | packaged |
| unity_2d_driftfolk_chronicle_challenge | Driftfolk Stormbound | packaged |
| unity_2d_fungus_cave_challenge | Fungus Cave | packaged |
| unity_2d_glitch_garden_challenge | Glitch Garden | packaged |
| unity_2d_noir_roombreak_challenge | Noir Roombreak | packaged |
| unity_2d_noir_roombreak_docv2_hard | Noir Roombreak Hard (alternate task) | packaged |
| unity_2d_there_are_signs_circuit | There Are Signs | packaged |
| unity_3d_dungeon_duel | Dungeon Duel | packaged |
| unity_3d_polyrace_challenge | PolyRace | packaged |
| unity_3d_undercooked_challenge | Undercooked | packaged |
