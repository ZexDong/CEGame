# Public Observation Contracts

Primary contract: `Benchmark.Dashboard.IGameStateDashboard` (`game-state-dashboard/v2`).

`GameStateDashboardV2.cs` defines the fixed read-only Snapshot types and the exact JSON serializer. A valid dashboard contains no action, reset, teleport, damage, victory, or scoring method.

Legacy compatibility sidecar: `GameCreate.Benchmark.NoirRoombreak.INoirRoombreakProbe`.

The legacy Probe remains required for backward compatibility with the earlier public observation contract. It reports the same state a player reaches through normal keyboard and pointer input; it is not the primary docv2 Dashboard, a test driver, command channel, result authority, or hidden shortcut.

Dashboard entity positions and Probe screen positions use bottom-left game-view coordinates. Values must describe the currently rendered player view. State counters increase only when player-visible state changes, not every frame.
