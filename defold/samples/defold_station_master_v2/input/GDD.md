# Station Master: Emergency Expansion Shift

Public input revision: `v2-dashboard-pilot-20260828`  
Benchmark ID: `defold.station_master.v2`

## 1. One-sentence task

Build a mouse-driven space-station management game in which the player generates energy, buys three
sequential physical expansions, uses passive production, and brings the station online before a
120-second shift expires.

## 2. Scope

Create one complete shift with this loop:

```text
briefing → start shift → click for energy → buy three expansions in order
         → final charge → station online | timer reaches zero → shift failed
         → restart or exit
```

Long-term progression, offline income, repeated price curves, multiple stations, free-form building,
drag-and-drop construction, and keyboard shortcuts are out of scope.

## 3. Starting state

The public input contains a minimal buildable Defold project, a left-mouse input binding, visual
references, and the read-only Dashboard transport. It intentionally contains no briefing, economy,
station assembly, shop, timer, pause, or result gameplay. Implement the game inside
`starter_project/`.

## 4. Player goal and complete flow

The player starts from a short briefing. A new shift begins with zero energy, +1 energy per completed
generator click, no passive income, no purchases, stage 1/4, and 120 seconds. The player purchases a
10-energy base module, a 50-energy solar wing, and a 150-energy power booster in that order. The solar
wing produces 5 energy per second; the booster raises each generator click to 10. After all three
expansions, reaching 100 energy brings the station online. If the timer reaches zero first, the shift
fails.

## 5. Normal controls

| Player action | Input | Expected response |
|---|---|---|
| Activate a control | Complete left-mouse press and release over the same visible control | Activate it once |
| Generate energy | Click the central generator while playing | Add exactly the current click power |
| Buy an expansion | Click its visible shop card | Buy only when unlocked, unowned, and affordable |
| Pause, resume, restart, or exit | Click the corresponding visible button | Perform the labelled action |

## 6. Numbered requirements — authoritative task-specific acceptance source

| Requirement | Formal requirement |
|---|---|
| `SM-START-01` | Launch into a readable briefing that explains clicking, expansion purchases, and the within-shift objective. Clicking Start Shift begins a clean shift with energy 0, click power 1, passive production 0/s, no purchases, stage 1/4, and a 120-second timer. No resource or timer changes occur before the shift starts. |
| `SM-CLICK-01` | During play, one complete press and release on the central generator adds exactly the current click power and increments the accepted manual-click count once. Holding without releasing, clicking outside the control, clicking while paused, or clicking after a result adds nothing. Rapid complete clicks are individually accepted without loss or duplication. The generator visibly responds to its pressed and released states. |
| `SM-UPGRADE-01` | At stage 1/4, the Base Module costs 10 energy. A valid purchase deducts exactly 10, installs one visible base module, advances to stage 2/4, and unlocks the Solar Wing. Insufficient, repeated, or otherwise invalid purchases do not deduct energy or advance the stage and give visible rejection feedback. |
| `SM-UPGRADE-02` | At stage 2/4, the Solar Wing costs 50 energy. A valid purchase deducts exactly 50, installs one visible solar wing, advances to stage 3/4, starts passive production at 5 energy per second, and unlocks the Power Booster. It cannot be purchased early or twice. |
| `SM-UPGRADE-03` | At stage 3/4, the Power Booster costs 150 energy. A valid purchase deducts exactly 150, installs one visibly distinct booster, advances to stage 4/4, and changes click power from 1 to 10 without changing passive production. It cannot be purchased early or twice. |
| `SM-SHOP-01` | All three shop cards remain identifiable and show their names, prices, and true locked, unaffordable, affordable, or purchased state. Only an unlocked, unowned, affordable card may succeed. Energy never becomes negative, and the order is Base Module → Solar Wing → Power Booster. |
| `SM-PASSIVE-01` | After the Solar Wing purchase and only while playing, energy increases continuously at 5 per real second. The visible energy value updates at least every 0.2 seconds. Passive income does not increment the manual-click count and stops while paused or after either result. |
| `SM-STAGE-01` | Stage progresses exactly 1/4 → 2/4 → 3/4 → 4/4. Each progression simultaneously changes the shop availability and adds the corresponding visible station expansion. Pause/resume cannot alter stage, and restart restores 1/4. |
| `SM-TIMER-01` | A shift counts down from 120 seconds according to real elapsed time. It freezes while paused and after either result, then resumes correctly after unpausing. If success and expiry become true in the same update, success takes precedence. |
| `SM-WIN-01` | Success occurs only when all three expansions are installed, stage is 4/4, and energy is at least 100. It immediately enters a terminal `STATION ONLINE` or equivalent state, freezes generation, passive income, purchases, and time, preserves the visibly complete station, and offers Restart and Exit. |
| `SM-LOSE-01` | If the timer reaches zero before the success condition is true, enter a terminal `SHIFT ENDED` or equivalent failure state. Freeze generation, passive income, purchases, and time; show final stage, energy, and the next missing goal; offer Restart and Exit. Failure and success cannot both be active. |
| `SM-HUD-01` | During play and pause, the HUD continuously shows true current energy, click power, passive production per second, stage, and remaining time. It does not obscure the generator, shop cards, or central station. |
| `SM-PAUSE-01` | Clicking Pause while playing opens a single clear pause layer with Resume, Restart, and Exit. While paused, underlying gameplay controls do not respond and resource, timer, purchases, and station state remain frozen. Resume returns to the same shift; Restart and Exit perform their labels. |
| `SM-RESULT-01` | Win and loss layers are visually distinguishable and simultaneously show the result title, final energy, stage or upgrade completion, Restart, and Exit. Underlying controls cannot operate, and the result remains until the player chooses a next action. |
| `SM-VISUAL-01` | At 1280 × 720, present a coherent space-management screen with a dark starfield, central station, large generator control, numeric HUD, upgrade shop, and clearly separated status panels. Each purchase adds a spatially and visually distinct physical expansion; the final station is visibly more complete than the initial core. Do not represent the station only with stage text, debug rectangles, or a plain text button list. |
| `SM-RESET-01` | Restart from play, pause, win, or loss returns to the briefing or an equivalent clean start. A newly started shift resets energy, click power, passive production, purchases, shop state, stage, station appearance, timer, overlays, and result state. Repeating restart remains stable. |
| `SM-LIFECYCLE-01` | Closing and relaunching the application returns to the initial briefing with no saved shift state or offline income. Exit controls terminate the application normally. |
| `SM-DASHBOARD-01` | Implement `DASHBOARD_SPEC.md` using exactly the slots, stable entity IDs, kinds, states, geometry, target kinds, and phase mapping in Section 12 and `naming-tables.json`. Values come from the same authoritative variables used by gameplay and rendering. |
| `SM-DASHBOARD-02` | The Dashboard is read-only. It exposes no click, purchase, resource, timer, restart, or result-forcing operation. Revision changes only when its reported payload changes. Reported phases, numeric slots, entity visibility and state, geometry, and target visibility/interactability must remain synchronized with the actual game. |

