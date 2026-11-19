# Cervantes Tactics: Chapter One (English Edition)

> Document version: v1.21-en (menu, dialogue, selection, and tactical-range presentation clarified)  
> This document defines only results that players can see, operate, and verify, plus the public asset identities explicitly permitted for static inspection in Section 6. **Only uniquely numbered items in Section 6 participate in acceptance.** Sections 1–5 and 7–9 provide background, explanation, indexes, and self-checks only and add no acceptance conditions. Code, nodes, scene trees, file organization, and algorithms are outside acceptance scope.

## 1. One-Sentence Task (Non-Acceptance Background)

Build the English edition of *Cervantes Tactics: Chapter One*: from a black-and-gold main menu, the player chooses among three save slots, enters an oblique-view 3D dungeon board, commands Erick, Mitzi, Diego, and Hercules to protect the Family Crystal and defeat three enemies, then gains progression in the results phase that persists across processes.

## 2. Scope and Language (Non-Acceptance Background)

Content includes the main menu, three slots, options, Chapter One information and story, a 12×9 battlefield, turns for both sides, all actions, traps, victory/defeat, results, progression, returning to menu, replay, and persistence. New chapters, multiplayer, accounts, shops, equipment, crafting, voice acting, and mobile are out of scope. See the `LANGUAGE-*`, `ASSET-*`, and other numbered items in Section 6 for actual acceptance.

## 3. Example Player Flow (Non-Acceptance Background)

### 3.1 Successful Trajectory

| Step | Input | Screen state | Commit point |
|---:|---|---|---|
| 1 | Launch; New Game; choose empty slot | Main menu → three slots → chapter information | Choosing a slot creates only an in-process active slot |
| 2 | Start; continue each segment | Opening dialogue → sole battle instance | Last dialogue segment closes |
| 3 | Click a battlefield unit or its left-side party card → action → legal target → “Confirm Action” | Target click previews only; confirmation resolves atomically and shows acted state | Click “Confirm Action” |
| 4 | Everyone acts or End Turn | Enemy actions → next player turn | New player phase appears |
| 5 | Defeat last enemy | Freeze → victory dialogue → results | Permanent save committed before results appear |
| 6 | Return to menu; close and reopen; Continue | Enter chapter information for the most recently saved successful slot | Chapter information appears |

### 3.2 Failure and Cancellation Trajectory

| Step | Input | Screen state | Commit? |
|---:|---|---|---|
| 1 | New Game on existing slot; Esc | Overwrite modal closes; old summary unchanged | No |
| 2 | Select Attack in battle; Esc | Return to action menu; HP/action eligibility unchanged | No |
| 3 | Esc while idle; Return to Menu; cancel | Return to same pause layer; board unchanged | No |
| 4 | Crystal reaches 0 | Freeze → defeat dialogue → results | Temporary results only |
| 5 | Return to menu or close/reopen | Slot retains pre-battle permanent progression | No |

### 3.3 Family-Wipeout Trajectory

| Step | Input | Screen state | Commit? |
|---:|---|---|---|
| 1 | Keep crystal above 0 HP and let the first three Family members die in sequence | Dead units release occupied cells; crystal remains intact | No |
| 2 | Last Family member takes lethal damage | Immediately lock “Family Wiped Out” defeat after that resolution | Lock defeat outcome |
| 3 | Continue defeat dialogue | Show dedicated wipeout dialogue and “Family Wiped Out” result reason | No |
| 4 | Return to menu and restart | Slot progression restores to pre-battle values | No |

### 3.4 Suggested Strategy (Non-Acceptance)

This table describes decision priorities a player may use. Healing, magic, defense, and Eagle Slash are complete only when a real action resolves and its visible state changes accordingly; merely showing a same-named button or an unavailable threshold is insufficient.

Starting with the first player turn, process Erick → Mitzi → Diego → Hercules and take the first currently legal action in each row. Break target ties Guard → Archer → Adept and destination ties Up → Left → Right → Down. After every target click, click “Confirm Action”; end the turn after all four are processed, repeating until all three enemies are dead.

| Character | Take the first legal action from left to right |
|---|---|
| Erick | Full-gauge Eagle Slash on adjacent target → target in normal attack range → move toward nearest target → Defend |
| Mitzi | Target in normal attack range → move toward nearest target → Defend |
| Diego | Magic can hit at least two enemies → target in normal attack range → magic hits one enemy → move toward nearest target → Defend |
| Hercules | Team heal when at least two Family members are wounded → single heal when any adjacent ally is wounded → target in normal attack range → move toward nearest target → Defend |

“Move toward nearest target” means choosing a reachable destination that minimizes Manhattan distance to that target. This strategy is only a starting point for self-testing; it does not guarantee victory under every action detail and is neither the only play style nor an acceptance script. Formal playability is judged only by `PLAYABILITY-01-02`.

## 4. Terms and Input (Non-Acceptance Explanation)

| Term | Meaning |
|---|---|
| Active slot | Slot selected in the current process as the Chapter One entry; not the same as an existing slot |
| Existing slot | Structurally complete, version-compatible record containing successfully committed victory progression |
| Atomic resolution | Uninterruptible state change comprising action movement/numbers, trap, death, experience events, and outcome checks |
| Tactical input | Selecting unit, action, target, confirm, and End Turn; excludes camera |
| Normal weapon damage | Ordinary “Attack”; excludes magic, Eagle Slash, and traps |

Common inputs are mouse, WASD/arrow keys, middle-button drag, C, and Esc; formal results are defined by `INTERACTION-*` and `PAUSE-*`.

## 5. Fixed Data (Non-Acceptance Index)

This section is only a readable copy of formal Section 6 data. No formal ID references it, and it does not independently participate in acceptance. If inconsistent, Section 6 prevails.

| Unit | Initial cell | HP | Move | Attack | Range | Unique initial value |
|---|---:|---:|---:|---:|---:|---|
| Erick | (2,4) | 12 | 4 | 3 | 1 | Limit 0/3; Eagle Slash ×3 |
| Mitzi | (1,4) | 8 | 4 | 2 | 3 | Detection/aura radius 2; reduction 1 |
| Diego | (2,6) | 7 | 3 | 4 | 2 | Magic-center radius 1; attack +1 |
| Hercules | (2,2) | 14 | 3 | 2 | 1 | Single heal 3; team heal 2 |
| Guardia Sin Memoria | (10,4) | 7 | 3 | 2 | 1 | Normal attack |
| Arquero Sin Memoria | (10,1) | 5 | 3 | 2 | 3 | Normal attack |
| Adepto Sin Memoria | (11,7) | 5 | 3 | 3 | 2 | Normal attack |
| Family Crystal | (6,4) | 5 | — | — | — | Cannot be occupied |

The board spans `(0,0)`–`(11,8)`. Fixed obstacles: `(3,4) (4,2) (10,2) (7,5) (11,2) (4,6) (9,6) (6,4)`; traps: `(2,5) (8,4) (9,2)`. Height-2 cells: `(6,4)`; height-1 cells: `(0,2) (0,3) (0,4) (0,5) (1,2) (1,3) (1,4) (1,5) (5,4) (6,3) (6,5) (7,4)`; all others height 0. Height affects presentation only.

All four initial permanent records have level 1, experience 0, and threshold 100; max HP/attack are as above. Only Hercules has single heal 3 and team heal 2.

## 6. Numbered Requirements: Sole Acceptance Basis

### 6.0 Interpretation Rules

| ID | Formal requirement |
|---|---|
| RULE-01 | Only uniquely numbered items in this section define game-specific required outcomes. |
| RULE-02 | Sections 1–5 and 7–9, `TOOLCHAIN-en.md`, `GODOT_BENCHMARK_TOOL_GUIDE.md`, `MaterialMapping-en.md`, and other files do not participate in acceptance; this section must not import hard data from them. |
| RULE-03 | For implementation-defined behavior, only the stated invariants are required; unspecified player paths remain free. |
| RULE-04a | Exact public asset paths may be statically checked only for `MENU-02a`, `MENU-02c`, `ASSET-01a-01g`, `ASSET-02a-02h`, `ASSET-03a`, `ASSET-03g`, `ASSET-03i`, and `ASSET-04a`. |
| RULE-04b | Except for `RULE-04a`, all other IDs are accepted only by final player-visible or operable outcomes and do not require a runtime style-reading interface. |
| RULE-05 | Parameterized items for one invariant, such as coordinate or character sets, report each listed parameter as a separate sub-assertion; one failure must not hide other parameter results, and unlisted parameters must not be introduced. |

### 6.1 Formal Fixed Data

