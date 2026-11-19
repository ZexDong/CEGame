# Third-Person Island Delivery

Public Input revision: `v2-pilot-20260828`  
GDD revision: `v2-dashboard-migration-20260828`  
Benchmark ID: `defold.third_person_delivery.v2`

> This revision preserves the established gameplay, quantities, timing, visual, and outcome
> requirements. Section 12 defines their mapping to the shared read-only Dashboard. Private
> evaluation journeys and implementation answers are not public requirements.

## 1. One-sentence task

Control a third-person character in a real three-dimensional island scene, find mission cargo, and
return it to the delivery zone. Deliver everything before the shift ends and reach a clear result.
The complete loop is defined by `Main-loop-01` through `Main-loop-04`, `Results-01`, and `Results-02`.

## 2. Scope

### 2.1 Required in this task

| Requirement | Summary |
|---|---|
| Main-loop-01 | Enter one delivery shift from a mission briefing |
| Main-loop-02, Main-loop-03 | Third-person 3D movement and a following camera |
| Main-loop-04 | Collect, carry, and deliver mission cargo |
| Rules-01, Rules-02, Rules-03 | Scene collision, exclusive cargo states, and the shift timer |
| Results-01, Results-02 | Complete success and failure flows |
| Interface-01, Interface-02, Interface-03 | HUD, pause, and result feedback |
| Visual-01 | A readable third-person 3D island presentation |
| Restart-save-01, Restart-save-02 | In-session restart and close/reopen behavior |

### 2.2 Out of scope

| Related requirement | Excluded content |
|---|---|
| Main-loop-01 through Main-loop-04 | Multiple levels, open world, combat, enemies, vehicles, and story quests |
| Main-loop-02 | Gamepad and touch virtual-stick input |
| Main-loop-03 | Player-controlled camera rotation or zoom |
| None | Reproducing every original cargo item, prop, asset, or shadow-quality setting |

## 3. Starting point

The supplied workspace is a starter project, not a finished game. It contains a minimal Defold
project that launches, shared build and read-only observation support, and this GDD's visual
references. These starting facts do not claim that target gameplay already exists.

| Item | Starting state | Related requirements |
|---|---|---|
| Scene or entry | Minimal launch entry; no delivery level | Main-loop-01 |
| Player or main objects | References/basic resources are not assembled into target gameplay | Main-loop-02 through Main-loop-04, Visual-01 |
| Initial resources and values | No completed shift, cargo progress, or countdown | Main-loop-01, Rules-03 |
| Existing UI | No target briefing, HUD, pause, or result UI | Interface-01 through Interface-03 |
| Existing infrastructure | Shared build, launch, and read-only observation support only | Starting fact, not gameplay |
| Work still required | Every game-specific target in Section 6.2 | All Section 6.2 IDs |

## 4. Player goal and complete flow

### 4.1 Goal

Before time expires, deliver all mission cargo to the delivery zone. Navigate around environmental
obstacles and use the HUD to decide whether to keep searching or return. See `Main-loop-02` through
`Main-loop-04`, `Rules-01`, `Rules-03`, `Results-01`, and `Results-02`.

### 4.2 Complete flow

```text
Enter the game
→ [Main-loop-01] Read the mission briefing and start a shift
→ [Main-loop-02, Main-loop-03] Search the third-person 3D scene
→ [Main-loop-04, Rules-02] Touch cargo, see it carried, and return to the delivery zone
→ [Rules-03, Interface-01] Use progress and remaining shift time to search again or return
→ [Results-01 or Results-02] Reach success or failure
→ [Interface-03, Restart-save-01] Start a new shift or exit
```

### 4.3 Core loop

```text
[Main-loop-02, Main-loop-03] Move through and observe the 3D area
→ [Main-loop-04, Rules-02] Pick up undelivered mission cargo
→ [Interface-01] Read carried count, delivered count, and time
→ [Main-loop-04] Return to the delivery zone and unload
→ Decide whether to depart again or finish the shift
```

## 5. Player controls

| Requirement | Player action | Context | Response summary |
|---|---|---|---|
| Main-loop-01 | Click or confirm Start | Mission briefing | Enter a new shift |
| Main-loop-02 | Use movement input | Active shift | Move and turn on the ground |
| Main-loop-04 | Approach cargo or enter the delivery zone | Active shift | Pick up or deliver automatically |
| Interface-02 | Toggle pause | Playing or paused | Pause or resume |
| Interface-02, Restart-save-01 | Choose a pause/result button | Matching overlay visible | Resume, restart, or exit |

## 6. Numbered requirements: the sole acceptance basis

### 6.1 Granularity

Each row defines one independently judgeable player outcome. Exact quantities, timing, inputs, and
result text are defined only here.

### 6.2 Game-specific requirements

