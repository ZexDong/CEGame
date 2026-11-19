# Typhoon Balloon: Wind Station Route Battle

## 1. One sentence task

Complete three consecutive voyages in the complete original route, Calibrate the wind station and deal with local wind areas, Keep cross-chapter star progress and completed chapter records. 

## 2. This range

### 2.1 Must be completed

Complete 67×67 Map and 99 Stars, 7 Checkpoint, 196 Spikes; Three consecutive segments Continued objectives; Local wind zone, E Operation of wind stations and mutually exclusive power supply in Chapter 3; Resurrection from normal danger, Archives between levels and final rating. 

### 2.2 Does not contain

Repeat the entire route three times, Limited life or Game Over, Forced to collect all the stars to pass the level, Random storm, Fuel economy, Weapons, Online and in-game saves.  Do not add unlisted mechanisms or undisclosed acceptance conditions. 

### 2.3 Original work and adaptation

The base gameplay is adapted from the upstream game of the same name. The three-chapter campaign, additional mechanisms, delivery requirements and persistence rules are specific to this benchmark. Third-party audio and video are not supplied. See [asset notes](assets/ASSET_MANIFEST.md) for available materials and licensing.

## 3. Starting state

The supplied `starter_project/` contains the Dashboard v3 transport, machine-readable naming tables and public self-check tools. It starts in `not_ready`, reports the window size and supports `Q` to quit. Implement gameplay and persistence according to the requirements below.
When the player runs the completed version for the first time without a valid save, Start from the main menu without progress. The effective level initial state and entry baseline are determined by[LEVEL_SPEC.md](LEVEL_SPEC.md), [campaign.json](campaign.json)Definition. 

## 4. Player goals and complete process

After meeting all the goals of the level 1 Chapter arrives at the checkpoint from the original starting point 1 → After meeting all the goals of the level 2 Chapter starts from the checkpoint 1 Starts, Enables the checkpoint 2 Wind Station A And arrives at the checkpoint 4 → After meeting all the goals of the level 3 Chapter starts from the checkpoint 4 Starts, Enable checkpoints respectively Checkpoint 5/6 Wind Station A/B Arrived after F → Battle Rating. 

can only be used through the normal keyboard / The mouse completes the entire process, Does not rely on debugging commands, File injection, Change dashboard, Change scores or skip levels. See common stages and transaction semantics[CAMPAIGN_RULES.md](CAMPAIGN_RULES.md). 

## 5. Player operations

| Actions | Normal input | Semantics |
|---|---|---|
| left/right | A/D or Left/Right | Continuously applying horizontal thrust; While holding offset |
| lift | Space/W/Up | Continuously applying lift; Release is still affected by inertia, Gravity and wind effects |
| interact | E pressed |  32 Switch to the nearest wind station within the world pixel range; Isometric press A  B Before; Don't long press to continue |
| pause / restart | Escape / R | Pause or try again from the baseline of this chapter |
| UI Confirm | Left click to complete Full click, Up and down selection and Enter | Menu, Description, Pause, Retry, Next, Continue, Clear file confirmation and exit; Only operate the current real control |

The interface and gameplay cannot consume the same gesture at the same time. The value of each control, For the conflict sequence and clock definition, see LEVEL_SPEC. 

## 6. Numbering requirements  The only task-level acceptance basis

The following requirements together with LEVEL_SPEC, campaign.json, CAMPAIGN_RULES constitute the public task boundary; [COMMON_BASELINE.md](COMMON_BASELINE.md)Supplementary general quality requirements. The same parameter is subject to the current level value of campaign.json , The value of another level cannot be hard-coded. Conflicts are found between documents and parameters The sudden change must be corrected before freezing, Another answer cannot be set by the private grader. 

