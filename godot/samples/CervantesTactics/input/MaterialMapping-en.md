# Asset Mapping

> Version v1.21-en.
>
> `Asserts/` preserves the original relative asset paths. The table below has been corrected against Chapter One's original `MainMenu.tscn`, `chapter_01.tres`, unit resources, and battlefield renderer. A “retained asset” is not necessarily referenced by the original game at runtime in Chapter One. All assets must still be used in accordance with `LICENSES.md`.

## Correspondence Rules

- This mapping is identity- and role-specific. A file appearing in the package does not make it interchangeable with another member of the same faction or asset category.
- A mapped asset counts as used only when it is visibly instantiated in the corresponding runtime context. Importing, preloading, placing offscreen, or mentioning its path is not sufficient.
- Character standees are battlefield-unit renderings; portraits are HUD, dialogue, result, and progression renderings. These two roles cannot substitute for each other.
- Environment assets are tied to the listed side, coordinate, or construction role. A visually similar door, gate, obstacle, banner, tile, or crystal cannot be moved into another mapped role.
- If a summary in this file conflicts with a numbered acceptance requirement, `GDD-en.md` Section 6—especially `ASSET-01-06`—is authoritative.

## Branding, Backgrounds, and Crystal Reference Art

| Path | Original-game mapping | the canonical Input usage boundary |
|---|---|---|
| `branding/logo-main-tight.png` | Actual main-menu logo in `MainMenu.tscn` | May be used as the required title logo; anchor it in the upper-left safe area, preserve its aspect ratio and transparent background, and place the menu-button group below it |
| `branding/logo-main.png` | Full branding image with generous clear space | May be used instead of the compact logo as the required upper-left title logo; preserve its aspect ratio and transparent background, and place the menu-button group below it |
| `maps/chapter01/chapter01-map-art-concept.png` | Actual background in `MainMenu.tscn` | Required main-menu background; cover the `1280×720` viewport proportionally without stretching |
| `maps/chapter01/chapter01-map-art-16-9.png` | 16:9 composition export | Background for the fixed `1280×720` results page; cover proportionally without stretching |
| `maps/chapter01/chapter01-map-art-16-10.png`, `21-9.png`, `wide.png`, `macbook.png` | Other aspect-ratio exports of the same composition | Retained assets only; the fixed 16:9 build does not reference them at runtime |
| `maps/chapter01/chapter01-crystal-pedestal.png` | Crystal-pedestal reference image in the asset package; the original Chapter One runtime did not use it as the central battlefield objective | Do not use it as a camera-facing sprite at `(6,4)`; the central objective must be a 3D crystal composed of a stone base, gold ring, blue luminous crystal, and blue light |

## Character Identities

| Identity | Standee | Portrait | Original display rule |
|---|---|---|---|
| Erick | `standees/family/erick-standee.png` | `portraits/family/erick-avatar.png` | Family knight; standee scale group `0.20` |
| Mitzi | `standees/family/mitzi-standee.png` | `portraits/family/mitzi-avatar.png` | Family archer; standee scale group `0.20` |
| Diego | `standees/family/diego-standee.png` | `portraits/family/diego-avatar.png` | Family mage; standee scale group `0.20` |
| Hercules | `standees/family/hercules-standee.png` | `portraits/family/hercules-avatar.png` | Family guardian; standee scale group `0.19` |
| Guardia Sin Memoria | `standees/rivals/guardia-sin-memoria-standee.png` | `portraits/rivals/guardia-sin-memoria-portrait.png` | Melee enemy; scale group `0.19`; horizontally flip the base single image according to enemy-facing rules |
| Arquero Sin Memoria | `standees/rivals/arquero-sin-memoria-standee.png` | `portraits/rivals/arquero-sin-memoria-portrait.png` | Ranged enemy; scale group `0.19`; horizontally flip the base single image according to enemy-facing rules |
| Adepto Sin Memoria | `standees/rivals/adepto-sin-memoria-standee.png` | `portraits/rivals/adepto-sin-memoria-portrait.png` | Spellcasting enemy; scale group `0.19`; horizontally flip the base single image according to enemy-facing rules |
| Tuffy | Chapter One does not use `tuffy-standee.png` to create a combat unit | `portraits/family/tuffy-avatar.png` | Guide used only in dialogue; the original unit resource is non-combat and non-blocking |

