# Dungeon Duel 3D v2 public input

This English-only Unity project is the complete implementation input for Dungeon Duel v2.
The launcher places it in the current working directory; work there directly and do not
create a nested project.

## Read order

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `BENCHMARK_MANIFEST.json` and `ASSET_MANIFEST.json`
4. `ASSET_CONTACT_SHEET.png`, `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json`
5. `UNITY_BENCHMARK_TOOL_GUIDE.md`
6. `TOOLCHAIN.md`
7. `Packages/com.omnigame.benchmark.dungeon-duel.contracts/README.md`

## Fixed project facts

- Input revision: `v2.6-existing-arena-feedback-3600s-20260827`
- Unity Editor: `6000.0.80f1`
- Unity CLI: `D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe`
- Required scene: `Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity`
- Authored root: `Assets/DungeonDuelBenchmark/**`
- Additional writable paths: `ProjectSettings/EditorBuildSettings.asset`, `Logs/**`
- Public EditMode filter: `OmniGame.Benchmark.DungeonDuel.PublicSmoke` (`6/6 Passed`)
- Public PlayMode filter: `OmniGame.Benchmark.DungeonDuel.PublicRuntimeSmoke` (`1/1 Passed`)
- Formal generation turn: one hard wall-clock limit of 3600 seconds; at the limit the launcher retains the current project and proceeds to evaluation without a second generation turn.

## Starting point and supplied media

The saved art-only arena is first in Build Settings and is also the canonical main Scene
at `Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity`. It already contains supplied
environment, camera, lighting, geometry and markers, but not the required combat game.
Extend that saved arena; an empty Scene or primary primitive-only graybox does not satisfy
`VISUAL-01` or `ASSET-01`. The root contact sheet is an attached inventory preview, not a final layout or Reference. Use the Catalog for exact
paths, hashes, GUIDs and handling notes. `DungeonDuelStarterAssetIndex.asset` is the compact
lookup for the supplied Tank, Imp, Boss, animation, gate, navigation, Input Actions, VFX
and battle/result music.

Create all authored runtime content under `Assets/DungeonDuelBenchmark/**`, save the final
scene and Build Settings change, and preserve protected source content.

## Engine feedback

The optional interfaces in `UNITY_BENCHMARK_TOOL_GUIDE.md` and the exact filters above are
available. Store fresh logs and NUnit XML under a stable project-local directory such as
`Logs/ToolChecks/<timestamp>/`; never use Unity `Temp/` for durable output. EditMode checks
import and public structure; PlayMode enters real frames and catches startup failures.
Neither smoke proves movement, combat, Dash, gate progression, outcomes, Restart or reopen.

Use `unity open` only when a controllable Game view exists. A shell-only process must not
claim that it operated the Game view. The finished game must connect visible normal player
controls to gameplay rather than using direct gameplay or result calls as a substitute.

## Runtime boundary

Use normal Unity Input System Mouse and Keyboard input. Actor and floor input surfaces need
real visible Renderer and Collider geometry. HUD and Restart need visible runtime uGUI or
TMP surfaces with a compatible EventSystem route. The saved scene contains exactly one
truthful, read-only `IDungeonDuelBenchmarkProbe` for contract `2.0`.
