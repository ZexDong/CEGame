# OpenRPG — Forest Reconstruction

Contract revision: `dashboard-contract-20261022-r2`

## 1. One-sentence task

Help the ghost by exploring the forest, earning four Coins, unlocking a house, solving its three-color wand puzzle, winning Bugcat and Wolf encounters, and finally making the grove safe (QUEST-01–06, PUZZLE-01–06, GHOST-01–02, COMBAT-01–13, END-01).

## 2. Scope

### 2.1 Included

| Requirements | Player goal |
|---|---|
| START-01–05 | Preserve opening, Gobot, movement, collision, and forest identity. |
| WORLD-01–03, QUEST-01–06 | Explore connected areas and earn access to the house. |
| PUZZLE-01–06, GHOST-01–02 | Complete the wand puzzle and follow the ghost's progression. |
| COMBAT-01–13, BOMB-01–05 | Fight two turn-based encounters with confirmation, cancellation, victory, defeat, and retry. |
| SAVE-01–07, END-01–03 | Retain progress across reopening, reach the ending, pause, or start again. |
| ART-01 | Use the supplied principal artwork. |

### 2.2 Excluded

Networking, multiplayer, a larger campaign, character leveling, shops beyond the Coin/Key exchange, and random encounter grinding are outside this task. Additional decoration and UI arrangement are free. NPC identities, fixed positions, dialogue, required regions, and progression values are defined in section 6.3.

## 3. Starting state

The supplied project is a forest starter with Gobot, camera, terrain/collision, continuous movement, and the five opening lines. Static building facades are part of the supplied forest terrain. Passive art/animation scenes are available. Adventure progression, house gameplay, quests, puzzle, ghost, saves, combat, and ending are absent. A read-only dashboard reports this starter state and needs integration with the implemented systems. Entry/resource paths are in TOOLCHAIN-en.md.

The final new-game opening and empty inventory are START-01–02, QUEST-02/04/06, PUZZLE-01, and SAVE-07. The starter is intentionally unfinished; public smoke checks package health, not the completed adventure.

## 4. Player goal and complete journey

```text
[START-01–05] Opening → forest movement
→ [WORLD-03, QUEST-01–04] four objectives → four Coins → one Key
→ [QUEST-05–06] unlock house → open chest for two Bombs
→ [PUZZLE-01–06] collect/select/place three colors → enter opened grove
→ [GHOST-01–02, COMBAT-01–13] accept Bugcat → victory → accept Wolf → victory
→ [END-01] interact with ghost again → safe-grove ending
```

A defeated party can retry the encounter (COMBAT-11–12). The player can pause, resume, restart, quit, and reopen with committed progress (END-02–03, SAVE-01–07). The repeating loop is movement/interaction → visible progress → next objective or battle action.

## 5. Player operations

| Requirements | Operation | Result |
|---|---|---|
| START-01–04 | Enter/Space/left click for opening; hold WASD/arrows after it | Advance opening; move with collision. |
| WORLD-02–03 | Walk through an open entrance; E/Space nearby | Change region or interact. |
| PUZZLE-03–04 | Choose a held color, confirm, or cancel | Place matching wand or get rejection. |
| GHOST-01, COMBAT-03 | Select visible choices/actions/targets, confirm; Escape cancels | Commit only the confirmed valid action. |
| END-02–03, SAVE-07 | Escape pause, Resume, Retry, New Game/Restart, Quit | Perform the labeled lifecycle operation. |

## 6. Numbered requirements — the only game-specific acceptance definitions

### 6.1 Reading the contract

Each row defines an independently observable result. Exact game-specific values and boundaries appear here. Global expectations such as startup, readable text, honest observations, responsive input, and no broken visuals are in COMMON_BASELINE.md (CB-01–18); they are not extra game-specific objectives. There is no requirement to run a particular tool or produce a particular test report.

### 6.2 Requirements

