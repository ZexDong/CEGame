<!-- Generated from the reviewed DOCX. GDD Section 6 is the sole source of game-specific requirements. -->

Reactor Relay Protocol Game Design Document

Public implementation specification

| Field | Value |
| --- | --- |
| Document purpose | Define the complete player-facing game contract for implementation and independent evaluation |
| Audience | Game implementation agent and reviewers |
| Game format | Single-player real-time control puzzle |
| Difficulty target | Very high, with deterministic information and no hidden random outcomes |
| Document version | 2.0 Hard |

This document defines a compact but demanding reactor-control game. The player must stabilize three bays across six timed cycles, manage shared resources, respond to a fixed incident schedule, and complete a final synchronization sequence. Section 6 is the sole source of game-specific acceptance requirements. All other sections summarize those requirements by identifier.

# 1 One Sentence Task

Build a playable reactor-control puzzle in which the player balances three bays through six timed cycles and completes a final synchronization sequence, with clear success, failure, warning, Restart, and reopen behavior defined by CORE-01 through VISUAL-01.

# 2 Scope

## 2.1 Required Scope

| Requirement group | Summary |
| --- | --- |
| CORE-01 through CORE-14 | Menu, three-bay control loop, stability delay, ordered locking, armed cycle commitment, and six-cycle progression |
| RULE-01 through RULE-12 | Shared resources, timer, deterministic incidents, scan, purge, penalties, order reset, arm expiry, loss, and complete input semantics |
| FINAL-01 through FINAL-03 | Eight-symbol preview, timed replay, and mutually exclusive terminal states |
| UI-01 through UI-06 | HUD, bay panels, action feedback, unavailable controls, warnings, and fixed logical layout |
| RESET-01 through RESET-02 | Clean Restart and clean reopen without saved progress |
| VISUAL-01 | Coherent, readable reactor presentation with state cues |

## 2.2 Excluded Scope

| Related requirement | Excluded content |
| --- | --- |
| None | Multiplayer, online services, monetization, leaderboards, procedural levels, and long-term progression |
| RESET-02 | Saved campaigns, cloud saves, and resume-from-last-cycle behavior |
| VISUAL-01 | A mandatory external art pack or prescribed implementation architecture |

# 3 Starting State

| Item | Starting state | Requirement |
| --- | --- | --- |
| Entry | A menu with a visible Start action | CORE-01 |
| Player role | A single reactor operator | CORE-01 |
| Run state | No active cycle before Start | CORE-01 |
| Initial resources | Initialized only after Start | CORE-02 and RULE-01 |
| Interface | Menu first, then the HUD and three bay panels | UI-01 and UI-02 |
| Persistence | No prior run is restored | RESET-02 |

# 4 Player Goal and Complete Flow

## 4.1 Player Goal

The player allocates limited power and coolant, aligns each bay phase, locks all three stable bays, and commits six cycles before integrity or fault limits cause loss. The run then ends with the synchronization sequence in FINAL-01 through FINAL-03.

## 4.2 Complete Player Flow

Enter menu → CORE-01 start a run → CORE-03 select bays → CORE-04 through CORE-08 match and hold each target → CORE-09 lock bays in the cycle order → CORE-11 and CORE-14 arm commit → CORE-12 commit within 3 seconds → RULE-05 and RULE-06 respond to the next incident → CORE-13 repeat through Cycle 6 → FINAL-01 observe the preview → FINAL-02 enter the sequence → FINAL-03 reach Won or Lost → RESET-01 restart or RESET-02 close and reopen.

## 4.3 Main Loop

CORE-03 select a bay → CORE-04 through CORE-06 adjust values → CORE-07 and CORE-08 compare current and target state → CORE-09 lock the stable bay → repeat for all bays → CORE-11 complete ordered locking → CORE-14 arm commit → CORE-12 commit within 3 seconds → read the incident summary and plan the next cycle.

# 5 Player Operations

