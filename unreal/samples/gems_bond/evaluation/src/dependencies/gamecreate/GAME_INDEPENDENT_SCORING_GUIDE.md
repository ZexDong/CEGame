# Game Scoring Guide

Task-specific checks follow the game design document (GDD). All engines use the
same six dimensions and score maxima.

| Dimension | Name | Maximum | Question |
|---|---|---:|---|
| D1 | Engineering Validity & Engine Integration | 10 | Does the project import, compile, and start? |
| D2 | Specification Fulfillment & Content Completeness | 30 | Is the required content present and usable during play? |
| D3 | Gameplay Correctness & System Behavior | 20 | Do rules, values, timing, and boundaries behave correctly? |
| D4 | End-to-End Flow & Lifecycle Integrity | 20 | Can players complete a game and restart or reopen correctly? |
| D5 | Interface Functionality & Player Feedback | 10 | Can players find, operate, and understand the interface? |
| D6 | Visual Assembly & Presentation Fidelity | 10 | How complete and coherent is the rendered presentation? |

## Assessment stages

1. Engineering checks assess D1 (10 points). Inspect the project structure,
   references, configuration, parsing, import, compilation, and build. A startup
   smoke test may run without player input.
2. Dynamic evaluation trajectories assess D2-D5 (80 points). Start through the
   public entry point, send normal player inputs, and observe actual results.
3. Visual review assesses D6 (10 points), using the fixed sample protocol.

A file or script's existence does not earn D2 credit. D2 requires content to
appear and support basic use at runtime. D3 assesses detailed correctness.
D5 checks actual visibility, readability, interaction, and feedback during play.
Visual similarity and VLM judgments do not determine D1-D5.

Engine independence means consistent questions and scoring semantics. Engine
commands, node types, classes, and internal algorithms may differ.
Do not compare candidate source code to reference source for similarity.

## Dynamic evidence

Use normal keyboard, mouse, or controller input. Read state through the public
read-only interface and cross-check it against runtime feedback.
Do not directly invoke internal attack, currency, win, loss, or reset functions.
Legal precondition setup remains separate from the outcome being tested.
Use independent trajectories or clean processes when success, failure, or
persistence tests could contaminate one another.

| Operation | Meaning |
|---|---|
| Start | Launch through the normal public entry point |
| Click | Click a player-visible button or object |
| Press / Hold / Release | Send normal player input |
| Drag | Press, move to the target, and release |
| Wait Until | Wait for an observable state with a bounded timeout |
| Read State | Read health, resources, counts, position, phase, and outcomes |
| Restart | Use the game's normal restart entry point |
| Reopen | End the old process and start a new process |

## Coverage and duplicate checks

Different dimensions may observe the same feature if they ask different
questions. For an upgrade system:

| Dimension | Check |
|---|---|
| D2 | The upgrade entry and screen appear and a basic upgrade is usable |
| D3 | Costs, stat changes, limits, and rejection rules are correct |
| D4 | The upgrade fits into a complete normal playthrough |
| D5 | The button, price, level, and result are visible and understandable |
| D6 | The upgrade screen's assets, layout, proportions, and finish are coherent |

Count repeated wording in a GDD once. Reusing a trajectory as evidence does not
create extra credit. Two identically worded checks are duplicates.
Initial-state correctness belongs to D3; restoring it after restart belongs to
D4. One defect may affect multiple dimensions only through distinct consequences.

## Scoring and faults

The fixed sample rules define meaningful checkpoints and weights.
For equally weighted checkpoints:

```text
dimension score = dimension maximum * passed checkpoints / checkpoint count
```

Detailed requirement-level credit, when supported, follows the sample rules.
Award no extra points for individual clicks, waits, captures, log writes, or
repetitions. Candidate-caused unreachable behavior is recorded as failure for
the affected check; it does not invalidate unrelated observations.
Infrastructure or evaluator faults leave affected scores unavailable until
resolved. They must not be converted into candidate zero scores.

Each evaluation trajectory has legal preconditions, ordered player actions,
observations, and an end condition. Include complete success and natural failure
paths, invalid actions, restart, retry, menu return, and reopen when required by
the GDD. Restart must remove temporary objects, timers, and stale terminal UI.
Reopen must end the old process and verify the documented persistence boundary.

Distinguish logical evaluation steps, low-level runner actions, trajectory count,
and scoring checkpoint count. Polling, screenshots, or repeated evidence do not
increase scoring coverage. Use the task's budgets and watchdog settings; a
watchdog failure is not evidence of an incorrect gameplay outcome.

## Visual review

Use the actual prompt, rubric, references, settings, and aggregation method
included with the sample. Original-game screenshots and public design/asset
references are different comparison scopes; follow the stated protocol.
Bind each response to the candidate screenshot and fixed reference/prompt hashes.
Review visible evidence only. Do not infer hidden gameplay from screenshots.

The standard five-part rubric allocates 0-2 points to each:

1. Scene completeness and asset assembly.
2. Composition and layout.
3. Scale, hierarchy, and clarity.
4. Style and color consistency.
5. Overall polish.

Standard anchors: 2.0 comparable or better with no obvious defect; 1.5 good with
minor defects; 1.0 substantially complete with visible gaps; 0.5 severely
incomplete or unclear; 0.0 missing, broken, or not meaningfully comparable.
Some samples provide a task-specific fixed rubric; use that rubric as published.

Where the sample specifies three rounds, use the same reviewer model and prompt
for every fixed visual state in all three rounds. Average equally weighted states
within each round, then average the three round scores. Keep all states and
rounds. Round the final D6 value as specified by the sample.

## Output

Use the distributed score schema and validator. The D1-D5 subtotal has maximum
90; the overall score is D1+D2+D3+D4+D5+D6 with maximum 100.
Unavailable D1-D5 values leave both subtotal and overall null. An unavailable D6
leaves overall null while a complete D1-D5 subtotal may remain available.
Every verdict must reference current-run evidence. Retain fault attribution and
candidate, evaluator, input, prompt, and evidence bindings in generated outputs.

Generation token usage and agent action counts are optional orchestration
statistics. They never alter D1-D6, solved status, or checkpoint verdicts.
Keep generation-only accounting separate from evaluator and visual-review costs.
Write generated results and evidence outside the distributed package.