| ID | Preconditions | Player action / trigger | Required result | Forbidden result | Player-visible feedback | Repeat / lifecycle boundary |
|---|---|---|---|---|---|---|
| START-01 | New game | Advance opening dialogue | Show the five supplied opening lines in their original order, one per Enter, Space, or left-click press. The fifth confirmation closes the dialogue. | Auto-advance or advance several lines from one held key. | Current line and a continuation hint. | A fresh new game starts at line one. |
| START-02 | Opening dialogue active | Attempt movement | Keep Gobot stationary until the last line closes, then enable movement. | Movement beneath the opening. | The dialogue remains the active interaction. | Closing the final line does not also move or interact with the world. |
| START-03 | Exploring | Hold WASD or arrow keys | Move Gobot continuously; diagonal movement has the same total speed as cardinal movement. | Movement continuing after release. | Gobot visibly moves. | Movement keys work in each exploration region. |
| START-04 | Exploring | Walk toward solid terrain or region boundaries | Trees, solid obstacles, and outer boundaries stop Gobot; designated entrances permit travel. | Walking through solids or becoming trapped on a transition. | Gobot stops at the obstacle. | Extend the map and its reachable paths as needed. |
| START-05 | Any exploration region | Explore | Preserve the supplied Gobot and the starting forest's tile arrangement, paths, and clearings; keep a camera view useful for navigation while connecting new areas. | Replace the starter with an unrelated scene or genre. | Forest, robot, and navigable surroundings. | Additional regions may use a different layout. |
| WORLD-01 | Forest accessible | Explore | Provide a recognizable house exterior, its interior, and a deeper grove with player-accessible connecting entrances. | Require launching another scene from the editor. | Recognizable areas and entrance hints. | The house and grove entry prerequisites are QUEST-05 and PUZZLE-06. |
| WORLD-02 | At an unlocked entrance | Cross into another region or return | Place Gobot safely at the corresponding destination entrance; returning exits beside the corresponding exterior door. | Teleport into solids or immediately bounce indefinitely between entrances. | Visible arrival at the matching entrance. | The same route remains usable on later visits. |
| WORLD-03 | Near townsfolk or a world interactable | Press E or Space | Interact with the nearby object. At least four named townsfolk offer readable speaker-labelled dialogue; dialogue holds movement and can be continued with Enter, Space, or left click. | Trigger a distant object or move underneath dialogue. | Speaker, text, and interaction hint. | Escape closes optional conversations without awarding unfinished objectives; the opening is completed normally. |
| QUEST-01 | Before obtaining the Key | Speak to each of Warrior, Thief, Monk, and Wizard | Use the fixed names, positions, and dialogue in section 6.3. Each first conversation completes that townsfolk's objective and awards one Coin; later conversations do not award another. | Require house entry, grove entry, combat victory, or an unavailable consumable to earn the four Coins. | Objective instructions and completion feedback. | Any optional quest-specific object uses the corresponding quest-object observation kind. |
| QUEST-02 | One NPC objective completed, reward unclaimed | Claim that NPC reward | Award exactly one Coin. Four different completed objectives yield four Coins in total. | Award before that objective is completed. | Coin count and completed-objective progress toward four. | New game begins with zero Coins and zero completed/rewarded objectives. |
| QUEST-03 | NPC reward already claimed | Repeat conversation or revisit | Keep that reward claimed and leave Coin count unchanged. | Duplicate any Coin reward. | Completed dialogue or indication. | The claimed state survives reopening. |
| QUEST-04 | Fan the gatekeeper available | Request the exchange | Exchange exactly four Coins for one Key as one transaction; fewer than four Coins produce rejection with no deductions. | Partial payment or more than one Key from the exchange. | Trade result and updated inventory. | The exchange is one-time; repeat requests change nothing. New game has no Key. |
| QUEST-05 | At the locked house door | Interact with the door | With a Key, consume exactly one Key and unlock the house permanently; without it, keep the door locked without changing inventory. | Enter while locked or charge another Key after unlocking. | Locked rejection or visibly open door. | Unlock state survives returning and reopening. |
| QUEST-06 | Inside the unlocked house, chest unopened | Open the chest | Award exactly two Bombs and leave the chest visibly opened. | Duplicate Bombs on repeat interaction. | Chest-open feedback and Bomb count. | New game has zero Bombs; chest-open state survives reopening. |
| PUZZLE-01 | Inside house | Find the puzzle | Provide one Red, one Blue, and one Green wand and three matching, distinguishable pedestals. | Require inaccessible items beyond the blocked route. | Visible wand colors and matching pedestal colors. | New game has no held wands and no filled pedestals. |
| PUZZLE-02 | An uncollected wand is reachable | Pick up the wand | Add that color once to inventory and remove its world pickup. | Duplicate ownership on repeat interaction. | Pickup feedback and held color. | A placed wand does not respawn. |
| PUZZLE-03 | At a pedestal with a held wand | Choose a held color and confirm placement | A matching color leaves inventory and fills/lights that pedestal. Let the player choose a color explicitly so a mismatch can be attempted. | Fill other pedestals or consume another color. | Selected color, inventory update, and lit pedestal. | Cancelling color choice changes nothing. |
| PUZZLE-04 | At an empty pedestal | Confirm a wrong color or an unowned wand | Reject the placement without changing inventory or any pedestal; explain the mismatch or missing wand. | Auto-substitute a matching wand or consume the wrong color. | Visible rejection. | The player may choose again. |
| PUZZLE-05 | A pedestal is filled | Interact again | Keep its filled state without consuming another wand or issuing a reward. | Duplicate placement effects. | Already-filled indication. | Filled state persists after reopening. |
| PUZZLE-06 | Fewer than three pedestals filled, then all filled | Try the route; complete the remaining placements | Block entry to the deeper grove until all three are filled, then visibly open the route. The player travels through the open entrance. | Early passage or automatic teleport to the ending. | Blocked/open route feedback. | The open route remains open. |
| GHOST-01 | Grove reached normally | Meet the visible ghost | Provide dialogue connecting the ghost to the opening plea and offering the next required encounter. | Start an encounter before the player accepts. | Ghost dialogue and an encounter confirmation choice. | Cancelling leaves the current encounter unwon and allows another conversation. |
| GHOST-02 | Ghost progression revisited | Accept or cancel an encounter | Offer Bugcat first, Wolf only after Bugcat victory, and the final resolution only after both victories. | Duplicate an already won encounter or bypass an unfinished one. | Current stage in ghost dialogue. | Revisiting and cancellation preserve stage order. |
| SAVE-01 | Exploration or combat | Obtain, spend, or place an inventory item | Coins, Key, Bombs, and held wands have consistent counts in the inventory HUD and relevant combat displays; counts never become negative. | Divergent exploration/combat inventory. | Counts update with the completed effect. | Opening inventory is all zero; internal storage architecture is unrestricted. |
| SAVE-02 | Inventory changed | Close normally and reopen in a fresh process | Restore committed Coin, Key, Bomb, and held-wand counts. | Refill a consumed Bomb or lose a collected item. | Restored inventory. | A completed effect is saved before normal closing can lose it. |
| SAVE-03 | Exploration progress changed | Close normally and reopen | Restore completed/claimed NPC objectives, trade, door, chest, pedestals, and grove-route states. | Respawn a claimed reward or undo a completed placement. | Restored world/objective state. | Counts and world flags stay consistent. |
| SAVE-04 | A region was entered | Close normally and reopen | Resume in that region at a safe corresponding entrance; exact walking position need not persist. The opening dialogue does not replay after it has been completed. | Spawn in a solid or require unlocking the same entrance again. | Recognizable restored region. | Closing during unfinished opening may restart the opening from line one. |
| SAVE-05 | Encounter active or completed; ending possibly reached | Close normally and reopen | Preserve won encounters and the ending. An unfinished battle resumes as a fresh attempt of that same encounter with full party HP, retaining already committed Bomb consumption. | Record an unfinished/lost encounter as won or refund used Bombs. | Restored encounter stage or ending. | Turn queues, transient selection, and animation positions need not persist. |
| SAVE-06 | Save absent or corrupt | Launch | Start a new game safely from the opening with zero inventory and no progression. | Use partial inconsistent progress or crash. | Opening dialogue; corrupt-save recovery may also display a notice. | Save-file location is the public TOOLCHAIN location. |
| SAVE-07 | Exploration, pause, defeat, or ending | Choose New Game/Restart | Return to opening line one; reset inventory, objectives/rewards, trade, door/chest, wands/pedestals, route, victories, ending, and pending battle state; replace old saved progress. | Restore old progress after restarting then reopening. | Fresh opening and reset state. | Ordinary retry is COMBAT-12, distinct from full restart. |
| COMBAT-01 | Ghost encounter accepted | Enter the offered battle | Use Baloo and Nutsy as the player party; the first encounter contains Bugcat enemies and the second Wolf enemies. The first contains three Bugcats and the second two Wolves, so group targeting is meaningful. | Require an editor launch or start Wolf before Bugcat victory. | Recognizable battlers and encounter identity. | Both party members start each attempt at full health. HP values are design choices. |
| COMBAT-02 | Battle active | Choose actions as turns arrive | Show the current actor and take one committed action at a time, alternating through an understandable turn order including enemy turns. | Accept extra queued effects from repeated confirmation. | Actor/turn indication and action menu. | Once a player confirms an action, its animation and resulting enemy turns may complete without further input; waiting at a player menu does not advance the battle. |
| COMBAT-03 | Living player actor has a turn | Choose an action, target, confirm, or cancel | Provide readable action descriptions, target selection/preview, and a separate confirmation; Escape cancels pending selection without spending the turn or changing HP. | Apply an effect on mere focus or selection. | Selected action and selected valid target(s). | Each action can be selected through visible clickable controls; target selection also has visible clickable targets. |
| COMBAT-04 | Battle active | Damage or heal a combatant | Show current/max HP and a visible effect for the affected combatants. HP stays in [0,max]; HP zero is visibly downed. | Negative HP, over-healing, or unchanged display after an effect. | HP display and damage/heal/downed feedback. | Reported health matches the real battle state. |
| COMBAT-05 | A combatant is downed | Choose a living target or advance turns | Exclude downed actors from acting and downed combatants from living-target selection. | Attack or heal a downed combatant as though living. | Downed/unavailable indication. | Victory/defeat follows the remaining living sides. |
| COMBAT-06 | Baloo alive and acting | Confirm Bear Arms on a living enemy | Damage the selected living enemy. | Damage an ally or an unselected enemy. | Bear Arms label, description, and damage. | Damage amount is a design choice; no Bomb is required. |
| COMBAT-07 | Nutsy alive and acting | Confirm First Aid on a living ally | Heal the selected living ally up to its maximum HP. | Heal an enemy, revive a downed ally, or exceed max HP. | First Aid label, description, and healing. | Healing a full-health living ally may have zero effect; it does not consume a Bomb. |
| COMBAT-08 | Nutsy alive and acting | Confirm Nutsy's Arrow Storm action | Damage a selected living enemy without using a Bomb. | Leave Nutsy unable to attack when Bombs run out. | Action description and damage. | Damage and animation are design choices. |
| BOMB-01 | Baloo action menu | Inspect Bomb action | Show exactly one Bomb action with the supplied Bomb icon and label `Bomb xN`; at zero it remains visible and disabled. With Bombs and living targets it is enabled on Baloo's turn. | Duplicate or hide the action at zero. | Correct label/icon and enabled state. | It cannot be used by a downed/non-acting Baloo or with no living enemy. |
| BOMB-02 | Valid Bomb selected | Preview targets before confirmation | Highlight all and only living enemies as the pending targets. | Include allies or downed enemies; change HP/inventory during preview. | Visible group preview. | Cancellation removes the preview without an effect. |
| BOMB-03 | Valid Bomb confirmed | Resolve the effect | Apply exactly 35 damage once to every living enemy and to no ally/downed enemy; HP clamps at zero. | Repeat damage from repeated input or an animation callback. | Per-target damage/HP changes. | A target with less than 35 HP reaches zero; its displayed damage may still read 35. |
| BOMB-04 | Bomb effect successfully resolved | Finish the action | Consume exactly one Bomb after the successful effect; update all counts and save the new count. | Consume on selection/queueing or more than once per effect. | Bomb xN decreases once. | A Bomb ending the encounter still consumes once before victory is committed. |
| BOMB-05 | Cancellation, zero Bombs, invalid actor, rejected pending action, or no living target | Attempt/cancel Bomb use | Leave all HP and inventory unchanged. | Damage or consumption for an invalid/rejected action. | Cancellation or rejection feedback. | Remaining ordinary actions stay usable. |
| COMBAT-09 | Enemy turn | Let the committed turn sequence resolve | Living enemies perform visible damaging actions against living party members. | Skip every enemy turn or use a downed enemy. | Enemy action and party HP change. | Enemy behavior and damage are design choices; a loss can be reached through normal poor choices. |
| COMBAT-10 | All enemies downed | Finish the battle | Show victory, record this encounter once, and provide a visible continuation back to exploration near the ghost. | Leave combat inputs active under victory or immediately win the next encounter. | Victory and return control. | The next stage requires another player interaction. |
| COMBAT-11 | Both party members downed | Finish the battle | Show defeat and a visible Retry control; leave this encounter unwon. | Record a victory or advance ghost progression. | Defeat, retry, and full-restart choices. | Gameplay inputs stop beneath the defeat screen. |
| COMBAT-12 | Defeat screen | Choose Retry | Restart only that encounter with full party HP, reset enemy HP and transient turn/selection state, and retain committed inventory/progression including spent Bombs. | Refund used Bombs, clear earlier victories, or duplicate actors. | A clean attempt of the same encounter. | Full reset uses New Game/Restart instead. |
| COMBAT-13 | Either encounter, even with zero Bombs | Use ordinary actions | Keep both encounters winnable with Bear Arms, First Aid, and Nutsy's attack. | Require a Bomb or another finite unavailable item to win. | Usable ordinary actions. | No timing challenge or real-time aiming is required to confirm turn-based actions. |
| END-01 | Ghost reachable | Request final resolution | Only after all pedestals and both victories, resolve the opening plea and clearly announce that the grove is safe. | Announce success on an early visit, on defeat, or just on entering the grove. | Distinct ending message connected to the plea. | After the last victory the final ghost interaction is still required. |
| END-02 | Exploration or non-outcome battle state | Press Escape when no cancellable selection/dialogue is active | Open pause with Resume, New Game/Restart, and Quit; resume returns to the same state. | Advance exploration or turns while paused. | Pause menu and labeled controls. | Pending selection/dialogue consumes Escape as cancellation first. |
| END-03 | Ending or pause | Use lifecycle controls | Offer New Game/Restart and Quit. The ending blocks further gameplay while leaving these controls usable. | Continue movement or attacks underneath the ending. | Readable ending/pause options. | Quit closes normally after committed progress is saved. |
| ART-01 | Exploration and battles | Play through the adventure | Use supplied robot, NPC/ghost, forest/building, party/enemy, item and Bomb-icon artwork in their semantic roles. UI frames, markers, effects, and additional decoration may be procedural. | Use plain placeholder blocks instead of the supplied principal artwork. | Recognizable art in world, inventory, and battles. | Composition, animation implementation, and UI layout are free; exact resources are catalogued separately. |

