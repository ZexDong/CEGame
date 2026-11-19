# Relay Foundry Roblox Studio task contract

Player-facing acceptance is defined by `GDD.md`. This file defines the Relay Foundry-specific project, public tool, normal-input, and observation boundary. Shared game-independent interfaces are listed individually in `ROBLOX_STUDIO_ENGINE_TOOL_GUIDE.md`.

## Fixed paths and versions

```text
Input revision:       v1.1-roblox-tool-catalog-3600s-20260826
Scaffold limit:       3600 seconds
Rojo:                 Tools/rojo.exe (7.7.0)
Luau compiler:        Tools/luau-compile.exe (0.734 track)
Starter project:      project/default.project.json
Authored source:      project/src/**
Required place:       RelayFoundryCandidate.rbxlx
Contract version:     relay-foundry-v1
```

The launcher must tell the scaffold/model about the 3600-second wall-clock limit before generation begins. At the limit it stops the exact generation process and freezes the current project for evaluation; it does not grant an automatic extension or second generation turn.

## Starter boundary

The starter project contains only a clean DataModel mapping and public protocol constants. Add server gameplay under `project/src/server/**`, client input/HUD under `project/src/client/**`, and shared modules under `project/src/shared/**`. Do not change the meaning or spelling of supplied `RFP_*` strings.

The candidate must not read `../gold`, `../evaluation`, `../original`, parent directories, private results, or historical candidates. Runtime code must not depend on developer-machine absolute paths, plugins, marketplace downloads, or network services.

## Public scaffold check

Run from the input directory:

```powershell
powershell -ExecutionPolicy Bypass -File '.\ScaffoldTests\RUN_SCAFFOLD_TESTS.ps1'
```

The script independently compiles all `.luau` files, builds the Rojo project, parses the generated RBXLX as XML, records hashes, and writes a fresh JSON result under `ScaffoldTests/results/`. A PASS proves only source parsing, project mapping, and place serialization. It does not create a PlayClient or complete any GDD flow.

## Normal player input

The required player-facing routes are:

```text
W/A/S/D       walk
mouse         camera
Space         jump
E             nearby operation through a visible ProximityPrompt
Q             nearby machine-mode cycle through a visible ProximityPrompt
R             restart through ordinary client input routed to authoritative server logic
```

Required world actions must originate from ordinary player input and proximity/contact. Direct business-function calls, direct Remote/Bindable invocation, programmatic prompt firing, character teleportation, state mutation, or hidden completion keys are not substitutes.

## Public observation contract

`EVALUABILITY_CONTRACT.md` and `EVALUATION_SCHEMA.json` define public Tags, Attributes, prompts, events, geometry, and timing. These fields are truthful read-only mirrors for interoperable tooling; they do not replace physical game behavior.

At runtime the contract includes:

- `Workspace.RFP_ContractVersion = "relay-foundry-v1"` and `RFP_Ready = true` only when the required world, state, prompts, HUD, and player surface are available;
- authoritative physical objects tagged with the public `RFP_*` Tags;
- continuously present player Attributes mirroring actual gameplay state;
- visible feedback matching each public event;
- real collision, touch, Humanoid death, prompt use, walking, respawn, gate blocking/opening, and evacuation-zone entry.

## Real Studio feedback

After meaningful changes, open the built RBXLX in Roblox Studio and use F5 for a real Play session. Inspect the current session Output/log for parse errors, invalid members, initialization stacks, infinite waits, absent PlayClient, missing HUD, or broken character/input. Stop with Shift+F5 and distinguish these conclusions:

```text
Luau compile
Rojo build
Studio Open
Studio Play startup
Full gameplay self-check
```

Record only checks actually performed in `RUN_REPORT.txt`; use `NOT RUN` for unexecuted scenarios. Keep `DEVELOPMENT_TRACE.txt` factual and separate.

## Delivery

Deliver these files outside `project/` at the input root:

```text
RelayFoundryCandidate.rbxlx
RUN_REPORT.txt
DEVELOPMENT_TRACE.txt
```

Also preserve the complete `project/` source. The place must rebuild from the delivered project with the bundled Rojo tool.

