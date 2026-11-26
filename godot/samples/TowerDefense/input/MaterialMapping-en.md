# Public Material Mapping

## 1. Canonical Material Root

All canonical source assets are under `Asserts/` in this input package. Copy only the files needed by the implementation into the runnable `sp/` project and let the required Godot toolchain import them. Do not copy `.godot/`, `.import`, or other generated cache data.

`Asserts/MANIFEST.json` describes source dimensions and hashes.  `Asserts/path_reference.json` describes only the player-visible route/build-space semantics.

## 2. File-to-Gameplay Mapping

| Canonical source file | Suggested runtime path | Required player-visible identity and use | GDD IDs |
|---|---|---|---|
| `Asserts/menu/bg.png` | `game_assets/menu/bg.png` | Primary initial-menu background | `ASSET-01` |
| `Asserts/maps/map1.webp` | `game_assets/maps/map1.webp` | Grassland battlefield, stone road, grass, obstacles, and base relationship | `MAP-01`, `MAP-02`, `ASSET-02` |
| `Asserts/turrets/technoturret.png` | `game_assets/turrets/technoturret.png` | Gatling Gun card, drag preview, placed tower, and details | `TOWER-01`, `ASSET-03` |
| `Asserts/turrets/laserturret.png` | `game_assets/turrets/laserturret.png` | Flamethrower card, drag preview, placed tower, and details | `TOWER-02`, `ASSET-03` |
| `Asserts/turrets/reallaser.png` | `game_assets/turrets/reallaser.png` | Raygun card, drag preview, placed tower, and details | `TOWER-03`, `ASSET-03` |
| `Asserts/turrets/dynamite.png` | `game_assets/turrets/dynamite.png` | Explosive card, drag preview, and details | `TOWER-04`, `ASSET-03` |
| `Asserts/turrets/dynamite-pack.png` | `game_assets/turrets/dynamite-pack.png` | Primary placed-state visual for Explosive; source is a 3×3 atlas of 32×32 cells | `TOWER-04`, `ASSET-03` |
| `Asserts/enemies/dino1.png` | `game_assets/enemies/dino1.png` | Red Dino; 24-frame horizontal atlas; the only regular Dino that attacks towers, continuing its route movement while firing | `ENEMY-01`, `ENEMY_ATTACK-01`, `ASSET-04` |
| `Asserts/enemies/dino2.png` | `game_assets/enemies/dino2.png` | Blue Dino; 24-frame horizontal atlas; never attacks towers | `ENEMY-01`, `ENEMY_ATTACK-04`, `ASSET-04` |
| `Asserts/enemies/dino3.png` | `game_assets/enemies/dino3.png` | Yellow Dino; 24-frame horizontal atlas; never attacks towers | `ENEMY-01`, `ENEMY_ATTACK-04`, `ASSET-04` |
| `Asserts/enemies/dino4.png` | `game_assets/enemies/dino4.png` | The single Green Dino boss, last enemy of Wave 10; 24-frame horizontal atlas; displayed at exactly 1.6× the normal Dino linear scale and continuing its route movement while firing | `BOSS-01`, `ENEMY_ATTACK-02`, `ASSET-04` |

Suggested runtime paths are not mandatory. Any project-local paths are acceptable if all assets remain offline, load under Godot, and preserve the identities above.

## 3. New Mechanism Visual Mapping

These visuals deliberately use engine-native drawing/UI and require no new bitmap files:

| Mechanism visual | Material source | Fixed presentation | GDD IDs |
|---|---|---|---|
| Red Dino projectile | Procedural filled circle | Red, 8 px diameter; visibly originates at the moving `dino1.png`, travels to a tower within the shared 102 px enemy attack range that matches Level 1 Explosive, and deals 1 damage on impact | `ENEMY_ATTACK-01`, `ENEMY_ATTACK-03`, `ASSET-05` |
| Green boss projectile | Procedural filled circle | Red, 20 px diameter; visibly originates at the moving enlarged `dino4.png` boss, travels to a tower within the shared 102 px enemy attack range that matches Level 1 Explosive, and deals 5 damage on impact | `ENEMY_ATTACK-02`, `ENEMY_ATTACK-03`, `ASSET-05` |
| Tower health bar | Engine-native UI/procedural rectangles | Dark backing plus green fill, attached directly above every living placed tower; fill equals current HP divided by maximum HP | `TOWER_HP-01`, `TOWER_HP-02`, `HUD-03`, `ASSET-05` |
| Tower HP text and Repair control | Engine-native UI/text/button | Selected-tower details show current/maximum HP and the label `Repair — 20 Gold` | `MANAGE-01`, `REPAIR-01`, `REPAIR-02`, `HUD-02`, `ASSET-05` |
| Green boss identity/health bar | `dino4.png` plus engine-native UI | Clearly readable `Boss` identity and health bar spatially associated with the 1.6× Green Dino | `BOSS-01`, `HUD-03`, `ASSET-04`, `ASSET-05` |

Do not map either enemy projectile to a turret projectile bitmap or replace a required Dino/tower sprite with a procedural placeholder. Procedural health bars, text, buttons, outlines, hit flashes, and projectiles supplement the canonical sprites; they do not replace them.

## 4. Allowed Transformations and Validation

Proportional scaling, cropping, flipping, atlas-region extraction, animation, tinting, outlines, and supporting effects are allowed as long as the mapped image remains the clearly recognizable primary visual. The Green boss's required 1.6× linear scale is measured relative to the normal displayed Dino scale; its hit area must grow proportionally.

Before delivery, preserve the licenses under `legal/`, and ensure all path capitalization matches on the target platform.
