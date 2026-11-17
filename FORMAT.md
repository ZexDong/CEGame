# Shared Release Format

Each engine package contains README, LICENSE, FORMAT, catalog, check_release,
template, and samples. Each task contains:

```text
sample.json
README.md
THIRD_PARTY_NOTICES.md
input-manifest.json
input/                       # Only input supplied during generation
evaluation/
  evaluate.py                # --preflight; --project ... --output ...
  rules.json                 # Fixed checkpoints, predicates, and weights
  coverage.json              # Design requirements mapped to checkpoints
  score.schema.json
  validate_score.py
  requirements.txt
  src/                       # Evaluator source and required dependencies
  d6/                        # Fixed prompt, protocol, and visual references
  tests/                     # Evaluator test source
  output-template/score.json  # Unexecuted structure; all scores are null
```

`sample.json.input` indexes prompt/design/tools/assets/starter_project/contracts/
self_check. Engine-native input layouts are supported. `input-manifest.json`
records the actual input file set and SHA-256 digests.
Supply an input copy during generation; use evaluation during assessment.

Results use schema version 2.1 and D1-D6 maxima of 10/30/20/20/10/10.
Each dimension includes score/max_score/status/evidence. Checkpoints include
requirement mappings, weights, verdicts, and evidence.
Use null for unexecuted checks, missing evidence, or infrastructure failures.
A complete total requires evidence for all six dimensions.
`validate_score.py` checks the structure, aggregates, and evidence paths.

Evaluators read state through the game's public interfaces and assess actual
inputs, rendered output, and observed behavior. State preparation may establish
legal preconditions only. Acceptance criteria come from the fixed evaluator.
D6 includes the prompt, visual references, settings, and aggregation method used
by that sample. The protocol specifies whether references are original-game
screenshots or the public design and assets.

Keep run records, actual scores, complete reference implementations, generated
candidates, caches, and credentials outside the distribution.
Result directories must be outside both the sample and candidate directories.
Sources, modifications, and applicable licenses belong in each task's
THIRD_PARTY_NOTICES.md and bundled license files.

`python -B check_release.py` checks files, input hashes, Python syntax, and
dependencies without launching a game. See the engine README for prerequisites
and execution commands.
