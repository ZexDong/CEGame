# Game Creation Benchmark

This directory contains 45 tasks across 44 games in five engine packages:
Unity (11), Godot (8), Roblox (10), Unreal (8), and Defold (8).
Noir Hard is an alternate task for the same game.

**Early release:** This repository is an early version. End-to-end workflows for some engines and samples are only partially implemented, and some samples are still under active development and maintenance.

Additional game samples for each engine will be released in stages after we verify their licenses and confirm that they comply with applicable open-source policies.

Each engine uses the same outer structure:

```text
<engine>/
  README.md
  LICENSE
  FORMAT.md
  catalog.json
  template/README.md
  samples/<sample_id>/
    README.md
    sample.json
    THIRD_PARTY_NOTICES.md

    input/
    evaluation/
```

`input/` contains the design, tool documentation, assets, starter project, public
interfaces, and self-checks. Their locations are indexed by `sample.json.input`.
Give the generation model an independent copy of `input/` only.
`evaluation/` contains evaluator source, fixed rules, coverage mappings, D6
dependencies, and the output schema and template.
Each engine's `template/` contains empty placeholder files; its root README
explains how to fill them.

See each engine README for candidate evaluation and review commands.
The D1-D6 maxima are 10/30/20/20/10/10. A complete total requires evidence for all
six dimensions.

The distribution contains input and evaluation materials. The unexecuted
`evaluation/output-template/score.json` has null dimension scores and a null
total. Write new logs, scores, screenshot receipts, and model responses to a new
directory outside this distribution.

Assets are organized and adapted for each benchmark task. Sources, modifications,
and applicable licenses are documented in each sample's `THIRD_PARTY_NOTICES.md`
and bundled license files.
