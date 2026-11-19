# Typhoon v2 Public segmented routes and wind stations

campaign.json.world Completely retained 67×67 Routes, 99 Stars, 7 Checkpoint, 196 Spikes and groups Combined collision parameters; Three chapters advancing along the same world, Does not require flying three times, Does not increase monsters or limited lives. rows First line y=66, Every grid 16 World pixels; Grid center[(x+0.5)×16,(y+0.5)×16]. #and P Solid; S Yes or no solid birth mark, C/*/F None of them are walls. 

| Chapter | Entry location / Initial respawn point | Current target | Additional mechanism |
|---|---|---|---|
| 1 departure | Original spawn_position, [88,88]; checkpoint_index=0 | Current touch CP1 | Basic navigation |
| 2 wind_station | CP1 Center; checkpoint_index=1 | Enabled A Once and currently touched CP4 | CP2 Wind station A and local wind zone |
| 3 wind_network | CP4 Center; checkpoint_index=4 | A, B Both enabled and currently touched F | CP5/CP6 Wind station, Overlapping wind zone, Mutually exclusive power supply |

Checkpoint number press world.checkpoints_cells Array from 1 Start. The complete map always exists, But only according to this chapter goal Judgment of completion; You cannot skip chapters if you contact the subsequent targets in advance. The level completion point of the three chapters is connected with the birth point of the next chapter, Next Clear the dynamic state of this chapter and enter the next chapter at 0 speed. 

## Fly Row and collision

Balloon reference position corresponding 22×32 Outer bounding box center; Airbag circle center relative[0,5], Radius 11; Gondola center[0,-9], Half width 3 Half height 7. Collision according to combined shape, Cannot use the entire outer frame to replace the solid body. Ordinary wall /P Blocks normal movement and eliminates the velocity towards the wall, Allows tangential sliding; No death when hitting the wall. 
Horizontal thrust 36, Lift 36, Gravity 18, Horizontal damping 18, Unit is world pixels / Seconds. A/Left and D/Right On the contrary, While holding offset; Space/W/Up apply lift. let go and still have inertia, wind and gravity. damping pushes the speed 0 without reverse direction; horizontal speed limit after the combined force±30, upward speed limit 30, downward speed limit 60, Follow world.physics. 
Camera view 256×144 World pixels, Follow and limit to 1072×1072 Boundaries; HUD Fixed to client area. Spikes are fixed spike_cells Center 12×12 Danger zone, Not randomly generated, Don't treat invisible background as a danger. 

## Synthetic wind and wind station operation

Global wind usage world.wind of 20 Second segment table, The clock is the current chapter elapsed, including resurrection waiting but not pause / Results. Each chapter starts from 0 Start, The cycle of the previous chapter is not inherited. 
Local wind zone rect=[left,bottom,width,height]is the world pixel; Judge based on the balloon reference point, Left / The lower boundary includes, The right / The upper boundary does not include. When overlapping, only select the id smallest area, Do not overlay all areas. If no area is selected, the additional wind is 0. 
total wind=The current global Wind+Selected area acceleration+A wind station that is associated with the selected area and has power supply powered_acceleration. Closing the wind station only removes its power supply increment, Does not remove the basic wind of the area itself. 
Distance from the wind station position Does not exceed 32 , E pressed Switch to the nearest station; Select the one with the smaller letter. Press and hold to release and switch only once, Over distance does not change any status. Switch from off to on Record this chapter for the first time used Mark, Repeated switching does not increase the count, Close without deleting Except used. 
After meeting all the goals of the level 2 Chapter Only A; After meeting all the goals of the level 3 Chapter A/B Mutually Exclusive, On A Also Off B, On B Also Off A. Both Stations used Can be true at the same time; The mission does not require both stations to be powered on at the same time. The stage goal requires all stations listed in this chapter used and the target is currently in contact. Leave after reaching the target, No remote automatic clearance is allowed when completing the wind station mission. 

## Stars, Dangers and chapter affairs

Stars use static grid coordinates as global unique keys, At most 99. Body contact 12×12 Remove once in the star zone, Removed items cannot be counted again. This Resurrection within the chapter retains the collection collected in this chapter, Wind station power supply and used Record. 
Checkpoint 32×32 The trigger area only updates the latest rebirth point, No order required; Other points are no longer active. Danger trigger retries Add 1, Only once, enter 1.5 Uncontrollable wait for seconds, Return to the nearest point in this chapter(or starting point of this chapter), speed 0; There is no lost, Number of lives or Timeout failed. 
If danger and star recovery / Interaction / Checkpoint / The target occurs in the same update, Danger priority, Cancel these new submissions in this frame; The old progress of this chapter is still retained. Pause, freeze, respawn and wait for all gameplay. 
When the chapter is successful, merge the new stars in this chapter into committed_star_cells, Save the results of this chapter; Next/Continue When entering the next chapter, These stars will no longer appear, But the wind station is full off, used All false, elapsed/retries are 0, Resurrection point to take the chapter initial_checkpoint. 
Retry, Return to the menu for unfinished chapters or close and reopen, Undo the new stars that have not been submitted in the current chapter and restore the baseline when entering the chapter committed_star_cells . The death and resurrection in this chapter cannot be confused with the complete Retry : The former retains this chapter and attempts, the latter withdraws this chapter without committing changes. 

## Save statistics and ratings

completed_results Each entry contains level_index, elapsed, retries, stars_delta, stations_used(All required sites in this chapter must be used). Save as committed_star_cells, There must be no duplicates and all belong to world  99 stars in; whose number is equal to the sum of submitted stars_delta . station status and intra-chapter coordinates are not saved across chapters. 
campaign_elapsed, campaign_retries only the sum of submitted records is obtained; stars_collected in the active chapter represents the union of the entry collection and the new addition to this chapter, inactive menu / the final summary only represents the submitted collection. The interface distinguishes the statistics of the current chapter and the statistics of the submitted campaign, The same chapter value cannot be added once after completion. 
After meeting all the goals of the level 3 Rating after chapter submission: A Requires global 99 Stars, cumulative retries=0 and cumulative elapsed<600; otherwise B requires stars≥80, retries≤4 and elapsed<900; remaining completions are C. rank Numerical values ​​ A/B/C are 3/2/1, Other stages 0. 
Campaign completion does not require all 99 stars or an A rank; a valid C-rank completion is accepted. Validate star reachability, Chapter 3 routes and mechanism interactions through normal gameplay. Valid static coordinates alone are not gameplay evidence.