| Requirements | Player action | When used | Response summary |
| --- | --- | --- | --- |
| CORE-01 | Click Start | Menu | Begin Cycle 1 |
| CORE-03 | Click Bay A, B, or C | Active cycle | Select one bay |
| CORE-04 through CORE-06 | Click plus, minus, left, or right controls | Selected bay is unlocked | Adjust one value and update shared resources |
| CORE-09 | Click Lock Bay | Selected bay is stable and next in order | Lock the bay and advance lock progress |
| CORE-14 | Click Arm Commit | All bays are locked in order | Open the 3-second commit window |
| CORE-12 | Click Commit Cycle | All bays are locked and commit is armed | Resolve and advance once |
| RULE-07 | Click Scan Next Incident | A scan charge remains | Reveal the next incident briefly |
| RULE-08 | Click Emergency Purge | An unlocked bay is selected and purge is available | Reset that bay with an integrity cost |
| FINAL-02 | Click bay symbols | Final input window | Replay the synchronization sequence |
| RESET-01 | Click Restart | Any non-menu state | Start a clean run |

# 6 Numbered Requirements

The following table is the sole formal definition of game-specific requirements. Each row describes an independently testable player-facing result.

## 6.1 Requirement Table

| ID | Precondition | Action or trigger | Required result | Prohibited result | Visible feedback | Boundary behavior |
| --- | --- | --- | --- | --- | --- | --- |
| CORE-01 | The menu is visible | Select Start | A playable run begins and the briefing gives the six-cycle objective | The game must not begin behind the menu | The board replaces the menu and Cycle 1 is identified | Repeated activation while a run is active has no effect |
| CORE-02 | A new run begins | The board initializes | Cycle is 1, integrity is 100, faults are 0, scan charges are 1, emergency purge is available, lock progress is 0, commit is unarmed, and no bay is locked | No value may carry over from an earlier run | The HUD and all three bay panels show the initial state | This same state is used after Restart |
| CORE-03 | The run is active | Select Bay A, B, or C | Exactly one bay becomes selected and all bay controls apply to it | Selecting a bay must not change its resources or lock state | The selected bay is visually distinct and named in the HUD | Selecting the already selected bay is a no-op |
| CORE-04 | An unlocked bay is selected | Increase or decrease its power | The bay power changes by exactly one within 0 to 4 and the shared pool changes by the opposite amount | Power must not become negative, exceed 4, or exceed the shared pool | Bay power and unallocated power update immediately | A blocked adjustment leaves state unchanged and explains why |
| CORE-05 | An unlocked bay is selected | Increase or decrease its coolant | The bay coolant changes by exactly one within 0 to 3 and the shared pool changes by the opposite amount | Coolant must not become negative, exceed 3, or exceed the shared pool | Bay coolant and unallocated coolant update immediately | A blocked adjustment leaves state unchanged and explains why |
| CORE-06 | An unlocked bay is selected | Rotate its phase left or right | The phase changes by exactly one step and wraps through the ordered values minus 2, minus 1, 0, 1, and 2 | One complete click must not advance more than one step | The phase value and dial marker update immediately | Left from minus 2 wraps to 2 and right from 2 wraps to minus 2 |
| CORE-07 | A cycle is active | Read a bay panel | Each bay shows its current power, coolant, and phase beside that cycle's target values; after all incident effects, the three power targets total no more than 7 and the three coolant targets total no more than 6 | Targets must not be hidden, ambiguous, or collectively impossible within the shared pools | Current and target values remain visible until the cycle is committed | The target set changes only when a new cycle begins |
| CORE-08 | A bay is unlocked | Adjust its three values | Its status reports Stable only after all three values continuously match its target for 0.75 seconds and otherwise reports Unstable | A partial or shorter match must not report Stable | Status text, a 0.75-second stability indicator, and a distinct visual treatment update with every adjustment | Returning to a mismatch immediately resets the stability interval and restores Unstable |
| CORE-09 | The selected bay reports Stable and is the next bay in the cycle's frozen lock order | Select Lock Bay | The bay becomes locked for the current cycle and lock progress advances by one | An unstable or out-of-order bay must not remain locked | The bay reports Locked, its controls become unavailable, and the next required bay is shown | An unstable attempt follows RULE-04 and an out-of-order stable attempt follows RULE-11 |
| CORE-10 | A bay is locked | Try any bay adjustment | Its values and the shared pools remain unchanged | A locked bay must not consume resources or rotate phase | The bay remains visibly locked and a short message explains the block | The lock is cleared only by a new cycle, Restart, or Emergency Purge on that bay |
| CORE-11 | The run is active | Lock bays in the frozen cycle order | Arm Commit becomes usable only while all three bays are locked with lock progress 3 | Arm Commit and Commit Cycle must not be usable with any unlocked bay | Lock progress, next required bay, and Arm Commit availability update immediately | A purge or lock-order reset clears lock progress and commit armed state |
| CORE-12 | All three bays are locked and commit is armed | Select Commit Cycle before the 3-second arm window expires | The cycle resolves once, applies the scheduled incident, advances the cycle, returns allocated resources to the shared pools, clears bay locks, and loads the next targets | An unarmed or expired click must not resolve a cycle, and one click must not resolve two cycles | A resolution summary identifies the incident and the new cycle | After Cycle 6, resolution proceeds to the final synchronization instead of Cycle 7 |
| CORE-13 | Cycles 1 through 6 are active | Complete every cycle | The player must stabilize and commit all three bays in each of the six cycles | The final synchronization must not appear before Cycle 6 is committed | Progress shows the current cycle out of 6 | Any loss condition stops cycle progress |
| CORE-14 | All three bays are locked with lock progress 3 | Select Arm Commit | Commit becomes armed for exactly 3 seconds while the cycle timer continues | Arm Commit must not resolve the cycle or pause either timer | The HUD shows Armed and the arm-window time remaining, and Commit Cycle becomes available | Repeated Arm Commit clicks during the same window do not extend or duplicate the window |
| RULE-01 | A new cycle begins | Resources reset for allocation | The shared power pool is 7 and the shared coolant pool is 6 before any bay allocation | Unused resources must not carry into the next cycle as a bonus | Both pool values appear in the HUD | Emergency Purge can alter a bay but does not increase these pool maxima |
| RULE-02 | A cycle begins | Time passes | An 18-second countdown starts and reaches zero in real time | The timer must not pause during selection, adjustment, stability waiting, locking, or commit arming | Seconds remaining are continuously visible and the final 5 seconds are emphasized | The timer stops in won, lost, menu, and final synchronization states |
| RULE-03 | The cycle timer reaches zero | Timeout resolves | Each unlocked bay adds one fault and removes 20 integrity, after which the next cycle begins unless a loss condition is reached | A locked bay must not add a timeout fault | The summary names every timed-out bay and the integrity loss | Three unlocked bays can therefore cause three faults and 60 integrity loss |
| RULE-04 | The selected bay is Unstable | Select Lock Bay | One overload is recorded for that bay and integrity decreases by 8 | The bay must remain unlocked and its values must not be corrected automatically | The bay flashes an overload warning and the HUD updates integrity | Further wrong lock attempts repeat the penalty |
| RULE-05 | A new run begins | Cycles advance | Incidents occur in this fixed order: Cycle 2 Coolant Leak on Bay B, Cycle 3 Phase Drift on Bay C, Cycle 4 Power Surge on Bay A, Cycle 5 Dual Leak on Bays A and C, and Cycle 6 Crossfeed on Bays B and C | No incident occurs in Cycle 1 and the order must not randomize | The active incident and affected bays are visible | Restart returns the schedule to its beginning |
| RULE-06 | An incident is active | Apply its effect | Coolant Leak adds 1 to the affected coolant target, Phase Drift rotates the affected phase target one step right, Power Surge adds 1 to the affected power target, Dual Leak applies Coolant Leak to both named bays, and Crossfeed swaps the named bays' power targets | Adjusted targets must remain within their legal ranges | Affected target values and an incident explanation update together | If an addition would exceed its maximum, that target wraps to 0 |
| RULE-07 | At least one scan charge remains | Select Scan Next Incident | One charge is consumed and the next cycle's incident name and affected bay or bays are revealed for 4 seconds | Scanning must not change current targets or cycle state | A temporary preview and remaining charge count are visible | At 0 charges, the control is unavailable and state does not change |
| RULE-08 | Emergency Purge is available and an unlocked bay is selected | Select Emergency Purge | The selected bay's allocations and phase return to 0, returned resources rejoin the shared pools, the bay's overload count clears, integrity decreases by 20, and purge becomes unavailable for the run | Purge must not lock or stabilize the bay automatically | The affected values, integrity, purge availability, lock progress, and commit armed state update together | Purge is blocked on a locked bay or after it has been used |
| RULE-09 | A run is active | Integrity or faults change | The run enters Lost immediately when integrity reaches 0 or faults reach 4 | Cycle controls must not remain active after loss | A failure panel states the triggering condition and offers Restart | Further gameplay input cannot change the terminal state |
| RULE-10 | Any clickable control is visible | Perform one complete press and release inside it | The control fires at most once | Press-only, release-only, or crossing the boundary between press and release must not activate it | The resulting state change or no-op feedback is observable | Rapid complete clicks are handled as separate actions without duplicate listeners |
| RULE-11 | A selected bay is Stable but is not the next bay in the cycle's frozen lock order | Select Lock Bay | Integrity decreases by 10, that bay gains one overload, every bay becomes unlocked, lock progress returns to 0, and commit becomes unarmed while all allocations remain unchanged | The out-of-order bay must not remain locked and the system must not silently accept the wrong order | The HUD identifies the required first bay and reports the order reset | A later correct attempt can restart the order without reallocating resources |
| RULE-12 | Commit is armed but Commit Cycle is not selected within 3 seconds | The arm window expires | Integrity decreases by 10, every bay becomes unlocked, lock progress returns to 0, commit becomes unarmed, and all allocations remain unchanged | The cycle must not resolve and the 18-second cycle timer must not restart | The HUD reports Commit Arm Expired and shows the first required bay | If the cycle timer reaches zero first, RULE-03 resolves instead and the arm-expiry penalty is not also applied |
| FINAL-01 | Cycle 6 resolves without loss | Observe the synchronization preview | The game displays the fixed eight-symbol sequence A, C, B, A, C, B, C, A one symbol at a time for 0.60 seconds each with a 0.25-second blank gap, then starts a 6-second input window | Sequence input must not be accepted during the preview | The current preview symbol and then eight empty input slots are visible | Restart during this phase starts a new run |
| FINAL-02 | The input window is active | Select bay symbols | Each correct next symbol fills one slot and advances sequence progress | A wrong symbol, a ninth input, or timeout must not be accepted as partial success | Filled slots show the accepted symbols and time remaining stays visible | A wrong symbol or timeout follows FINAL-03 |
| FINAL-03 | The synchronization input window is active | Complete or fail the sequence | Entering A, C, B, A, C, B, C, A within 6 seconds enters Won; any wrong symbol or timeout enters Lost | Won and Lost cannot both occur and neither can return to active play without Restart | The terminal panel states Reactor Synchronized or Synchronization Failed | Terminal state remains stable under further bay and control input |
| UI-01 | The board is visible | Read the HUD | The HUD shows cycle, seconds remaining, integrity, faults, unallocated power, unallocated coolant, scan charges, purge availability, selected bay, lock progress, next required bay, commit armed state, and arm-window time | Displayed values must not lag behind the playable state | Labels and values remain readable at the supported window size | Terminal panels may replace timers but must retain the final integrity and fault values |
| UI-02 | The board is visible | Read the bay panels | Bay A, Bay B, and Bay C are simultaneously distinguishable and each shows current values, target values, stability, lock state, and overload count | Information for one bay must not appear under another bay's identity | Each bay has a persistent name and separate status treatment | Incident emphasis does not hide any required value |
| UI-03 | Any accepted, blocked, or penalized action occurs | Observe feedback | A concise message identifies the action and result within 0.25 seconds and remains readable for at least 1 second | A success message must not appear for a blocked action | Messages distinguish resource limits, locked controls, wrong locks, scans, purge, incidents, and terminal outcomes | A newer message may replace an older one |
| UI-04 | A control cannot legally act | Observe and try the control | The control is visibly unavailable when possible and activation leaves gameplay state unchanged | Unavailable controls must not silently consume a resource | Disabled appearance and explanatory feedback agree with the state | This applies to Arm Commit, Commit Cycle, Scan, Purge, and locked-bay adjustments |
| UI-05 | The timer is at 5 seconds or less or integrity is 25 or less | Observe the board | The relevant warning becomes visually prominent without hiding controls or values | The warning must not change gameplay values by itself | Timer and integrity warnings are distinguishable | Warnings clear after Restart and update when the condition no longer holds |
| UI-06 | The menu or board is rendered | Observe the interface at any supported desktop viewport | The game uses the fixed 1600 by 900 logical canvas, bay-panel rectangles, and 19 control rectangles in Section 6.2, uniformly letterboxed when the viewport aspect ratio differs | Controls must not be independently reflowed, reordered, mirrored, or placed outside their frozen logical rectangles | Every visible control occupies its declared rectangle and remains readable | The evaluator uses live engine AbsolutePosition and AbsoluteSize; the logical rectangles are a deterministic consistency contract, not permission to ignore engine geometry |
| RESET-01 | Any non-menu state is active | Select Restart | The game returns to the exact new-run state in CORE-02 and starts Cycle 1 with the schedule reset | No old timer, target, lock, listener, sequence input, or terminal overlay may remain | The board visibly refreshes and a new Cycle 1 timer starts | Repeated Restarts still produce one clean run |
| RESET-02 | The application is closed during any state | Open it again | The menu appears with no saved run progress | The prior cycle, resources, incidents, or terminal state must not resume | Start is available and no gameplay HUD is active before starting | This task has no persistence requirement |
| VISUAL-01 | Menu, active play, warning, and terminal states are shown | Observe the presentation | The reactor theme, three-bay structure, current targets, hazards, and terminal outcome are visually coherent and distinguishable | Debug text, broken placeholders, overlapping controls, or unreadable contrast must not appear | State changes use readable text plus a second cue such as color, icon, motion, or sound | Equivalent visual composition is allowed when all required information remains clear |