The `capitan`, `oraculo`, and `tirador` standees and `orden-vidrio-negro-concept-sheet.png` are cult expansion/concept assets. They are not the three enemies participating in Chapter One and must not replace the guard, archer, or adept. Likewise, a correct standee paired with another character's portrait is a broken mapping rather than partial identity reuse.

In dialogue, the mapped portrait occupies the panel's left column, the matching speaker name appears below that portrait, and the body text appears to the right of the portrait-and-name column. When the final segment closes, the panel and all of these dialogue-only renderings disappear together.

## Chapter One Board and Obstacles

| Coordinate or area | Original meaning | Corresponding asset/construction | Blocking? |
|---|---|---|---:|
| Family Terrace, Archive Grass | Moss-green brick surface | KayKit `3d/kaykit_dungeon/Models/gltf/tileBrickA_large.glb`, with Family-area tint and tactical highlight layer | No |
| Memory Stone Road, Crystal Dais, Broken Ground, Cult Area, and the rest of the board | Stone-brick surface | KayKit `3d/kaykit_dungeon/Models/gltf/tileBrickB_large.glb`, with a stone appearance related to `3d/Textures/stylized_stone_floor.png`, tinted by area; tactical highlights are thin overlays only | No |
| `(3,4)` | Rubble on broken road | `3d/rubble.glb` | Yes |
| `(4,2)` | Stone pillar | Original procedural column with stylized stone texture | Yes |
| `(10,2)` | Stone pillar | Original procedural column with stylized stone texture | Yes |
| `(7,5)` | Rubble | `3d/rubble.glb` | Yes |
| `(11,2)` | Cult obelisk | Original procedural hexagonal obelisk in dark-purple stone | Yes |
| `(4,6)` | Brambles/grass | `3d/grass.glb` | Yes |
| `(9,6)` | Chest | `3d/chest.glb` | Yes |
| `(6,4)` | Family Crystal | Procedural 3D stone base, gold ring, blue crystal, and blue light | Yes |
| `(10,1)` | Cult banner | `3d/banner.glb` | No |

`3d/floor_tile_decorated.glb` and `3d/doorway.glb` were preloaded or retained in the original project, but the active Chapter One composition does not depend on them. In particular, do not place `doorway.glb` at the right exit as a substitute for the metal-bar gate, and do not let decorative floor tiles alter cell height or blocking rules.

## Entrances, Boundaries, and Vegetation

| Path | Original mapping | Correct use |
|---|---|---|
| `third_party/kenney_modular_dungeon_kit/glb/gate-door.glb` | Door decoration at the left-side Family entrance | Place on the Family-side boundary with a procedural dark stone doorway and two `3d/torch.glb` assets; do not add board-cell blocking |
| `third_party/kenney_modular_dungeon_kit/glb/gate-metal-bars.glb` | Metal-bar gate at the right-side Cult exit | Place outside `(11,4)`; do not swap it with the left-side door |
| `third_party/kenney_modular_dungeon_kit/glb/stairs-wide.glb` | Wide stairs at the lower-right exit | Place outside and near `(11,7)`; it is not the bramble obstacle at `(4,6)` |
| `template-wall-half.glb`, `template-wall-corner.glb` | Dungeon perimeter and corner walls | Use small model scales outside the playable boundary; do not obscure units or objectives |
| `3d/torch.glb` | Paired lights at the Family entrance | Place on both sides of the left entrance; they are not the column at `(10,2)` |
| `textures/foliage/oaktoonbranchesgreen.png` | Original leaf material for the Memory Tree | Apply it to canopy geometry with a trunk and use alpha cutout; do not turn the entire texture into a giant Sprite3D |
| `textures/foliage/treetoonbranchtextures.png` | Retained alternate leaf texture | May be used for additional canopy variants; the original active Chapter One renderer primarily used `oaktoonbranchesgreen.png` |

