# Match 3 Swipe: three-chapter chain challenge

## 1. One sentence task

Make three consecutive levels of all-directional match-3 games: Complete the score target in sequence, Clear De-icing layer, Color quota on the stone chessboard, And save completed levels correctly. 

## 2. This range

### 2.1 Must be completed

Three levels to advance in sequence; 15×10 Six-color plate; Full plate direction exchange; Normal matching, 4/5 Even rewards, Chain; Fixed Ice Layer, Immovable Stones, Color Quota; Retry within a level and save between levels. 

### 2.2 Does not contain

Partial two-stone exchange mode, Paid props, Automatic shuffling, Random levels, Network rankings, In the game Archive.  Do not add unlisted mechanisms or undisclosed acceptance conditions. 

### 2.3 Original work and adaptation

The base gameplay is adapted from the upstream game of the same name. The three-chapter campaign, additional mechanisms, delivery requirements and persistence rules are specific to this benchmark. Third-party audio and video are not supplied. See [asset notes](assets/ASSET_MANIFEST.md) for available materials and licensing.

## 3. Starting state

The supplied `starter_project/` contains the Dashboard v3 transport, machine-readable naming tables and public self-check tools. It starts in `not_ready`, reports the window size and supports `Q` to quit. Implement gameplay and persistence according to the requirements below.
When the player runs the completed version for the first time without a valid save, Start from the main menu without progress. The effective level initial state and entry baseline are determined by[LEVEL_SPEC.md](LEVEL_SPEC.md), [campaign.json](campaign.json)Definition. 

## 4. Player goals and complete process

New Campaign → After meeting all the goals of the level 1 Guanda points → level_clear/Next → After meeting all the goals of the level 2 Guanda points and clearing the ice → Next → After meeting all the goals of the level 3 Clearing the ice and completing the two-color quota → campaign_won. Any level where the number of steps is exhausted but the goals are not met is lost. 

can only be used through the normal keyboard / The mouse completes the entire process, Does not rely on debugging commands, File injection, Change dashboard, Change scores or skip levels. See common stages and transaction semantics[CAMPAIGN_RULES.md](CAMPAIGN_RULES.md). 

## 5. Player operations

| Actions | Normal input | Semantics |
|---|---|---|
| left/right/up/down | A/D/W/S or arrow keys pressed | A full direction action; Press and hold for non-stop shooting |
| board_drag | Left-click drag within the board | Triggered once when the spindle displacement reaches 64 logical pixels; Tie level |
| pause / restart | Escape / R | Pause or retry the currently uncleared level |
| UI Confirm | Left click to complete Full click, Up and down selection and Enter | Menu, Description, Pause, Retry, Next, Continue, Clear file confirmation and exit; Only operate the current real control |

The interface and gameplay cannot consume the same gesture at the same time. The value of each control, For the conflict sequence and clock definition, see LEVEL_SPEC. 

## 6. Numbering requirements  The only task-level acceptance basis

The following requirements together with LEVEL_SPEC, campaign.json, CAMPAIGN_RULES constitute the public task boundary; [COMMON_BASELINE.md](COMMON_BASELINE.md)Supplementary general quality requirements. The same parameter is subject to the current level value of campaign.json , The value of another level cannot be hard-coded. Conflicts are found between documents and parameters The sudden change must be corrected before freezing, Another answer cannot be set by the private grader. 

