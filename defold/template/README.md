# Shared Empty Release Template

Copy `samples/sample_id`, rename it, and fill in sample.json.
Zero-byte files show required locations. Replace them with real materials before
publishing a runnable sample.

```text
samples/sample_id/
  README.md                      # Usage
  sample.json                    # Versions, source commit, commands, input paths
  THIRD_PARTY_NOTICES.md          # Sources and licenses for assets and code

  input/
    INITIAL_AGENT_PROMPT.md
    GDD.md
    CONTENT.json
    tools/TOOL_GUIDE.md
    tools/tool-config.example.json
    assets/ASSET_CATALOG.json
    assets/files/asset.placeholder
    starter-project/project.placeholder
    contracts/GAME_SESSION_SPEC.md
    contracts/SESSION_MODEL.json
    contracts/src/contract.placeholder
    self-check/check.placeholder
  evaluation/
    evaluate.py
    rules.json
    coverage.json
    score.schema.json
    validate_score.py
    requirements.txt
    src/session_driver.placeholder
    src/behavior_checks.placeholder
    d6/prompt.txt
    d6/protocol.json
    d6/reference-image.placeholder
    tests/evaluator_test.placeholder
    output-template/score.json
    output-template/evidence/evidence.placeholder
```

Only input is supplied to the generation model. Tools, assets, the starter
project, and public interfaces must form a complete input package.
Exclude reference solutions and generated candidates. Existing inputs may keep
their engine-native layouts; map their roles through sample.json.input.

Standard entry points:

```text
python -B evaluation/evaluate.py --project "<absolute-candidate>" --output "<new-absolute-output>"
```

Additional engine parameters are allowed. Report missing editors, shared code,
visual reviews, or other required dependencies as setup errors. Paid services
are not called automatically by default.

Output all six dimensions with maxima 10/30/20/20/10/10 and
score/max_score/status/evidence per dimension. Unexecuted templates contain null
scores. Validate with `validate_score.py --score ... --check-evidence`.
Preserve native checkpoint verdicts, evidence, and fault attribution when
adapting formats. Interface or file existence alone does not prove gameplay.
State setup may establish legal preconditions; it must not write the success,
damage, or score outcomes being tested.
Acceptance criteria come from the frozen evaluator rather than editable
candidate rules.

Publish the actual D6 prompt, references, reviewer model/settings, and aggregation
method. Bind external visual reviews to the candidate, screenshots, prompt,
references, and real response records.

Include necessary release files only. Keep credentials, personal machine paths,
private services, reference solutions, generated candidates, historical runs and
scores, and caches outside the package.
Document asset sources, modifications, and licenses in THIRD_PARTY_NOTICES.md.
All template instructions are in this README; the other empty files are location
placeholders. New results use schema_version 2.1. A complete total requires
evidence for all six dimensions.
