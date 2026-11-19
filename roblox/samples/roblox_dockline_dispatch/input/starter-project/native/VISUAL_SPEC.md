# Dockline Dispatch Public Visual Specification

## 1. Visual goal

A complete night-shift warehouse with clear functional areas and readable cargo
flow. Package identity, preparation state, routes, hazard phase, and dispatch
must be clear. Layout and pixel-level replication are not fixed.

Suggested language: dark steel/concrete/warm-white ceiling lamps; orange fragile
goods with glass/crack icons and foam; cyan cold goods with snowflake/temperature
icons and cold mist/light; purple secure goods with lock/data icons.
Routes A/B/C use red/yellow/blue plus letters. Safe/completed is green,
error/danger red. DispatchSeal is white metal with a green luminous band.
Pair color with text, icons, material, or component changes.

## 2. Area and object readability

Show directions to Manifest and three Inbound shelves from spawn.
Name scanner, three processes, scale, printer, conveyor, both diverters,
RejectBuffer, three Bays, pallet, seal shelf, hazard lane, and truck terminal.
Packages remain identifiable in Inbound, Carried, OnConveyor, Rejected, Staged,
and Palletized states. Diverter Left/Right, route table, conveyor Busy/Empty,
and hazard Safe/Active are observable on world objects.
Billboard/SurfaceGui labels cannot overlap, pass through walls, or fill the
viewport. Preserve readable hierarchy. No placeholder text, debug blocks,
developer coordinates, test buttons, or unassembled floating assets.

## 3. HUD

Display the 13 protocol fields, preferably a compact panel and brief feedback bar.
Keep text inside the viewport without overlap or blocking the central view.
Packages may use three lines/cards for Glass/Cold/Cipher.
Routing shows One, Two, and the route table. Feedback persists >=1.5 seconds.
Completion uses a separate panel with dispatch success, final time, and R restart.

## 4. Representative states

1. AwaitingStart: spawn, Manifest, three Inbound packages, HUD.
2. Processing: carried cargo at scanner/process workspace.
3. Routing: package on conveyor, both diverters, route table.
4. Pallet/Checkpoint: all packages loaded, seal carried or staged.
5. Completed: truck terminal and completion panel.

The public input specifies states and visual language; it contains no reference
screenshots, scoring weights, or private visual assessment method.