| ID | Formal requirement |
|---|---|
| DATA-01a | Board width is 12 cells. |
| DATA-01b | Board height is 9 cells. |
| DATA-01c | Top-left board coordinate is `(0,0)`. |
| DATA-01d | Bottom-right board coordinate is `(11,8)`. |
| DATA-02a | Family Crystal coordinate is `(6,4)`. |
| DATA-02b | Family Crystal initial HP is 5. |
| DATA-02c | Family Crystal maximum HP is 5. |
| DATA-02d | Units cannot occupy the Family Crystal cell. |
| DATA-03 | Fixed obstacle set is `(3,4) (4,2) (10,2) (7,5) (11,2) (4,6) (9,6) (6,4)`, with no other fixed obstacles. |
| DATA-04 | Fixed trap set is `(2,5) (8,4) (9,2)`, with no other initial trap cells. |
| DATA-05 | Height-2 cell set is `(6,4)`. |
| DATA-06a | Height-1 cell set is `(0,2) (0,3) (0,4) (0,5) (1,2) (1,3) (1,4) (1,5) (5,4) (6,3) (6,5) (7,4)`. |
| DATA-06b | Cells not listed by `DATA-05` or `DATA-06a` have height 0. |
| DATA-07a | Erick starts at `(2,4)`. |
| DATA-07b | Erick's movement is 4. |
| DATA-07d | Erick's normal attack range is 1. |
| DATA-07c | Erick's Limit gauge starts at 0. |
| DATA-07e | Erick's Limit gauge maximum is 3. |
| DATA-07f | Erick's Eagle Slash damage multiplier is 3. |
| DATA-08a | Mitzi starts at `(1,4)`. |
| DATA-08b | Mitzi's movement is 4. |
| DATA-08e | Mitzi's normal attack range is 3. |
| DATA-08c | Mitzi's detection radius is 2. |
| DATA-08d | Mitzi's aura radius is 2. |
| DATA-08f | Mitzi's aura reduces normal attack damage by 1. |
| DATA-09a | Diego starts at `(2,6)`. |
| DATA-09b | Diego's movement is 3. |
| DATA-09d | Diego's normal attack range is 2. |
| DATA-09c | Diego's magic radius is 1. |
| DATA-09e | Diego's magic damage modifier is current attack +1. |
| DATA-10a | Hercules starts at `(2,2)`. |
| DATA-10b | Hercules's movement is 3. |
| DATA-10e | Hercules's normal attack range is 1. |
| DATA-10c | Hercules's initial single-target heal is 3. |
| DATA-10d | Hercules's team heal is fixed at 2. |
| DATA-11a | Guardia Sin Memoria starts at `(10,4)`. |
| DATA-11b | Guardia Sin Memoria initial HP is 7. |
| DATA-11f | Guardia Sin Memoria maximum HP is 7. |
| DATA-11c | Guardia Sin Memoria movement is 3. |
| DATA-11d | Guardia Sin Memoria attack is 2. |
| DATA-11e | Guardia Sin Memoria range is 1. |
| DATA-12a | Arquero Sin Memoria starts at `(10,1)`. |
| DATA-12b | Arquero Sin Memoria initial HP is 5. |
| DATA-12f | Arquero Sin Memoria maximum HP is 5. |
| DATA-12c | Arquero Sin Memoria movement is 3. |
| DATA-12d | Arquero Sin Memoria attack is 2. |
| DATA-12e | Arquero Sin Memoria range is 3. |
| DATA-13a | Adepto Sin Memoria starts at `(11,7)`. |
| DATA-13b | Adepto Sin Memoria initial HP is 5. |
| DATA-13f | Adepto Sin Memoria maximum HP is 5. |
| DATA-13c | Adepto Sin Memoria movement is 3. |
| DATA-13d | Adepto Sin Memoria attack is 3. |
| DATA-13e | Adepto Sin Memoria range is 2. |
| DATA-14a | Without a permanent record, Erick is level 1. |
| DATA-14b | Without a permanent record, Erick's current experience is 0. |
| DATA-14c | Without a permanent record, Erick's next-level threshold is 100. |
| DATA-14d | Without a permanent record, Erick's maximum HP is 12. |
| DATA-14e | Without a permanent record, Erick's attack is 3. |
| DATA-15a | Without a permanent record, Mitzi is level 1. |
| DATA-15b | Without a permanent record, Mitzi's current experience is 0. |
| DATA-15c | Without a permanent record, Mitzi's next-level threshold is 100. |
| DATA-15d | Without a permanent record, Mitzi's maximum HP is 8. |
| DATA-15e | Without a permanent record, Mitzi's attack is 2. |
| DATA-16a | Without a permanent record, Diego is level 1. |
| DATA-16b | Without a permanent record, Diego's current experience is 0. |
| DATA-16c | Without a permanent record, Diego's next-level threshold is 100. |
| DATA-16d | Without a permanent record, Diego's maximum HP is 7. |
| DATA-16e | Without a permanent record, Diego's attack is 4. |
| DATA-17a | Without a permanent record, Hercules is level 1. |
| DATA-17b | Without a permanent record, Hercules's current experience is 0. |
| DATA-17c | Without a permanent record, Hercules's next-level threshold is 100. |
| DATA-17d | Without a permanent record, Hercules's maximum HP is 14. |
| DATA-17e | Without a permanent record, Hercules's attack is 2. |
| DATA-17f | Without a permanent record, Hercules's single-target heal is 3. |
| DATA-17g | Without a permanent record, Hercules's team heal is 2. |
| DATA-18a | With a permanent record, all four Family members use their respective level from the current slot. |
| DATA-18b | With a permanent record, all four Family members use their respective current experience from the current slot. |
| DATA-18c | With a permanent record, all four Family members use their respective next-level threshold from the current slot. |
| DATA-18d | With a permanent record, all four Family members use their respective maximum HP from the current slot. |
| DATA-18e | With a permanent record, all four Family members use their respective attack from the current slot. |
| DATA-18f | With a permanent record, Hercules uses the current slot's single-target heal amount. |
| DATA-18g | With a permanent record, Hercules uses the current slot's team-heal amount. |
| DATA-18h | With a permanent record, all four Family members enter this chapter at their respective maximum HP. |

### 6.2 Language, Menu, and Exit

| ID | Formal requirement |
|---|---|
| LANGUAGE-01a | Functional UI uses English; action, state, and flow terms explain behavior and do not mandate final rendered copy. |
| LANGUAGE-01b | Chapter name and objective text use English. |
| LANGUAGE-01c | Tutorial and tactical hints use English. |
| LANGUAGE-01d | Story dialogue uses English. |
| LANGUAGE-01e | Results and progression-settlement text use English. |
| MENU-01 | After startup completes, exactly one main-menu instance is visible. |
| MENU-02a | The main-menu background uses `Asserts/maps/chapter01/chapter01-map-art-concept.png`, covers the `1280×720` viewport proportionally, and is not stretched out of aspect ratio. |
| MENU-02b | The title logo is visibly anchored in the upper-left area of the main menu and remains inside the `LAYOUT-01i` safe margin. |
| MENU-02c | Main menu uses `Asserts/branding/logo-main.png` or cropped `logo-main-tight.png`; either qualifies. |
| MENU-02d | The six main-menu entry buttons form one group below the title logo; no entry overlaps the logo or appears above it. |
| MENU-03a | Main menu shows “Continue”. |
| MENU-03b | Main menu shows “Load Game”. |
| MENU-03c | Main menu shows “New Game”. |
| MENU-03d | Main menu shows “Chapter One”. |
| MENU-03e | Main menu shows “Options”. |
| MENU-03f | Main menu shows “Exit”. |
| MENU-04a | Every available main-menu entry can be single-clicked with the mouse. |
| MENU-04b | After returning from a subpage, exactly one menu instance exists. |
| MENU-04c | One click on a main-menu entry produces exactly one page transition or action. |
| EXIT-01 | Main-menu “Exit” opens an English modal containing “Confirm Exit” and “Cancel”. |
| EXIT-02a | Clicking Cancel on the exit modal returns to the same main menu. |
| EXIT-02b | Pressing Esc on the exit modal returns to the same main menu. |
| EXIT-02c | Closing the exit modal returns to the same main menu. |
| EXIT-02d | None of `EXIT-02a-02c` modifies saves. |
| EXIT-02e | None of `EXIT-02a-02c` modifies applied settings. |
| EXIT-03 | After confirming exit, the game process ends and leaves no running process for this game. |
| EXIT-04 | Closing the window outside battle is equivalent to confirming exit and retains only committed saves and applied settings. |
| EXIT-05a | Closing the window during battle ends the game process. |
| EXIT-05b | Closing the window during battle does not commit temporary battle state. |
| EXIT-05c | Reopening after `EXIT-05a` loads only progression committed before battle. |

### 6.3 Saves and Chapter

