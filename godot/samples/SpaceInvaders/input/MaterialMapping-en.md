# SpaceInvaders Material Mapping

Input revision: `dashboard-contract-20261022-r2`.

The paths below are relative to `sp/`; prefix them with `res://` inside the Godot project. `Assets/` contains the catalog, coverage, contact sheet, and manifest. The mapping is identity-specific: visually similar members of one enemy row do not substitute for another row's required score identity.

## Principal roles

| Requirement | Exact path | Information | Use |
|---|---|---|---|
| `VISUAL-01` | `assets/tank/Lazer Tank.png` | 25x25 PNG | Player cannon |
| `VISUAL-01` | `assets/tank/minime.png` | 9x9 PNG | Life indicator |
| `VISUAL-01` | `assets/tank/tank_destroyed/fire1.png`–`fire5.png` | 25x25 PNG sequence | Player-hit destruction |
| `VISUAL-01`, `SCORE-01` | `assets/Enemies/enemy1/invader_type1f0.png`, `invader_type1f1.png` | 24x24, two frames | High-value invader row |
| `VISUAL-01`, `SCORE-01` | `assets/Enemies/enemy2/invader_type2f1.png`, `invader_type2f2.png` | 24x24, two frames | Middle-value invader rows |
| `VISUAL-01`, `SCORE-01` | `assets/Enemies/enemy3/invader_type3f1.png`, `invader_type3f2.png` | 24x24, two frames | Low-value invader rows |
| `ATTACK-01` | `assets/Enemies/enemy_pop/enemy pop1.png`–`enemy pop5.png` | 23x23, five frames | Invader destruction |
| `PLAYER-02`, `VISUAL-02` | `assets/missile/hero_missile.png` | 5x8 PNG | Upward player projectile |
| `ENEMY-01`, `VISUAL-02` | `assets/missile/enemy_missile/spear/enemy_missile1.png`–`enemy_missile7.png` | 5x8, seven frames | Downward enemy projectile |
| `ENEMY-01`, `VISUAL-02` | `assets/missile/enemy_missile/zigzag/enemy_missile_zag.png`, `enemy_missile_zig.png` | 5x8, two frames | Alternate enemy projectile animation |
| `ATTACK-02` | `assets/baracade.png` | 48x14 PNG | Non-destructible barrier |
| `VISUAL-01` | `assets/Cabnet border.png` | 3840x2160 image with transparent play area | Proportional arcade/cabinet frame |
| `VISUAL-01` | `assets/icon.png`, `assets/icon.svg`, `assets/icon.ico` | Project icons | Window/project identity |

## Optional bonus identity

The bonus-saucer images under `assets/Enemies/bonus saucer/` are retained as optional visual material. The GDD does not require a bonus-score system, so an implementation may leave them unused without penalty.

## Audio

`assets/Audio/doot1.wav`–`doot4.wav`, `shoot.wav`, `explode.wav`, and `saucer.wav` are available for the corresponding movement cadence, firing, destruction, and optional saucer feedback. Exact synchronization is not a hard gameplay requirement, but audio must never contradict the visible state.

## Import and layout rules

- Use nearest-neighbor filtering for the pixel sprites and preserve aspect ratio.
- The cabinet image may be scaled proportionally to cover the viewport; its transparent central area must not conceal gameplay.
- Frame sequences are source art, not a prescribed animation tree. Implementations may use the supplied frames in a different order or timing where the GDD does not fix it.
- The upstream `PixeloidMono-d94EV.ttf` file is not distributed. Use the engine default font or another cleared font.
- `.import` sidecars are source import settings; regenerate them through a cold Godot import rather than copying `.godot/` caches.

## Licensing

The upstream repository is MIT-licensed, and its README states that the original images and sounds were made by the upstream author. Preserve `legal/LICENSE` and `legal/CREDITS.md`. The separate font is excluded because its license has not been established.
