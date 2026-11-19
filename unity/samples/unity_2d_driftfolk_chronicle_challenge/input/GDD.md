# Driftfolk: Stormbound Archipelago

Public revision: `stormbound-docv2-v1-20260918`  
Benchmark ID: `unity.driftfolk_stormbound.v2`

## 1. Required delivery

Create a **complete playable two-island survival-and-logistics game plus its required game-session/v1 services**. Both are mandatory. Automated acceptance uses the public services to enter the real game, capture and restore complete legal situations, and find actual visible objects. Missing or incorrect services can lose credit for the requirements that genuinely depend on them; a decorative or separate simulated service is not sufficient. The ordinary player journey must also work from the lobby through either ending.

This is a new reconstruction from an art-and-tools starter, not an extension of an existing game. Do not implement just a prototype, isolated rule, or mock state reporter. No game implementation is supplied.

## 2. Authority and scope

This GDD is the sole behavioral authority. `SESSION_MODEL.json` is the sole authority for initial values, balancing numbers, controls, state identities, editable fields and legal save relationships. References to its tables below do not introduce a second rule set. `GAME_SESSION_SPEC.md` owns common service semantics, and `BENCHMARK_MANIFEST.json` owns file paths.

Included: two islands sharing a single ferry; six individually managed residents; distinct island inventories; jobs, fatigue, morale and health; a repeating weather cycle; construction with local prerequisites, work and cancellation; blocking narrative decisions; ordered escape stages; a causal chronicle; speed, pause and explicit single-period step; real Save/Load, both endings, Restart and fresh-process Reopen. Excluded: networking, multiplayer, procedural extra islands, combat, additional recipes, recruitment or reproduction, mods, online services and additional save slots.

The listed balance is intentional. The player's challenge is to distribute work and rest, keep each island supplied, move cargo and residents without duplicating them, build both beacons and reunite the survivors for escape. Supplied modular media must be assembled into a coherent maritime world; no fixed layout or reference composition is required.

## 3. Complete player flow

Lobby -> clean archipelago -> inspect residents and inventories -> assign jobs and manage time -> build and ship supplies -> resolve mandatory decisions -> prepare both islands -> complete escape or lose every resident -> review result and chronicle -> Restart. Save/Load remains available during active, paused, decision and terminal states. A new process opens at the lobby; a stored run is continued only by explicit Load.

Every keyboard action in `rules.controls` needs an equivalent visible, labelled player control. Selection and the meaning of contextual event keys are visible. Disabled choices and invalid orders provide useful feedback without changing the simulation.

## 4. Numbered gameplay requirements

### FLOW-01 — Entry and clean world

Launch shows a title, premise, Start and explicit Load. Start/Enter creates the exact clean world in `rules.initial`, with six named map residents, island inventories, unbuilt construction sites, docked ferry, untouched escape project and one opening chronicle entry. Every clean Start uses the public seed. The lobby may hide or defer creating world objects: capture their stable identities and initial semantic values with truthful presence flags, and instantiate the real visible world on Start or chapter entry. Start never silently restores the disk slot.

### SELECT-01 — Player management

Island, resident, building and cargo selection follow the published controls. All selectors show the selected object. A living land resident can be assigned exactly one job; aboard or dead residents cannot be assigned or added to a passenger manifest. Island selection clears the draft cargo/passenger manifest, not actual resources or residents. Invalid repeated commands do not accumulate costs, work or side effects.

### TIME-01 — Deterministic periods and work order

At 1x, a period completes after `rules.period_seconds` real seconds; higher speeds multiply elapsed simulation time, not the rule outcomes. Each complete tick processes, in order: eligible resident jobs and fatigue; local construction using available builders; ferry travel/arrival; escape work using home builders not consumed by local construction; night consumption/pressure when the old period was night; deaths and extinction; escape completion if still legal; date advance and next day's weather; then the earliest unresolved due narrative event. Every completed tick advances exactly one period in morning/day/night order. A large frame may process multiple ticks, but must stop immediately on an event or ending and must not accumulate hidden catch-up time behind that blocker. All randomness or ordering needed for continuation is saved. Same state and normal inputs produce the same state and chronicle regardless of speed or Save/Load.

### TIME-02 — Pause, step and modal boundaries

Escape/pause freezes automatic time and every simulation quantity, including fractional tick time. `N`/Step is an explicit exception: only while paused, playing and without a decision, it completes exactly one whole tick, sets the fractional remainder to zero and leaves pause intent selected. It does nothing while running, in the lobby, during a decision or after an ending. Pause may be changed during a decision and must survive resolving it. While a decision modal is open, all other management/selection commands are blocked; only its choices, pause intent, Save, explicit Load, chronicle scrolling and Restart operate. UI selection, permitted management commands and Save/Load remain usable while paused; they do not themselves advance time. Speed controls are contextual: event keys choose options rather than changing speed. No latent held key can cause a command to repeat after Load, Restart or a dismissed modal.

