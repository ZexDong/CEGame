# Noir Source Asset Catalog

This is a **public, source-only media catalog**. It records supplied-media paths and import facts without prescribing the final room layout, encounter coordinates, or camera composition. Read it together with `ASSET_CONTACT_SHEET.png` and `ASSET_CATALOG.json` before authoring the final Scene.

## Mandatory first-pass conclusions

1. The major PNG silhouettes are visually tiny inside 128x128 source textures. Source dimensions are not visible-character dimensions.
2. `Player/Idle.png` is imported as a **single full-texture sprite** at 100 PPU although its visible silhouette occupies only a few pixels. Blindly using scale 1 will look empty.
3. `AndaDead.png` also has a full-texture declared slice around a tiny mark. Inspect or derive a project-owned crop.
4. The Vulto JPG files are opaque character frames on black. **They are not backgrounds.**
5. `Ground.png` and `Obstacle.png` are opaque white squares. Tint/tile them for authored geometry.
6. Source prefabs can preserve renderers, colliders, VFX, and references, but prefabs listed with omitted upstream scripts are not runnable gameplay answers.
7. Keep protected files unchanged. Put derived sprites, materials, prefabs, scripts, tests, and the final scene under `Assets/NoirChallenge/**`.
8. `ASSET_CONTACT_SHEET.png` is supplied with the initial request as the visual inventory; use the catalogs for exact paths and source facts.

## Role-to-path map

- **Player:** `Sprites/Player/Idle.png`, `Sprites/Player/BackAttack.png`, `Prefabs/GameManager/Player.prefab`; Player audio under `Audio/Player/`.
- **Anda:** `Sprites/Anda/AndaIdle.png`, `Sprites/Anda/AndaDead.png`, `Prefabs/Enemies/Anda.prefab`, vision cone material, alert/motion audio.
- **Obser:** `Sprites/Vig/Vigia.png`, `Prefabs/Enemies/Obser.prefab`, laser/aura/cone materials, alert and laser audio.
- **Room geometry:** Tile `Ground.png`, `Obstacle.png`, their Tile assets, and `Prefabs/LevelDesing/Grid.prefab`.
- **VFX/lighting:** `Prefabs/VFX/VFX.prefab`, Light/Volume source prefabs, and the supplied materials.
- **Vulto JPG set:** optional supplementary humanoid reference frames only; do not stretch one across a room.

All paths above are relative to `Assets/TaskAssets/NoirSource/`. Exact machine-readable path groups are in `ASSET_CATALOG.json`.

## Sprite and texture import facts

Content bounds use a top-left origin. Unity slice rectangles use the bottom-left origin documented in the table. For opaque JPGs, the reported content box is the non-dark (`luma > 24`) foreground, not alpha.