| Requirement | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback | Failure, repetition, restart, or other boundary |
|---|---|---|---|---|---|---|
| Main-loop-01 | The application has launched | Select ` Start the shift ` (START SHIFT) on the briefing | Enter a real 3D island; place the character at spawn; create exactly `3` uncollected cargo items; set delivered and carried counts to `0`; start a `90`-second shift | Launch must not immediately show success/failure; a 2D top-down view cannot substitute for a 3D scene | The briefing states "collect and deliver 3 cargo" and a "90 second shift"; after entry, the character, cargo, delivery zone, and an environment with perspective and height are visible | Every new shift restores the same task size and initial state |
| Main-loop-02 | The shift is playing | Hold or release arrow keys or `WASD` | Move continuously across the horizontal plane of the 3D ground; face the actual movement direction while moving; stop after release | No grid teleportation, leaving the walkable area, or passing through solid obstacles | Position, facing, and walk/run presentation change continuously with input | Orthogonal keys may produce reasonable diagonal motion; opposite directions together must not create uncontrolled motion |
| Main-loop-03 | The shift is playing and the character moves | No extra action | A third-person elevated oblique camera follows the character and keeps the character and nearby routes visible across the walkable area | The camera cannot remain far away so the character leaves the frame, become first-person, or become a purely overhead 2D view | Perspective, occlusion, height differences, and smooth camera translation are clear | Pausing holds the current view; restart restores the initial following view |
| Main-loop-04 | The shift is playing and the player touches uncollected cargo or enters the delivery zone while carrying | Movement only | Contact automatically picks up cargo and changes it to carried; entering the delivery zone automatically delivers carried cargo one by one and increases total delivered | No extra interaction key; delivered count cannot increase outside the zone; one cargo item cannot count twice | Picked-up cargo leaves its original location and appears at the character's carrying position; delivered cargo leaves the character and appears in the zone; HUD updates in sync | The player may carry multiple items; delivered cargo remains delivered after leaving the zone |
| Rules-01 | The shift is playing | Move toward trees, fences, crate stacks, rocks, or the area boundary | At least three visually distinct classes of solid environment obstacle stop the player and together create routes to navigate around | The character cannot pass through obstacles; obstacles cannot seal spawn, any cargo item, or the delivery zone | Collision stops the character outside the obstacle while an alternate nearby route remains visible | Every reachable position retains a route back to the delivery zone |
| Rules-02 | Cargo is world, carried, or delivered | Pick up, deliver, pause, or resume | Each cargo item belongs to exactly one of those three states at any time; their counts always sum to `3` | Cargo cannot duplicate, disappear, or be counted repeatedly | Scene position, carried appearance, and HUD numbers agree | Re-entering a cargo's old location or the delivery zone cannot create false progress |
| Rules-03 | A new shift has begun and no result exists | Time passes, pause, or resume | While playing, count down from `90` to `0` using real elapsed time; pause freezes time; resume continues it | Frame rate cannot alter shift duration; pause and result states cannot continue reducing time | HUD shows whole seconds remaining | If the final delivery and zero time occur in the same update, success wins when that delivery has already become true |
| Results-01 | Delivered count is below the target and remaining time is above `0` | The third cargo item becomes delivered | Immediately enter success and stop movement, pickup, delivery, and timing; show ` Transportation completed ` (DELIVERY COMPLETE) | No success below `3` deliveries; progress cannot change after success | Result UI shows a success title, `3/3` delivered, and remaining time | Provide ` Restart ` (RESTART) and ` Exit the game ` (EXIT) |
| Results-02 | Delivered count is below `3` | Remaining time reaches `0` | Immediately enter failure and stop movement, pickup, delivery, and timing; show ` End of shift ` (SHIFT ENDED) | No failure after the goal is complete; progress cannot change after failure | Result UI shows a failure title and final delivered progress | Provide ` Restart ` (RESTART) and ` Exit the game ` (EXIT) |
| Interface-01 | Playing or paused | Cargo state or time changes | Continuously show ` Carrying ` (CARRIED), ` Delivered ` (DELIVERED), and ` Remaining time ` (TIME); values match real state in the same visible update | Do not hide task total or show stale values that contradict real state | The player can choose search versus return without leaving the game view | HUD location, color, and component type are free, but it cannot cover the character or main routes |
| Interface-02 | Playing or paused | Press `Esc`, or choose ` Continue ` (RESUME), ` Restart ` (RESTART), or ` Exit the game ` (EXIT) on pause UI | Esc opens pause from play; Esc or Resume returns to play; Restart and Exit perform their labels | No movement, pickup, delivery, or time loss while paused; visible buttons must accept their clicks | Pause UI shows ` Paused ` (PAUSED), ` Continue ` (RESUME), ` Restart ` (RESTART), and ` Exit the game ` (EXIT) | Rapid repeated Esc presses leave the final state matching press parity and never stack pause layers |
| Interface-03 | Success or failure exists | View the result or choose a result button | Result title, final delivery progress, remaining time, and both next choices are visible and operable together | The game cannot still look like active play or accept gameplay input under the result layer | Success and failure have clearly distinguishable titles or visual states | Result remains until Restart or Exit is chosen |
| Visual-01 | Any required screen is visible in a `1136 × 640` client area | View briefing, island, carrying, delivery, pause, or result | Present one coherent bright low-poly 3D island: a recognizable third-person character is the main subject; cargo and delivery zone have distinct silhouettes; at least three of trees, fences, rocks, crate stacks, or equivalents create a layered navigable environment; perspective, occlusion, height, lighting, and the following camera together prove it is a walkable 3D world | A 2D overhead view, flat debug grid, solid-color boxes, or text labels cannot replace final character, cargo, delivery zone, or major environment; HUD and overlays cannot hide the character or main routes | Without debug text, the player can distinguish the character, world cargo, carried cargo, delivered cargo, delivery zone, obstacles, and walkable ground | Pixel-identical reference reproduction and a unique model set are not required; an equivalent complete 3D composition is valid, and the current world remains legible beneath pause/result overlays |
| Restart-save-01 | Playing, paused, won, or lost | Choose `RESTART` | Start a new shift and restore character, camera, three cargo items, delivery progress, carried state, and timer to `Main-loop-01` | Do not retain previous cargo state, result layer, character position, or remaining time | Show the briefing again or a visibly reset shift | Two consecutive restarts produce the same initial state |
| Restart-save-02 | Any in-run state | Close and relaunch the application | Return to the briefing with no previous playing, won, lost, or cargo progress | Do not resume the previous position, cargo state, or timer | A fresh launch matches the first launch | This task saves no in-run progress |

