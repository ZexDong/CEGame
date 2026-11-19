# Arrow Escape v2 public input

This English-only Unity project is the complete implementation input for Arrow Escape v2.
The launcher has already placed it in the current working directory; work in that project
directly. Do not create another nested project copy.

## Read order

1. `INITIAL_AGENT_PROMPT.md`
2. `GDD.md`
3. `BENCHMARK_MANIFEST.json` and `ASSET_MANIFEST.json`
4. `ASSET_CONTACT_SHEET.png`, `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json`
5. `UNITY_BENCHMARK_TOOL_GUIDE.md`
6. `TOOLCHAIN.md`
7. `Packages/com.omnigame.benchmark.arrow-escape.contracts/README.md`

## Fixed project facts

- Input revision: `v2.6-tool-interface-catalog-3600s-20260826`
- Unity Editor: `6000.0.80f1`
- Unity CLI: `D:\game\engine\shared-tools\unity\cli\1.0.0-beta.3\unity.exe`
- Required scene: `Assets/ArrowEscapeBenchmark/Scenes/ArrowEscape.unity`
- Authored root: `Assets/ArrowEscapeBenchmark/**`
- Additional writable file: `ProjectSettings/EditorBuildSettings.asset`
- Public EditMode filter: `OmniGame.Benchmark.ArrowEscape.PublicSmoke` (`4/4 Passed`)
- Public PlayMode filter: `OmniGame.Benchmark.ArrowEscape.PublicSmoke` (`1/1 Passed`)

The supplied bootstrap contains protected source art and public contract assets but not the
target playable game. The contact sheet is an inventory preview, not a finished layout or
target composition. Use the Catalog for exact paths and importer facts, implement all numbered
requirements in GDD Section 6, save the real runtime scene and serialized assets, and
preserve protected content.

## Engine feedback

Use the optional interfaces in `UNITY_BENCHMARK_TOOL_GUIDE.md` and the exact filters above.
Store fresh logs, NUnit XML, and screenshots in a stable project-local directory such as
`Logs/ToolChecks/<timestamp>/`; never use Unity `Temp/` for durable output. A successful
EditMode smoke confirms import and public structure only. The PlayMode smoke enters real
frames and catches startup failures, but neither smoke proves the full puzzle.

Use `unity open` only when a controllable desktop Game view exists; a shell-only process
must not claim that it operated the Game view. The finished game must connect visible
player controls to gameplay rather than using direct gameplay or result calls as its
player-input route.

## Public runtime contract

Exactly one active `IArrowEscapeReadOnlyProbe` for contract `3.0` must truthfully expose
the current visible state and complete visible-target registry. The Probe is observation
only. Arrow targets use visible world geometry and Collider2D; Hint, Restart, and Next Level
use visible runtime controls. A complete click is a press and release on the same target.
See `TOOLCHAIN.md` and the Contracts README for the exact public fields and geometry rules.
