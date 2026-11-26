# Dungeon Duel v2 offline command reference

This file lists Dungeon-specific paths, filters, counts, supplied-media inventory pointers,
and runtime checks. Shared Unity 6 and CLI facts are in `UNITY_BENCHMARK_TOOL_GUIDE.md`.

## Fixed values

```powershell
$Project = (Get-Location).Path
$Cli = $env:UNITY_CLI
$Editor = $env:UNITY_EDITOR
$Scene = 'Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity'
$Catalog = 'ASSET_CATALOG.json'
$Coverage = 'ASSET_COVERAGE.json'
$ContactSheet = 'ASSET_CONTACT_SHEET.png'
```

The contact sheet is a startup inventory preview, not a final encounter layout. Use the
catalog and coverage files for exact supplied paths, hashes, GUIDs, semantic roles, and
handling notes. The current implementation turn has one hard wall-clock limit of 3600
seconds; at that limit retain the project as-is and proceed directly to evaluation without
a second generation turn or operator repair.

## Public tests

Use the exact commands in `TOOLCHAIN.md` with fresh output paths under
`Logs/ToolChecks/<timestamp>/`. Require:

```text
EditMode: OmniGame.Benchmark.DungeonDuel.PublicSmoke -> 6/6 Passed
PlayMode: OmniGame.Benchmark.DungeonDuel.PublicRuntimeSmoke -> 1/1 Passed
```

Read each new XML and its matching project-local log. The PlayMode test advances real
frames but does not complete gameplay.

## Player controls and required outcomes

The player left-clicks visible reachable floor to move, right-clicks a visible living enemy
to attack, points at reachable floor and presses `2` to Dash, presses `R` to Restart, and
left-clicks the visible terminal Restart control. The completed game must provide Player
movement, nonterminal enemy damage, multi-hit combat, actor death, Dash cooldown, first-Imp
gate lock, final-Imp gate opening, Boss activation, Victory, enemy-owned Defeat, terminal
freeze, both Restart routes, and a clean distinct-process reopen. Direct action, damage,
Restart, or result calls are not a player-input implementation.

## Unity-specific checks

- Use `Keyboard.current`, `Mouse.current`, enabled `InputAction`, or `PlayerInput`.
- Use `LegacyRuntime.ttf` or an imported/serialized font, not `Arial.ttf`.
- Keep the active Camera, actor and floor Colliders, serialized references, and visible
  runtime uGUI or TMP HUD/Restart surfaces valid.
- Put runtime code outside Editor assemblies and keep `UnityEditor` out of runtime code.
- If using AI Navigation, bake a reachable NavMesh before moving a `NavMeshAgent`.
- Check `Material.HasProperty` before writing optional shader properties.
- Clear listeners, coroutines, actors, cooldowns, HUD, audio, and static state on Restart.
- A new process must not inherit encounter progress.

Use `unity open` only with a controllable Game view. A shell-only process must not claim
that it operated or observed player interaction in the Game view.