### 6.3 Shared numbered requirements

These shared quality requirements define only cross-game playability. All game-specific 3D movement,
camera, delivery, timing, outcome, reset, UI, and visual targets remain in Section 6.2.

| Requirement | Formal requirement |
|---|---|
| Quality-01 | The project starts, runs, exits, and starts again through the published normal procedure. |
| Quality-02 | The main flow uses normal player input and does not depend on answer buttons, cheat entries, or direct result shortcuts. |
| Quality-03 | Critical entries, text, and controls are visible, discoverable, readable, and operable. |
| Quality-04 | Player actions have perceivable feedback synchronized with the real game state. |
| Quality-05 | No severe error blocks the main flow. |
| Quality-06 | Repeated runs from the same initial conditions are substantially stable. |

## 7. Success, failure, and stages

### 7.1 Success

| Requirements | Steps before success | Condition | State after success | Feedback |
|---|---|---|---|---|
| Main-loop-04, Rules-02, Results-01 | Search, carry, and return | Deliver all cargo within the shift | Gameplay and time stop | Clear completion result and next choices |

### 7.2 Failure

| Requirements | Condition | State after failure | Feedback | Retry |
|---|---|---|---|---|
| Rules-03, Results-02, Restart-save-01 | Time expires before completion | Gameplay and time stop | Clear failure result and final progress | Start a new shift from the result |

### 7.3 Stages

| Stage | Requirements | Summary | Must not appear early |
|---|---|---|---|
| Departure | Main-loop-01, Main-loop-02, Main-loop-03 | Understand the goal and enter the 3D area | Results-01, Results-02 |
| Delivery | Main-loop-04, Rules-01, Rules-02, Interface-01 | Alternate between searching and returning | Results-01 |
| Result | Rules-03, Results-01, Results-02, Interface-03 | Enter exactly one outcome from completion and time | None |

## 8. UI and feedback summary

| Requirements | Information or state | When shown or updated | What the player distinguishes |
|---|---|---|---|
| Main-loop-01 | Mission information | Opening entry | Goal and shift limit |
| Interface-01 | Carried, delivered, and time | Continuously during the shift | Search, return, or time pressure |
| Interface-02 | Pause and choices | While paused | Resume, restart, or exit |
| Interface-03, Results-01, Results-02 | Final result | When an outcome occurs | Success/failure and the next action |
| Visual-01 | 3D character, island, cargo, zone, and obstacle hierarchy | Every player-facing view | World, routes, and cargo states |

## 9. Restart, close/reopen, and save summary

| Scenario | Requirement | Reset | Retain | Final state |
|---|---|---|---|---|
| Restart current game | Restart-save-01 | Character, camera, cargo, progress, result, and time | No in-run progress | New-shift initial state |
| Close and reopen | Restart-save-02 | All previous in-run state | Nothing | Mission briefing |