| Requirement number | Preconditions | Player operation or trigger | Results that must occur | Results that cannot occur | Visible feedback to players | Failure, Repeat, Restart Boundary |
|---|---|---|---|---|---|---|
| `M3-BOARD-01` | Create current level | Start/Next/Continue/Retry | Complete in campaign.json 's seed and stone set creation disk; No initial three-link; Score, The quota count is 0, The remaining steps are the value of this level | The seeds of the 1 th level cannot be applied, Target or 150 fixed The number reaches the level containing stones | gems, ice layer, stones and the target of this level are visible | Retry return to the initial random cursor of this level, cannot reset the previous level that has been completed |
| `M3-INPUT-01` | playing and busy=0 | direction pressed or qualified drag | only one step will be deducted for one action; Valid for all legal neighbor pairs | busy Input is not queued; Cannot change a pair locally, Long press and burst, Drag across borders or let one gesture deduct multiple steps | Real-time feedback on direction and remaining steps | Insufficient 64 No step deducting when dragging from pixels or outside the board; Final and temporary Stop ignoring gameplay |
| `M3-SWAP-01` | Accepted action | Looking for legal exchanges | Complete in LEVEL_SPEC Conflict order processing without reusing adjacent pairs of gems; Accept only after at least one end of the exchange is a≥3 line | Do not penetrate stones, Do not exchange stones, Do not unconditionally translate the entire row | There are visible changes in the actual exchange | There is still one step deducted if there is no legal exchange, The board and the score are not falsely changed |
| `M3-MATCH-01` | In settlement | Normal matching | Merging the maximum continuous lines of the same color horizontally and vertically; Crossing gems can only be cleared once per batch; Stones separated by normal matching | No slash matching, Put the two sections into a line without crossing the stone, No repeated counting according to animation | Highlighting is consistent with actual removal | All chains belong to the same action, No extra steps |
| `M3-POWER-01` | Ordinary batches have 4 connections or≥5 connections | bonus batches | 4 connections are added to correspond to the entire row / Column, ≥5 Join adjacent lines; Get union and clear stones; Reward can be applied to non-stone cells on the other side of the stone | Reward clearing itself does not generate rewards again; Do not count cross cells or reward stone points repeatedly | The whole line rewards can be distinguished from ordinary matches | The order is fixed to ordinary removal→Supplement→Rewards to be cleared→Supplement→Normal matching again |
| `M3-ICE-01` | There is an ice layer in the grid where the cleared gem is | Removed by normal or reward | The grid is reduced by one level; The ice layer is fixed in the grid, Does not follow the exchange or whereabouts; Reduced to 0 disappears | Multiple lines in the same batch cannot be reduced if they overlap; You cannot use ice layers as gems, Remove stones or get extra points | Display 1/2 Layer appearance, Total remaining layers and elimination feedback | You can reduce layers again in different batches with the same action; Retry Restore all ice layers in this level |
| `M3-STONE-01` | After meeting all the goals of the level 3 Level | Swapping, Matching and gravity | Stones cannot be exchanged, Cannot be cleared; Each column is divided into independent supplementary segments by stones, Survival gems do not drop across stones | Cannot leave permanent holes or count stones as new gems | Stones and spaces, Ice layers are different | 144 gems plus 6 stone coverage 150 Grid; The stones remain in place throughout the process |
| `M3-REFILL-01` | Removal occurs | Compaction supplement | Complete in x Increment, Segment from bottom to top, The lowest space in the segment draws colors upward; Use the subsequent sequence of this level, Until the disk is stable and the animation ends | Do not reset the random cursor, Do not copy surviving instances, Not unlimited busy | Whereabouts, Supplementary and chain batches are visible | Pause and freeze unfinished batches, Continue to resume the same settlement |
| `M3-GOAL-01` | All actions are stable | Check the target | Press this level goals Get Logical AND: Minimum score limit, The ice layer is cleared, Complete only when the specified color removal quota is met | You cannot just look at the total score, Pass the level if you reach one item or count the color count of the previous level into this level | Display the current value of each goal and whether it is completed. | All goals in the last step meet priority clearance, Otherwise the remaining steps 0 are lost |
| `M3-SCORE-01` | Real gems are removed | Normal or bonus batch | Each 10 Points; According to the original color of the removed gems, add one count to the count; score=10×cleared_total | Not due to ice layer, Stones, Repeated scoring in multiple lines or changing levels in the same grid | Color count, Scores are consistent with the board | Color quota excess allowed, Counting is not truncated; Retry the current level to zero |
| `M3-END-01` | Successful or the number of steps is exhausted | Settlement after stabilization | Successfully completed the campaign submission; Failed to keep the progress of this level and previous levels, Allow Retry/Menu/Exit | Cannot be used in busy Success in advance during the period, Determine failure first and then miss the last chain | The reason for failure or the level completion result is clear | Do not submit if it fails; The direction and dragging under the result layer are invalid |
| `M3-CAMPAIGN-01` | Menu, Level completion or final summary | Normal UI Confirm | Strictly abide by the CAMPAIGN_RULES three-level sequence, stages and Next conditions | not open for unfinished level selection, Skip level, same click to span two levels or treat partial success as the entire campaign is completed | current level / Total number of levels, Complete and subsequent entrances are clear | All UI Supports mouse and up and down selection /Enter; Old gestures cannot operate new scenes |
| `M3-COMMIT-01` | All goals of this level are met | Complete submission | Only append one of the current consecutive levels completed_results, Save the corresponding progress and cumulative statistics | No repeated submissions, Repeated bonus points, Submit failed levels or accumulated unfinished attempts | Number completed, The number saved is consistent with the placement record | After closing the completion page Continue Rebuilding the next level; After meeting all the goals of the level 3 Only the final summary will be displayed after the level is completed |
| `M3-RESET-01` | playing/paused/lost | R/Retry | The current level is completed Rebuild, run_serial Add 1, Keep the previous level submission record; Typhoon Restore the star collection after entering the level by chapter | do not return to the first level 1 Level, Do not use the old object / Random cursor / Enemies / Mechanism timing / Press and hold the state | Restore the clear initial state of this level | Continuous Retry The results are consistent; There is no level in the submitted level Retry |
| `M3-PERSIST-01` | Menu or close and reopen | Continue/New Campaign | Complete in CAMPAIGN_RULES Restore submitted boundaries; New process run_serial=0; New battles need to be confirmed and then cleared | Do not save unfinished levels, Do not read other tasks or v1 Old files, Restore two worlds without duplication | Continue Availability, The restored levels and invalid archive prompts are clear | No change in canceling the cleanup; Missing / Damage / Unknown formats are processed according to common rules |
| `M3-PAUSE-01` | playing/paused | Escape/Pause/Resume | Freeze / Restore all gameplay and timing; Keep the same level, The same transaction, The pause menu is normally available | Do not advance the frozen animation, Reset the timing, Overlay or let the overlay continue to respond | The pause layer is consistent with the actual control | Normal input in the result stage is invalid; Retry while paused / Return to menu According to common rules |
| `M3-CLEAN-01` | Level switching or retry | Create a new level | Only one active player / Board, One HUD and a set of timing input processing; Old level callbacks cannot modify new levels | No collisions left, Enemies, Event monitoring or old level entities ID | Screen, The number of objects is consistent with the current level | Repeat Next, Enter the menu repeatedly, After crossing the level Retry Do not destroy the completed level record |
| `M3-OBSERVE-01` | All stages | Read-only observation | Complete in DASHBOARD_REQUIREMENTS Report Real stage, Target, Resources, Level progress, Entities and hit areas | Cannot fabricate visible objects, Prefill unimplemented fields as answers, or add write status / Force success interface | Φ, Screen, Normal input effect is consistent with the archive | Old level data is not disguised as new level; Read-only query does not change the state |
| `M3-UI-01` | All player interfaces | Normal viewing and operation | Complete menu /HUD/ Description / Pause / Level and campaign results; Key content is visible and the area hit can be drawn according to it | Log cannot be used, Hide button, Empty network Grid or pure state interface instead of playable screen | Text can be equivalently expressed, Not specified OCR Password | Still hitting correctly even after the window size is adjusted by the system; Allow equivalent art that fits the theme and is identifiable |

