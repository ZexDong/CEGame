# Arrow Escape

Supply an independent copy of `input/` during generation; use `evaluation/` during assessment.

## File locations

- prompt: `input/INITIAL_AGENT_PROMPT.md`
- design: `input/GDD.md`
- tools: `input/UNITY_BENCHMARK_TOOL_GUIDE.md`
- assets: `input/Assets`
- starter_project: `input`
- contracts: `input/Packages`
- self_check: `input/Assets`

`sample.json` indexes input locations, versions, and commands.
`evaluation/` contains scoring rules, coverage mappings, and the result schema. `output-template/score.json` is unexecuted with all scores null.

## Usage

See the engine root README for candidate execution commands, engine arguments, and D6 steps.
Write results to a new directory outside the sample and candidate, then run:

```text
python -B evaluation/validate_score.py --score "<result>/score.json" --check-evidence
```

Assets are organized and adapted for this benchmark task. See `THIRD_PARTY_NOTICES.md` and the license files in input for sources, modifications, and applicable licenses.