## 6.2 Frozen Deterministic Data

Target tuples use Power/Coolant/Phase. Effective targets are the player-visible values after the fixed incident for that cycle is applied.

| Cycle | Base A | Base B | Base C | Incident | Effective A | Effective B | Effective C |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2/1/0 | 3/2/1 | 2/3/-1 | None | 2/1/0 | 3/2/1 | 2/3/-1 |
| 2 | 1/2/-1 | 3/1/2 | 2/2/0 | Coolant Leak B | 1/2/-1 | 3/2/2 | 2/2/0 |
| 3 | 4/1/1 | 1/2/-2 | 2/3/0 | Phase Drift C | 4/1/1 | 1/2/-2 | 2/3/1 |
| 4 | 2/2/-2 | 2/1/1 | 2/3/2 | Power Surge A | 3/2/-2 | 2/1/1 | 2/3/2 |
| 5 | 3/1/2 | 2/2/0 | 2/1/-1 | Dual Leak A C | 3/2/2 | 2/2/0 | 2/2/-1 |
| 6 | 1/2/0 | 4/1/-2 | 2/3/2 | Crossfeed B C | 1/2/0 | 2/1/-2 | 4/3/2 |

The frozen lock orders are Cycle 1 A/B/C, Cycle 2 B/C/A, Cycle 3 C/A/B, Cycle 4 B/A/C, Cycle 5 A/C/B, and Cycle 6 C/B/A. A bay must match continuously for 0.75 seconds before it becomes Stable. Arm Commit opens one non-extendable 3-second window. The final sequence is A/C/B/A/C/B/C/A with a 6-second input window.