| ID | Preconditions | Player action / trigger | Required result | Forbidden result | Player-visible feedback | Repeat / lifecycle boundary |
|---|---|---|---|---|---|---|
| WORLD-04 | Explore the connected world | Travel between regions | Use the region and object landmarks in section 6.3.1; equivalent connected reachable locations are allowed. Every entrance to the deeper grove stays blocked until PUZZLE-06. | Bypass the three-pedestal gate through the forest entrance. | Consistent entrances and destination hints. | WORLD-02 controls safe return. |
| DIALOGUE-01 | Speak to townsfolk or ghost | Continue conversation | Use the required names and ordered dialogue in section 6.3.2/4. Warrior, Thief, Monk and Wizard each award only when the full first conversation completes. Fan moves to the second listed location after trading. | Award when Escape cancels an unfinished conversation. | Speaker-labelled lines and reward/trade feedback. | Runner, Smith and Sign remain optional. |
| PUZZLE-07 | Enter the house | Inspect pickups and pedestals | Provide the color/object arrangement in section 6.3.3, or equivalent reachable positions; any matching-color placement order is valid. | Enforce an unpublished placement order. | Distinct colors and lit pedestal feedback. | PUZZLE-01–06 define pickup and placement effects. |
| COMBAT-14 | Baloo is alive and acting | Select and confirm Focus | Spend the current action to increase Baloo's next Bear Arms damage; show the pending boost and consume it on that next attack. | Damage an enemy immediately or consume a Bomb. | Focus label, description and boosted attack feedback. | Boost magnitude is a design choice; cancellation has no effect; retry clears it. |