| ID | Formal requirement |
|---|---|
| SAVE-01 | Load and New Game pages each show exactly three fixed-number slots. |
| SAVE-02 | A target slot changes from empty to existing only after a victory settlement is successfully committed. |
| SAVE-03a | An existing-slot summary shows “Chapter One”. |
| SAVE-03b | An existing-slot summary shows the highest level among the four Family members. |
| SAVE-03c | An existing-slot summary shows the last victory commit time. |
| SAVE-03d | An empty slot shows no chapter, level, or update-time summary. |
| SAVE-04 | Load permits only existing slots; selection makes it active and shows chapter information. |
| SAVE-05a | Continue selects the existing slot with the latest update time; ties choose the lowest slot number. |
| SAVE-05b | The slot chosen by Continue becomes active. |
| SAVE-05c | After Continue selects a slot, exactly one chapter-information instance opens. |
| SAVE-05d | Repeatedly clicking Continue performs only one page transition. |
| SAVE-06 | With no existing slot, Continue is disabled; activating it neither creates progress nor enters battle. |
| SAVE-07a | After New Game selects an empty slot, initial progression uses `DATA-14-17`. |
| SAVE-07b | The empty slot selected for New Game becomes active in the current process. |
| SAVE-07c | After New Game selects an empty slot, exactly one chapter-information instance opens. |
| SAVE-07d | An empty slot remains empty across processes until its first victory commit. |
| SAVE-08 | Selecting an existing slot for New Game first shows overwrite confirmation containing its number; the slot is unchanged before confirmation. |
| SAVE-09 | Cancel, Esc, or close on the overwrite modal returns to the slot list with original content unchanged. |
| SAVE-10 | Double-clicking a slot or repeatedly confirming produces only one overwrite flow. |
| SAVE-11a | After overwrite confirmation, the old record is immediately and persistently deleted. |
| SAVE-11b | The overwrite target becomes the current active empty slot using `DATA-14-17`. |
| SAVE-11c | After overwrite completes, the modal and slot page close and exactly one chapter-information instance opens. |
| SAVE-12 | If closed/reopened after overwrite but before victory, the target remains empty and retains no cross-process active-slot state. |
| SAVE-13a | Loading, creating, overwriting, or saving any slot does not change progression in the other two. |
| SAVE-13b | Loading, creating, overwriting, or saving any slot does not change update times in the other two. |
| SAVE-14 | Only a victory commit updates time; loading, starting battle, failing, viewing results, and returning to menu do not. |
| CHAPTER-01a | With an active slot, Chapter One opens exactly one chapter-information instance. |
| CHAPTER-01b | Without an active slot, Chapter One opens a separate three-slot “Choose Chapter One Save” page. |
| CHAPTER-01c | Selecting an empty slot on that page follows `SAVE-07a-07d`. |
| CHAPTER-01d | Selecting an existing slot there makes it active and opens one chapter-information instance without overwrite. |
| CHAPTER-02a | Information-page title is fixed as “Chapter One: Gate of the Mountains”. |
| CHAPTER-02b | Protection objective is fixed as “Protect the Family Crystal (5/5)”. |
| CHAPTER-02c | Victory condition is fixed as “Defeat All Enemies”. |
| CHAPTER-02d | Defeat condition is fixed as “Family Crystal shatters, or all four Family members fall”. |
| CHAPTER-02e | Tactical hint is fixed as “Block the paths to the Crystal, focus attacks on wounded enemies, and heal Family members in time.” |
| CHAPTER-03a | Clicking Back or pressing Esc on information always returns to the main menu. |
| CHAPTER-03b | Returning from information does not modify a slot or generate battle. |
| CHAPTER-03c | After returning, the page can be entered again from the main menu and restores its unconfirmed initial state. |
| CHAPTER-04 | The first Start click locks entry; repeated clicks generate only one battle instance. |
| FLOW_ORDER-01a | Once Start input is accepted, chapter information closes first. |
| FLOW_ORDER-01b | After it closes, exactly one battle instance is generated. |
| FLOW_ORDER-02 | After battle generation and before any turn begins, immediately play the five opening dialogue segments `STORY-04-08`. |
| FLOW_ORDER-03a | Tactical input remains locked until all five opening segments close. |
| FLOW_ORDER-03b | Until then, turn, phase, units, and crystal state do not advance. |
| FLOW_ORDER-04a | After the fifth segment closes, set the turn number to 1. |
| FLOW_ORDER-04b | After setting turn 1, enter the player phase. |

### 6.4 Scene and Assets

| ID | Formal requirement |
|---|---|
| SCENE-01a | The battle board uses perspective, not orthographic, projection. |
| SCENE-01e | Every traversable cell displays horizontal and vertical boundary lines. |
| SCENE-01h | Initial camera uses an oblique overhead angle that simultaneously distinguishes board top, x direction, and y direction. |
| SCENE-01i | In fixed `1280×720`, the player can distinguish four corners, crystal, and seven initial units without moving camera. |
| SCENE-01j | The initial camera's screen-space box around four corner-cell centers is at least 52% of window width and 40% of height, making the board the primary battle visual. |
| SCENE-05a | Fixed obstacles conform to `DATA-03`. |
| SCENE-05b | Initial traps conform to `DATA-04`. |
| SCENE-05c | Board heights conform to `DATA-05-06`. |
| SCENE-05d | Height does not change movement cost. |
| SCENE-05e | Height does not change normal attack or ability range. |
| SCENE-05f | Height does not block line of sight. |
| SCENE-05g | Height does not change damage. |
| SCENE-06a | Cells outside `DATA-03` are not blocked by fixed terrain. |
| SCENE-06b | Cells occupied by living units block other units. |
| SCENE-06c | Units may enter untriggered trap cells. |
| ASSET-01a | Erick uses `Asserts/standees/family/erick-standee.png`. |
| ASSET-01b | Mitzi uses `Asserts/standees/family/mitzi-standee.png`. |
| ASSET-01c | Diego uses `Asserts/standees/family/diego-standee.png`. |
| ASSET-01d | Hercules uses `Asserts/standees/family/hercules-standee.png`. |
| ASSET-01e | Guardia Sin Memoria uses `Asserts/standees/rivals/guardia-sin-memoria-standee.png`. |
| ASSET-01f | Arquero Sin Memoria uses `Asserts/standees/rivals/arquero-sin-memoria-standee.png`. |
| ASSET-01g | Adepto Sin Memoria uses `Asserts/standees/rivals/adepto-sin-memoria-standee.png`. |
| ASSET-01h | Transparent areas of all seven battlefield standees show no rectangular background. |
| ASSET-01i | A standee foot point is the screen projection of its unit cell's world center; render back-to-front by ascending foot-point screen Y. |
| ASSET-01j | For equal foot-point screen Y, continue with ascending board y, board x, and fixed unit order; the larger key renders above. Fixed order: Erick, Mitzi, Diego, Hercules, Guard, Archer, Adept. |
| ASSET-01k | Align the bottom-center of each standee's nontransparent subject to its cell center. Initially and after movement, feet touch the visible cell surface without lateral offset, floating, or sinking caused by PNG transparent padding. |
| ASSET-01l | In the `1280×720 (16:9)` windowed initial camera, every visible overlap uses the same `ASSET-01i-01j` sort key; no fixed overlap area is required. |
| ASSET-01m | All seven standees always face the battle camera. |
| ASSET-02a | Erick portrait uses `Asserts/portraits/family/erick-avatar.png`. |
| ASSET-02b | Mitzi portrait uses `Asserts/portraits/family/mitzi-avatar.png`. |
| ASSET-02c | Diego portrait uses `Asserts/portraits/family/diego-avatar.png`. |
| ASSET-02d | Hercules portrait uses `Asserts/portraits/family/hercules-avatar.png`. |
| ASSET-02e | Guardia portrait uses `Asserts/portraits/rivals/guardia-sin-memoria-portrait.png`. |
| ASSET-02f | Arquero portrait uses `Asserts/portraits/rivals/arquero-sin-memoria-portrait.png`. |
| ASSET-02g | Adepto portrait uses `Asserts/portraits/rivals/adepto-sin-memoria-portrait.png`. |
| ASSET-02h | Tuffy portrait uses `Asserts/portraits/family/tuffy-avatar.png`. |
| ASSET-02i | Tuffy generates no selectable or acting combat unit. |
| ASSET-03a | Board stone surfaces use the appearance of `Asserts/3d/Textures/stylized_stone_floor.png`: moss-green Family side, blue-gray central dais, dark-purple Cult side. |
| ASSET-03b | Left Family entrance shows a door and paired torches; the door must not be misplaced at the right Cult exit. |
| ASSET-03c | Perimeter shows Kenney modular/corner walls outside playable bounds. |
| ASSET-03d | Right Cult exit shows a metal-bar gate and the lower-right exit shows wide stairs; `doorway.glb` must not substitute for the gate. |
| ASSET-03e | `(3,4)` and `(7,5)` show rubble. |
| ASSET-03f | `(10,1)` shows a nonblocking Cult banner; do not place it on obstacle `(9,6)` instead of the chest. |
| ASSET-03g | The Family-side Memory Tree has a recognizable trunk and canopy; `oaktoonbranchesgreen.png` is canopy foliage material, not an independent giant rectangular standee. |
| ASSET-03h | Family Crystal at `(6,4)` is a 3D objective with stone base, metal ring, and glowing blue crystal; `chapter01-crystal-pedestal.png` is not a camera-facing central standee. |
| ASSET-03i | Family Terrace and Archive Grass floor instances use `Asserts/3d/kaykit_dungeon/Models/gltf/tileBrickA_large.glb`; Memory Stone Road, Crystal Dais, Broken Ground, Cult Area, and all other board tiles use `Asserts/3d/kaykit_dungeon/Models/gltf/tileBrickB_large.glb`. |
| ASSET-03j | With no movement/attack/ability preview, KayKit brick seams and model contours remain recognizable; opaque highlight boxes must not continuously obscure them. |
| ASSET-03k | Initial Chapter One includes these nonblocking narrative decorations: Family blue cluster `(0,2)`; Cult purple clusters `(9,1) (10,6)`; Family runes `(1,3) (4,4) (6,3) (7,4)`; Cult runes `(8,4) (9,2) (9,4) (10,4)`; Family shrines `(1,2) (5,3)`; Cult shrines `(8,3) (11,1)`; crate pile `(3,7)`; small ruins `(2,3) (7,5)`. Local visual offsets needed by the original composition are allowed. |
| ASSET-03l | Besides `(10,1)`, a second nonblocking Cult banner appears near `(10,6)`; both are on the Cult side. |
| ASSET-03m | Left Family entrance combines a dark stone frame, door, and two torches; the frame must not look like two isolated bright square columns without a top connection. |
| ASSET-04a | Detected/triggering traps use orange-red diamond hazard runes, not `Asserts/branding/logo-main-tight.png`; that logo appears on no board cell, trap, attack range, or ability marker. |
| ASSET-05a | Decorations add no rule blocking outside `DATA-03`. |
| ASSET-05b | Every fixed obstacle in `DATA-03` is rule-occupied and impassable. |
| ASSET-05c | Movement highlights exclude fixed obstacles in `DATA-03`. |
| ASSET-05d | Original Chapter One obstacles: rubble `(3,4)`, column `(4,2)`, column `(10,2)`, rubble `(7,5)`, obelisk `(11,2)`, brambles `(4,6)`, chest `(9,6)`; Family Crystal at `(6,4)`. |
| ASSET-05e | A cell outside `DATA-03` and not dynamically occupied by a living unit is not rejected because of purely decorative visuals. |
| ASSET-06a | Every named combat identity keeps one fixed correspondence across battlefield standee, HUD portrait, dialogue portrait, targeting feedback, results, and save/progression summaries; no image belonging to another named identity may substitute for it. |
| ASSET-06b | Standees and portraits are role-specific: the seven mapped standees render battlefield units, while the eight mapped portraits render 2D UI/dialogue; a portrait cannot replace a battlefield standee, and a standee cannot replace a portrait. |
| ASSET-06c | Tuffy's mapped portrait is used only for guide/dialogue presentation and never creates a cell occupant, selectable target, HUD combat card, turn action, or results combatant. |
| ASSET-06d | The Guard, Archer, and Adept use their own rival standee/portrait pairs and gameplay roles; `capitan`, `oraculo`, `tirador`, and concept-sheet art cannot replace any of those three Chapter One enemies. |
| ASSET-06e | Each mapped environment asset or procedural construction appears at the role/anchor stated by ASSET-03-05; importing, preloading, hiding offscreen, or listing a file without visibly assembling it in the corresponding runtime scene is not asset use. |
| ASSET-06f | Asset reuse never changes rules: decorative mappings remain nonblocking, every DATA-03 obstacle remains blocking, and visual substitutions cannot change unit identity, cell occupancy, height, range, or damage. |

