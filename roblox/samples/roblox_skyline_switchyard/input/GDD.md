# Skyline Switchyard Game Design Document

## Concept

A single-player urban rail dispatch game. Manage drones A/B/C at an elevated
switchyard, delivering manifests addressed NORTH/EAST/WEST to the correct hubs.
Allocate battery/fuel and switch routes in three consecutive windows, then enter
the fixed A-C-B-A-C synchronization sequence.

## Core loop

Each window starts with battery 6 and fuel 6.
Select a drone, use its nearby Load Prompt, toggle Switch 1/2, then Dispatch.
The window publicly displays route mappings.
A wrong route removes 20 integrity and adds a fault; zero integrity or four
faults causes failure. Commit after all three drones arrive to advance.
Each dispatch consumes 1 fuel; loading consumes 1 battery.

## Fixed rules

Drone A/B/C destinations are NORTH/EAST/WEST respectively.
Switch 1 selects the primary route. Switch 2 provides visual support and
next-window strategy hints. Count each successful delivery.
Scan shows safe-hub hints.
After the third commit, preview and open the 12-second A-C-B-A-C input window.
R restarts at any time. No persistence.

## Feedback and space

Include continuous elevated ground, three drone pads, two visible track
branches, three hubs, dispatch and commit stations.
HUD shows window, resources, switches, each drone destination/load state,
integrity, faults, delivery count, and latest feedback.