### 6.3 Parameters for WORLD-04, DIALOGUE-01, PUZZLE-07 and COMBAT-14

This section fixes the values that must be reproducible. Coordinates are player-visible world positions in units where one terrain tile spans 16 units. Implementations may use another scene architecture, but all fixed interactions must remain reachable at these locations or at equivalent locations connected by the documented routes.

### 13.1 Player and region locations

| Object | Coordinate | Required behavior |
|---|---:|---|
| Gobot start | `(24, 200)` | New-game spawn after the opening; movement is locked until line five closes. |
| Forest-to-grove transition | `(200, 280)` | After PUZZLE-06 opens the grove, travel to arrival `(632, 424)`; before that, this entrance also remains blocked. |
| Grove-to-forest transition | `(632, 408)` | Return to forest arrival `(200, 264)`. |
| House door | `(120, 176)` | Locked until one Key is consumed. |
| House-to-town transition | `(824, 24)` | Return beside the exterior door. |
| House-to-grove route | `(936, 8)` | Blocked until all three pedestals are correct. |
| Grove-to-house return | `(952, 440)` | Return to house arrival `(936, 24)`. |
| Ghost | `(840, 488)` | Final objective after Bugcat and Wolf victories. |

### 13.2 Fixed NPCs and dialogue

| Dashboard ID | Name | Coordinate | Dialogue sequence |
|---|---|---:|---|
| `npc_1` | Warrior | `(296, 24)` | 1. "You may ask, why am I so popular with the ladies?" 2. "Is it because I'm super edgy? My angelic appearance? My poor social skills?" 3. "Why, it's my unfathomably large sword, of course!" 4. First visit: "Of course you would want my autograph!" 5. "Here's the awkward part, I can't write. Really." 6. "Have this coin instead. If you squint real hard, you can pretend it has my face on it! Aren't I generous?" |
| `npc_2` | Thief | `(248, 8)` | 1. "We defeated the Horrible Thing at the Centre of the Universe and all I got was a stupid badge." 2. "What's in the chest? Well, what I stole is another matter! Heh heh heh..." 3. First visit: "You want what? An autograph? Do you know what parchment costs these days?" 4. "Take this trinket instead. Don't say I never did anything for you." |
| `npc_3` | Monk | `(344, 8)` | 1. "Me and the fam just got back from slaying another ancient being." 2. "Punch 'im? What kind of monster do I look like?" 3. "We got 'im with the power of friendship!" 4. First visit: "An autograph? I'm sorry, but I can't unclench my mighty fists." 5. "Here. Have one of these instead. May your little robot arms be strong." |
| `npc_4` | Wizard | `(344, 72)` | 1. "FUS RO DOH!" 2. "...No wait, that's not right." 3. First visit: "You want my autograph? Bah, I do not have time for small tin people." 4. "Here, take this meager handout and begone." |
| `gatekeeper` | Fan | `(280, 104)`, then `(368, 208)` | First visit: "THEY'RE HERE! The Gang of Four, THEY'RE THE BEST!!!" / "They're so cool! They can TIME TRAVEL at whim!..." / "I would give ANYTHING for their autograph, but I'm TOO NERVOUS! AHHHHH!!!" With four Coins: "They wanted me to have these?" / "THIS IS THE BEST DAY OF MY LIFE!!!" / "How can I ever thank you? Here, take this key I borrowed from that crazy old lady." Too few Coins: "EXCITED? ME? WHY WOULD YOU THINK THAT?" |
| Optional | Runner | `(296, 184)` | First visit: "Does your mom tell you to stop and look carefully at things?" / "My mom always tells me I never notice anything unless I look twice!" Repeat: "What did that crazy lady say again?" / "\"Green, blue, red?\"" |
| Optional | Smith | `(136, 88)` | "You wouldn't walk into someone's house unannounced, would you?" |
| Optional | Sign | `(152, 168)` | "Marvellous Mathilda's Magnificent Munitions" / "(Closed for pest control)" / "Darn kids stay off my lawn or I'll turn you all into newts!!!" |

