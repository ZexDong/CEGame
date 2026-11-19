# Undercooked Kitchen Shift - Public Input

Input revision: `v2.6-docv2-session-gate-20260912`

Read `INITIAL_AGENT_PROMPT.md` first. The task is a complete playable kitchen game plus its required session service; `GDD.md` Section 1 explains automated acceptance and delivery consequences.

## Reading index and rule authority

| File | Purpose |
|---|---|
| `GDD.md` | Complete player-facing game and numbered requirements |
| `GAME_SESSION_SPEC.md` | Common session service behavior |
| `SESSION_MODEL.json` | Kitchen-only state names, ranges, legal relations and spatial semantics |
| `BENCHMARK_MANIFEST.json` | Project paths, tool paths, enabled interfaces and public test suites |
| `TOOLCHAIN.md` | Technical delivery rules and optional development check usage |
| `ASSET_MANIFEST.json` | Allowed source-content boundary and primary roles |
| `ASSET_CATALOG.md`, `ASSET_CATALOG.json` | Asset inventory, import facts and use notes |
| `ASSET_COVERAGE.json` | Supplied versus supporting procedural presentation roles |
| `ASSET_CONTACT_SHEET.png` | Isolated allowed-asset previews, not a target game layout |
| `COMMON_BASELINE.md` | Conditional general playable-game expectations |
| `UNITY_BENCHMARK_TOOL_GUIDE.md` | Optional common Unity tool capabilities |

The supplied project contains assets, an empty saved starter Scene, public service types and optional checks. It contains no game implementation. All current task rules are local to this input; no source checkout or external asset download is required.
