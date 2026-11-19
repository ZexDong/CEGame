# Time Echo: Gem Exit

Supply an independent copy of `input/` during generation. Run `evaluation/` after construction.

## File locations

- prompt: `input/INITIAL_AGENT_PROMPT.md`
- design: `input/GDD.md`
- tools: `input/DEFOLD_ENGINE_INTERFACE_GUIDE.md`
- assets: `input/assets/`
- starter_project: `input/starter_project/`
- contracts: `input/DASHBOARD_SPEC.md`
- self_check: `input/tools/dashboard_self_check.py`

`sample.json` records the engine, source, input locations and evaluation command.

`evaluation/output-template/score.json` is an unexecuted D1-D6 output structure with null scores.

## Usage

From this sample directory:

```text
python3 -B evaluation/evaluate.py --project "/absolute/candidate" --output "/absolute/new-result"
python3 -B evaluation/validate_score.py --score "/absolute/new-result/score.json" --check-evidence
```

See the engine README for host prerequisites and D6 review/finalization.
Write new results outside the distribution and candidate project.
Sources and applicable licenses are in `THIRD_PARTY_NOTICES.md` and `input/legal/`.