| Role | Path | Source | Visible/non-dark content and padding | Unity importer |
|---|---|---:|---|---|
| `anda_defeated` | `Assets/TaskAssets/NoirSource/Sprites/Anda/AndaDead.png` | 128x128 RGBA | 7x2 at (54,68) top-left; padding L54 T68 R67 B58 | multiple, 100 PPU; none declared |
| `anda_idle` | `Assets/TaskAssets/NoirSource/Sprites/Anda/AndaIdle.png` | 128x128 RGBA | 6x8 at (55,60) top-left; padding L55 T60 R67 B60 | multiple, 100 PPU; none declared |
| `player_backstab` | `Assets/TaskAssets/NoirSource/Sprites/Player/BackAttack.png` | 128x128 RGBA | 7x7 at (61,72) top-left; padding L61 T72 R60 B49 | multiple, 100 PPU; none declared |
| `player_idle` | `Assets/TaskAssets/NoirSource/Sprites/Player/Idle.png` | 128x128 RGBA | 6x7 at (61,72) top-left; padding L61 T72 R61 B49 | single, 100 PPU; none declared |
| `room_ground` | `Assets/TaskAssets/NoirSource/Sprites/Tile/Ground.png` | 256x256 RGB | 256x256 at (0,0) top-left; padding L0 T0 R0 B0 | multiple, 256 PPU; none declared |
| `room_obstacle` | `Assets/TaskAssets/NoirSource/Sprites/Tile/Obstacle.png` | 256x256 RGB | 256x256 at (0,0) top-left; padding L0 T0 R0 B0 | multiple, 256 PPU; none declared |
| `obser` | `Assets/TaskAssets/NoirSource/Sprites/Vig/Vigia.png` | 128x128 RGBA | 4x13 at (62,57) top-left; padding L62 T57 R62 B58 | multiple, 100 PPU; none declared |
| `vulto_idle_1` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/Idle/VultoIdle1.jpg` | 128x128 RGB | 29x34 at (52,46) top-left; padding L52 T46 R47 B48 | multiple, 100 PPU; none declared |
| `vulto_idle_2` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/Idle/VultoIdle2.jpg` | 128x128 RGB | 28x34 at (52,46) top-left; padding L52 T46 R48 B48 | multiple, 100 PPU; none declared |
| `vulto_idle_3` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/Idle/VultoIdle3.jpg` | 128x128 RGB | 28x35 at (52,45) top-left; padding L52 T45 R48 B48 | multiple, 100 PPU; none declared |
| `vulto_idle_4` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/Idle/VultoIdle4.jpg` | 128x128 RGB | 27x36 at (52,44) top-left; padding L52 T44 R49 B48 | multiple, 100 PPU; none declared |
| `vulto_idle_5` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/Idle/VultoIdle5.jpg` | 128x128 RGB | 27x35 at (52,45) top-left; padding L52 T45 R49 B48 | multiple, 100 PPU; none declared |
| `vulto_idle_6` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/Idle/VultoIdle6.jpg` | 128x128 RGB | 28x35 at (52,45) top-left; padding L52 T45 R48 B48 | multiple, 100 PPU; none declared |
| `vulto_down_attack` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/VultoDownAttack.jpg` | 128x128 RGB | 28x41 at (52,47) top-left; padding L52 T47 R48 B40 | multiple, 100 PPU; none declared |
| `vulto_sword_launch` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/VultoLaunchSword.jpg` | 128x128 RGB | 26x34 at (52,46) top-left; padding L52 T46 R50 B48 | multiple, 100 PPU; none declared |
| `vulto_stun` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/VultoStun.jpg` | 128x128 RGB | 19x30 at (58,58) top-left; padding L58 T58 R51 B40 | multiple, 100 PPU; none declared |
| `vulto_sword` | `Assets/TaskAssets/NoirSource/Sprites/Vulto/VultoSword.jpg` | 128x128 RGB | 6x22 at (74,58) top-left; padding L74 T58 R48 B48 | multiple, 100 PPU; none declared |

### Safe crop/slice workflow

Do not edit anything under `Assets/TaskAssets/**`. If a protected importer yields an unusably padded sprite, either:

- create a `Sprite` from the supplied texture and an explicit source rect in project code; or
- make a project-owned derived copy under `Assets/NoirChallenge/**`, document its source path, and configure its importer there.

The supplied source must remain recognizable in its player-facing role. A non-null `SpriteRenderer.sprite` alone is not enough if transparent padding makes the result effectively invisible.

## Audio role map

| Role | Path | Duration | Format |
|---|---|---:|---|
| `enemy_alert` | `Assets/TaskAssets/NoirSource/Audio/Enemy/AlertSound.wav` | 0.594s | 1 ch / 22050 Hz / 8 bit |
| `enemy_dash_or_motion` | `Assets/TaskAssets/NoirSource/Audio/Enemy/Dash.wav` | 2.157s | 1 ch / 44100 Hz / 8 bit |
| `obser_laser` | `Assets/TaskAssets/NoirSource/Audio/Enemy/laserShoot.wav` | 0.228s | 1 ch / 44100 Hz / 8 bit |
| `attack` | `Assets/TaskAssets/NoirSource/Audio/Player/Attack.wav` | 1.826s | 1 ch / 44100 Hz / 16 bit |
| `player_dash` | `Assets/TaskAssets/NoirSource/Audio/Player/Dash.wav` | 0.394s | 1 ch / 44100 Hz / 16 bit |
| `jump` | `Assets/TaskAssets/NoirSource/Audio/Player/Jump.wav` | 1.210s | 1 ch / 8000 Hz / 16 bit |
| `enemy_defeat` | `Assets/TaskAssets/NoirSource/Audio/Player/Kill.wav` | 0.191s | 1 ch / 44100 Hz / 16 bit |
| `player_death` | `Assets/TaskAssets/NoirSource/Audio/Player/PlayerDeath.wav` | 2.235s | 1 ch / 22050 Hz / 8 bit |

Both persistent `AudioSource.clip + Play()` and clipless-source `PlayOneShot(suppliedClip)` architectures are valid. What matters is that the supplied clips are actually referenced by semantic role and normal player actions produce audible playback.

## Prefab composition and missing-script facts

“Package/engine component” references (URP lights, Volume, camera packages, and built-in components) are not the same as intentionally omitted upstream gameplay scripts. Only the latter make a source prefab non-runnable as gameplay.

| Prefab | Intentionally omitted upstream scripts | Serialized component composition | Use classification |
|---|---|---|---|
| `Assets/TaskAssets/NoirSource/Prefabs/Enemies/Anda.prefab` | Anda, EnemyPatrol, VisionConeMesh | AudioSource x1, BoxCollider2D x3, GameObject x4, MeshFilter x1, MeshRenderer x1, MonoBehaviour x3, Rigidbody2D x1, SpriteRenderer x1, Transform x4, UnityClassID_210 x2 | visual/reference source; reconstruct project-owned gameplay components |
| `Assets/TaskAssets/NoirSource/Prefabs/Enemies/Obser.prefab` | Obser, TargetedPatrol, VisionConeMesh | AudioSource x1, BoxCollider2D x1, GameObject x5, LineRenderer x2, MeshFilter x1, MeshRenderer x1, MonoBehaviour x3, Rigidbody2D x1, SpriteRenderer x1, Transform x5, UnityClassID_210 x1 | visual/reference source; reconstruct project-owned gameplay components |
| `Assets/TaskAssets/NoirSource/Prefabs/GameManager/GameManager.prefab` | GameManager | GameObject x1, MonoBehaviour x1, Transform x1 | visual/reference source; reconstruct project-owned gameplay components |
| `Assets/TaskAssets/NoirSource/Prefabs/GameManager/Global Light 2D.prefab` | none | GameObject x1, MonoBehaviour x1, Transform x1 | reusable supplied composition; still inspect before use |
| `Assets/TaskAssets/NoirSource/Prefabs/GameManager/Global Volume.prefab` | none | GameObject x1, MonoBehaviour x1, Transform x1 | reusable supplied composition; still inspect before use |
| `Assets/TaskAssets/NoirSource/Prefabs/GameManager/Main Camera.prefab` | none | AudioListener x1, Camera x1, GameObject x1, MonoBehaviour x1, Transform x1 | reusable supplied composition; still inspect before use |
| `Assets/TaskAssets/NoirSource/Prefabs/GameManager/Player.prefab` | Controller | Animator x1, BoxCollider2D x1, GameObject x9, MonoBehaviour x1, ParticleSystem x3, ParticleSystemRenderer x3, Rigidbody2D x1, SpriteRenderer x1, TrailRenderer x1, Transform x9 | visual/reference source; reconstruct project-owned gameplay components |
| `Assets/TaskAssets/NoirSource/Prefabs/LevelDesing/Checkpoint.prefab` | Checkpoint | CircleCollider2D x1, GameObject x1, MonoBehaviour x1, SpriteRenderer x1, Transform x1 | visual/reference source; reconstruct project-owned gameplay components |
| `Assets/TaskAssets/NoirSource/Prefabs/LevelDesing/Grid.prefab` | none | GameObject x3, Rigidbody2D x2, Transform x3, UnityClassID_156049354 x1, UnityClassID_1839735485 x2, UnityClassID_19719996 x2, UnityClassID_483693784 x2, UnityClassID_66 x2 | reusable supplied composition; still inspect before use |
| `Assets/TaskAssets/NoirSource/Prefabs/VFX/VFX.prefab` | none | GameObject x3, ParticleSystem x2, ParticleSystemRenderer x2, Transform x3 | reusable supplied composition; still inspect before use |
| `Assets/TaskAssets/NoirSource/Sprites/Tile/TilePalette/GroundPalette.prefab` | none | GameObject x2, MonoBehaviour x1, Transform x2, UnityClassID_156049354 x1, UnityClassID_1839735485 x1, UnityClassID_483693784 x1 | reusable supplied composition; still inspect before use |
| `Assets/TaskAssets/NoirSource/Sprites/Tile/TilePalette/ObstaclePallete/ObstaclePalette.prefab` | none | GameObject x2, MonoBehaviour x1, Transform x2, UnityClassID_156049354 x1, UnityClassID_1839735485 x1, UnityClassID_483693784 x1 | reusable supplied composition; still inspect before use |

See `ASSET_CATALOG.json` for exact child names, dependency paths, script GUID classifications, component counts, and handling notes.

## Runtime-use reminder

Player, Anda, Obser, room geometry, VFX/lighting, and audio must appear or play in recognizable intended roles; public smoke coverage does not define those presentation roles.

