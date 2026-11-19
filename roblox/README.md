# Roblox Release

## Scope and structure

10 tasks include input, evaluator source, required rules, and visual references.
All engines share README, LICENSE, FORMAT, catalog, template, and samples.
The template contains empty placeholder files with instructions in its root README.

sample.json.input indexes the tools, assets, starter project, public interfaces, and self-checks for each task.
Supply an independent input copy during generation; access evaluation during assessment.

## Requirements

Windows interactive desktop; Roblox Studio 0.742.0.7421053; Rojo 7.7.0; Luau 0.734. The task toolchain specifies Python 3.14.2 and Pillow 11.3.0.

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
python -B evaluation/evaluate.py --project "<candidate>" --output "<new-output>" --rojo "<rojo.exe>" --luau-compile "<luau-compile.exe>" --luau "<luau.exe>"
python -B evaluation/validate_score.py --score "<result>/score.json" --check-evidence
```

## Native steps and visual protocol

--prepare-only performs native preparation and static checks without opening Studio or producing a complete total. Supply external D6 with --visual "<visual.json>". See evaluation/d6/protocol.json and evaluation/d6/EVIDENCE_FORMAT.md. Provide four state screenshots and three actual response records from the same candidate, binding candidate, references, prompt, and responses. Pocket Greenhouse and Reactor Relay Protocol support rbxlx and optional --source-zip. See sample.json for other directory/ZIP requirements.

## Results and assets

Results use format 2.1 with D1-D6 maxima of 10/30/20/20/10/10.
A complete total requires evidence for all six dimensions. Missing evidence or infrastructure failures leave the total null.
Write results, logs, screenshot receipts, and model responses outside the distribution.

Assets are organized and adapted for each task. Sources, modifications, and applicable licenses are documented in
THIRD_PARTY_NOTICES.md and license files within input.

## Tasks

| sample_id | Title | Package status |
|---|---|---|
| roblox_coolant_cargo | Coolant Cargo | packaged |
| roblox_deep_relay | Deep Relay | packaged |
| roblox_dockline_dispatch | Dockline Dispatch | packaged |
| roblox_moonlit_greenhouse | Moonlit Greenhouse | packaged |
| roblox_pocket_greenhouse | Pocket Greenhouse | packaged |
| roblox_reactor_relay_protocol | Reactor Relay Protocol | packaged |
| roblox_relay_foundry | Relay Foundry | packaged |
| roblox_skyline_switchyard | Skyline Switchyard | packaged |
| roblox_tidal_lock | Tidal Lock | packaged |
| roblox_tidelock | Tide Lock / Deep Dive Station | packaged |