### 6.5 Interaction, Turns, and Common Actions

| ID | Formal requirement |
|---|---|
| TURN-01a | Turn 1 starts in the player phase. |
| TURN-01b | Each living Family member commits at most one action per player phase. |
| TURN-02a | Successful movement consumes one action eligibility. |
| TURN-02b | Successful normal attack consumes one action eligibility. |
| TURN-02c | Successful Defend consumes one action eligibility. |
| TURN-02d | Successful Wait consumes one action eligibility. |
| TURN-02e | Successful Eagle Slash consumes one action eligibility. |
| TURN-02f | Successful Magic consumes one action eligibility. |
| TURN-02g | Successful Single Heal consumes one action eligibility. |
| TURN-02h | Successful Team Heal consumes one action eligibility. |
| TURN-02i | The four unique actions are “Eagle Slash”, “Magic”, “Single Heal”, and “Team Heal”. Both heals share one “Heal” button, distinguished by targeting an adjacent ally versus Hercules himself. |
| TURN-03 | After everyone acts, the enemy phase begins automatically. |
| TURN-04a | Clicking End Turn in player phase opens exactly one confirmation modal. |
| TURN-04b | Its first valid confirmation forfeits all remaining actions and begins enemy phase. |
| TURN-04c | Cancel closes it and retains turn state. |
| TURN-04d | Esc or closing the modal is equivalent to `TURN-04c`. |
| TURN-04e | Double-click/repeated confirm advances phase only once. |
| TURN-04f | Activating End Turn in enemy phase neither opens a modal nor changes phase. |
| INTERACTION-01 | While idle, clicking a living unacted Family member shows their action menu. |
| INTERACTION-01a | A living unacted Family member can be selected by clicking their visible battlefield standee. |
| INTERACTION-01b | The same member can also be selected by clicking their corresponding card in the left party panel. |
| INTERACTION-01c | Either selection route highlights the same member and opens that member's action panel on the right; neither route consumes an action. |
| INTERACTION-02 | Switching to another actionable member consumes no action. |
| INTERACTION-03a | Esc or empty-board click while selected cancels selection and returns to idle. |
| INTERACTION-03b | Esc in action menu returns to selected state for the same unit. |
| INTERACTION-04 | Esc or right-click in target/route preview returns to action menu and clears preview. |
| INTERACTION-05 | Clicking a legal target/destination only previews; the player must click a separate Confirm Action button. |
| INTERACTION-06 | Repeated input during resolution, enemy performance, or dialogue creates no extra action. |
| INTERACTION-07a | Illegal-target input executes the unified rejection transaction. |
| INTERACTION-07b | Wrong-faction input executes the unified rejection transaction. |
| INTERACTION-07c | Out-of-range input executes the unified rejection transaction. |
| INTERACTION-07d | Input on an acted unit executes the unified rejection transaction. |
| INTERACTION-07e | Input on a dead unit executes the unified rejection transaction. |
| INTERACTION-07f | Unified rejection changes no unit position. |
| INTERACTION-07g | Unified rejection changes no unit/crystal HP. |
| INTERACTION-07h | Unified rejection changes no action eligibility. |
| INTERACTION-07i | Unified rejection changes no experience. |
| INTERACTION-07j | Unified rejection changes no save. |
| INTERACTION-07k | Unified rejection changes no outcome. |
| INTERACTION-08 | Illegal input shows text, color, or disabled feedback for at least 0.5 seconds. |
| STATE-01 | “Select” determines actor/action type only and changes no board values. |
| STATE-02 | “Preview” shows only legal targets, range, or route and changes no board values. |
| STATE-02a | Clicking “Defend” shows a no-target preview stating “Next applicable damage halved”, not yet committed. |
| STATE-02b | Clicking “Wait” shows a no-target preview stating “End this unit's action”, not yet committed. |
| STATE-02c | Both show Confirm Action and allow Esc back to action menu. |
| STATE-03 | “Confirm” occurs only when the player clicks Confirm Action in preview; cancellation locks from that valid input. |
| STATE-04a | Non-movement rule commit point is completion of outcome check `UNIFIED_SEQUENCE-05`; eligibility is consumed there. |
| STATE-04b | Same for a surviving mover. |
| STATE-04c | For a mover dying en route, commit is completion of `UNIFIED_SEQUENCE-05`; eligibility follows `TRAP-03e`. |
| STATE-05a | A nonterminal action flow ends after `UNIFIED_SEQUENCE-06d`, on input unlock or phase advance. |
| STATE-05b | A terminal action ends when `ENDGAME_FLOW-02b`, `03b`, `04b`, or `05` begins showing the sole results page. |
| MOVEMENT-01 | Highlight only destinations reachable through four-direction contiguous empty cells at cost ≤ movement; cost is 1 per cell. |
| MOVEMENT-01a | Clicking Move immediately displays clearly distinguishable highlights on the board for all and only the legal destination cells defined by `MOVEMENT-01`, `MOVEMENT-02`, `MOVEMENT-06`, and `MOVEMENT-07`; the highlights remain until the movement preview is canceled or committed. |
| MOVEMENT-02 | Paths cannot leave bounds, move diagonally, or cross obstacles, crystal, or living units. |
| MOVEMENT-03 | Equal-cost paths break ties by neighbor order Up, Left, Right, Down. |
| MOVEMENT-04 | Preview shows actual cell-by-cell route and cost; confirmation follows it. |
| MOVEMENT-05 | Illegal destination changes neither position nor eligibility. |
| MOVEMENT-06 | Destination differs from origin and route enters at least one adjacent cell. |
| MOVEMENT-07 | Current cell is neither shown nor confirmable as a legal destination. |
| ATTACK-01 | Normal attack selects only living enemies within Manhattan-distance range. |
| ATTACK-01a | Clicking Attack immediately displays clearly distinguishable board-cell highlights for the selected member's Manhattan-distance normal-attack range; living enemies that satisfy `ATTACK-01` remain visibly identifiable as legal targets until the attack preview is canceled or committed. |
| ATTACK-02 | Normal attack ignores walls, units, and height for line of sight and deals current attack damage. |
| ATTACK-03a | Unit HP has minimum 0. |
| ATTACK-03b | At 0 HP a unit immediately enters dead-rule state and releases its cell. |
| DEFENSE-01 | Defend consumes action and displays status; clears only after the next applicable positive-damage resolution. |
| DEFENSE-02 | Defense persists across turns until applied, death, battle end, or return to menu. |
| WAIT-01 | Wait only consumes action; it changes no position, HP, defense, or ability resource. |

### 6.6 Damage, Abilities, Traps, and Crystal

