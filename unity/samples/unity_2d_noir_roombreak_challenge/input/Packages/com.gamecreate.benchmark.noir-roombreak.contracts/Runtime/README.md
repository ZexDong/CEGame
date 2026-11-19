# Public Contract

Namespace: `GameCreate.Benchmark.NoirRoombreak`

The final Scene must include at least one active `MonoBehaviour` that implements `INoirRoombreakProbe`. The interface is an observation surface only. It reports the same state a player can reach with normal keyboard and pointer input; it is not a test driver, command channel, result authority, or hidden shortcut.

Screen-space points and rectangles use bottom-left screen coordinates. Values must describe the currently rendered player view. `StateSequence` increases when a player-visible gameplay state changes, not every frame. Enemy snapshots may be returned in any stable order, but an enemy ID remains stable during one run.

`CurrentRoomIndex` uses one fixed convention: the menu is `-1`; Rooms 1 through 5 are `0` through `4`.