All named townsfolk use speaker-labelled dialogue. Dialogue pauses movement and advances one line per Enter, Space, or left-click press. Escape cancels optional dialogue without awarding an unfinished objective.

### 13.3 Fixed house and puzzle objects

| Object | Coordinate | Required behavior |
|---|---:|---|
| Red wand pickup | `(792, 80)` | Adds one Red Wand once and disappears. |
| Blue wand pickup | `(808, 80)` | Adds one Blue Wand once and disappears. |
| Green wand pickup | `(824, 80)` | Adds one Green Wand once and disappears. |
| Chest | `(840, 120)` | Awards exactly two Bombs once and remains open. |
| Red pedestal | `(888, 40)` | Accepts only a Red Wand; wrong colors are rejected without changing inventory. |
| Blue pedestal | `(872, 40)` | Accepts only a Blue Wand; wrong colors are rejected without changing inventory. |
| Green pedestal | `(856, 40)` | Accepts only a Green Wand; wrong colors are rejected without changing inventory. |

The pedestals may be filled in any order. Once all three matching wands are placed, the route at `(936, 8)` opens. Placed colors and the open route persist after normal close and reopen.

### 13.4 Fixed encounters and ending dialogue

| Encounter | Legacy map landmark (not a battle trigger) | Combatant composition | Victory effect |
|---|---:|---|---|
| Bugcat | `(83, 6)` | Three Bugcats against Baloo and Nutsy. | Record the Bugcat victory; never repeat that encounter. |
| Wolf | `(200, 264)` | Two Wolves against Baloo and Nutsy. | Record the Wolf victory; never repeat that encounter. |

Encounter entry is always the ghost confirmation in GHOST-01/02; the legacy landmarks do not start combat. The Bugcat encounter is unavailable after victory. Wolf appears only after Bugcat is won. The final ghost trigger is inactive until both victories. Ghost dialogue is:

1. "I've been waiting for you."
2. "For a very, very long time. I should have packed a lunch."
3. "Now I'm hungry and grumpy. Time to work out those bugs!"

After the final interaction, display a distinct safe-grove ending. The ending blocks normal gameplay but leaves New Game/Restart and Quit usable.

### 13.5 Combat actions

- Baloo has Bear Arms, Focus (COMBAT-14), and Bomb xN.
- Nutsy has Arrow Storm (COMBAT-08, one selected living enemy) and First Aid.
- `Bomb xN` is visible even at zero, disabled when `N` is zero or no living enemy exists, damages every living enemy for exactly 35 once, and consumes one Bomb only after resolving.
- Target selection remains separate from confirmation. Escape cancels pending selection without changing HP or inventory.


## 7. Success, failure, and intermediate stages

| Stage | Requirements | Outcome | Not yet allowed |
|---|---|---|---|
| Opening | START-01–02 | Fifth line closes | Movement while opening is active |
| Quests / house | QUEST-01–06 | Trade, unlock, chest reward | Duplicate rewards, entry without Key |
| Puzzle | PUZZLE-01–06 | Three filled pedestals and opened route | Early grove entry |
| First battle | GHOST-02, COMBAT-10 | Bugcat victory, return to ghost | Wolf before victory; final ending |
| Second battle | GHOST-02, COMBAT-10 | Wolf victory, return to ghost | Automatic ending on battle return |
| Final objective | END-01 | Explicit ghost resolution and ending | Ending before all prerequisites |
| Defeat | COMBAT-11–12 | Lost encounter with usable retry | Victory or progression on loss |

## 8. Interface and feedback

| Requirements | Information |
|---|---|
| START-01, WORLD-03, QUEST-01–06 | Dialogue, speaker, controls, objectives, Coin progress, trade/door/chest results |
| PUZZLE-01–06 | Wand colors/ownership, chosen color, lit pedestals, route state, invalid-placement feedback |
| COMBAT-02–05, BOMB-01–05 | Actor, action description, selected targets, current/max HP, damage/heal effects, Bomb count/availability |
| COMBAT-10–12, END-01–03 | Victory, defeat, retry, final ending, pause and lifecycle controls |

