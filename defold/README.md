# Defold Release

Eight tasks provide construction input, evaluator source, rules, requirement
coverage, visual review protocols and the shared D1-D6 result format.
`sample.json.input` indexes tools, assets, starter projects and public interfaces.
Give the construction model an independent copy of `input/` only.

## Requirements

Dynamic evaluation uses an interactive macOS arm64 desktop, Python 3.11+,
Defold 1.13.0 installed at `/Applications/Defold.app`, bundled JDK 25+36, and
Xcode Command Line Tools. The recorded Defold revision is
`f735c12192bf95684e6ae1ae27c400b8170fc6d8`.
The six checkpoint-runtime tasks additionally use Tesseract 5.5.2 at
`/opt/homebrew/bin/tesseract` with `eng` and `chi_sim`.
Grant the executing terminal Accessibility, Input Monitoring and Screen Recording
permissions. Run one dynamic evaluation per desktop.

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
state, obtain three independent gpt-4o judgments per state, and retain each raw
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
registered states. A complete final score is the sum of D1-D6, with fixed maxima
10/30/20/20/10/10. Missing evidence leaves the final score null.

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
