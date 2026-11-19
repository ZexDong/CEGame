# Unreal Release

## Scope and structure

8 tasks include input, evaluator source, required rules, and visual references.
All engines share README, LICENSE, FORMAT, catalog, template, and samples.
The template contains empty placeholder files with instructions in its root README.

sample.json.input indexes the tools, assets, starter project, public interfaces, and self-checks for each task.
Supply an independent input copy during generation; access evaluation during assessment.

## Requirements

Windows interactive desktop, PowerShell 7, Python 3.12.13, and matching Visual Studio C++ tools and Windows SDK. See sample.json for each task engine version.

Run from any sample directory:

```text
python -m pip install -r evaluation/requirements.txt
python -B evaluation/evaluate.py --help
python -B evaluation/validate_score.py --score evaluation/output-template/score.json
```

output-template is unexecuted with null scores.

## Candidate evaluation

Run from the sample directory. Write results to a new directory outside the sample and candidate. Short output paths are recommended on Windows.

```text
python -B evaluation/evaluate.py --project "<returned-input-or-project-or-uproject>" --output "<new-output>" --engine "<engine-root>"
python -B evaluation/validate_score.py --score "<result>/score.json" --check-evidence
```

## Native steps and visual protocol

--phase stage reconstructs dependencies and an isolated project without launching the game; exit code 3 (incomplete) and null scores are expected. After collect, complete actual visual/semantic reviews using evaluation/d6 and src/native/scripts, then run --phase finalize in the same result directory with --review or --d6 as needed. Some collectors require independent precondition mappings through --adapter; unknown source layouts are evaluator faults. src/native/tests contains native gameplay tests for the reconstructed workspace. evaluation/tests contains distribution regressions requiring no editor.

## Results and assets

Results use format 2.1 with D1-D6 maxima of 10/30/20/20/10/10.
A complete total requires evidence for all six dimensions. Missing evidence or infrastructure failures leave the total null.
Write results, logs, screenshot receipts, and model responses outside the distribution.

Assets are organized and adapted for each task. Sources, modifications, and applicable licenses are documented in
THIRD_PARTY_NOTICES.md and license files within input.

## Tasks

| sample_id | Title | Package status |
|---|---|---|
| action_roguelike | Rift Hunting | packaged |
| bomber | Bomber Local Duel | packaged |
| bonekest | BoneMaze | packaged |
| captain_2d_platformer | Captain's Key Run | packaged |
| chomp | Chomp: Neon Maze Chase | packaged |
| gems_bond | Gem's Bond | packaged |
| night_sky_engine | Night Sky Duel Lab | packaged |
| roll_ball | RollBall Fixed Maze | packaged |
