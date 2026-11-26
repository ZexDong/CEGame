# Defold Release

Eight tasks provide construction input, evaluator source, rules, requirement
coverage, visual review protocols and the shared D1-D6 result format.
`sample.json.input` indexes tools, assets, starter projects and public interfaces.
Give the construction model an independent copy of `input/` only.

## Requirements

Dynamic evaluation uses an interactive desktop, Python and the native input tools.
Set `DEFOLD_BOB_JAR` and `DEFOLD_JAVA` to the Bob JAR and Java executable, or set
`DEFOLD_PACKAGES` to the installed packages directory. Six tasks also require
Tesseract on PATH (or `TESSERACT_EXE`).
Grant the executing terminal desktop input and screen capture permissions.
Run one dynamic evaluation per desktop.

From any sample directory:

```text
python3 -B -m unittest discover -s evaluation/tests -p "test_*.py"
python3 -B evaluation/validate_score.py --score evaluation/output-template/score.json
```

The empty `template/` files show the shared input/evaluator locations; instructions
are in `template/README.md`.

## Candidate evaluation

From the sample directory, provide the directory containing the candidate's
`game.project`. Use absolute paths and a new result directory outside both the
candidate and this distribution.

```text
python3 -B evaluation/evaluate.py --project "/absolute/candidate" --output "/absolute/new-result"
python3 -B evaluation/validate_score.py --score "/absolute/new-result/score.json" --check-evidence
```

The native evaluator builds an isolated copy, sends ordinary keyboard/mouse input
and reads the game's Dashboard interface. Interface values are checked alongside
input causality, rendered evidence and lifecycle behavior. Repeated observations
of one checkpoint must all pass. A declared functional score cap is allocated
proportionally across positively credited functional checkpoints and remains
visible in the result extensions.

Collection emits resolved D1-D5 observations. It exits 3 while the six-dimension
result is incomplete; infrastructure failures exit 2 and leave affected scores
null. A low observed candidate score is separate from an infrastructure failure.

## Visual review

Each sample's `evaluation/d6/protocol.json` fixes states, available references,
comparison scope, judge model/settings, rubric, anchors and aggregation.
`evaluation/d6/prompt.txt` is the fixed visual prompt.
Use collected PNGs indexed in `evidence/visual-captures.json` and identity/hash
data in `evidence/binding.json`. Register one candidate capture for each named
state, obtain three independent judgments from the registered model per state, and retain each raw
provider response in a result-relative receipt JSON. The protocol lists the
review and response fields. Judge credentials remain outside the distribution.
No model service is called by the functional collector.

Finalize a collection using the resulting review JSON:

```text
python3 -B evaluation/evaluate.py --project "/absolute/candidate" --output "/absolute/new-result" --phase finalize --d6-review "/absolute/visual-review.json"
python3 -B evaluation/validate_score.py --score "/absolute/new-result/score.json" --check-evidence --require-final
```

The visual evaluator rejects changed candidates, references, captures, model
settings, missing states, duplicate request IDs and missing raw response receipts.
Each state's D6 leaf uses the median of three five-item totals; D6 averages the
registered original states. Design-and-asset reviews are supplemental. The total
uses D1-D5 plus the journey-adjusted D6 credit in `extensions.scorecard`.

## Tasks

| sample_id | Title |
|---|---|
| defold_bomb_frog_v3 | Bomb Frog: Twin Chambers |
| defold_mansion_key_escape_v2 | Mist Mansion: Key Escape |
| defold_match3_swipe_v2 | Match 3 Swipe: Three-Chapter Cascade Challenge |
| defold_station_master_v2 | Station Master: Emergency Expansion Shift |
| defold_third_person_delivery_v2 | Third-Person Island Delivery |
| defold_timelooper_v2 | Time Echo: Gem Exit |
| defold_typhoon_balloon_v2 | Typhoon Balloon: Wind Station Campaign |
| defold_urban_climber_v3 | Urban Climber: Two-Roof Relay |

Sources, modifications and applicable licenses are recorded in each sample's
`THIRD_PARTY_NOTICES.md` and `input/legal/` files.
