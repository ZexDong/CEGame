# Moonlit Greenhouse Game Design Document

## Concept

A single-player third-person resource-allocation and cultivation puzzle.
Manage beds A/B/C in a moonlit greenhouse: allocate limited water and energy,
adjust plant phase, lock stable beds, commit four growth cycles, and finish the
A-C-B-A-C pollination signal.

## Core loop

Each cycle starts with water 8 and energy 6. Select a bed and operate its actual
nearby ProximityPrompts: Water+, Light+, Phase+, Lock.
Targets are fixed and public. Commit requires all three beds to be stable.
An incorrect lock removes 5 integrity and adds one fault. Integrity zero or
four faults causes failure. Each commit loads the next deterministic targets.
After cycle four, preview the signal and open a 12-second input window.

## Initial and terminal states

Entry starts a fresh game with Cycle 1/4 on the HUD. R clears and restarts.
Completing the pollination sequence enters Won; failure enters Lost.
Only R resets terminal states. No saving or randomness.

## Fixed targets

Values are Water/Light/Phase:

| Cycle | A | B | C |
|---|---|---|---|
| 1 | 2/2/0 | 1/3/1 | 3/1/-1 |
| 2 | 1/3/1 | 2/1/-1 | 2/2/0 |
| 3 | 3/2/-1 | 2/2/0 | 1/3/1 |
| 4 | 2/1/0 | 3/2/1 | 1/2/-1 |

## Feedback and space

Provide continuous ground, three beds, a commit station, scan station, and
emergency purification station. HUD simultaneously shows resources, targets,
locks, integrity, faults, and latest feedback. Use both color and text.