All rectangles use logical X/Y/Width/Height coordinates inside a 1600 by 900 canvas. Bay panel rectangles are A 60/120/480/400, B 560/120/480/400, and C 1060/120/480/400.

| Target | Logical rectangle | Target | Logical rectangle | Target | Logical rectangle |
| --- | --- | --- | --- | --- | --- |
| start_button | 600/390/400/120 | restart_button | 1340/28/180/52 | lock_button | 980/560/180/56 |
| bay_a | 80/145/440/56 | bay_b | 580/145/440/56 | bay_c | 1080/145/440/56 |
| power_minus | 80/560/120/56 | power_plus | 220/560/120/56 | arm_button | 1180/560/160/56 |
| coolant_minus | 380/560/120/56 | coolant_plus | 520/560/120/56 | scan_button | 80/650/260/56 |
| phase_left | 680/560/120/56 | phase_right | 820/560/120/56 | commit_button | 1360/560/160/56 |
| purge_button | 360/650/260/56 | sequence_a | 440/480/200/110 | sequence_b | 700/480/200/110 |
| sequence_c | 960/480/200/110 |  |  |  |  |

# 7 Success Failure and Stages

## 7.1 Success

| Requirements | Steps before success | Success condition | Terminal state | Feedback |
| --- | --- | --- | --- | --- |
| CORE-12 through CORE-14 and FINAL-01 through FINAL-03 | Arm and commit six complete cycles, observe the preview, and replay A C B A C B C A | All eight symbols are correct within 6 seconds | Won | Reactor Synchronized panel |

