# Tide Lock — game design and delivery requirements

IDs identify individual requirements. `CONTENT.json` contains game data; the requirements below define the task.

## Concept and player input

- **TL-01.01** Build a single-player, third-person, single-level underwater facility repair game: a central hub connects routing, pressure and core-transfer sectors. All sectors are walkable from the start and can be completed in any order; each sector retains its own internal order. Complete all three, then perform the timed final lockdown. An initial full playthrough should take approximately 6–10 minutes; precision platforming is not the challenge.
- **TL-02.01** Use W/A/S/D for movement, mouse for third-person camera, Space for ordinary jumping and E for world ProximityPrompt interactions. No additional key is required for the main flow.
- **TL-02.02** R starts a completely clean run in Active, Failed and Completed states. It may be ignored while a text box has focus; normal play must not open a text input box.
- **TL-02.03** The failure overlay has a Retry button operated by a real left mouse click.

## Initial state and central hub

- **TL-03.01** Within 12 seconds of Play, the character is controllable, HUD visible, run Active, and all three systems incomplete. All sectors are reachable by ordinary walking.
- **TL-03.02** Initial HUD shows three system states, current objective, run timer and latest feedback. The routing board displays all three names in this run's order. The final console is locked.
- **TL-03.03** No sector locks another sector's entrance. A failed or missing sector must not block access to the other two.

## Routing

- **TL-04.01** Each new run chooses one complete permutation of Delta, Nova and Echo from the six possible permutations. It is stable during that run; R may produce the same or a different permutation.
- **TL-04.02** A clear text board displays all three names simultaneously in order. The three authoritative nodes have distinct TL_OrderIndex values 1, 2 and 3 matching the board. The order is a visible puzzle, not a hidden answer.
- **TL-04.03** E at the required node activates it and increases progress by exactly one. Within 1 second its authoritative base changes Color, Material or an attached light's enabled state.
- **TL-04.04** E at a node not yet required is rejected without losing progress or changing the order. E at an already active node is also rejected without progress change.
- **TL-04.05** After three correct activations RoutingComplete is true, progress is three and node visuals persist until R. Wrong actions provide feedback without killing the player or clearing another system.

## Pressure calibration

- **TL-05.01** Port and Starboard can be calibrated in either order. Each has a player-visible gauge and live public TL_GaugeValue in 0–100.
- **TL-05.02** First E changes Idle to Running and starts the gauge at zero. It follows a continuous triangle wave 0→100→0, with full period 8 seconds, tolerance ±0.8 seconds. Show the fixed inclusive safe interval [40,60] on the world gauge or HUD.
- **TL-05.03** E while Running locks the pump only when the live value is in [40,60], including both endpoints. The locked value freezes in that interval.
- **TL-05.04** E outside the interval changes only that pump to Rejected, gives early/late feedback, then returns it to Idle and zero after 1 second.
- **TL-05.05** E at a Locked pump is rejected as already locked. Both pumps Locked makes PressureComplete true. Normal death or failure elsewhere preserves locked pumps; R clears both.

## Core transfer, checkpoint and hazards

- **TL-06.01** A real touch at the transfer entrance activates the Transfer checkpoint and produces visible feedback.
- **TL-06.02** E at the rack when not carrying sets CarryingCore true. The unique authoritative core remains clearly visible and physically follows the character. Hiding it and changing an attribute alone is insufficient.
- **TL-06.03** Only one core exists. Operating the rack while carrying is rejected.
- **TL-06.04** ArcA, ArcB and ArcC are real damage hazards. Each alternates Inactive and Active, with each continuous phase lasting at least 2.5 seconds. Cycle lengths and phases may differ.
- **TL-06.05** Inactive physical contact does no damage. Active contact kills a default full-health character within 0.75 seconds. Visible color/material/particle changes match TL_HazardState and TL_Active. Safe waiting places separate hazards.
- **TL-06.06** Death while carrying, whether from an arc or ordinary Roblox death, preserves RunId and RunStart, increments DeathCount, and respawns near Transfer. The core returns to the rack within 2 seconds and CarryingCore becomes false.
- **TL-06.07** Ordinary death preserves completed routing, locked pumps and final state unless final failure has occurred. It is not R.
- **TL-06.08** E at the socket while carrying visibly installs the core, clears carrying and sets CoreTransferComplete true. The installed core cannot be picked up again. Socket E without a core is rejected.

## Final lockdown

