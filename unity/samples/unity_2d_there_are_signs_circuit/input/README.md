# There Are Signs - Sign Circuit Unity project

Public Input revision: `v2.5-tool-guide-v5-20260825`  
GDD revision: `v2.4-player-goals-only-20260825`  
Common Unity tool guide: `unity-common-tool-guide-v5-20260825`

This project contains the English Sign Circuit task specification, the Unity
starter project, supplied source-game assets, public Unity tests, and a protected
read-only observation contract. `GDD.md` Section 6 is the sole source of
player-facing acceptance conditions.

## 1. Read order

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `BENCHMARK_MANIFEST.json`
4. `TOOLCHAIN.md`
5. `UNITY_BENCHMARK_TOOL_GUIDE.md`
6. `ASSET_MANIFEST.json`
7. `UNITY_OFFLINE_AGENT_MANUAL.md` when a concise command detail is needed

## 2. Player goal

The player selects the visible `SIGN CIRCUIT` menu entry, starts at `30.0`
seconds and `0/3`, configures the three route signs to `STOP`, `UP`, and `RIGHT`,
passes their checkpoints in that order, crosses the opened gate, and physically
reaches the finish before time expires. The challenge also includes wrong-route
penalties, pause/resume, keyboard and visible-button Restart, timeout failure,
best-time persistence, and the preserved original menu and `Level1+2` behavior.
Refer to the numbered requirements in `GDD.md` for the complete boundaries.

## 3. Project map

- Unity Editor: `6000.0.80f1`
- Challenge scene: `Assets/Scenes/Benchmark/SignCircuit.unity`
- Existing menu: `Assets/Scenes/Menu.unity`
- Preserved level: `Assets/Scenes/Levels/Level1+2.unity`
- Runtime work root: `Assets/Benchmark/Runtime/**`
- Optional editor-only helper root: `Assets/Benchmark/Editor/**`
- Protected contract: `Assets/BenchmarkContract/**`
- Supplied asset inventory: `ASSET_MANIFEST.json`

Only the paths listed under `write_policy.allowed` in
`BENCHMARK_MANIFEST.json` may be changed. All paths listed under
`write_policy.protected` are read-only.

## 4. Public Unity checks

Use the Unity CLI and commands in `TOOLCHAIN.md` from the current project. The
fixed results are:

- EditMode filter:
  `OmniGame.Benchmark.SignCircuit.PublicTests.SignCircuitPublicEditModeTests`
  - expected: `2/2 Passed`
- PlayMode filter:
  `OmniGame.Benchmark.SignCircuit.PublicTests.SignCircuitPublicPlayModeTests`
  - expected: `1/1 Passed`

Each command needs exit code `0` and a new readable timestamped NUnit XML under
`Logs/PublicSmoke/`. The public checks confirm import, saved-scene startup,
blocking runtime-log health, and host Input System availability. They do not
confirm that the completed gameplay consumes input correctly.

## 5. Runtime boundary

The task uses Input System 1.19 keyboard and pointer controls through the player-facing
runtime route. Required runtime controls are real visible uGUI `Button` surfaces, and
required text/panels are real visible uGUI/TMP surfaces under a Canvas with a
GraphicRaycaster and an Input-System-compatible EventSystem. Runtime code must
not depend on `UnityEditor`, legacy `UnityEngine.Input`, or IMGUI-only controls.

The protected `Assets/BenchmarkContract/**` assembly supplies a read-only
snapshot and visible-target publication API. Keep it unchanged and publish only
truthful current state and screen geometry. It cannot execute gameplay.
`TOOLCHAIN.md` defines all snapshot fields and exact semantic IDs.