### WORK-01 — Local production, fatigue and rest

Only a living land resident below the fatigue cutoff can work. Job, location and fatigue eligibility are determined at the start of the tick for all production, healing, construction and escape work; fatigue gains during that tick do not remove already eligible work, and ferry arrivals begin working only on the next tick. Forage, timber and ore jobs add their base output to that resident's own island; the workshop bonus applies to local timber/ore output. Storm forage and low-morale output divisors apply successively with integer flooring. Every non-resting land resident gains the listed working fatigue on a tick, including one too tired to produce; rest recovers the listed fatigue. Aboard residents recover neither work fatigue nor rest during transit and never produce. Values are clamped. A job change affects subsequent ticks without retroactively changing previous output.

### HEALTH-01 — Treatment, food, heat and death

Eligible medics with a completed local clinic heal the lowest-health living resident on their own island, resolving ties by stable resident ID, up to maximum health. They do not heal aboard residents or revive the dead. On a night tick each island pays its complete local living-resident food requirement, consuming all available food if insufficient. A shortage damages every living land resident there and reduces morale by the published amount; full payment increases morale. Heating is similarly local and weather-dependent; its shortage deals the published damage, halved with a local beacon. Passengers consume their separate ferry-food requirement and suffer the food-shortage health/morale penalty if it is not met. Actual cargo food is consumed once, never a duplicate island stock. Dead residents immediately stop work, cease counting as living and leave the live passenger manifest, but retain a distinct visible deceased representation and named chronicle outcome. Pressure counts each inhabited island with either food or heating shortage once, not once per missing resource. If no inhabited island has a shortage, apply the fully-supplied-night change once; apply the storm change once as well. These changes use the public numbers and clamp the final pressure to range. Empty islands create neither consumption nor shortage. Extinction requires zero living residents, not merely an empty selected island.

### WEATHER-01 — Visible coherent weather

The current weather follows the published repeating day cycle. It changes at day boundaries, is visible on both islands and affects forage, heating and ferry movement as specified. Pause, decisions and endings stop weather progression. The visual storm/rain state and resource consequences must agree.

### BUILD-01 — Two independent construction pipelines

Each island offers Workshop, Clinic and Beacon with its published local cost, prerequisite and work requirement. At most one building per island is under construction; the two islands can progress concurrently. Ordering is atomic: check state, local prerequisite, local stock and available local construction slot before deducting the full cost once. Insufficient resources, a repeated order, a built structure or unmet prerequisite changes nothing. Each eligible local builder contributes the published work per tick to that island's active construction, capped at its remaining work. Builders used by local construction cannot also advance escape that tick. Completion changes the visible structure and its actual capability. A finished structure is not charged or built again.

### BUILD-02 — Construction cancellation and refunds

Cancel affects only the selected unfinished building. Return each charged material's `floor(cost * remaining_work / total_work)` to its own island, reset it to unbuilt with zero work and free the local slot. Work already spent is lost. Invalid and repeated cancellation changes nothing. Previously completed prerequisites are not cancelled. Save/Load cannot charge the order again, increase the refund or duplicate construction.

### FERRY-01 — Atomic loading and exclusive ownership

The draft manifest displays selected cargo and up to the passenger capacity, but does not remove anything until departure. The ferry must be idle at the selected island. Dispatch atomically verifies total cargo capacity, passengers' actual presence, each local cargo stock and the separate departure food cost. Only then deduct cargo and departure cost, move selected residents into the ferry, clear the draft and start the published travel duration toward the other island. Food cargo and departure food are additive costs. Any failure leaves world, draft and resources unchanged. One resident cannot exist on land and aboard; one item unit cannot be in two inventories.

### FERRY-02 — Transit, arrival and interruption

Each non-storm tick decreases remaining travel by one; a storm tick does not decrease it. Transit cargo/passengers are visible and cannot be unloaded, reassigned, charged again or dispatched elsewhere. At zero remaining, unload surviving passengers and remaining cargo once onto the destination island, then empty the boat and dock it there. A storm delay, overnight passenger consumption, pause, decision, save or restore never duplicates cargo or arrival. A resident who dies aboard is not resurrected or unloaded as a living passenger.

### EVENT-01 — Scheduled blocking choices

Events become due at the completed-tick thresholds in `rules.events`, once per run. If several are due, present the lowest unresolved ID; resolving it presents the next already-due event before automatic time resumes. Each modal shows its title, description, two choices, costs and disabled conditions. Its normal buttons and contextual 1/2 keys apply exactly one defined consequence. Unaffordable, repeated, empty and out-of-range input changes neither state nor resolution bits. Resolution records a causal entry and preserves pause/speed intent. Consequences that kill the final survivor immediately create extinction, not a return to running play.

### ESCAPE-01 — Sequential paid stages

