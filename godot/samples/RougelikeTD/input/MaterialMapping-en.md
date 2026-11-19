# RougelikeTD Material Mapping

Input revision: `dashboard-contract-20261022-r2`.

Paths are relative to `sp/`; prefix them with `res://` inside the project. The public starter preserves the upstream `assets/` folder placement, so the runtime paths intentionally contain `assets/assets/`.

## Principal roles

| Requirement | Exact runtime path | Information | Use |
|---|---|---|---|
| `VISUAL-01` | `assets/assets/tilesets/GroundTileset.png` | 256x256 tileset | Grass/path terrain |
| `WAVE-04` | `assets/assets/sprites/Portals.png` | 94x72 sheet | Locked/open spawn portals |
| `HERO-01`, `VISUAL-03` | `assets/assets/sprites/heroes/Archer_idle.png`, `Archer_attack1.png`, `Archer_attack2.png` | 390x540 each | Archer idle and ranged attack |
| `HERO-02`, `VISUAL-03` | `assets/assets/sprites/towers/SlowTower.png` | 22x30 | Mage visual source, tinted to distinguish the magical role |
| `HERO-03`, `VISUAL-03` | `assets/assets/sprites/towers/AoeTower.png` | 23x33 | Warrior visual source, tinted to distinguish close-range area attacks |
| `ENEMY-01`, `VISUAL-04` | `assets/assets/sprites/enemies/BaseEnemy.png` | 48x48 | Basic enemy |
| `ENEMY-02`, `VISUAL-04` | `assets/assets/sprites/enemies/RunnerEnemy.png` | 48x48 | Runner enemy |
| `ENEMY-03`, `VISUAL-04` | `assets/assets/sprites/enemies/TankEnemy.png` | 48x48 | Tank enemy |
| `ENEMY-04`, `VISUAL-04` | `assets/assets/sprites/enemies/BossEnemy.png` | 48x48 | Boss enemy |
| `HERO-04` | `assets/assets/sprites/projectiles/Projectile.png` | 6x6 | Projectile source; tinting/scale may distinguish effects |
| `VISUAL-01` | `assets/icon.svg` | Vector icon | Project/window identity |

## Import and layout rules

- Use nearest-neighbor filtering and preserve aspect ratio.
- The ground image is a source tileset, not a level screenshot. `sp/data/map.json` records the 18-by-10 layout in GDD MAP-01: interpolate consecutive axis-aligned corners into cells; both paths end at the same base. One cell spans 32 world units; range and speed values in the GDD use those units.
- The hero and enemy images are source identities. Animation order, origin, tint, scale, and collision size may differ where the GDD does not fix them.
- Health bars, range previews, placement markers, reward cards, and result overlays may be runtime-drawn.


## Licensing

The upstream repository includes the MIT license reproduced in `legal/LICENSE`. The repository documentation includes generated-art instructions, but the distributed files are part of the upstream repository. `legal/LICENSES.md` and `legal/CREDITS.md` preserve the source status; no asset outside this mapped set is distributed.