| Requirement number | Preconditions | Player operation or trigger | Results that must occur | Results that cannot occur | Visible feedback to players | Failure, Repeat, Restart Boundary |
|---|---|---|---|---|---|---|
| `TB-WORLD-01` | Create the current chapter | Start/Next/Continue/Retry | Create the same public complete map; Use the spawn point of this chapter, Checkpoint baseline, Wind Zone and Wind Station; Remove submitted stars | Cannot move walls randomly / Spikes, Cannot treat S or wind areas as new solid walls | World, Wind station and current chapter target are distinguishable | Next Do not copy old active objects; Static global stars are deduplicated by grid identification |
| `TB-FLIGHT-01` | playing and are not resurrected | Normal direction / Lift input | Thrust in public seconds, Damping, Gravity, Speed ​​limit and synthetic wind points; Can move at the same time / Lift-off | Cannot release hover, Press to teleport, Level switching inherits the old speed or crosses the wall | Balloon movement, Wind arrow and speed status are consistent | Menu / Pause / Flight input is not accepted while waiting for resurrection |
| `TB-SOLID-01` | Contact ordinary wall /P Platform | Physical movement | Press the public airbag circle+Gondola rectangular block, Remove the normal speed towards the wall, Allow sliding along the wall | The entire outer bounding box cannot be used to replace the assembly, Ordinary wall contact will cause death or pass through the wall | The graphics are consistent with the collision | The default landing is stable and can be lifted off the ground |
| `TB-ZONE-01` | Second / Chapter 3 | enter, Leaving or crossing the wind zone | Based on whether the reference point is within the open half-open rectangle, select the lowest id area; total wind=global periodic wind+basic wind in this area+increment of powered wind stations in this area | overlapping areas are not all added; no power applied by unpowered stations; regional wind must not remain in the leaving area | HUD Clear the area number, Total wind direction and wind station switch | Pause and freeze the global wind cycle; The area selection changes with the real position |
| `TB-STATION-01` | Controllable and distance from a certain wind station≤32 | E One press | Switch the nearest station power supply; Record this chapter from off to on for the first time Use bits; Chapter 3 to open one station and close another station | Remote invalid, Long press cannot switch repeatedly, Touched but not pressed E Cannot complete the calibration task | Station letter, The status and operation prompt are consistent | Repeating the switch does not repeat the counting task; off Do not clear used records |
| `TB-CHAPTER-01` | Touch the target of this chapter | Physical contact | After meeting all the goals of the level 1 Chapter target CP1; After meeting all the goals of the level 2 Chapter required A Used and currently in contact CP4; After meeting all the goals of the level 3 Chapter required A/B Both used and currently in contact F | Cannot pass the level just based on the switch record of having been to the target or other chapters; Cannot touch in advance F Skip the previous chapter | When not satisfied, it will prompt that there is still a missing wind station, It will be displayed as completed when it is satisfied | Using the mechanism is not an automatic pass; You must still reach the current target after the conditions are met |
| `TB-CHECKPOINT-01` | Current chapter playing | Touch 32×32 Checkpoint area | The most recent actual activator becomes the respawn point of this chapter, Not forced to order; Other points are no longer active | Cannot predict future checkpoints or use the last position of the old chapter as the starting point of the new chapter | The current respawn point is clearly displayed | The new chapter is configured initial_checkpoint Start; Dangers in this chapter retain the closest point |
| `TB-STAR-01` | Body contact 12×12 Star area | Physical contact | Each global star grid can only be collected once; This chapter will be resurrected and retained. This chapter has already received stars, Chapter change and retention has been submitted for collection. | Submitted stars will not be generated repeatedly due to return visits or chapter changes, Do not re-accumulate 99 into 297 | Stars /99 consistent with the actual remaining objects | Retry/ Close and reopen when unfinished Cancel unsubmitted stars for this chapter, Only restore entry set |
| `TB-HAZARD-01` | Hit a spike or cross the boundary | Danger judgment | Only add once retries, 1.5 Return to the nearest point or the starting point of this chapter after uncontrollable seconds, speed 0; Keep the stars of this chapter, Wind station power and usage records | Cannot deduct life, Directly Game Over, Repeatedly during resurrection Accumulate or transfer to another chapter | Danger and resurrection countdown visible | Danger priority in the same frame, Cancel the new star collection in this frame / Switch / Checkpoint / Complete; Pause and freeze waiting |
| `TB-CARRY-01` | Successful submission of this chapter | Next/Menu/ Close and reopen | Save the new global star collection and the time of this chapter / Number of retries; Rebuild the wind station and timing according to its own baseline in the next chapter | Stars of unfinished chapters cannot be saved together, Time, Wind station or halfway position | Progress in three chapters, Global star number and saved progress can be checked | Next and Continue Enter the same clean chapter; Retry Return to the entry base of this chapter only Line |
| `TB-RANK-01` | After meeting all the goals of the level 3 Chapter submission completed | Display campaign summary | Complete in campaign.json Cumulative time for three submitted chapters, Number of retries, Global star number calculation A/B/C; Other stages rank=0 | Cannot be rated by single chapter time, Repeated accumulation of previous chapters or failure to judge the correct C level implementation function | Stars, Accumulated time, Cumulative retries and ratings are on the same screen | New Campaign Clear all; Continue Only summary of completed files will be reproduced, No more submission |
| `TB-CAMPAIGN-01` | Menu, Level completion or final summary | Normal UI Confirm | Strictly abide by the CAMPAIGN_RULES three-level sequence, stages and Next conditions | not open for unfinished level selection, Skip level, same click to span two levels or treat partial success as the entire campaign is completed | current level / Total number of levels, Complete and subsequent entrances are clear | All UI Supports mouse and up and down selection /Enter; Old gestures cannot operate new scenes |
| `TB-COMMIT-01` | All goals of this level are met | Complete submission | Only append one of the current consecutive levels completed_results, Save the corresponding progress and cumulative statistics | No repeated submissions, Repeated bonus points, Submit failed levels or accumulated unfinished attempts | Number completed, The number saved is consistent with the placement record | After closing the completion page Continue Rebuilding the next level; After meeting all the goals of the level 3 Only the final summary will be displayed after the level is completed |
| `TB-RESET-01` | playing/paused | R/Retry | The current level is completed Rebuild, run_serial Add 1, Keep the previous level submission record; Typhoon Restore the star collection after entering the level by chapter | do not return to the first level 1 Level, Do not use the old object / Random cursor / Enemies / Mechanism timing / Press and hold the state | Restore the clear initial state of this level | Continuous Retry The results are consistent; There is no level in the submitted level Retry |
| `TB-PERSIST-01` | Menu or close and reopen | Continue/New Campaign | Complete in CAMPAIGN_RULES Restore submitted boundaries; New process run_serial=0; New battles need to be confirmed and then cleared | Do not save unfinished levels, Do not read other tasks or v1 Old files, Restore two worlds without duplication | Continue Availability, The restored levels and invalid archive prompts are clear | No change in canceling the cleanup; Missing / Damage / Unknown formats are processed according to common rules |
| `TB-PAUSE-01` | playing/paused | Escape/Pause/Resume | Freeze / Restore all gameplay and timing; Keep the same level, The same transaction, The pause menu is normally available | Do not advance the frozen animation, Reset the timing, Overlay or let the overlay continue to respond | The pause layer is consistent with the actual control | Normal input in the result stage is invalid; Retry while paused / Return to menu According to common rules |
| `TB-CLEAN-01` | Level switching or retry | Create a new level | Only one active player / Board, One HUD and a set of timing input processing; Old level callbacks cannot modify new levels | No collisions left, Enemies, Event monitoring or old level entities ID | Screen, The number of objects is consistent with the current level | Repeat Next, Enter the menu repeatedly, After crossing the level Retry Do not destroy the completed level record |
| `TB-OBSERVE-01` | All stages | Read-only observation | Complete in DASHBOARD_REQUIREMENTS Report Real stage, Target, Resources, Level progress, Entities and hit areas | Cannot fabricate visible objects, Prefill unimplemented fields as answers, or add write status / Force success interface | Φ, Screen, Normal input effect is consistent with the archive | Old level data is not disguised as new level; Read-only query does not change the state |
| `TB-UI-01` | All player interfaces | Normal viewing and operation | Complete menu /HUD/ Description / Pause / Level and campaign results; Key content is visible and the area hit can be drawn according to it | Log cannot be used, Hide button, Empty network Grid or pure state interface instead of playable screen | Text can be equivalently expressed, Not specified OCR Password | Still hitting correctly even after the window size is adjusted by the system; Allow equivalent art that fits the theme and is identifiable |

## 7. Success and failure

There is no lost Or life limit. You will really wait for hitting the spikes 1.5 Seconds and resurrect; Chapter completion requires the use conditions of the current target Zephyr Station in this chapter, No Is it just touching any checkpoint or F.  Success or failure cannot be established at the same time. Failure of the current level does not cancel the submission record of the previous level; Complete all three levels to form a complete campaign success. Normal gameplay input does not change the determined result in the result layer. 

## 8. Interface and feedback

HUD must display the current chapter time, global star number /99, this chapter retries, current respawn point, synthetic wind direction / strength, current wind area and wind station power supply of this chapter / usage status; clearly prompts the current chapter program Standards and missing wind stations. The final page shows the cumulative time of the three submitted chapters, Number of retries, Global stars and ratings. Current chapter statistics and cumulative statistics cannot be confused with the same meaning. 

Default client area 1024×576. Display current level, Total progress of three levels, Goal of this level, Necessary resources and pause entrance; New mechanisms for each level should have explanations and visibility status. Level completion and campaign completion must be distinguishable. 
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