Both beacons are required to begin any escape stage. All stage costs come from the home island. `E`/Begin deducts the current stage's costs once and commits it; eligible home builders not used by construction advance it on ticks. A paid stage can be suspended/resumed by E without another payment or loss of accumulated work. Completion records the stage, advances to the next stage with zero work and requires a new explicit Begin. The final stage additionally requires all living residents at home and the ferry docked there before it can start, receive work or complete. A paid final stage may remain suspended or unable to work while these conditions are temporarily false; it is not silently cancelled or repaid. Invalid repeated starts change nothing. Escape occurs only after real final-stage work completes with survivors still alive.

### ESCAPE-02 — Cancellation and shared worker safety

`V`/Cancel cancels only the current unfinished escape stage, refunds each charged resource by the same remaining-work fraction as construction, and clears its work/payment/activity. Completed stages remain completed. A resident contributes work at most once per tick across local construction and escape. Repeated cancel, suspension, Load or Restart never duplicates escrow, progress, refunds or completed-stage rewards.

### CHRONICLE-01 — Causal persistent history

The chronicle is visible, scrollable, day/period-labelled and oldest-to-newest. It records the opening and meaningful production/shortages, named resident changes and deaths, construction orders/cancellation/completion, ferry departure/arrival, weather, event decisions, escape stages/cancellation and both endings. Entries have increasing stable IDs, name affected people/islands/facts and state the consequence. They remain readable beyond thirty entries. Capture/Restore and Load restore history without inventing actions or duplicating entries. Same saved state plus same actions produces the same semantic record, including stable ordering.

### SAVE-01 — Complete in-memory service state

Implement the common game-session/v1 contract and every legal relationship in SESSION_MODEL. Capture is detached and side-effect free. Restore reconstructs real visible residents, structures, ferry, inventories, exact fractional time, pause/speed, event and escape state plus the ordered history. Published editable values must not be overridden by opaque history or implementation data. Reject invalid requests atomically. Service completion suspends gameplay until ResumeSimulation; normal menu and player controls still work independently.

### SAVE-02 — Real player Save/Load

F5/Save writes one local slot with clear success feedback. F9/Load explicitly restores its complete saved state from any listed phase, including a pending event, fractional period, moving loaded ferry, partial construction, suspended paid escape stage and either result. Repeated Load must remain exact without additional costs, events, residents, chronicle entries, ambience or input listeners. A missing or malformed slot is rejected visibly and atomically; it does not reset or partly corrupt the active world. Do not require a network service. A process crash or unavailable file cannot be reported as a successful save.

### END-01 — Stable escape and extinction

Escape and extinction show different readable summaries, the final chronicle and Restart. Terminal states stop automatic simulation, production, work, travel and all mutable management actions; Save, explicit Load, chronicle scrolling and Restart remain available. Death/extinction has priority if a tick would otherwise complete escape. Results and ending feedback occur once. One island having no living residents is not extinction while survivors exist elsewhere or aboard.

### RESTART-01 — Clean reusable restart

R/Restart from playing, paused, event, suspended escape or either result restores the exact initial playing archipelago within two seconds. Date, residents, resources, weather, pressure, selections, draft, ferry, projects, history, event resolution, fractional time, speed and pause must all reset. The disk slot is left intact but is not automatically loaded. Repeating Restart leaves one world, one input response and one ambience stream.

### REOPEN-01 — Independent-process continuity

After closing the process, a new process opens at the lobby without runtime state or automatic loading. Start is clean. Explicit Load restores the prior saved slot, including a save made during transport or a pending decision, and subsequent normal inputs continue coherently. Source generation or the in-memory session service cannot substitute for the actual disk save/load flow.

### PRESENT-01 — Readable complete maritime presentation

At 1280x720, both island areas, their separate inventories, named resident locations/jobs/health/fatigue/morale, weather/pressure, selected controls, building costs/work/prerequisites, draft and transit cargo/passengers, escape stage/payment/work, clock/speed/pause, event choices and chronicle are readable and non-overlapping. Map residents and ferry visibly correspond to their locations and state. Completed buildings have distinguishable supplied-media states. Controls communicate unavailable actions and rejections. Use the supplied modular visuals for terrain, residents, buildings, resource symbols, weather, escape and interface; supplemental styling is allowed, replacement by a text-only spreadsheet is not. Equivalent layouts and rendering frameworks are accepted.

### AUDIO-01 — Coherent audible feedback

Use supplied audio for maritime ambience and distinct meaningful feedback for player actions, warnings/events, construction, travel, saving/loading and the two endings. State transitions and repeated Restart/Load must not create stacking ambience or uncontrolled repeated cues.

## 5. Development and delivery boundaries

Use normal New Input System keyboard and pointer input. Internal code organization, object hierarchy, simulation architecture, UI framework and save format are your choice; public semantics and observable results are not. The contact sheet shows isolated supplied parts, not a required scene layout. Public checks are optional development aids, not an implementation and not a guarantee of complete gameplay. Keep immutable supplied media and contract files intact and create the full game in the declared writable paths.