## 9. Restart, reopening, and saves

| Scenario | Requirements | Summary |
|---|---|---|
| Full New Game/Restart | SAVE-07 | Reset all progress and saved state to opening line one. |
| Retry defeat | COMBAT-12 | Reset encounter health and transient state; preserve spent Bombs and earlier progress. |
| Reopen | SAVE-02–05 | Restore committed inventory, world flags, safe region entrance, encounter victories, and ending. |
| Reopen during battle | SAVE-05 | Fresh attempt of the same unfinished encounter, retaining spent Bombs. |
| No valid save | SAVE-06 | Safe new game. |

## 10. Preserved starter features

START-01–05 preserve the opening text/order, movement lock, Gobot, continuous movement, initial forest appearance/collision, and useful camera. Extend beyond the supplied forest while preserving its existing arrangement (START-05); internal architecture remains unrestricted.

## 11. Assets and content

ART-01 defines the principal visual requirements. MaterialMapping-en.md and Assets/material-index.json describe precise source paths, dimensions, regions, filtering, passive-scene dependencies, and optional procedural roles. Licensing files describe attribution separately from gameplay.

## 12. Dashboard naming tables and operation mode

This section maps concepts already defined in section 6 to the public read-only observation vocabulary. Internal object names, scripts, and layouts are unrestricted. The canonical machine-readable table is sp/benchmark/naming-tables.json, referenced in TOOLCHAIN-en.md.

### 12.1 Numeric slots

| Slot | Meaning | Source requirements |
|---|---|---|
| `region` | 0 forest, 1 house, 2 grove; during battle/outcome use 2 | WORLD-01, WORLD-02, SAVE-04 |
| `opening_complete` | Opening dialogue has finished (0/1) | START-01, START-02, SAVE-04 |
| `dialogue_open` | A dialogue/choice is open (0/1) | START-01, WORLD-03, GHOST-01 |
| `opening_line` | 1..5 while opening is visible; 0 otherwise | START-01 |
| `coins` | Current inventory count | QUEST-02, QUEST-04, SAVE-01, SAVE-02 |
| `key` | Current inventory count | QUEST-04, QUEST-05, SAVE-01, SAVE-02 |
| `bombs` | Current inventory count | QUEST-06, BOMB-04, SAVE-01, SAVE-02 |
| `wand_red` | Held unplaced red wand (0/1) | PUZZLE-02, PUZZLE-03, SAVE-02 |
| `pedestal_red` | Filled red pedestal (0/1) | PUZZLE-03, PUZZLE-05, SAVE-03 |
| `wand_blue` | Held unplaced blue wand (0/1) | PUZZLE-02, PUZZLE-03, SAVE-02 |
| `pedestal_blue` | Filled blue pedestal (0/1) | PUZZLE-03, PUZZLE-05, SAVE-03 |
| `wand_green` | Held unplaced green wand (0/1) | PUZZLE-02, PUZZLE-03, SAVE-02 |
| `pedestal_green` | Filled green pedestal (0/1) | PUZZLE-03, PUZZLE-05, SAVE-03 |
| `quest_1_complete` | Objective for NPC 1 complete (0/1) | QUEST-01, QUEST-02, SAVE-03 |
| `quest_1_claimed` | NPC 1 Coin reward claimed (0/1) | QUEST-02, QUEST-03, SAVE-03 |
| `quest_2_complete` | Objective for NPC 2 complete (0/1) | QUEST-01, QUEST-02, SAVE-03 |
| `quest_2_claimed` | NPC 2 Coin reward claimed (0/1) | QUEST-02, QUEST-03, SAVE-03 |
| `quest_3_complete` | Objective for NPC 3 complete (0/1) | QUEST-01, QUEST-02, SAVE-03 |
| `quest_3_claimed` | NPC 3 Coin reward claimed (0/1) | QUEST-02, QUEST-03, SAVE-03 |
| `quest_4_complete` | Objective for NPC 4 complete (0/1) | QUEST-01, QUEST-02, SAVE-03 |
| `quest_4_claimed` | NPC 4 Coin reward claimed (0/1) | QUEST-02, QUEST-03, SAVE-03 |
| `trade_complete` | Committed completion flag (0/1) | QUEST-04, SAVE-03 |
| `house_open` | Committed completion flag (0/1) | QUEST-05, SAVE-03 |
| `chest_open` | Committed completion flag (0/1) | QUEST-06, SAVE-03 |
| `grove_open` | Committed completion flag (0/1) | PUZZLE-06, SAVE-03 |
| `bugcat_won` | Committed completion flag (0/1) | COMBAT-10, GHOST-02, SAVE-05 |
| `wolf_won` | Committed completion flag (0/1) | COMBAT-10, GHOST-02, SAVE-05 |
| `ending_complete` | Committed completion flag (0/1) | END-01, SAVE-05 |
| `encounter` | 0 none, 1 Bugcat, 2 Wolf; retained on that battle outcome | COMBAT-01, COMBAT-10, COMBAT-11 |
| `battle_stage` | 0 outside battle, 1 action menu, 2 selection/preview, 3 resolving, 4 victory, 5 defeat | COMBAT-02, COMBAT-03, COMBAT-10, COMBAT-11 |
| `acting_party` | 0 none/enemy, 1 Baloo, 2 Nutsy | COMBAT-02 |
| `selected_action` | 0 none, 1 Bear Arms, 2 First Aid, 3 Nutsy attack, 4 Bomb | COMBAT-03, BOMB-02 |
| `hp_baloo` | Current HP; -1 outside battle/outcome | COMBAT-04 |
| `max_hp_baloo` | Maximum HP; -1 outside battle/outcome | COMBAT-04 |
| `hp_nutsy` | Current HP; -1 outside battle/outcome | COMBAT-04 |
| `max_hp_nutsy` | Maximum HP; -1 outside battle/outcome | COMBAT-04 |