## 7.2 Failure

| Requirements | Failure condition | Terminal state | Feedback | Retry |
| --- | --- | --- | --- | --- |
| RULE-09 | Integrity reaches 0 or faults reach 4 | Lost | Panel identifies integrity or fault limit | RESET-01 |
| FINAL-03 | Wrong synchronization symbol or 6-second timeout | Lost | Synchronization Failed panel | RESET-01 |

## 7.3 Stage Summary

| Stage | Requirements | Summary | Must not appear early |
| --- | --- | --- | --- |
| Menu | CORE-01 | Start the game | Active HUD and cycle timer |
| Cycles 1 through 6 | CORE-02 through CORE-14 and RULE-01 through RULE-12 | Stabilize, lock in order, arm, commit, and respond to incidents | Final synchronization |
| Final synchronization | FINAL-01 through FINAL-03 | Observe and replay the sequence | Won before all five correct inputs |
| Terminal | RULE-09 and FINAL-03 | Remain Won or Lost until Restart | Further gameplay changes |

# 8 Interface and Feedback

| Requirements | Information | When updated | Player distinction |
| --- | --- | --- | --- |
| UI-01 | Run resources and progress | Every state change and timer tick | Current operational limits |
| UI-02 | Three bay states and targets | Every selection, adjustment, incident, lock, and cycle | Bay identity and readiness |
| UI-03 | Action result message | Within 0.25 seconds of an action | Accepted, blocked, or penalized |
| UI-04 | Control availability | Whenever its precondition changes | Available versus unavailable |
| UI-05 | Critical timer and integrity warnings | At the defined thresholds | Time risk versus integrity risk |
| UI-06 | Frozen logical canvas, bay panels, and control rectangles | At every render and viewport change | Deterministic placement with uniform letterboxing |
| VISUAL-01 | Overall presentation | Across menu, play, warnings, and terminal states | Theme and state without debug artifacts |