## 7. Success and failure

The total battle score and total number of steps come from three submitted results. Only when the level is stable can it be judged that the level is completed; After meeting all the goals of the level 3 Complete the level is the victory of the campaign.  Success or failure cannot be established at the same time. Failure of the current level does not cancel the submission record of the previous level; Complete all three levels to form a complete campaign success. Normal gameplay input does not change the determined result in the result layer. 

## 8. Interface and feedback

HUD The score and score target of this level must be displayed(The quota target is clearly displayed when there is no score threshold), Remaining steps / Initial number of steps, Number of used steps and current chain batch; Levels with ice layers display the total number of remaining layers, After meeting all the goals of the level 3 Off to display the current count and target of red/blue . The level completion page displays the level score and the number of steps taken, The final page displays campaign_score and campaign_moves_used. 

Default client area 960×720. Display current level, Total progress of three levels, Goal of this level, Necessary resources and pause entrance; New mechanisms for each level should have explanations and visibility status. Level completion and campaign completion must be distinguishable. 
Actual visible objects, HUD and the target control must be consistent with the same periodΦ. cannot exist as a"entity list"Instead of actually drawing, , it cannot be required to use the same color as Gold , Font, node name or internal structure. interface copywriting with the same semantics allows equivalent expressions. 

## 9. Restart, Close, reopen and save