### 12.2 Entities

Visible entities use viewport rectangles; off-screen entities may be omitted. Persistent progress is always in slots. Stable public IDs distinguish repeated enemy/object kinds without exposing internal node names.

| Kind | Meaning | States | Source requirements |
|---|---|---|---|
| `player` | Exploration Gobot | normal, dialogue_locked, paused | START-02, START-03, END-02 |
| `npc_1` | Quest NPC 1; bind this index consistently, independent of displayed name | available, objective_complete, rewarded | WORLD-03, QUEST-01, QUEST-02, QUEST-03 |
| `quest_object_1` | Optional world goal object for NPC 1; omit when quest is dialogue-only | available, completed | QUEST-01 |
| `npc_2` | Quest NPC 2; bind this index consistently, independent of displayed name | available, objective_complete, rewarded | WORLD-03, QUEST-01, QUEST-02, QUEST-03 |
| `quest_object_2` | Optional world goal object for NPC 2; omit when quest is dialogue-only | available, completed | QUEST-01 |
| `npc_3` | Quest NPC 3; bind this index consistently, independent of displayed name | available, objective_complete, rewarded | WORLD-03, QUEST-01, QUEST-02, QUEST-03 |
| `quest_object_3` | Optional world goal object for NPC 3; omit when quest is dialogue-only | available, completed | QUEST-01 |
| `npc_4` | Quest NPC 4; bind this index consistently, independent of displayed name | available, objective_complete, rewarded | WORLD-03, QUEST-01, QUEST-02, QUEST-03 |
| `quest_object_4` | Optional world goal object for NPC 4; omit when quest is dialogue-only | available, completed | QUEST-01 |
| `gatekeeper` | Coin exchange speaker (may be a quest NPC role) | available, traded | QUEST-04 |
| `house_door` | Exterior door | locked, open | QUEST-05 |
| `house_exit` | Interior return entrance | open | WORLD-02 |
| `grove_entrance` | Route from house to grove | blocked, open | PUZZLE-06 |
| `grove_exit` | Return from grove to house | open | WORLD-02 |
| `chest` | Bomb reward chest | closed, opened | QUEST-06 |
| `wand_red` | Uncollected red wand; omit after pickup | available | PUZZLE-01, PUZZLE-02 |
| `pedestal_red` | Red pedestal | empty, filled | PUZZLE-03, PUZZLE-04, PUZZLE-05 |
| `wand_blue` | Uncollected blue wand; omit after pickup | available | PUZZLE-01, PUZZLE-02 |
| `pedestal_blue` | Blue pedestal | empty, filled | PUZZLE-03, PUZZLE-04, PUZZLE-05 |
| `wand_green` | Uncollected green wand; omit after pickup | available | PUZZLE-01, PUZZLE-02 |
| `pedestal_green` | Green pedestal | empty, filled | PUZZLE-03, PUZZLE-04, PUZZLE-05 |
| `ghost` | Grove ghost/final objective | bugcat_pending, wolf_pending, resolution_pending, safe | GHOST-01, GHOST-02, END-01 |
| `baloo` | Battle combatant; each instance has its own HP and stable ID | living, downed | COMBAT-01, COMBAT-04, COMBAT-05 |
| `nutsy` | Battle combatant; each instance has its own HP and stable ID | living, downed | COMBAT-01, COMBAT-04, COMBAT-05 |
| `enemy_bugcat` | Battle combatant; each instance has its own HP and stable ID | living, downed | COMBAT-01, COMBAT-04, COMBAT-05 |
| `enemy_wolf` | Battle combatant; each instance has its own HP and stable ID | living, downed | COMBAT-01, COMBAT-04, COMBAT-05 |

### 12.3 Clickable targets

| Kind | Meaning | Source requirements |
|---|---|---|
| `dialogue_continue` | Visible dialogue continuation surface | START-01, WORLD-03 |
| `dialogue_choice` | Dialogue choice; stable id distinguishes several options | QUEST-01, GHOST-01 |
| `encounter_accept` | Accept the offered encounter | GHOST-01 |
| `cancel_button` | Cancel dialogue/placement/action selection | WORLD-03, PUZZLE-03, COMBAT-03 |
| `place_red` | Choose Red wand | PUZZLE-03, PUZZLE-04 |
| `place_blue` | Choose Blue wand | PUZZLE-03, PUZZLE-04 |
| `place_green` | Choose Green wand | PUZZLE-03, PUZZLE-04 |
| `placement_confirm` | Confirm chosen placement | PUZZLE-03, PUZZLE-04 |
| `bear_arms_action` | Select Bear Arms | COMBAT-06 |
| `first_aid_action` | Select First Aid | COMBAT-07 |
| `nutsy_attack_action` | Select Nutsy offensive action | COMBAT-08 |
| `focus_action` | Select Focus | COMBAT-14 |
| `bomb_action` | Select Bomb | BOMB-01 |
| `combatant_target` | Select a combatant; id matches its entity id | COMBAT-03, COMBAT-05 |
| `action_confirm` | Confirm pending battle action | COMBAT-03, BOMB-03 |
| `victory_continue` | Return from victory to exploration | COMBAT-10 |
| `retry_button` | Retry encounter after defeat | COMBAT-11, COMBAT-12 |
| `restart_button` | New Game / full restart | SAVE-07 |
| `resume_button` | Resume paused state | END-02 |
| `quit_button` | Quit normally | END-03 |

### 12.4 Operations and reporting

Movement is continuous WASD/arrows; world interaction is E/Space; dialogue advancement is Enter/Space/left click; Escape cancels the active selection/conversation or opens pause. Visible choices, combat actions/targets/confirmation, placement choices, and lifecycle controls use ordinary left clicks. No dashboard action endpoint exists. Exact InputMap and snapshot transport details are in TOOLCHAIN-en.md.

