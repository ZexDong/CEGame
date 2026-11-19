# Public pre-delivery Play checklist

Perform these with real player input in Studio Play; record PASS, FAIL or NOT RUN, observations and session ID in RUN_REPORT.txt. These are public GDD checks, not the private scoring suite or a coverage certificate. Source inspection, string matching or manual attribute changes do not replace Play. Record environmental limitations honestly.

1. Within 12 seconds of F5, verify control/HUD and W/A/S/D, Space and mouse camera.
2. Check contract version, ready flag, remote, tag/attribute counts and HUD roles against SESSION_MODEL.
3. Walk normally from the hub to all three sectors and final area without shortcuts.
4. Record the visible routing order and matching node OrderIndex values.
5. At an unready final console, E preserves Locked and gives FinalNotReady feedback.
6. Wrong first node E preserves zero progress and order and gives RoutingWrongOrder.
7. Correct first node E gives progress one, correct next target and visibly changed authoritative base.
8. Repeat the first node: progress remains one; RoutingAlreadyActive appears.
9. Another wrong-order action preserves accepted progress and visuals.
10. Complete the remaining routing nodes; verify progress three, completion flag and event.
11. Start Port; observe the complete continuous gauge cycle and agreement of world, HUD and attribute.
12. E outside the safe zone rejects only Port, then returns it to Idle/zero after the prescribed interval.
13. Restart Port and lock within the public safe interval; confirm frozen value and changed appearance.
14. E on Locked Port leaves it locked and gives PumpAlreadyLocked.
15. Start and safely lock Starboard; verify both locked and PressureComplete.
16. Physically touch Transfer checkpoint and verify state/feedback.
17. Socket E without carrying is rejected without transfer completion.
18. Rack E picks up the unique visible authoritative core, which follows the character.
19. Repeat rack E while carrying: rejection and no second core.
20. Physically contact an Inactive arc; verify no damage and matching state/appearance.
21. Carry the core into an Active arc; observe death within the public limit and hazard/death events.
22. Respawn near Transfer with stable RunId/RunStart, increased DeathCount, preserved routing/pressure and timely core return.
23. Pick up again and walk Waypoint 0→1→2→3 while observing hazards; do not teleport.
24. Socket E while carrying visibly installs the core, clears carrying and completes transfer.
25. Once all systems complete, verify Ready; Right first is rejected without starting a window.
26. Left E, deliberately exceed its window: verify Failed, halted world progression, overlay and Retry.
27. Click Retry with the mouse: Active/Ready, preserved systems, increased RetryCount and hidden failure overlay.
28. Left then timely Right, deliberately exceed the confirmation window: verify Failed again.
29. Retry and complete timely Left→Right→console E; verify completion only after real console input and frozen final time.
30. E after completion cannot duplicate the Completed event or alter final time.
31. Completed R produces a new clean run within the public limit, central spawn and reset systems/objects/checkpoint/overlays/timing.
32. Die before touching Transfer in that new run; the old Transfer checkpoint must not persist.
33. Active with partial progress: R also cleans everything.
34. Failed R starts a clean run; it must not retain the three systems as Retry would.
35. Stop/reopen Play: no prior session progress persists.
36. Inspect the four public visual states at 1280×720 for readability, clipping, overlap, graybox and debug remnants.
37. Build from a clean complete project with Rojo; open the resulting place and perform a real startup smoke.
38. Complete the required run and development reports. Explicitly identify every unverified item.