The shared `COMMON_BASELINE.md` supplies the game-independent requirements. It does not add hidden
Station-specific prices, routes, controls, or result conditions.

## 7. Visual references

The MIT-licensed reference images define the intended information hierarchy and visible distinction
between an initial core and expanded station. They do not require pixel-identical reproduction.

| Reference | Purpose |
|---|---|
| `reference_images/original_opening.png` | Starfield, station, generator, and shop hierarchy |
| `reference_images/original_module_and_panel.png` | A purchased module and adjacent information panel |
| `reference_images/original_info_panel.png` | Readable management information grouping |
| `reference_images/original_exit_confirm.png` | Modal pause/exit hierarchy |

Equivalent science-fiction art and layout are allowed if all numbered requirements remain true.

## 8. Player-visible feedback

The player must be able to distinguish generator press/release, successful generation, locked or
insufficient purchases, successful installation, passive production, pause, win, and loss without
reading logs. Dashboard feedback entities report only feedback that is actually visible.

## 9. Restart and persistence

No run progress persists. Restart resets the entire shift, and a fresh process begins at the
briefing. Closing the application never grants offline income.

## 10. Existing functionality

This is a standalone reconstruction. No legacy game behavior needs to be preserved.

## 11. Assets and content

The supplied files are reference images and license material, not an importable Gold asset pack.
Create or assemble the required station, shop, generator, starfield, panels, and three expansions in
the Defold project. Do not copy a reference screenshot into the game as the playable interface.

## 12. Dashboard names and control scheme

`naming-tables.json` is machine-readable and authoritative for spelling. This section explains the
same mapping.

### 12.1 Phases

| Game state | Dashboard phase |
|---|---|
| Briefing | `menu` |
| Active shift | `playing` |
| Pause layer | `paused` |
| Station online | `won` |
| Shift ended | `lost` |
| Starter before target gameplay exists | `not_ready` |

### 12.2 Numeric slots

| Slot | Meaning |
|---|---|
| `energy` | Authoritative energy, including any fractional passive accumulation |
| `display_energy` | Numeric energy value currently shown to the player |
| `manual_click_count` | Accepted complete generator clicks in the current shift |
| `click_power` | Energy granted by one accepted generator click |
| `passive_per_second` | Current passive production rate |
| `stage` | Current expansion stage |
| `stage_total` | Total stage count, always 4 in target gameplay |
| `time_remaining` | Remaining seconds; use 0 while no shift is active |

### 12.3 Entities

All Station entity kinds use `rect` geometry in `[left, bottom, width, height]` logical game pixels.
Every instance has a stable ID for the entire run.

| Stable ID | Kind | Allowed states |
|---|---|---|
| `station-core` | `station_core` | `active` |
| `base-module` | `base_module` | `hidden`, `installed` |
| `solar-wing` | `solar_wing` | `hidden`, `installed` |
| `power-booster` | `power_booster` | `hidden`, `installed` |
| `base-module-card` | `base_module_card` | `locked`, `unaffordable`, `affordable`, `purchased` |
| `solar-wing-card` | `solar_wing_card` | `locked`, `unaffordable`, `affordable`, `purchased` |
| `power-booster-card` | `power_booster_card` | `locked`, `unaffordable`, `affordable`, `purchased` |
| `generator-control` | `generator_control` | `disabled`, `idle`, `pressed` |
| `feedback-banner` | `feedback_banner` | `hidden`, `shift_started`, `generator_click`, `purchase_insufficient`, `purchase_locked`, `purchase_owned`, `purchase_success` |

An installed part or visible feedback uses `visible: true`; a part not yet installed or an empty
feedback banner uses `visible: false` with the corresponding state. Shop cards and the station core
remain visible whenever the underlying UI is visible.

### 12.4 Clickable targets

Targets use the same bottom-left rectangle convention. Report only currently relevant controls.

`start_button`, `exit_button`, `generator_button`, `pause_button`, `base_module_card`,
`solar_wing_card`, `power_booster_card`, `resume_button`, and `restart_button`.

Normal input is one left-mouse press and release. Dashboard targets report where a player can click;
they do not perform the click.

## 13. Implementation boundary

The numbered requirements define player outcomes, not class names, object hierarchy, algorithms, or
scene organization. Internal implementation is free as long as gameplay, rendering, normal mouse
input, and the read-only Dashboard all agree. Gold code, private checkpoints, score weights, and
answer actions are not part of this public input.