| ID | Formal requirement |
|---|---|
| DAMAGE-01 | Damage order: base → Mitzi aura (normal attacks only) → defense halves, rounded up → minimum 1 → subtract HP. |
| DAMAGE-02a | Normal attacks use Mitzi's aura. |
| DAMAGE-02b | Normal attacks use defense. |
| DAMAGE-02c | Magic ignores Mitzi's aura. |
| DAMAGE-02d | Magic uses defense. |
| DAMAGE-02e | Eagle Slash ignores Mitzi's aura. |
| DAMAGE-02f | Eagle Slash uses defense. |
| DAMAGE-02g | Traps ignore Mitzi's aura. |
| DAMAGE-02h | Traps ignore defense. |
| DAMAGE-02i | Trap damage does not clear existing defense. |
| MAGIC-01 | Diego may choose any board cell within his range as center, ignoring occupancy, obstacles, height, and line of sight. |
| MAGIC-02 | Every living enemy within Manhattan radius 1 of center takes current attack +1; allies/crystal are unharmed. |
| MAGIC-03 | With no living enemy in area, confirmation is unavailable and no action is consumed. |
| HEAL-01 | Single heal targets only a wounded living ally at distance 1 (not self), restoring current single-heal amount up to max HP. |
| HEAL-02a | Targeting Hercules himself with Heal enters team-heal preview; the caster is included among candidates. |
| HEAL-02b | Team heal restores 2 HP to each living Family member below max HP. |
| HEAL-02c | Dead Family members receive no team heal. |
| HEAL-02d | Full-HP members receive no team heal and show no 0-heal feedback. |
| HEAL-02e | When only some survivors are wounded, only those members are healed. |
| HEAL-02f | Team heal shows positive feedback only at members whose HP is actually restored. |
| HEAL-03a | Team heal can be confirmed when at least one living Family member is below max HP. |
| HEAL-03b | Otherwise it cannot be confirmed and consumes no action. |
| HEAL-04 | Level-ups increase only single heal; team heal permanently remains 2. |
| LIMIT-01 | Erick gains 1 charge the first time each action actually deals positive damage, at most once per action. |
| LIMIT-02 | Erick gains 1 charge each time he actually takes positive damage; normal attacks, magic, Eagle Slash, and traps count. |
| LIMIT-03a | Eagle Slash becomes available at 3/3. |
| LIMIT-03b | It targets only living enemies at Manhattan distance 1. |
| LIMIT-03c | It deals three times Erick's current attack to a legal target. |
| LIMIT-03d | Gauge resets to zero after its damage resolves. |
| LIMIT-04 | If gauge is not full or target is illegal, it deals no damage and consumes neither gauge nor action. |
| TRAP-01a | At battle start, all three untriggered traps are hidden. |
| TRAP-01b | While Mitzi lives, hidden traps entering Manhattan distance 2 from her become detected and visible. |
| TRAP-01c | Detected traps remain visible after Mitzi leaves range or dies. |
| TRAP-01d | Detected-visible state persists across player/enemy phases. |
| TRAP-01e | Undetected traps outside range remain hidden until detected or triggered. |
| TRAP-01f | Entering a hidden trap reveals it and plays trigger feedback before it becomes consumed. |
| TRAP-01g | A consumed trap is removed from board trap state and never appears/triggers again. |
| TRAP-02 | When a Family member enters a trap cell step-by-step, they stop, take 1 damage ignoring aura/defense, and the trap is consumed. |
| TRAP-03a | If the unit survives, it continues the remaining confirmed route. |
| TRAP-03b | On reaching destination alive, mark “movement complete”; movement XP is added only at `UNIFIED_SEQUENCE-04b`. |
| TRAP-03c | Lethal-trap feedback appears at the trap cell where death occurred. |
| TRAP-03d | Lethal traps release rule occupancy at `UNIFIED_SEQUENCE-03`; the cell is then traversable. |
| TRAP-03e | Lethal-trap action eligibility is considered consumed. |
| TRAP-03f | Lethal-trap movement awards no movement XP. |
| AURA-01 | At normal-attack resolution start, if Mitzi lives and target is within 2, reduce base damage by 1. |
| CRYSTAL-01 | An enemy adjacent to crystal with no legal Family target in range may attack crystal for fixed 1 damage. |
| CRYSTAL-02 | Crystal value, damage number, and visuals update synchronously in the same resolution. |
| CRYSTAL-03 | The first transition from above 3 HP to 2 or below triggers low-HP dialogue once. |

### 6.7 Enemies, Resolution Order, and Outcomes

| ID | Formal requirement |
|---|---|
| ENEMY-01a | Lock player tactical input immediately when enemy phase begins. |
| ENEMY-01b | Activation queue contains exactly enemies alive at phase start. |
| ENEMY-01c | Generate that queue once per enemy phase. |
| ENEMY-01d | Later enemy movement does not reorder it. |
| ENEMY-01e | Later enemy death does not reorder it; skip a dead member's turn. |
| ENEMY-02a | Sort by phase-start x descending. |
| ENEMY-02b | For equal x, sort phase-start y ascending. |
| ENEMY-02c | Each living queued enemy activates at most once that phase. |
| ENEMY-03a | If a Family target is in range, enemy only normal-attacks. |
| ENEMY-03b | Compare HP ratios of candidates A/B with integer cross-products `A current HP×B max HP` and `B current HP×A max HP`, without float conversion/rounding. |
| ENEMY-03c | Strictly lower HP ratio wins; equal products continue to next tie break. |
| ENEMY-03d | Equal ratios choose nearer Manhattan distance. |
| ENEMY-03e | Equal ratio/distance chooses earlier Erick → Mitzi → Diego → Hercules. |
| ENEMY-04 | With no Family attack target but crystal attack available, attack only crystal. |
| ENEMY-05 | With no attack, choose lowest-path-cost standable adjacent crystal cell; ties: Up `(6,3)`, Left `(5,4)`, Right `(7,4)`, Down `(6,5)`. |
| ENEMY-05a | Move along a lowest-cost path exactly `min(current movement, path length)` steps, without unjustified early stop. |
| ENEMY-05b | Do not attack after enemy movement. |
| ENEMY-06 | Enemy routes use `MOVEMENT-03` and same bounds/occupancy/obstacles; enemies do not trigger traps. |
| ENEMY-07a | With no legal attack/move, Wait and end activation. |
| ENEMY-07b | After all queued members, increment turn by 1. |
| ENEMY-07c | Then restore eligibility to all living Family members. |
| ENEMY-07d | Then switch to player phase. |
| RESOLUTION-01 | Non-movement actions execute `UNIFIED_SEQUENCE-01-08`. |
| RESOLUTION-01a | Movement subprocess only repeats “enter next cell → check trap → apply trap damage → detect death”; it adds no XP, checks no outcome, and plays no feedback. |
| RESOLUTION-01b | If alive and not at destination after a death check, enter next route cell. |
| RESOLUTION-01c | On reaching destination alive, end subprocess and report “movement complete.” |
| RESOLUTION-01d | On death, immediately stop remaining route and report “died during movement.” |
| RESOLUTION-02a | On terminal conditions, determine one outcome reason; simultaneous win/loss chooses loss. |
| RESOLUTION-02b | Immediately freeze tactical input, positions, HP, crystal, and enemy queue, but not yet match XP or results data. |
| RESOLUTION-02c | Add survival reward per `XP-06a-06b`. |
| RESOLUTION-02d | Then freeze each character's match XP count. |
| RESOLUTION-02e | Use frozen match XP for `PROGRESSION-02-05` credit/level calculation. |
| RESOLUTION-02f | Then lock final outcome, progression, and results-page data. |
| UNIFIED_SEQUENCE-01 | Lock input first after any action confirmation. |
| UNIFIED_SEQUENCE-02 | Then execute only damage, healing, or pure movement subprocess `RESOLUTION-01a-01d`. |
| UNIFIED_SEQUENCE-03 | After return, centrally process all deaths caused by the action and release each dead unit's rule occupancy once. |
| UNIFIED_SEQUENCE-04a | Then centrally add behavior XP; count each behavior once only here. |
| UNIFIED_SEQUENCE-04b | Add 4 from `XP-01a` on “movement complete”; add 0 per `XP-01b` on “died during movement.” |
| UNIFIED_SEQUENCE-05 | Then execute exactly one outcome check. |
| UNIFIED_SEQUENCE-06a | If nonterminal, enqueue normal events per `STORY-17b-17c`. |
| UNIFIED_SEQUENCE-06b | Then play this action's feedback first. |
| UNIFIED_SEQUENCE-06c | Then play queued normal dialogue with tactical input locked. |
| UNIFIED_SEQUENCE-06d | After all normal dialogue closes, unlock input or advance phase. |
| UNIFIED_SEQUENCE-07a | If terminal, discard normal events not yet played at this checkpoint. |
| UNIFIED_SEQUENCE-07b | Then play action feedback, including death feedback. |
| UNIFIED_SEQUENCE-07c | After feedback, execute `RESOLUTION-02a-02f`. |
| UNIFIED_SEQUENCE-08 | After `RESOLUTION-02f`, execute only `ENDGAME_FLOW-01-05`; no normal story event caused by the action plays. |
| OUTCOME-01 | Last enemy death, without simultaneous defeat, triggers Victory terminal handling exactly once. |
| OUTCOME-02a | Crystal HP 0 triggers “Crystal Shattered.” |
| OUTCOME-02b | Crystal above 0 and last Family member death triggers “Family Wiped Out.” |
| OUTCOME-02c | If both occur in one resolution, reason is “Crystal Shattered.” |
| OUTCOME-03a | After `RESOLUTION-02f`, cancel enemy activations and queued input not yet begun. |
| OUTCOME-03b | After it, positions, HP, crystal, and frozen match XP never change. |
| OUTCOME-03c | After it, final outcome and progression never change. |
| PLAYABILITY-01 | From the no-record initial state `DATA-01-17`, at least one legal sequence using only normal player input here and none of `PROHIBITION-01a-01g` can trigger `OUTCOME-01` victory. |
| PLAYABILITY-02 | Any legal strategy may satisfy `PLAYABILITY-01`; the Section 3.4 example is neither mandatory nor guaranteed. |