## 10. Legacy functionality

This task is an independent reconstruction, so no legacy project behavior must be preserved.

## 11. Assets and content summary

| Requirement | Asset or content | Required | Use | Equivalent allowed |
|---|---|---:|---|---:|
| Visual-01 | Complete 3D character, island, cargo, delivery zone, and three obstacle classes | Yes | Build the player-visible world required by Section 6.2 | Yes, equivalent 3D models and layout |
| Visual-01 (reference only) | [original_arena.png](reference_images/original_arena.png) | No | Island, third-person composition, and environment hierarchy | Yes |
| Visual-01 (reference only) | [original_carrying_gold.png](reference_images/original_carrying_gold.png) | No | Recognition of cargo attached near the character | Yes |
| Visual-01 (reference only) | [original_delivery_zone.png](reference_images/original_delivery_zone.png) | No | Delivery-zone and delivered-cargo reference | Yes |

The images explain the visible role coverage and legibility required by `Visual-01`; they do not
require copying specific source assets, colors, or pixel layout.

## 12. Dashboard mapping and implementation boundary

This section only maps the player-visible facts already required by Section 6.2 into the shared
read-only Dashboard. It adds no gameplay, values, level layout, or scoring requirement. Exact field
spelling comes from `naming-tables.json`; transport format comes from `DASHBOARD_SPEC.md`.

### 12.1 Phase mapping

| Game state | Dashboard `phase` |
|---|---|
| Mission briefing | `menu` |
| Active shift | `playing` |
| Pause overlay | `paused` |
| Delivery complete | `won` |
| Shift ended | `lost` |
| Starter has no target gameplay | `not_ready` |

### 12.2 Numeric slots

| Slot | Meaning |
|---|---|
| `time_remaining` | Real seconds remaining; `0` at the briefing |
| `carried_count` | Cargo currently in `carried` state |
| `delivered_count` | Cargo currently in `delivered` state |
| `cargo_total` | Total mission cargo, fixed at `3` by Section 6.2 |

### 12.3 3D entities and coordinates

Entities use continuous 3D `position: [x, y, z]` and full `size: [width, height, depth]`; y points
up and units are Defold world units. Every entity uses one nonempty ID for the entire process and
reports its real `kind`, `state`, and `visible` value.

| Kind | Allowed states | Mapped object |
|---|---|---|
| `player` | `idle`, `moving` | Player's real position and volume |
| `cargo` | `world`, `carried`, `delivered` | Each cargo item's exclusive current state, position, and volume |
| `delivery_zone` | `active` | Real delivery-region position and volume |
| `obstacle` | `tree`, `rock`, `fence`, `crate_stack` | Environment obstacles used for collision and navigation |

Dashboard geometry for cargo, player, zone, and obstacles comes from the same authoritative state
used by rendering, pickup, delivery, and collision. Do not create a separate observation-only map.
Equivalent implementations may choose stable IDs and exact compliant island layouts.

### 12.4 Clickable targets and normal input

Briefing, pause, and result UI report only currently visible targets whose rectangles match real GUI
hit areas: `start_button`, `resume_button`, `restart_button`, and `exit_button`. Rectangles use
`[left, bottom, width, height]` in the `1136 × 640` client area with a bottom-left origin. Hidden
controls are not current targets, and `interactable` matches whether a left click works now.

Normal gameplay still uses Section 5 keyboard movement, Esc, and GUI left click. Dashboard can only
observe; it cannot receive input, move the player, pick up or deliver cargo, change time, restart,
or force an outcome.

### 12.5 Implementation and evaluation boundary

- Section 6.2 is the sole source of game-specific targets; Section 6.3 only supplies shared
  cross-game playability requirements.
- Read-only runtime observation neither prescribes internal architecture nor changes results.
- Class names, object hierarchy, algorithms, data structures, component composition, scene
  organization, and reset implementation are not GDD targets.
- Public tool and asset documents define engine, build, input, observation, and import facts.
- Any equivalent implementation, 3D models, and UI layout are allowed when Section 6.2 outcomes and
  boundaries remain exact.

## 13. Pre-submission checklist

- [ ] Every acceptance-relevant "must" and "must not" appears in a numbered Section 6 requirement.
- [ ] Scope, core loop, success, failure, UI, visual, restart, and asset summaries reference those IDs.
- [ ] All exact quantities, timing, result text, ordering, and formats are preserved.
- [ ] The main flow uses normal player input and forms a complete success/failure/restart lifecycle.
- [ ] The game is a legible third-person 3D world, not a flat diagram or debug presentation.
- [ ] Dashboard is truthful and read-only and uses the public mapping in Section 12.
- [ ] No Gold implementation, private evaluation journey, or unique internal architecture is exposed.
