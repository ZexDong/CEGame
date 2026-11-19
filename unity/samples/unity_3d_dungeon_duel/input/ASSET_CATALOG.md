# Dungeon Duel Supplied Asset Catalog

This public catalog describes the supplied source media and saved art-only arena without prescribing a final encounter layout, combat implementation, camera path, or evaluation workflow. Read it with `ASSET_CONTACT_SHEET.png`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json`.

## First-pass conclusions

1. `Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity` is already the canonical main Scene and already contains the supplied art-only arena, Camera, Lighting, environment geometry, and named markers. Extend this saved composition; do not replace it with an empty Scene or a primarily Primitive-only graybox.
2. `ASSET_CONTACT_SHEET.png` is an inventory preview rendered from the public starter Scene and source Prefabs. It is not a final game screenshot or evaluation Reference.
3. `PlayerVisual.prefab`, `ImpVisual.prefab`, and `BossVisual.prefab` are presentation-only sources. They do not implement movement, combat, AI, health, Dash, gate progression, terminal state, HUD, or Restart.
4. `DungeonDuelStarterAssetIndex.asset` is the compact serialized lookup for the approved visual, animation, navigation, input, VFX, and audio sources.
5. Preserve protected assets and importers. Put candidate-authored gameplay, colliders, derived materials, Prefabs, scripts, tests, and the final saved Scene under `Assets/DungeonDuelBenchmark/**`.
6. The supplied arena and media are present; only the completed playable encounter logic is intentionally absent.

## Role-to-path map

| Role | Canonical public paths | Handling |
|---|---|---|
| Canonical art-only arena | `Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity`; source copy at `Assets/DungeonDuelDemo/Starter/DungeonDuelStarter.unity` | Extend the staged environment, Camera, Lighting, geometry, and markers already present in the canonical Scene. |
| Asset index | `Assets/DungeonDuelDemo/Starter/DungeonDuelStarterAssetIndex.asset` | Serialized lookup; inspect its references rather than searching the whole project blindly. |
| Player / Tank | `Assets/DungeonDuelDemo/Visuals/PlayerVisual.prefab`; `Controllers/Player.controller` | Add candidate-owned gameplay and physical/input surfaces. |
| Two Imps | `Assets/DungeonDuelDemo/Visuals/ImpVisual.prefab`; `Controllers/Imp.controller` | Instantiate two smaller enemies with independent runtime state. |
| Boss | `Assets/DungeonDuelDemo/Visuals/BossVisual.prefab`; `Controllers/Boss.controller` | Keep dormant/unattackable until the two-Imp prerequisite completes. |
| Boss gate | `Assets/Prefabs/Dungeon/Dungeon Pieces/animated/env_door_boss_ani.prefab` | Candidate logic must own the visible and physical closed/open state. |
| Input | `Assets/InputSystem/PlayerActions.inputactions` | New Input System action source; equivalent enabled InputAction/PlayerInput/direct polling is allowed. |
| Navigation | `Assets/Scenes/BossRoom/NavMesh-DungeonNavMesh.asset` | Optional baked data; equivalent custom movement is allowed. |
| Battle / Victory music | `Assets/Sounds/Music/Boss_Room_Battle_Loop.ogg`; `Boss_Room_Victory.ogg` | Avoid duplicate stacked playback; Restart returns to battle audio. |
| VFX examples | `Assets/VFX/Prefabs/Imp/FX_ImpDefeat.prefab`; `Assets/VFX/Prefabs/Tank/fx_TankAttack1.prefab`; `FX_TankSkill2_hit.prefab` | Optional recognizable attack, Dash/hit, and defeat feedback. |

Exact bytes, SHA-256 values, Unity GUIDs, and per-file handling notes are in `ASSET_CATALOG.json`. `ASSET_COVERAGE.json` maps the supplied roles to the player-facing GDD requirement IDs.
