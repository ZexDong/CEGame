# Undercooked Kitchen Shift — Public Game Design Document

Task ID: `unity.undercooked_kitchen_shift.v2`

Public Input revision: `v2.6-docv2-session-gate-20260912`  
GDD revision: `v2.6-docv2-session-gate-20260912`

The numbered requirements in Section 6 define the complete player-facing game. Section 6.6 enables the published session and delivery contracts by reference. Their detailed rules have one authority: common service behavior in `GAME_SESSION_SPEC.md`, kitchen state semantics in `SESSION_MODEL.json`, technical delivery in `TOOLCHAIN.md`, and file paths in `BENCHMARK_MANIFEST.json`. General playable-game expectations are in `COMMON_BASELINE.md`; its conditional Dashboard item does not apply because this task enables only the session service.

## 1. Complete game and required services

Create a complete single-player 3D kitchen shift in which the player switches between two independent visible chefs, prepares tomato soup through contextual kitchen stations, serves timed orders for score, reaches a clear result, and restarts or reopens into a clean shift.


### Automated acceptance

Deliver the complete playable game and the required session services described in
GAME_SESSION_SPEC.md. Automated acceptance checks will use normal player controls
and these services to access chapters, restore valid saved states, and identify
the actual game objects. The services are mandatory parts of the delivered game.
They must operate the real game with the same content and rules as normal play.

Missing or incorrect required services are incomplete delivery: the service
requirements and any requirements that genuinely depend on the broken capability
cannot receive credit. Unrelated working capabilities are checked independently.
A manually playable game with broken required services is still incomplete.
Compiling or passing basic smoke checks does not establish that the game or its
session services are correct. The supplied contract defines observable behavior;
your internal architecture and implementation remain your choice.

## 2. Scope

In scope: a title/menu entry, one furnished kitchen, exactly two visible independent chefs with one active at a time, player-controlled switching, tomato crate, countertop, chopping board, cooking pot, clean plates, delivery, trash, timed orders, score, pause, result, Restart, and full close/reopen.

Out of scope: more than two chefs, simultaneous multi-input control, online play, additional levels, persistent progression, purchases, advertisements, procedural kitchens, character customization, dish washing, and recipes beyond tomato soup.

## 3. Starting state

The public project supplies original-author kitchen art, a chef model and animation, food and appliance models, materials, audio, Input Actions, and an empty saved starter Scene. The target gameplay is not implemented.

The implemented menu, clean shift and initial orders follow `FLOW-01` and `ORDER-01`. Both the whole game and its required session service are absent from this starting project and must be implemented.

## 4. Player goal and complete flow

```text
open the saved game entry
→ start the shift from the visible menu
→ move the active chef and switch control to the other chef
→ take tomato from the crate
→ chop it on a chopping board
→ cook three chopped tomatoes in a pot without burning them
→ place the completed soup on a clean plate
→ serve it against a visible order
→ gain score and continue until time expires
→ see a result grade
→ Restart into a clean shift
```

The player can also pause and resume. Premature serving, repeated station actions, burnt soup, and expired orders must not silently reward the player.

## 5. Player actions

| Action | Normal input | Required player-facing response |
|---|---|---|
| Move chef | WASD or arrow keys | The chef travels through walkable kitchen space and is blocked by counters and walls. |
| Switch active chef | Q | Control changes exactly once to the other visible chef; each chef keeps their own position and held item. |
| Primary interact | E | Pick up, put down, start/continue a station action, or serve according to context. |
| Secondary action | F | Cancel or discard when context permits; it never grants an order result directly. |
| Pause/resume | Escape | Gameplay timing and actions pause, then resume from the same state. |
| Restart | R or a visible Restart button | A complete clean shift returns. |
| Start | Enter, Space, or a visible Start button | The menu opens a clean active shift (`FLOW-01`). |

## 6. Numbered requirements — sole acceptance source