### 6.8 Story

| ID | Formal requirement |
|---|---|
| STORY-01 | Each segment shows the speaker portrait, name, English body, and a visible button labeled “Continue”; tactical/camera input is locked. |
| STORY-02 | Clicking the visible Continue button or pressing Esc advances exactly one segment; double-click does not skip two. |
| STORY-02a | When the final segment in a dialogue event closes, the dialogue panel, portrait, speaker name, body, and Continue button all disappear; none remains over the interactive battle or following results page. |
| STORY-03 | Opening event triggers once per battle. |
| STORY-04 | Opening 1, Erick: “The Cult is attacking the Crystal. The moment they touch it, this memory will begin to shatter.” |
| STORY-05 | Opening 2, Mitzi: “We don't have to win a war today. We only have to protect what reminds us who we are.” |
| STORY-06 | Opening 3, Diego: “Then let them come. I'll hold this red light.” |
| STORY-07 | Opening 4, Hercules: “Hercules stands before the Crystal. No one gets past without saying hello.” |
| STORY-08 | Opening 5, Tuffy: “Think in turns: block the paths first, then punish anyone who gets too close.” |
| STORY-09 | First enemy phase once per battle, Tuffy: “Watch their steps. The Cult does not attack at random, but it will change routes when the path is blocked.” |
| STORY-10 | After first Family positive damage once per battle, Hercules: “Take a deep breath. As long as we're together, this memory won't shatter.” |
| STORY-11 | After first enemy death once per battle, Mitzi: “One down. Don't give up the center; the Crystal is still calling to them.” |
| STORY-12 | `CRYSTAL-03`, Diego: “The light is fading. One more hit on the Crystal, and we'll have no room for error.” |
| STORY-12a | If an enemy attack triggers it, pause queue and immediately play `STORY-12` before next activation. |
| STORY-12b | After it closes, resume with next unactivated living enemy; completed enemies do not repeat. |
| STORY-13 | On first level-up from `RESOLUTION-02e`, Tuffy gives one separate pre-results line: “The memory answered us. Protecting it will make you stronger, too.” |
| STORY-14 | Victory 1, Erick: “The Crystal is still whole. The Family's memory has survived its first trial.” |
| STORY-15 | Victory 2, Tuffy: “A memory guarded by love will always find its way home.” |
| STORY-16a | Crystal Shattered, Erick: “The Cult touched the Crystal. We have to try again before the memory goes dark.” |
| STORY-16b | Family Wiped Out, Tuffy: “The Family has fallen, but the Crystal still shines. Let the memory help us stand again.” |
| STORY-17a | Enqueue first-enemy-phase event after queue generation, before first activation. |
| STORY-19 | Play `STORY-09` immediately after enqueue; first enemy cannot act before it fully closes. |
| STORY-17b | Enqueue wound, kill, and low-crystal events after their atomic resolution's outcome check. |
| STORY-17c | Multiple normal events at one checkpoint play: first Family wound → first kill → low crystal. |
| STORY-18a | On terminal condition discard unplayed normal story events per `UNIFIED_SEQUENCE-07a`; after final lock play only corresponding ending. |
| STORY-18b | First-level-up dialogue plays after ending dialogue and before results. |
| ENDGAME_FLOW-01 | After `RESOLUTION-02f`, first play `STORY-14-16b` matching outcome reason. |
| ENDGAME_FLOW-02a | After two victory segments, play `STORY-13` if first level-up occurred. |
| ENDGAME_FLOW-02b | Otherwise directly open sole victory results page. |
| ENDGAME_FLOW-03a | After Crystal Shattered dialogue, play `STORY-13` if first level-up occurred. |
| ENDGAME_FLOW-03b | Otherwise directly open sole Crystal Shattered results page. |
| ENDGAME_FLOW-04a | After Family Wiped Out dialogue, play `STORY-13` if first level-up occurred. |
| ENDGAME_FLOW-04b | Otherwise directly open sole Family Wiped Out results page. |
| ENDGAME_FLOW-05 | After `STORY-13` closes, immediately open sole results page matching locked reason. |

### 6.9 Experience, Progression, Results, and Saving

| ID | Formal requirement |
|---|---|
| XP-01a | Reaching movement destination alive earns 4 match XP. |
| XP-01b | Movement interrupted by trap death earns no movement XP. |
| XP-02 | One normal attack, Magic, or Eagle Slash action hitting ≥1 enemy earns 6 once, not per target. |
| XP-03 | Actor earns extra 16 per enemy killed, stackable with damage XP. |
| XP-04 | A heal action actually restoring ≥1 HP earns 8 once, not per member/point. |
| XP-05a | Successful Defend earns 6. |
| XP-05b | Successful Wait earns 3. |
| XP-06a | Victory adds 10 match XP to each living Family member before freezing. |
| XP-06b | Either defeat adds 4 match XP to each living Family member before freezing. |
| XP-07 | Dead members retain XP earned before death but receive no later event/survival reward. |
| PROGRESSION-01 | Without records, use `DATA-14-17`. |
| PROGRESSION-02a | Behavior XP and survival reward enter settlement XP once only at `RESOLUTION-02e`. |
| PROGRESSION-02b | Level calculation occurs after match XP freeze and before final lock. |
| PROGRESSION-02c | Battle actions do not immediately increase permanent XP, level, or stats. |
| PROGRESSION-03 | At threshold: subtract threshold, level +1, next threshold +20; multiple levels allowed. |
| PROGRESSION-03a | Sequentially use each threshold: level 1, XP 250, threshold 100 becomes level 3, XP 30, threshold 140. |
| PROGRESSION-04a | Each Hercules level adds 2 max HP. |
| PROGRESSION-04b | Each Erick/Mitzi/Diego level adds 1 max HP. |
| PROGRESSION-04c | Reaching any even level adds 1 attack. |
| PROGRESSION-04d | Reaching an odd level does not change attack. |
| PROGRESSION-05 | Hercules reaching an even level adds 1 single heal; team heal unchanged. |
| PROGRESSION-06a | If a results-page survivor gains max HP from levels, current HP rises by same amount. |
| PROGRESSION-06b | A dead character remains at 0 HP and “Fallen” after results leveling. |
| PROGRESSION-06c | Next battle starts all members at permanent max HP. |
| RESULT-01a | Victory title “Victory”; reason “All enemies have been defeated”. |
| RESULT-01b | Crystal loss title “Defeat”; reason “The Family Crystal has shattered”. |
| RESULT-01c | Wipeout title “Defeat”; reason “All Family members have fallen”. |
| RESULT-02a | Results show portrait and alive/dead state for each of four members. |
| RESULT-02b | Results show before/after level and match XP earned for each. |
| RESULT-02c | Results show post-settlement current XP/next threshold for each. |
| RESULT-02d | Results show this change to max HP and attack for each. |
| RESULT-02e | Hercules shows single-heal change; the other three show “—” in healing. |
| RESULT-03a | Survivors and dead both settle XP earned before death. |
| RESULT-03b | Results offer only Return to Main Menu; Esc is equivalent; no direct retry. |
| DEFEAT_RESOLUTION-01 | Either failure page uses frozen match XP and temporary level result from `RESOLUTION-02d-02e`. |
| DEFEAT_RESOLUTION-02 | Failure page level, XP/threshold, max HP, attack, and single heal show temporary post-settlement values. |
| DEFEAT_RESOLUTION-03 | Failure attribute-change fields show before/after temporary differences. |
| DEFEAT_RESOLUTION-04 | Temporary levels exist only on current failure page; leaving/closing discards all. |
| DEFEAT_RESOLUTION-05 | Reentering after failure restores level, XP, threshold, max HP, attack, and heals to pre-battle permanent records. |
| PERSISTENCE-01 | Victory writes post-settlement level, XP, threshold, max HP, attack, single heal, and fixed team heal for all four to current slot. |
| PERSISTENCE-02 | Commit occurs before results first fully displays; visible results means success. |
| PERSISTENCE-03a | Public pre-commit boundary: close during ending/level-up dialogue after victory lock; reopen retains complete old progression. |
| PERSISTENCE-03b | Public post-commit boundary: close after victory results first fully displays; reopen contains complete new progression. |
| PERSISTENCE-03c | Only these player-observable close/reopen boundaries are required; frame-forced termination and internal write-window behavior are unspecified. |
| PERSISTENCE-04a | Failure writes back no match XP or level. |
| PERSISTENCE-04b | Failure writes back no max HP, attack, or heals. |
| PERSISTENCE-04c | After failure menu/reopen, restore pre-battle permanent record. |
| PERSISTENCE-05 | Reenter using permanent full-HP attributes `DATA-18a-18h`, rebuilding board from `DATA-01-13` instead of mid-battle state. |

### 6.10 Pause, Camera, Options, and Layout

