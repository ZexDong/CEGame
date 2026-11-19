# Three-level battle: Status, Progress and life cycle

This is v2 a common part of the public requirement draft, with this question GDD and campaign.json Read together. Only defines player-visible actions and read-only observations, Does not specify internal modules, Scenario organization or development steps. 

## Battle process

Fixed for each question 3 Level, Complete in 1→2→3 order. No level selection, Skip level, Debugging victory or automatic progress replenishment. 
First startup display New Campaign, Continue, Controls, Exit; When there is no valid progress Continue Inoperable. New Campaign Display confirmation first when there is progress, Cancel without changing any data, Confirm to clear the progress of this question and start from 1 Level. 
Controls Only switch the description page, Do not create a level, Time or consumption Resources. 

After meeting all the goals of the level 1, 2 , Complete the submission once and enter level_clear, Freeze the gameplay of this level; Provide Next, Menu, Exit. Next Only create the next level once, You cannot skip the levels that have not yet been cleared. After meeting all the goals of the level 3 After the level has met all the goals, submit it once and enter Enter campaign_won, Remove the active gameplay object, Display the cumulative results of the three levels and New Campaign, Menu, Exit. Normal direction / Action keys do not change the final data. 
Press and release at the same time, The same mouse click cannot confirm the old panel, and operate the new level; New The panel must not inherit the direction held in the old level, drag state or callback. 

playing medium Escape or visible Pause enter paused; Resume/Escape resume the same level. pause and freeze gameplay time, animation, Collision, spawn monsters, invincible window, mechanism timing and resurrection waiting; UI Still operable. Twice in a row Escape Return to the original stage, Cannot superimpose the pause layer. Clear the continuous direction when entering the pause, The hold state of lift and rewind, A new press is required before re-applying these continuous inputs after resumption; Newly pressed gameplay keys during the pause are not queued. Accepted match-3 settlements or frog jumps are only frozen, do not cancel, Resume and then continue the original transaction. 
R/Retry only reopen the currently uncompleted level in playing, paused, lost ; do not return to the first level 1 Level, do not clear the submitted previous level progress. level_clear are not provided Retry; To replay the completed level, you must explicitly open it New Campaign. campaign_won Also only allowed when new campaign, menu and exit. 

from playing/paused/lost Return Menu , Prompt and discard unsubmitted attempts at the current level; Continuing the campaign will rebuild the entry status of the level, Do not continue the midway position. The menu will not advance the gameplay. Close the process and only retain the submitted levels. 
Typhoon There is no lost stage; danger resurrects in the current chapter according to the rules of this question. 

## the only progress submission rule

when completing the n level, only if it is the current unfinished level(n=cleared_levels+1)and all the success conditions of this question have been met, can add one completed_results And change cleared_levels from n−1 to n. re-entry callback, Repeated clicks, Pause or exit cannot be re-submitted. 
When level_clear/campaign_won announces that the progress has been saved, the corresponding record should have been placed. on the completion page Next will not add points again or Write duplicate records. 
Cumulative statistics are only summarized completed_results, Current attempts are listed separately; Retry, Returning to the menu and reopening will not mix unfinished attempts into the cumulative value. 

## Close, reopen and archive

Only save the level boundary, Do not save the entities of unfinished levels, Time, Enemies, animation, Random cursor or temporary input. Typhoon Additionally save the star grid collection submitted by the completed chapter, See it for details LEVEL_SPEC. 
New process enters the menu first, run_serial=0. When there is 1 or 2 valid progress of the level, Continue Create a clean entry for the cleared_levels+1 level Level status; All 3 When the level is completed, Continue Only open the completed campaign summary, Do not regenerate the gameplay or add points. 
The entry baseline of each level is subject to campaign.json and the submitted data of the previous level. All dynamic level objects, Monitoring, Collisions and old level delayed tasks must be cleared; Two levels of players or two sets cannot exist at the same time HUD. 

The default archive uses this question task_id Exclusive application data directory, Cannot be read v1, Other tasks, Original or other candidate archives. If an absolute path is provided at startup Path environment variables BENCHMARK_PROFILE_DIR, are used in the directory campaign-v2.json, to facilitate isolation of different runs; It only selects the archive location, does not provide a state change or jump interface. 
The file is UTF-8 JSON, including schema_version=2, task_id, campaign_id, cleared_levels and completed_results; Typhoon and committed_star_cells. completed_results must have exactly cleared_levels items, level_index is a continuous sequence starting from 1 , See this question for statistical fields LEVEL_SPEC. 
Missing files are treated as new files; Syntax error, Unknown schema, task_id/campaign_id Inconsistent, Level index jump, Illegal values ​​or files with repeatedly submitted records cannot be partially restored, Return to the no-progress menu and display a short description. No need to migrate Move the old format, It is not required to read the old high score. Regular writing must completely replace the record, Avoid closing and reopening to read half of the record JSON. 
If the actual writing fails, It must be clearly stated that it is not saved, and report it truthfully saved_levels; You cannot lie about the number of passes in the memory as having been placed. The test will not require the game to break through the file permissions of the host system. 

## Public read-only observation

Continue to use revision, phase, slots, entities, targets Five parts. Already supported Dashboard v3 Machine readable word list and minimum project; The new stage and the actual client area space shall be subject to this question naming-tables.json and DASHBOARD_SPEC.md , Do not use v1 Fixed space. 

| Field | Definition |
|---|---|
| phase | not_ready / menu / playing / paused / level_clear / campaign_won / lost; Typhoon Not used lost |
| slots.level_index | When there are active levels, it is 1–3; Menu, not_ready and the final battle summary is 0 |
| slots.client_width / slots.client_height | The current complete client area coordinate range; targets.rect Uses the same unit, Includes actual white space / Viewport offset. Pressable x/client_width, y/client_height Map to full client area, Design aspect ratio cannot be second-guessed |
| slots.level_total | Implemented tasks are 3; Unimplemented not_ready Starting points are handled as Not Ready Contracts |
| slots.cleared_levels | Number of consecutive levels this campaign has submitted in memory, 0–3 |
| slots.saved_levels | Number of consecutive levels that have been actually successfully saved recently, 0–3; Not possible It is assumed that the total is consistent with the memory |
| slots.run_serial | The number of times this process has created levels; Start/Retry/Next/Continue Add each unfinished level 1, Simple menu cut / Pause / Open the final summary without adding |
| entities | Objects that currently exist and are generated by the gameplay / rendering shared state; Old levels cannot remain; Static backgrounds and entities should be described truthfully if they are still drawn |
| targets | Currently truly visible / Interactive controls and actual hit areas, Use the coordinates of the lower left origin of the client area in this question |

Controls kind Includes menu_new_campaign, menu_continue, menu_controls, menu_exit, controls_back, new_confirm, new_cancel, pause_button, pause_resume, level_retry, return_menu, next_level, campaign_new, exit_button; Only publish currently existing controls. Continue When disabled visible=true, interactable=false. Confirm new campaign, Pause, Controls under overlays such as level results cannot be interacted. 
This question can be added Add normal action targets with clear semantics, Cannot add command injection, teleport, set_score, force_win or arbitrary write state interface. Entity ID Stable within the lifetime of the same object; New level / Must be distinguishable from old instances when retrying to create a new object, Cannot allow old tasks to update new objects. 

Window shrink After resizing or resizing by the system, The mouse click must still be consistent with the rendering control; Cannot mix logical design coordinates, Window pixels and world coordinates. Screenshots and the same periodΦMust be cross-checked, ΦThe existence in does not mean that the picture has been drawn.