- **TL-07.01** Both safety levers and the console are physically reachable before all systems complete. E gives system-not-ready feedback without advancing FinalStage or completion.
- **TL-07.02** All three complete changes FinalStage to Ready and HUD directs the player to Left. Right first at Ready is rejected and starts no timer.
- **TL-07.03** Left E changes to LeftArmed and starts a 10-second window. Right E within that window changes to DualArmed and starts a fresh 8-second confirmation window. Repeating an already armed lever is rejected.
- **TL-07.04** Only a real E inside the console's prompt range during DualArmed's 8-second window completes the run. Server time determines windows; at most 0.25 seconds input/replication tolerance is permitted.
- **TL-07.05** Expiry of either window makes RunState Failed. Show the failure overlay and clickable Retry. Further world interactions cannot advance the run.
- **TL-07.06** Retry preserves all three completed systems, resets final levers and windows, returns FinalStage Ready and RunState Active, increments RetryCount and closes the failure overlay.
- **TL-07.07** Successful confirmation sets RunState and CompletionState to Completed. Freeze FinalTime at nonnegative elapsed run time. Show the completion overlay, final time and R instruction. Further E cannot emit a second completion event.

## Clean restart and session lifecycle

- **TL-08.01** R completes within 2 seconds: strictly increase RunId, update RunStart, zero FinalTime and return the character near the central spawn.
- **TL-08.02** R clears all systems and pump states, displays the new routing order, returns the core to the rack, sets checkpoint Central and DeathCount zero, FinalStage Locked and RunState Active, clears overlays and restores initial world visuals. It must work in Active, Failed and Completed; no prior checkpoint or progress survives.
- **TL-08.03** A fresh Play after stopping/reopening starts clean and does not inherit progress from a prior Play session.

## HUD and feedback

- **TL-09.01** During play continuously display the three system states, full routing order and current step, both pump states and each running gauge with safe interval, carrying state, FinalStage/current objective, elapsed timer and latest feedback. Freeze the timer at completion.
- **TL-09.02** Each prescribed event has clear feedback visible for at least 1.5 seconds. HUD text, world visuals, Player attributes and authoritative object states agree.
- **TL-09.03** All required semantic HUD roles and overlays in the public contract exist and are readable at 1280×720. Failed and Completed overlays are distinct and show only in their corresponding states.

## Geometry and accessibility

- **TL-10.01** Every core objective is within 180 horizontal studs of central spawn. Continuous static walkways to sector entrances and core interactions are at least 10 studs wide with at least 8 studs headroom.
- **TL-10.02** Main progression does not require ladders, teleporting, moving platforms, precise jumps, pushing boxes or passing through decorative collision.
- **TL-10.03** Each of the ten world interaction targets has a unique, reachable, noncolliding TL_ApproachPoint on standing ground. A default character within 3 studs of its center is in prompt range; ordinary nonhazard target standing surfaces differ from the approach by at most 2 studs in height.
- **TL-10.04** TL_TransferWaypoint indices 0→1→2→3 define a safe walk route across the three hazards; each point is a standable safe waiting area.
- **TL-10.05** Default WalkSpeed 16 permits Left→Right and Right→console within their windows with at least 3 seconds left for interaction. All required player content exists in Play, not only Edit.

## Visual direction

- **TL-11.01** Present a coherent near-future underwater research station using readable low-poly native Roblox parts/materials: dark blue-gray metal, cyan work lights, limited amber warning highlights and red danger. No external mesh or paid asset is required. Remove default graybox/baseplate appearance, debug text and unfinished placeholders.
- **TL-11.02** Show central sector directions and console; three consistently designed labeled routing nodes and readable board; two pumps with 0–100 gauges and safe zones; glowing core/rack/socket/checkpoint/three arcs/safe platforms; separated Left/Right levers and confirmation console. HUD hierarchy must leave character and main targets visible.
- **TL-11.03** Objects are recognizable from shape, color, lights and labels. Aim for two visible activation differences (for example color plus light). Active arcs look dangerous and inactive arcs safe but locatable. The carried core stays visible near the character without obscuring the camera. Text must not overlap, clip or leave the safe screen area.
- **TL-11.04** Support four representative ordinary-player views: V1 initial hub with locked console/incomplete HUD/no overlay; V2 at least one active routing node plus running pump/visible board, gauge and safe zone; V3 visibly carried glowing core plus active arc and safe waiting area with matching HUD; V4 completed final area, completed lever/console visuals, readable completion/time/R overlay and no leftover failure/debug UI. These are public state descriptions, not pixel-matching reference images.

## Public contract and implementation freedom

- **TL-12.01** Implement `contracts/GAME_SESSION_SPEC.md`, `contracts/SESSION_MODEL.json` and the public constants. Discoverable tags identify actual authoritative objects; state mirrors cannot replace real physics, normal input and UI. No Capture/Restore or chapter jump service exists in this historical contract; evaluation must not add one silently.
- **TL-12.02** Layout, orientation, room shapes, instance names/hierarchy, source architecture, decoration and equivalent UI layouts may vary while preserving the specified rules and public identities.
- **TL-12.03** Do not auto-complete, add hidden completion keys or teleport shortcuts, move normal characters directly with CFrame, fake Touched, fake carrying without a physical core, modify only attributes, replace E interactions with UI clicks or detect evaluator processes/files to change behavior.
- **TL-12.04** Follow the delivery and 3600-second development requirements in `INITIAL_AGENT_PROMPT.md`. Ship a full, reproducible dependency closure and accurately report Play checks and untested items.