# 9 Restart Reopen and Saving

| Scenario | Requirement | Reset | Preserve | Final state |
| --- | --- | --- | --- | --- |
| Restart current run | RESET-01 | All run values, targets, locks, timer, incidents, sequence, overlays, and listeners | Nothing from the old run | Fresh Cycle 1 board |
| Close and reopen | RESET-02 | All run progress | No gameplay progress | Menu with Start |

# 10 Existing Functions

Not applicable. This is an original standalone task, so no legacy player function is required.

# 11 Assets and Content

| Requirement | Content | Hard requirement | Player-facing use | Equivalent replacement |
| --- | --- | --- | --- | --- |
| VISUAL-01 | Reactor control room presentation | Yes | Communicate the three bays, hazards, warnings, and terminal state | Allowed if all required states remain clear |
| None | Decorative models, textures, icons, and audio | No | Support the reactor theme | Allowed |

# 12 Dashboard Naming and Operation

The names below mirror concepts already defined in Section 6. They form a read-only observation contract and do not add gameplay requirements.

## 12.1 Numeric Slots

| Slot name | Meaning | Requirements |
| --- | --- | --- |
| revision | Monotonic state revision | RULE-10 |
| cycle | Current cycle from 1 through 6 | CORE-13 |
| time_remaining | Seconds left in the current timed phase | RULE-02 and FINAL-02 |
| integrity | Current integrity from 0 through 100 | CORE-02 and RULE-09 |
| faults | Current fault count | CORE-02 and RULE-09 |
| unallocated_power | Power remaining in the shared pool | CORE-04 and RULE-01 |
| unallocated_coolant | Coolant remaining in the shared pool | CORE-05 and RULE-01 |
| scan_charges | Remaining incident scans | RULE-07 |
| purge_available | Whether Emergency Purge remains available | RULE-08 |
| selected_bay | 0 for none, 1 for A, 2 for B, 3 for C | CORE-03 |
| lock_progress | Number of bays locked in the cycle order | CORE-09 and RULE-11 |
| expected_lock_bay | Next required bay in the frozen lock order | CORE-09 and RULE-11 |
| commit_armed | Whether the 3-second commit window is active | CORE-14 and RULE-12 |
| arm_time_remaining | Seconds left in the current commit arm window | CORE-14 and RULE-12 |
| sequence_index | Number of accepted final symbols | FINAL-02 |