## 13. Implementation freedom

The public technical contract defines paths, controls and observation transport. Internal node names, scene hierarchy, algorithms and storage architecture are free. Section 6.3 contains public player-visible content, not an implementation prescription.

## 14. Requirement index

| ID | Player outcome |
|---|---|
| START-01 | Show the five supplied opening lines in their original order, one per Enter, Space, or left-click press. The fifth confirmation closes the dialogue. |
| START-02 | Keep Gobot stationary until the last line closes, then enable movement. |
| START-03 | Move Gobot continuously; diagonal movement has the same total speed as cardinal movement. |
| START-04 | Trees, solid obstacles, and outer boundaries stop Gobot; designated entrances permit travel. |
| START-05 | Preserve the supplied Gobot and the starting forest's tile arrangement, paths, and clearings; keep a camera view useful for navigation while connecting new areas. |
| WORLD-01 | Provide the house exterior, house interior, and grove at the fixed routes in section 6.3. |
| WORLD-02 | Place Gobot safely at the corresponding destination entrance; returning exits beside the matching exterior entrance. |
| WORLD-03 | Interact with the nearby object. The fixed townsfolk and speakers in section 6.3 offer readable speaker-labelled dialogue. |
| QUEST-01 | Warrior, Thief, Monk, and Wizard each complete one objective on the first conversation and indicate that it is complete. |
| QUEST-02 | The first completed conversation with each townsfolk awards exactly one Coin, for four Coins in total. |
| QUEST-03 | Repeat conversations and revisits do not duplicate a Coin reward. |
| QUEST-04 | Fan exchanges exactly four Coins for one Key. Fewer than four Coins are rejected without deductions. |
| QUEST-05 | With a Key, the door consumes exactly one Key and unlocks permanently. Without it, the door remains locked. |
| QUEST-06 | The chest awards exactly two Bombs once and remains visibly opened. |
| PUZZLE-01 | Provide the fixed Red, Blue, and Green wand pickups and matching pedestals from section 6.3. |
| PUZZLE-02 | Each wand pickup adds that color once and disappears. |
| PUZZLE-03 | A matching color leaves inventory and fills/lights its pedestal after explicit selection and confirmation. |
| PUZZLE-04 | A mismatched color is rejected without changing inventory or any pedestal and displays visible feedback. |
| PUZZLE-05 | A filled pedestal cannot consume another wand or duplicate its effect. |
| PUZZLE-06 | The grove route remains blocked until all three pedestals are filled, then opens permanently. |
| GHOST-01 | The ghost dialogue connects the opening plea to the next required encounter and allows the player to accept it. |
| GHOST-02 | Bugcat is offered first, Wolf only after Bugcat victory, and final resolution only after both victories. |
| SAVE-01 | Coin, Key, Bomb, and held-wand counts remain consistent and nonnegative in exploration and combat. |
| SAVE-02 | Normal close and fresh-process reopen restore committed inventory counts. |
| SAVE-03 | Completed objectives, reward claims, trade, door, chest, pedestals, encounters, and route state are restored. |
| SAVE-04 | Reopen resumes in the saved region at its safe fixed entrance; the completed opening does not replay. |
| SAVE-05 | Won encounters and the ending persist; an unfinished encounter restarts with full party HP and committed Bomb usage retained. |
| SAVE-06 | Missing or corrupt save data starts safely at the opening with zero inventory and no progression. |
| SAVE-07 | New Game/Restart clears all inventory, flags, positions, encounters, and ending state and returns to opening line one. |
| COMBAT-01 | Baloo and Nutsy fight three Bugcats first and two Wolves second. |
| COMBAT-02 | Show the current actor and commit one action at a time through an understandable turn order including enemy turns. |
| COMBAT-03 | Provide action descriptions, target preview, confirmation, and cancellation without applying unconfirmed effects. |
| COMBAT-04 | Show current/max HP and visible damage or healing; HP remains in `[0, max]`. |
| COMBAT-05 | Downed combatants cannot act and cannot be selected as living targets. |
| COMBAT-06 | Bear Arms damages the selected living enemy. |
| COMBAT-07 | First Aid heals the selected living ally without exceeding maximum HP. |
| COMBAT-08 | Arrow Storm damages selected living enemies without requiring a Bomb. |
| BOMB-01 | Baloo shows exactly one `Bomb xN` action with the supplied Bomb icon; at zero it is visible and disabled. |
| BOMB-02 | Selecting Bomb previews all and only living enemies before confirmation. |
| BOMB-03 | Confirming Bomb deals exactly 35 damage once to every living enemy and no ally or downed enemy. |
| BOMB-04 | A successful Bomb resolves once and consumes exactly one Bomb after the effect. |
| BOMB-05 | Cancellation, zero Bombs, invalid state, or no living target leaves HP and inventory unchanged. |
| COMBAT-09 | Living enemies visibly damage living party members during their turns. |
| COMBAT-10 | Victory records the encounter once and returns control near the ghost. |
| COMBAT-11 | Defeat leaves the encounter unwon and displays Retry and full-restart controls. |
| COMBAT-12 | Retry restarts only the same encounter with full party HP and retains committed inventory, including spent Bombs. |
| COMBAT-13 | Both encounters remain winnable using ordinary actions even with zero Bombs. |
| END-01 | Only after all pedestals and both victories, the final ghost interaction announces that the grove is safe. |
| END-02 | Escape opens pause with Resume, New Game/Restart, and Quit; Resume returns to the same state. |
| END-03 | New Game/Restart and Quit remain available at the ending while normal gameplay is blocked. |
| ART-01 | Use the supplied robot, NPC, ghost, forest, building, battler, item, and Bomb artwork in their documented semantic roles. |