### 6.1 Entry, movement, and camera

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback and boundary |
|---|---|---|---|---|---|
| `FLOW-01` | The saved entry loads. | Start Play or reopen to the menu, then use Start; Restart starts a fresh active shift directly. | A title/menu is visible on ordinary launch; starting it produces one clean active kitchen with exactly two chefs, chef one clearly active, score 0, 120 seconds, both hands empty, available stations, and no stale result. | No direct gameplay result, missing or extra chef, two simultaneously controlled chefs, already-cooked food, carried score, or duplicate runtime roots. | Menu, kitchen, both chefs, active-chef marker, HUD, and controls are readable; repeated starts reproduce the same invariants. |
| `INPUT-01` | A listed action is available. | Complete one full key tap/hold/release. | One input creates at most one matching player intent and remains reusable. | No duplicate intent or world action caused by a visible UI click. | Movement, interaction, pause, or restart response is visible. |
| `MOVE-01` | Active play is running. | Hold movement toward open floor, then toward a counter or wall. | Only the active chef travels a meaningful distance over open floor and remains blocked by kitchen geometry; the inactive chef stays in place. | No movement through counters/walls, simultaneous movement of both chefs, or movement while paused. | Locomotion, active selection, and changing position are visible. |
| `SWITCH-01` | Active play is running with two chefs. | Tap Q once, move or interact, then tap Q again. | Control changes exactly once per tap between the two chefs; both remain visible and each retains their own position and held item. | No teleport, duplicated chef, dropped or copied item, simultaneous control, or extra switch caused by one tap. | The active-chef marker and HUD clearly identify the newly controlled chef. |
| `CAMERA-01` | Either chef moves or control switches. | The active kitchen state changes. | One active 3D camera keeps both chefs and the important working area readable. | No blank view, severe clipping, or loss of both chefs or all actionable stations. | Reasonable fixed or tracking compositions are accepted. |

### 6.2 Ingredient and station workflow

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback and boundary |
|---|---|---|---|---|---|
| `PICKUP-01` | The active chef has empty hands near the tomato crate. | Press E. | Exactly one raw tomato is held by that chef; the crate remains reusable. Pressing E near a valid empty counter places it, and E again picks it back up. Switching chefs preserves both chefs' independent held items. | No wrong ingredient, duplication, remote pickup, transfer to the inactive chef, or replacement of an occupied counter. | Active chef, held item, and counter occupancy are visibly clear. |
| `CHOP-01` | A raw tomato is on an empty chopping board and the chef is in range. | Hold or repeatedly use E until the action completes. | Chopping progresses over at least 1 second and produces one chopped tomato. | No instant completion on placement, chopping from afar, wrong output, duplicate output, or progress while paused. | Progress and clear chopped feedback are shown. |
| `COOK-01` | A pot is available and the chef holds chopped tomatoes. | Add three chopped tomatoes, then wait. | The pot shows count/progress, cooks for 4–8 seconds, and becomes one completed tomato soup. | No raw ingredient acceptance, completion below three pieces, or remote addition. | Ingredient count, cooking progress, steam or equivalent feedback, and completion are perceivable. |
| `BURN-01` | Tomato soup is fully cooked and remains on heat. | Wait at least 5 additional seconds without collecting it. | The soup becomes burnt and cannot satisfy an order; the player can empty/discard it and reuse the pot. | No endless safe holding, valid score from burnt soup, or permanently unusable pot. | Burn warning/state and recovery are visible. |
| `PLATE-01` | A clean empty plate and completed non-burnt soup exist. | Use E in range to collect/transfer the soup. | One plate becomes plated tomato soup and the pot becomes reusable. | No plate from raw, chopped, or burnt contents, duplication, or remote transfer. | Plate contents and emptied pot are clear. |

### 6.3 Orders, delivery, and score

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback and boundary |
|---|---|---|---|---|---|
| `ORDER-01` | A fresh active shift begins. | Wait up to 3 seconds and continue playing. | A visible tomato soup order appears with at least 25 seconds remaining; later orders appear without exceeding three simultaneous orders. | No invisible order state, zero-time spawn, or more than three simultaneous orders. | Each order visibly shows recipe and remaining time or progress. |
| `DELIVERY-01` | A live order exists and the chef holds plated tomato soup. | Press E at delivery. | The oldest order completes once, the plate leaves the chef, and score increases by 20 plus a visible 0–10 time bonus. | No reward for empty, raw, chopped, burnt, or unplated delivery; no double reward from one plate. | Success feedback, removed order, and updated score agree. |
| `ORDER-02` | An order reaches zero before valid delivery. | Let it expire. | That order is removed and score decreases by 5 without ending the shift. | No positive reward, duplicate penalty, or negative-time order left visible. | Expiry and score loss are clearly communicated. |