## 12.2 Entities and Clickable Targets

| Category name | Meaning | State values | Requirements |
| --- | --- | --- | --- |
| bay_a bay_b bay_c | The three reactor bays and their selectable targets | unlocked_unstable unlocked_stable locked_stable faulted | CORE-03 through CORE-10 |
| incident_panel | Current incident display | none coolant_leak phase_drift power_surge dual_leak crossfeed | RULE-05 and RULE-06 |
| run | Overall phase | menu cycle preview sequence won lost | CORE-01 RULE-09 FINAL-03 |
| start_button | Start target | visible hidden | CORE-01 |
| power_minus power_plus | Selected-bay power targets | available unavailable | CORE-04 |
| coolant_minus coolant_plus | Selected-bay coolant targets | available unavailable | CORE-05 |
| phase_left phase_right | Selected-bay phase targets | available unavailable | CORE-06 |
| lock_button arm_button commit_button | Ordered lock, commit arm, and commit targets | available unavailable armed expired | CORE-09 through CORE-14 and RULE-11 through RULE-12 |
| scan_button purge_button | Limited-use support targets | available unavailable | RULE-07 and RULE-08 |
| sequence_a sequence_b sequence_c | Final synchronization targets | available unavailable | FINAL-01 through FINAL-03 |
| restart_button | Clean Restart target | visible hidden | RESET-01 |

## 12.3 Operation Declaration

| Item | Content |
| --- | --- |
| Movement template | Pointer clicks on visible controls; no character movement is required |
| Primary input | Complete left-button press and release inside one target |
| Optional shortcuts | Keys 1, 2, and 3 may select Bay A, Bay B, and Bay C, but pointer controls must remain available |

# 13 Implementation Boundary

- Section 6 is the complete source of game-specific player requirements.
- The dashboard is the only public read-only observation channel. It reports player-visible and runtime state, but cannot perform actions, change values, or declare completion.
- Classes, object hierarchy, algorithms, data structures, and component choices are not acceptance targets.
- Supported engine input, scene entry, user interface, and observation compatibility belong in the public toolchain contract rather than this document.
# 14 Requirement Index

