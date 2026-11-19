# OpenRPG material mapping

Input revision: `dashboard-contract-20261022-r2`.

`sp/` is the only Godot project and contains the canonical runtime materials. Paths below are package-relative; strip `sp/` and prefix `res://` inside the project. `Assets/` holds the material index and source-art contact sheet. Duplicate source mirrors have been consolidated into the usable project copies.

 `Assets/material-index.json` preserves engine-read dimensions, texture regions, dependencies, and role coverage. `Assets/asset-contact-sheet.png` previews individual supplied assets and prescribes no scene layout.

## Principal roles

| Role | Exact asset path | Dimensions / region |
|---|---|---|
| gobot: Robot in exploration | `sp/assets/characters/gobot_field.png` | [72, 162]; region [1, 1, 16, 16] |
| npc: Quest townsfolk | `sp/assets/characters/character_generic.png` | [72, 162]; region whole sheet |
| ghost: Grove ghost | `sp/assets/characters/ghost.atlastex` | [16, 16]; region [17.0, 170.0, 16.0, 16.0] |
| terrain: Forest and buildings | `sp/assets/terrain/town_tilemap.png` | [203, 186]; region whole sheet |
| interior: House interior tiles | `sp/assets/terrain/dungeon_tilemap.png` | [203, 186]; region whole sheet |
| arena: Battle background | `sp/assets/arenas/steppes.png` | [1920, 1080]; region whole sheet |
| baloo: Baloo battle sheet | `sp/battlers/bear/bear.png` | [418, 370]; region whole sheet |
| nutsy: Nutsy battle sheet | `sp/battlers/squirrel/squirrel.png` | [343, 302]; region whole sheet |
| bugcat: First encounter sheet | `sp/battlers/bugcat/bugcat.png` | [241, 326]; region whole sheet |
| wolf: Second encounter sheet | `sp/battlers/wolf/wolf.png` | [422, 470]; region whole sheet |
| coin: Coin icon | `sp/assets/items/coin.atlastex` | [16, 16]; region [153.0, 119.0, 16.0, 16.0] |
| key: Key icon | `sp/assets/items/key.atlastex` | [16, 16]; region [153.0, 153.0, 16.0, 16.0] |
| bomb: Bomb icon | `sp/assets/items/bomb.atlastex` | [16, 16]; region [153.0, 136.0, 16.0, 16.0] |
| wand_red: Red wand icon | `sp/assets/items/wand_red.atlastex` | [16, 16]; region [119.0, 170.0, 16.0, 16.0] |
| wand_blue: Blue wand icon | `sp/assets/items/wand_blue.atlastex` | [16, 16]; region [136.0, 170.0, 16.0, 16.0] |
| wand_green: Green wand icon | `sp/assets/items/wand_green.atlastex` | [16, 16]; region [102.0, 170.0, 16.0, 16.0] |

## Import, layout, and transparency

- Pixel art uses nearest filtering without mipmaps; use integer enlargement when practical and preserve aspect ratio. The starter's main CanvasItem uses nearest filtering.
- The terrain TileSet `sp/assets/terrain/tilesets/kenney_obstacles.tres` has 16 x 16 tile cells. Tile IDs/atlas layout are in the supplied TileSet; no prescribed new map layout is hidden here.
- `*.atlastex` files are binary Godot AtlasTexture resources despite their extension. Load them as Texture2D; do not parse them as text or infer whole-sheet frame counts. The material index publishes their source atlas, crop rectangle, margin, dimensions, and used-pixel bounds as read by Godot. `opaque_bounds` describes the nontransparent bounding region, not collision geometry.
- Character graphic PackedScenes and battler animation scenes are passive art. Animation tracks describe frame/region changes and referenced visual-node paths; they do not supply movement, inventory, quest, or turn systems. Inspect the existing scenes when reusing their animation data; an implementation may instead use their textures directly.
- `sp/assets/characters/ghost_gfx.tscn` uses the supplied `ghost.atlastex`; Lady graphics use `generic.atlastex`. No `lady.atlastex` is supplied or required.
- Character visuals depend on `sp/src/field/gamepieces/animation/gamepiece_animation.tscn`; battler visuals depend on `sp/src/combat/battlers/battler_anim.tscn`. These are script-free visual base scenes. Keep their referenced visual nodes when reusing inherited animation scenes, or rebuild equivalent art presentation with the same sources.
- Font source files are imported by Godot. The starter declares its font on the relevant scene controls, so a completely cold import does not depend on a pre-existing global-theme font cache.
- Material `.import` sidecars are source import settings. `.godot/` is generated cache and is not part of the input.

## Audio and fonts

Music in `sp/assets/music/` can accompany exploration or battles; no exact track/event pairing or playback duration is required. Door, confirmation, error, drop, chop, and impact sounds in `sp/assets/sfx/` are available feedback for the corresponding interactions. Audio is optional decoration unless needed to complement visible feedback; there is no hidden event sequence. Durations are included for engine-loaded streams in the material index. UI font files live in `sp/assets/gui/font/`; Kenney Pixel is the starter font.

## Licensing

Retain `legal/LICENSE`, `legal/CREDITS.md`, `sp/LICENSE`, `sp/CREDITS.md`. The credits list upstream asset authors and licenses; their external links are attribution, not a requirement to fetch anything.

## Supplied and procedural coverage

All 16 principal artwork roles above are supplied. The following presentation roles may be procedural under ART-01; no required visual role is missing.

| Role | Permitted presentation |
|---|---|
| pedestals | Color-coded pedestal markers. Use supplied tiles/textures where useful; code-drawn equivalents allowed by ART-01. |
| route_gate | Blocked/open route indication. Use supplied tiles/textures where useful; code-drawn equivalents allowed by ART-01. |
| quest_markers | Optional NPC goal markers. Use supplied tiles/textures where useful; code-drawn equivalents allowed by ART-01. |
| menus | UI arrangement, labels, bars, selection outlines. Use supplied tiles/textures where useful; code-drawn equivalents allowed by ART-01. |
| effects | Damage/heal and invalid-action feedback. Use supplied tiles/textures where useful; code-drawn equivalents allowed by ART-01. |

 The JSON index contains descriptive resource facts, not a second file-hash inventory. Preserve source materials; import sidecars are source settings, while `.godot/` remains generated cache.
