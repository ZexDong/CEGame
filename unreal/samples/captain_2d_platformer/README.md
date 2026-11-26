# Captain's Key Run

Prepare the independent generation input with `python -B input/self-check/check_package.py --export-input <new-directory>` to include the shared interface catalog.

## File locations

- prompt: `input/INITIAL_AGENT_PROMPT.md`
- design: `input/GDD.md`
- tools: `input/tools/TOOL_GUIDE.md`
- assets: `input/assets/ASSET_CATALOG.json`
- starter_project: `input/starter-project`
- contracts: `input/contracts`
- self_check: `input/self-check/check_package.py`

`sample.json` indexes input locations, versions, and commands.
`evaluation/` contains scoring rules, coverage mappings, and the result schema. `output-template/score.json` is unexecuted with all scores null.

## Usage

See the engine root README for candidate execution commands, engine arguments, and D6 steps.
Write results to a new directory outside the sample and candidate, then run:

```text
python -B evaluation/validate_score.py --score "<result>/score.json" --check-evidence
```

Assets are organized and adapted for this benchmark task. See `THIRD_PARTY_NOTICES.md` and the license files in input for sources, modifications, and applicable licenses.