| ID | Formal requirement |
|---|---|
| PAUSE-01a | Esc first cancels selection, action menu, or preview layer-by-layer per `INTERACTION-03a-04`. |
| PAUSE-01b | Esc opens pause only from battle idle. |
| PAUSE-02a | Pause shows only “Continue”, “Options”, and “Return to Main Menu”. |
| PAUSE-02b | Repeated Esc does not stack pause layers. |
| PAUSE-03a | Opening pause from idle stops turn count, phase, units, and crystal. |
| PAUSE-03b | Continue restores the exact pre-pause state. |
| PAUSE-04 | Esc/close in paused options returns only to pause, not battle. |
| PAUSE-05a | Esc during resolution lock/enemy performance does not open pause. |
| PAUSE-05b | In dialogue Esc only advances one segment per `STORY-02`. |
| PAUSE-06a | Return to Main Menu opens exactly one English abandon-confirmation modal. |
| PAUSE-06b | Its Cancel returns to the same pause layer. |
| PAUSE-06c | Esc/close is equivalent to `PAUSE-06b`. |
| PAUSE-07a | After canceling abandon, all unit positions are unchanged. |
| PAUSE-07b | Turn and phase are unchanged. |
| PAUSE-07c | Unit/crystal HP is unchanged. |
| PAUSE-07d | Action eligibility is unchanged. |
| PAUSE-07e | Match XP is unchanged. |
| PAUSE-06e | First valid abandon confirmation discards temporary battle state and returns to the sole main menu. |
| PAUSE-06f | Confirming abandon writes no match progression. |
| PAUSE-06g | Double-click/repeated confirmation transitions only once. |
| CAMERA-01a | Initial battle framing fully shows four corners of 12×9 board, crystal, and seven initial units. |
| CAMERA-01b | When unlocked, WASD, arrows, and middle-button drag all pan camera. |
| CAMERA-01c | Pan bounds keep at least 81 cell centers visible at all times. |
| CAMERA-02a | C restores `CAMERA-01a` initial framing. |
| CAMERA-02b | Camera operation changes no selection, route, unit state, or board rule. |
| HUD-01a | HUD shows chapter name and current objective. |
| HUD-01b | HUD shows crystal current/max HP. |
| HUD-01c | HUD shows living enemy count. |
| HUD-01d | HUD shows turn and current phase. |
| HUD-01e | HUD shows party panel for four Family members. |
| HUD-01f | Selected-unit info shows name, current/max HP, attack, movement, range, and acted/actionable state. |
| HUD-01g | Each member has an independent card with portrait, name, level, action state, HP bar, and current/max HP; Erick also shows current Limit/3. |
| HUD-01h | Selected member card has a border/background highlight directly distinguishable from unselected cards. |
| HUD-03a | Selecting Erick additionally shows current Limit/3. |
| HUD-03b | Selecting Mitzi additionally shows the fixed text “Trap detection radius: 2; Evasion aura radius: 2; Normal attack damage reduction: 1”. |
| HUD-03c | Selecting Diego additionally shows “Magic: Attack +1, radius 1”. |
| HUD-03d | Selecting Hercules additionally shows current single heal and team heal 2. |
| HUD-04a | All four action panels contain “Move”, “Attack”, “Defend”, and “Wait”. |
| HUD-04b | Erick's contains “Eagle Slash”. |
| HUD-04c | Diego's contains “Magic”. |
| HUD-04d | Hercules's contains “Heal” and the hint “Adjacent ally: Single Heal; Self: Team Heal”. |
| HUD-04e | Clicking Heal highlights every adjacent, living, non-full ally and Hercules himself when `HEAL-03a` holds. |
| HUD-04f | Selecting adjacent ally enters Single Heal preview. |
| HUD-04g | Selecting Hercules enters Team Heal preview. |
| HUD-04h | Either preview commits only after Confirm Action. |
| HUD-04i | Esc returns to heal-target selection without consuming action. |
| HUD-02a | HUD values synchronize with real state after every atomic resolution. |
| HUD-02b | Acted units show unavailable state. |
| HUD-02c | Dead units show dead state. |
| HUD-02d | Currently unavailable actions show disabled state. |
| OPTIONS-01a | Quality offers “Low”, “Medium”, and “High”. |
| OPTIONS-01b | Options shows fixed “1280×720, 16:9, Windowed” read-only and offers no other resolution/aspect/fullscreen entry. |
| OPTIONS-01c | Options contains only quality, fixed display info, “Apply”, and “Close”. |
| OPTIONS-02a | First launch defaults to High and `1280×720 (16:9)` windowed. |
| OPTIONS-02b | Every launch forces that display mode; legacy resolution/aspect/fullscreen fields cannot change it. |
| OPTIONS-03a | Apply immediately applies/saves quality with no display preview/countdown. |
| OPTIONS-03b | Unapplied quality changes are discarded by Close, Esc, menu return, exit, or reopen. |
| OPTIONS-03c | Applied quality persists across menu, battle, and reopen, independent of active slot. |
| OPTIONS-03d | Switching/creating/overwriting slots changes neither applied quality nor fixed window specification. |
| LAYOUT-01a | At `1280×720`, six menu entries do not overlap/clip and remain onscreen. |
| LAYOUT-01b | Chapter name, objective, win/loss conditions, and hint do not overlap/clip and remain onscreen. |
| LAYOUT-01c | `HUD-*` information does not occlude each other and remains onscreen. |
| LAYOUT-01d | Dialogue portrait, name, body, and Continue do not overlap/clip and remain onscreen. |
| LAYOUT-01e | Results uses two compact columns; all four records, settlement explanation, and Return to Main Menu are visible without scrolling to exit. |
| LAYOUT-01f | Quality, fixed spec, Apply, and Close are visible/operable. |
| LAYOUT-01g | Protection objective, win/loss conditions, and tactical hint occupy separate bounded areas; Start Battle/Back are outside them. |
| LAYOUT-01h | The battle dialogue main panel is anchored at the bottom of the battle view above the bottom status bar; the crystal and ≥4 initial Family members remain distinguishable, and the panel does not cover the status bar. |
| LAYOUT-01i | Menu, slots, chapter, and options retain ≥24 px visible safe margin; overflow scrolls operably instead of clipping entries. |
| LAYOUT-01j | Both battle side panels lie between chapter and status bars; dynamic action count cannot expand them offscreen. |
| LAYOUT-01k | Right panel directly shows current-unit summary, target hint, and End Turn; only action list scrolls internally and never hides End Turn/moves whole HUD. |
| LAYOUT-01l | Dialogue box is horizontally centered with ≥24 px on each side; body line width stays within panel. |
| LAYOUT-01m | Results uses two columns×two rows; cards, explanation, and Return button stay within client area. Vertical scrolling allowed only below supported size. |
| LAYOUT-01n | Persistent top bar ≤60 px, bottom bar ≤48 px; they do not further compress board vertical view. |
| LAYOUT-01o | In initial camera, corner centers, crystal, and seven units lie outside persistent panels/bars; corner centers are ≥8 px from nearest side-panel edge. |
| LAYOUT-01p | Left panel ≤280×380 px; four cards fully show `HUD-01g`, with no bottom blank area taller than one card. |
| LAYOUT-01q | Right panel ≤280×480 px; summary, hint, End Turn always directly visible; only actions scroll. |
| LAYOUT-01r | Within every dialogue segment, the speaker portrait occupies the left side of the dialogue panel. |
| LAYOUT-01s | The speaker name appears directly below the portrait within the same left-side column. |
| LAYOUT-01t | The dialogue body occupies the area to the right of the portrait-and-name column and never overlays that column. |
| LAYOUT-02a | Final rendered size of menu entries, chapter body, fixed HUD labels, dialogue body, buttons, slot summaries, and results fields is ≥16 px. |
| LAYOUT-02b | Floating numbers, transient feedback, board coordinates, and decorative text are exempt. |
| LIFECYCLE-01a | A “10-second block” timer starts when legal navigation is accepted and ends when target page stabilizes. |
| LIFECYCLE-01b | Waiting for player reading/confirmation on menus, chapter, dialogue, modals, and results does not start it. |
| LIFECYCLE-01c | Target page absent 10 seconds after legal navigation blocks main flow. |
| LIFECYCLE-01e | Window ceasing to respond to player input blocks main flow. |
| LIFECYCLE-01f | Abnormal process exit during normal flow blocks main flow. |
| LIFECYCLE-01d | Logs/warnings that do not prevent continued player flow do not participate in acceptance. |

### 6.11 Appearance, Feedback, and Prohibited Interfaces