### 6.4 Pause, result, restart, and reopen

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback and boundary |
|---|---|---|---|---|---|
| `PAUSE-01` | Active play is running. | Tap Escape, wait, then tap Escape again. | A visible pause panel appears; countdown, orders, cooking/burning, movement, and interactions freeze; resume restores the same state. | No hidden timer loss, station progress, movement, order spawn/expiry, or reset during pause. | Paused and resumed states are unambiguous. |
| `FLOW-02` | The 120-second countdown reaches zero. | Let the shift finish. | One stable result panel appears with final score and grade: Bronze below 40, Silver from 40–79, Gold at 80 or more. | No early result, simultaneous active play, changing final score, or hidden continued timers. | Result, score, grade, and Restart are readable. |
| `RESTART-01` | The shift is active, paused, or finished. | Tap R once or click the visible Restart control once. | Within 2 seconds the complete `FLOW-01` active-shift state returns: exactly two chefs at their starting positions, chef one active, score 0, 120 seconds, both hands empty, clean stations, no orders/results carried, and reusable movement/switch/interaction input. | No partial UI reset, retained food/order/score/timer/chef selection, duplicate actors/listeners, or multiple reset from one action. | Fresh neutral HUD, active-chef marker, and kitchen are visible. |
| `REOPEN-01` | Any runtime state exists. | Fully close Unity/runtime, launch a new process, and start the game. | The authored menu and a new clean shift appear with no prior runtime progress. | No retained score, timer, station contents, chef position, pause, or result. | Reopened experience matches a new run. |

### 6.5 HUD, audio, visual assembly, and quality

| ID | Preconditions | Player action or trigger | Required result | Forbidden result | Visible feedback and boundary |
|---|---|---|---|---|---|
| `UI-01` | The menu, active shift, pause, or result is visible at 1280×720. | Observe and perform required actions. | The player-facing interface clearly exposes Start, score, countdown, active chef, that chef's held item, Q switch control, station progress, up to three orders, controls, pause/resume, result grade, and Restart when relevant. | No unreadable overlap, placeholder labels, or controls that are only decorative. | UI values remain synchronized with true gameplay and active-chef state. |
| `AUDIO-01` | Audio output is available. | Start, interact, chop, cook, deliver, fail an order, pause, and finish. | Background kitchen ambience and distinct action/success/warning/result feedback are perceivable without duplicate stacked playback. | No completely silent required flow or contradictory result audio. | Reasonable mixing is accepted. |
| `VISUAL-01` | A menu, active, cooking, or result state is visible. | Observe the whole frame. | The supplied original-author two-chef presentation, kitchen, food, appliances, materials, animation, active-chef marker, and UI form a coherent colorful isometric cooking game with readable roles and effects. | No empty graybox, missing chef, primary placeholder primitives, broken materials, severe clipping, stretched/cropped UI, or unrelated replacement assembly. | Pixel-perfect matching is not required; supplied roles must remain recognizable. |
| `QUALITY-01` | The saved game entry is available. | The player starts the game. | The entry, player controls, and required states remain usable without severe blocking errors. | No broken entry, one-run-only setup, or severe error that blocks required play. | Restart and clean-start behavior follow their numbered requirements; equivalent internal architecture is accepted. |


### 6.6 Required service and technical delivery

| ID | Requirement | Authority |
|---|---|---|
| `SESSION-DELIVERY` | Deliver all common session behavior and the kitchen-specific service requirements `SESSION-01` through `SESSION-11`. These are requirements of the real game, in addition to its normal player controls. | `GAME_SESSION_SPEC.md` and `SESSION_MODEL.json` |
| `DELIVERY-TECH` | Save the complete playable project using the declared engine, input, user-interface and file-boundary contract. | `TOOLCHAIN.md` and `BENCHMARK_MANIFEST.json` |

## 7. Asset and state indexes

- Allowed asset facts, inventory, image previews and source-use boundaries: `ASSET_MANIFEST.json`, `ASSET_CATALOG.json`, `ASSET_CATALOG.md`, `ASSET_COVERAGE.json` and `ASSET_CONTACT_SHEET.png`.
- Public service types and signatures: `Packages/com.gamecreate.game-session/`.
- Authoritative kitchen vocabulary, actor/value fields, legal ownership, timers and spatial description: `SESSION_MODEL.json`; `Assets/Resources/session-model.json` is its byte-identical runtime copy.
- Optional public development checks and their exact scope: `TOOLCHAIN.md`.

No internal class hierarchy, object names other than the published service IDs, algorithm, camera angle, HUD layout or source-code organization is prescribed.