| Requirement | Area | Player goal summary |
| --- | --- | --- |
| CORE-01 | Main cycle control and progression | A playable run begins and the briefing gives the six-cycle objective |
| CORE-02 | Main cycle control and progression | Cycle is 1, integrity is 100, faults are 0, scan charges are 1, emergency purge is available, lock progress is 0, commit is unarmed, and no bay is locked |
| CORE-03 | Main cycle control and progression | Exactly one bay becomes selected and all bay controls apply to it |
| CORE-04 | Main cycle control and progression | The bay power changes by exactly one within 0 to 4 and the shared pool changes by the opposite amount |
| CORE-05 | Main cycle control and progression | The bay coolant changes by exactly one within 0 to 3 and the shared pool changes by the opposite amount |
| CORE-06 | Main cycle control and progression | The phase changes by exactly one step and wraps through the ordered values minus 2, minus 1, 0, 1, and 2 |
| CORE-07 | Main cycle control and progression | Each bay shows its current power, coolant, and phase beside that cycle's target values; after all incident effects, the three power targets total no more than 7 and the three coolant targets total no more than 6 |
| CORE-08 | Main cycle control and progression | Its status reports Stable only after all three values continuously match its target for 0.75 seconds and otherwise reports Unstable |
| CORE-09 | Main cycle control and progression | The bay becomes locked for the current cycle and lock progress advances by one |
| CORE-10 | Main cycle control and progression | Its values and the shared pools remain unchanged |
| CORE-11 | Main cycle control and progression | Arm Commit becomes usable only while all three bays are locked with lock progress 3 |
| CORE-12 | Main cycle control and progression | The cycle resolves once, applies the scheduled incident, advances the cycle, returns allocated resources to the shared pools, clears bay locks, and loads the next targets |
| CORE-13 | Main cycle control and progression | The player must stabilize and commit all three bays in each of the six cycles |
| CORE-14 | Main cycle control and progression | Commit becomes armed for exactly 3 seconds while the cycle timer continues |
| RULE-01 | Resources incidents penalties and input boundaries | The shared power pool is 7 and the shared coolant pool is 6 before any bay allocation |
| RULE-02 | Resources incidents penalties and input boundaries | An 18-second countdown starts and reaches zero in real time |
| RULE-03 | Resources incidents penalties and input boundaries | Each unlocked bay adds one fault and removes 20 integrity, after which the next cycle begins unless a loss condition is reached |
| RULE-04 | Resources incidents penalties and input boundaries | One overload is recorded for that bay and integrity decreases by 8 |
| RULE-05 | Resources incidents penalties and input boundaries | Incidents occur in this fixed order: Cycle 2 Coolant Leak on Bay B, Cycle 3 Phase Drift on Bay C, Cycle 4 Power Surge on Bay A, Cycle 5 Dual Leak on Bays A and C, and Cycle 6 Crossfeed on Bays B and C |
| RULE-06 | Resources incidents penalties and input boundaries | Coolant Leak adds 1 to the affected coolant target, Phase Drift rotates the affected phase target one step right, Power Surge adds 1 to the affected power target, Dual Leak applies Coolant Leak to both named bays, and Crossfeed swaps the named bays' power targets |
| RULE-07 | Resources incidents penalties and input boundaries | One charge is consumed and the next cycle's incident name and affected bay or bays are revealed for 4 seconds |
| RULE-08 | Resources incidents penalties and input boundaries | The selected bay's allocations and phase return to 0, returned resources rejoin the shared pools, the bay's overload count clears, integrity decreases by 20, and purge becomes unavailable for the run |
| RULE-09 | Resources incidents penalties and input boundaries | The run enters Lost immediately when integrity reaches 0 or faults reach 4 |
| RULE-10 | Resources incidents penalties and input boundaries | The control fires at most once |
| RULE-11 | Resources incidents penalties and input boundaries | Integrity decreases by 10, that bay gains one overload, every bay becomes unlocked, lock progress returns to 0, and commit becomes unarmed while all allocations remain unchanged |
| RULE-12 | Resources incidents penalties and input boundaries | Integrity decreases by 10, every bay becomes unlocked, lock progress returns to 0, commit becomes unarmed, and all allocations remain unchanged |
| FINAL-01 | Final synchronization and terminal outcome | The game displays the fixed eight-symbol sequence A, C, B, A, C, B, C, A one symbol at a time for 0.60 seconds each with a 0.25-second blank gap, then starts a 6-second input window |
| FINAL-02 | Final synchronization and terminal outcome | Each correct next symbol fills one slot and advances sequence progress |
| FINAL-03 | Final synchronization and terminal outcome | Entering A, C, B, A, C, B, C, A within 6 seconds enters Won; any wrong symbol or timeout enters Lost |
| UI-01 | Visible state and action feedback | The HUD shows cycle, seconds remaining, integrity, faults, unallocated power, unallocated coolant, scan charges, purge availability, selected bay, lock progress, next required bay, commit armed state, and arm-window time |
| UI-02 | Visible state and action feedback | Bay A, Bay B, and Bay C are simultaneously distinguishable and each shows current values, target values, stability, lock state, and overload count |
| UI-03 | Visible state and action feedback | A concise message identifies the action and result within 0.25 seconds and remains readable for at least 1 second |
| UI-04 | Visible state and action feedback | The control is visibly unavailable when possible and activation leaves gameplay state unchanged |
| UI-05 | Visible state and action feedback | The relevant warning becomes visually prominent without hiding controls or values |
| UI-06 | Visible state and action feedback | The game uses the fixed 1600 by 900 logical canvas, bay-panel rectangles, and 19 control rectangles in Section 6.2, uniformly letterboxed when the viewport aspect ratio differs |
| RESET-01 | Restart and reopen lifecycle | The game returns to the exact new-run state in CORE-02 and starts Cycle 1 with the schedule reset |
| RESET-02 | Restart and reopen lifecycle | The menu appears with no saved run progress |
| VISUAL-01 | Readable reactor presentation | The reactor theme, three-bay structure, current targets, hazards, and terminal outcome are visually coherent and distinguishable |