| ID | Formal requirement |
|---|---|
| PRESENTATION-01a | In final `1280×720` screenshots, choose one uniform text/border-free 16×16 block from each main panel of menu, information, HUD, dialogue, and results; average RGB differs from `#171020` by ≤24 per channel. |
| PRESENTATION-01b | In the same screenshots, choose one non-antialiased core pixel from a title/border on each page; RGB differs from `#D6B15E` by ≤24 per channel. |
| PRESENTATION-01c | Body text is readable in the final `1280×720` visuals; no particular font implementation or style architecture is required. |
| PRESENTATION-01d | Unspecified background images, gradients, decoration, and art similarity do not participate. |
| PRESENTATION-02a | Family highlight uses `#6FC3FF` or blue within 24 per RGB channel. |
| PRESENTATION-02b | Enemy/threat highlight uses `#C85CFF` or magenta within 24 per channel. |
| PRESENTATION-03a | Continue (when a save exists) and Start Battle use solid-gold primary buttons; same-page secondary entries use dark backgrounds so primary is distinguishable without reading. |
| PRESENTATION-03b | Normal, hover, keyboard focus, and pressed states of every button differ by background or border; disabled weakens text/border and differs from operable. |
| PRESENTATION-03c | Scrollbars appear only on overflow; nonoverflowing menu/options/actions/results leave no inert scrollbar or large reserved blank area. |
| FEEDBACK-01a | Movement visibly moves the unit cell-by-cell. |
| FEEDBACK-01b | Normal attack shows actual damage number for ≥0.5 s. |
| FEEDBACK-01c | Magic shows each target's actual damage for ≥0.5 s. |
| FEEDBACK-01d | Eagle Slash shows actual damage for ≥0.5 s. |
| FEEDBACK-01e | Trap shows actual damage for ≥0.5 s. |
| FEEDBACK-02a | Single heal shows actual restoration for ≥0.5 s. |
| FEEDBACK-02b | Team heal shows actual restoration at each recipient for ≥0.5 s. |
| FEEDBACK-02c | Defense shows persistent state and feedback when applied/cleared. |
| FEEDBACK-02d | Wait shows English feedback for ≥0.5 s. |
| FEEDBACK-03a | Death shows feedback and rule occupancy releases immediately at 0 HP. |
| FEEDBACK-03b | Player phase start shows the corresponding English title/banner. |
| FEEDBACK-03c | Enemy phase start shows the corresponding English title/banner. |
| FEEDBACK-03d | Final lock shows an English victory/defeat title/banner. |
| PROHIBITION-01a | Player UI has no debug interface directly increasing HP. |
| PROHIBITION-01b | No debug interface directly increasing XP/level. |
| PROHIBITION-01c | No debug interface directly killing any unit. |
| PROHIBITION-01d | No interface skipping battle and directly locking victory. |
| PROHIBITION-01e | No debug-console entry. |
| PROHIBITION-01f | No test-scene entry. |
| PROHIBITION-01g | UI does not directly publish guaranteed-victory steps or hidden internal state; normal tutorials, action explanations, objective conditions, and non-acceptance strategy background are exempt. |

## 7. Asset Index (Non-Acceptance Background)

| Directory | Purpose | Acceptance ID |
|---|---|---|
| `Asserts/branding/` | Logo | MENU-02c |
| `Asserts/maps/chapter01/` | Required main-menu background plus non-acceptance composition references | MENU-02a |
| `Asserts/portraits/` | Identity-locked UI/dialogue portraits | ASSET-02a-02i, ASSET-06a-06d |
| `Asserts/standees/` | Identity-locked battlefield standees | ASSET-01a-01m, ASSET-06a-06d |
| `Asserts/3d/`, `third_party/`, `textures/foliage/` | Role/anchor-locked environment | ASSET-03a-03m, ASSET-05a-05e, ASSET-06e-06f |
| Runtime-generated hazard runes | Trap reveal/trigger feedback | ASSET-04a, TRAP-01a-01g |

See `MaterialMapping-en.md` and `legal/LICENSES.md` for detailed mapping and licenses. Unquantified composition, atmosphere, and art similarity are reference only.

Non-acceptance depth-sort reproduction example: under the initial camera move Erick to `(5,4)` and Mitzi to `(4,4)`, then observe whether overlap follows `ASSET-01i-01j`; these coordinates and overlap area do not themselves participate.

## 8. Quality Mapping (No New Requirements)

| Topic | Sole acceptance source |
|---|---|
| Start, exit, reopen | MENU-*, EXIT-*, LIFECYCLE-01 |
| Three slots and saving | SAVE-*, PERSISTENCE-* |
| Success, two failures, replay | OUTCOME-*, RESULT-*, PERSISTENCE-* |
| Cancel, repeated input, pause | INTERACTION-*, CHAPTER-03-04, PAUSE-* |
| Combat and feedback | TURN-* through CRYSTAL-*, ENEMY-*, FEEDBACK-* |
| Battle composition/HUD share | SCENE-01h-01j, CAMERA-*, HUD-*, LAYOUT-01n-01q, LAYOUT-02* |
| No debug residue | PROHIBITION-01 |

Logs, caches, absolute paths, source structure, and unmapped generic advice do not participate.

## 9. Pre-Submission Self-Check (No New Requirements)

- [ ] `SAVE-*` covers empty/existing slots, cancel, tied times, and cross-process behavior;
- [ ] `INTERACTION-*`, `PAUSE-*` cover Esc, repeated confirmation, lock, and abandon;
- [ ] `SCENE-*`, `ASSET-*`, `LAYOUT-*` are observable from player visuals, and every character/environment asset preserves its mapped identity, role, and anchor;
- [ ] Combat, abilities, enemies, and both failures are independently decidable by ID;
- [ ] `XP-*` through `PERSISTENCE-*` cover alive/dead and victory/defeat combinations;
- [ ] Self-check introduces no gameplay requirement outside Section 6.

Non-acceptance suggestion: additionally record camera pitch/yaw/FOV, final font sizes, and keyboard focus after modal close at `1280×720` for regression comparison; these values and focus positions do not participate.

## 12. Dashboard Naming Tables and Control Scheme

This section mirrors `sp/benchmark/naming-tables.json` in human-readable form. It names only concepts already required in Section 6 and adds no gameplay requirement.

### 12.1 Numeric slots

| Slot | Meaning | Existing requirement source |
|---|---|---|
| `crystal_hp` | Current crystal HP | `HUD-01b`, `CRYSTAL-01`–`CRYSTAL-03` |
| `turn` | Current turn number | `TURN-01a`, `HUD-01d` |
| `active_unit_index` | Stable numeric index of the active Family unit | `TURN-02a`–`TURN-02e` |
| `unit_hp`, `unit_max_hp`, `unit_attack` | Selected unit's current combat values | `HUD-01f`–`HUD-01g` |
| `unit_xp`, `unit_level` | Selected unit's current progression | `XP-*`, `PROGRESSION-*` |
| `enemy_count` | Living enemy count | `HUD-01c` |

### 12.2 Entities and clickable targets

| Kind | Meaning | Allowed states or role | Existing requirement source |
|---|---|---|---|
| `family_unit` | A Family battlefield combatant | `ready`, `selected`, `acted`, `down`; clickable | `TURN-*`, `INTERACTION-01a` |
| `family_unit_card` | A Family member's card in the left party panel | `ready`, `selected`, `acted`, `down`; clickable when actionable | `HUD-01g`, `INTERACTION-01b–01c` |
| `enemy_unit` | An enemy combatant | `living`, `selected`, `down`; clickable | `ENEMY-*`, `ATTACK-*` |
| `legal_cell` | A legal board destination | `open`, `occupied`; clickable when legal | `MOVEMENT-*`, `STATE-02` |
| `illegal_cell` | A rejected board destination | `blocked`, `occupied`, `outside` | `MOVEMENT-*`, `INTERACTION-07a`–`07k` |
| `move_range_cell` | A board cell shown in the current Move range | `highlighted`; coincides with a legal destination | `MOVEMENT-01`, `MOVEMENT-01a` |
| `attack_range_cell` | A board cell shown in the current normal-attack range | `highlighted`; target legality remains governed by `ATTACK-01` | `ATTACK-01`, `ATTACK-01a` |
| `new_game_button`, `load_game_button`, `continue_button` | Main-menu entries | clickable targets | `MENU-*`, `SAVE-*` |
| `save_slot_empty`, `save_slot_existing`, `chapter_one_button`, `chapter_start_button` | Save and chapter-flow entries | clickable targets | `SAVE-*`, `CHAPTER-*`, `FLOW_ORDER-*` |
| `move_action`, `attack_action`, `defend_action`, `wait_action` | Common action controls | clickable targets | `MOVEMENT-*`, `ATTACK-*`, `DEFENSE-*`, `WAIT-01` |
| `magic_action`, `heal_action`, `limit_action` | Unique action controls | clickable targets | `MAGIC-*`, `HEAL-*`, `LIMIT-*` |
| `confirm_action_button`, `end_turn_button`, `confirmation_button` | Action commit, phase control, and the visible confirmation button in overwrite/End Turn/abandon modals | clickable targets while the matching control is visible | `INTERACTION-05`, `TURN-*`, `SAVE-08`–`SAVE-11a`, `PAUSE-06a`–`PAUSE-06g` |
| `dialogue_continue_button` | Advances the currently visible dialogue segment | clickable while dialogue is visible | `STORY-01`, `STORY-02` |
| `retry_button`, `main_menu_button`, `options_button` | Result and settings controls | clickable targets | `ENDGAME_FLOW-*`, `OPTIONS-*` |

### 12.3 Controls

Family selection uses clicks on either visible battlefield standees or their left-party-panel cards. Movement and targeting use clicks on action controls and board cells. Dialogue advances by clicking its visible Continue button or by pressing Escape. Enter confirms where the visible UI offers confirmation; Escape otherwise cancels or pauses according to the current modal. Camera controls remain those published in Section 6 and `TOOLCHAIN-en.md`.

## 13. Implementation Boundary

Section 6 remains the sole source of game-specific acceptance requirements. The dashboard only reports the public names above and cannot execute actions or declare completion. Internal node names, scene hierarchy, scripts, algorithms, and data structures remain implementation choices. Technical paths and engine behavior are defined by `TOOLCHAIN-en.md` and `BENCHMARK_MANIFEST.json`.