## Non-Blocking Chapter One Narrative Decorations

The following entries come from `decoration_cells` in the original `chapter_01.tres`. Coordinates are decoration anchors; local offsets affect only visual composition and do not change cell occupancy or height.

| Anchor | Original identity | the canonical Input mapping |
|---|---|---|
| `(0,2)` | Blue Family crystal cluster | Procedural hexagonal blue luminous crystal cluster near the Family entrance |
| `(9,1)`, `(10,6)` | Purple Cult crystal clusters | Procedural hexagonal purple luminous crystal clusters |
| `(1,3)`, `(4,4)`, `(6,3)`, `(7,4)` | Family runes | Cyan luminous ring runes |
| `(8,4)`, `(9,2)`, `(9,4)`, `(10,4)` | Cult runes | Purple luminous ring runes |
| `(1,2)`, `(5,3)` | Family shrines | Low cyan ring shrines |
| `(8,3)`, `(11,1)` | Cult shrines | Low purple ring shrines |
| `(3,7)` | Crate pile | Procedural wooden crate pile; not the chest on blocking cell `(9,6)` |
| `(2,3)`, `(7,5)` | Small ruins | Procedural low rubble structures; the fixed rubble at `(7,5)` remains the primary obstacle |
| `(10,6)` | Second Cult banner | `3d/banner.glb`; together with the banner at `(10,1)`, reinforces the Cult-side composition |

## Trap Markers

- The three traps remain fixed at `(2,5)`, `(8,4)`, and `(9,2)`.
- The original did not designate a separate public bitmap for traps. the canonical Input uses runtime-generated orange-red diamond hazard runes to show detected/triggered state.
- `branding/logo-main-tight.png` serves only as the brand logo and application icon; it must not be used for traps, attack ranges, board runes, or other tactical markers.

## Tactical Range Highlights

- Move and normal-attack ranges use runtime UI highlights over board cells; no separate bitmap asset is assigned.
- Move highlights identify legal destinations, while Attack highlights identify the selected member's normal-attack range and keep legal enemy targets distinguishable.
- Range overlays must remain transparent or thin enough that KayKit brick seams and model contours stay recognizable.

## Usage Boundaries

- Assemble the runtime scene in practice; merely having or preloading a file is not correct use.
- Character standees, portraits, and logos must retain their one-to-one identities; do not substitute concept art or another character from the same faction.
- The identity pair remains consistent everywhere: battlefield standee ↔ HUD card ↔ dialogue/result portrait ↔ name and statistics. Any cross-character swap breaks the correspondence even if each individual file is otherwise valid.
- Tuffy is portrait-only and narrative-only in Chapter One; never synthesize a Tuffy battlefield unit from a portrait, placeholder, or retained standee.
- The seven battlefield standees and their corresponding portraits must not be collapsed into a shared generic player/enemy image.
- Decoration coordinates must not change the rule-defined obstacle set in `GDD-en.md`; decorative doors, walls, stairs, banners, and trees must not create extra impassable cells.
- Model scale follows the original “small tabletop dungeon” composition; do not enlarge Kenney walls, doors, or stairs until they obscure the main board.
- KayKit A/B floor tiles must actually be instantiated at runtime. Merely retaining the `.glb` files or replacing them with unmodeled solid-color boxes does not satisfy the floor-tile mapping. Cell-selection overlays must not completely hide brick seams and model contours.
- Runes, crystal clusters, shrines, crate piles, small ruins, and the second banner are purely decorative and must not be added to the fixed obstacle set.
- Original `.import` files are not included in the public asset package; the target project regenerates import caches.