For complete rules, see CAMPAIGN_RULES: Retry Rebuild the current level; Menu/ Close and discard unsubmitted attempts; Continue Restore the next unfinished level; New Campaign Clear this battle after confirmation. For the submission statistics of each level and the additional data carried by this question, please see LEVEL_SPEC. 
Need to verify separately: Retry in the first level, Close and reopen after completing a level, Retry the next level without knowing the previous level, Continuous Next, Restart after final completion and cancel the new campaign confirmation. 

## 10. Basic functions that must be retained

Keep this GDD Normal input listed in clear text, Basic gameplay, Failure / Danger feedback, Pause, Restart, Exit and read-only observation; New mechanisms must work with them. v2 Is a stand-alone task, There is no requirement to preserve old engineering code, Old archive formats or old evaluation paths, Nor is runtime compatibility required v1. 

## 11. Materials and content

Layout, Values and mechanisms are in this public documentation package. Map derived data See the upstream license[MIT License](legal/UPSTREAM_MIT_LICENSE.txt), See the material boundaries assets/ASSET_MANIFEST.md. You can create equivalent art that you have permission to use; Add new organs / Obstacles must be discernible, Does not require copying of unauthorized original audio and video. No complete original source code provided, Gold, Private route, Score weight or answer status. 

## 12. Read-only dashboard contract

See[DASHBOARD_REQUIREMENTS.md](DASHBOARD_REQUIREMENTS.md). Generated from the authoritative state shared by gameplay and rendering revision, phase, slots, entities, targets, Cannot maintain the second set"Answer status". 
Field semantics have been implemented naming-tables.json, v3 Schema and self-test tools. Structural self-inspection does not replace real gameplay and screen acceptance, Cannot continue to use v1 Phase enumeration or fixed design Size guess actual hit area. Observation interface can only read, Cannot call game commands. 

## 13. Achieve free and public operation

Satisfy public behavior, Feedback, Data and life cycle are enough, Internal module, Object pool, Free collision and rendering organization. There is no mandatory fixed tool combination or development sequence. 
Build and run using `RUNNING.md` and `TOOLCHAIN.md`. `DEFOLD_ENGINE_INTERFACE_GUIDE.md` documents optional tools. Generation has a 3,600-second wall-clock limit enforced by the launcher.

## 14. Self-check before submission

- [ ] Complete three levels from the no-progress menu, No level jumps or status modifications in the middle. 
- [ ] The new mechanism and basic input of each level are established at the same time, Repeated operations do not count repeatedly or exceed authority. 
- [ ] Within the level Retry, Between levels Next, Menu/Continue, Close and reopen respectively in line with the submission boundary. 
- [ ] Each visible object, Buttons, HUD and saved progress can be explained by the real state. 
- [ ] Verified successfully, Failure / Danger, Pause, Continuous operation and cross-level cleanup; Static data inspection does not replace actual play. 
- [ ] Parameters, GDD, The observation vocabulary is consistent with the minimum project, The public package does not contain Gold, Scorer or private track.
