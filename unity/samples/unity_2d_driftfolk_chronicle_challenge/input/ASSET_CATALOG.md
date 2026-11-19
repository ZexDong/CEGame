# Driftfolk: Stormbound — Public Asset Catalog

This is the human-facing
index for the protected assets supplied with this public Input. Machine-readable paths and
per-file import facts live in `ASSET_MANIFEST.json` and the visual-kit JSON files.

## Visual inventory

Root: `Assets/DriftfolkStarter/VisualKit`

`Assets/DriftfolkStarter/VisualKit/CONTACT_SHEET.png` is a labeled inventory preview of
the supplied components. Never display it or `PALETTE.png` as a runtime background,
finished map, HUD, or substitute gameplay screen.

| Coverage role | Count | Paths or IDs |
|---|---:|---|
| Sea, land, and modular shoreline | 9 | `Terrain/*.png`, IDs beginning `terrain.` |
| Residents and visible conditions | 6 | `Residents/*.png`, IDs beginning `resident.` |
| Buildings and construction | 5 | `Buildings/*.png`, IDs beginning `building.` |
| Decor, weather, and pressure | 14 | `Environment/*.png`, IDs beginning `environment.`, `weather.`, or `pressure.` |
| Food, firewood, and materials | 3 | `Resources/*.png`, IDs beginning `resource.` |
| Escape-stage components | 3 | `Escape/*.png`, IDs beginning `escape.` |
| UI skins, chronicle icon, and shadow | 5 | `UI/*.png`, IDs beginning `ui.` or `fx.` |

Exact paths, semantic roles, dimensions, transparency, tileability, and suggested scale
are in:

- `Assets/DriftfolkStarter/VisualKit/ASSET_CATALOG.json`
- `Assets/DriftfolkStarter/VisualKit/IMPORT_FACTS.json`
- `ASSET_MANIFEST.json`

Runtime PNGs are preconfigured as single Unity Sprites with Point filtering, no mip maps,
no compression, alpha transparency, Full Rect meshes, and 16 pixels per unit. Terrain
wraps; the three `_9slice` UI skins use a four-pixel border. These are import facts, not a
required architecture or screen layout.

## Supplied-component boundary

The visual kit contains modular components rather than a final Scene, prefab, gameplay
script, object hierarchy, completed island composition, HUD layout, event layout, or
ending layout. The components are derived from the upstream procedural art grammar. You
remain responsible for composition, scale, crop, layering, contrast, spacing, runtime
state binding, and visual validation.
Authored visuals may supplement the kit, but they do not replace the required visible
supplied-kit coverage for terrain, residents, buildings, weather or pressure, resources,
the escape project, and runtime UI.

## Audio inventory

Root: `Assets/DriftfolkStarter/Audio/Resources/Audio`

- 7 ambience clips under `ambience/`;
- 7 music clips under `music/`;
- 12 action and feedback clips under `sfx/`.

Use the cataloged clips in player-facing roles that fit the GDD.

## Source and redistribution boundary

The fixed source is commit `3022c09bf53e396e90694be70b319c625a75931e` of
`euuuuuuan/driftfolk-unity-public`; no newer branch or additional download is needed.
The 45 visual components are Apache-2.0 derivatives of the upstream visual grammar.
The 26 audio files and their notices are preserved byte-for-byte and may be
redistributed with the work project, not as a standalone asset pack. Preserve the
applicable credits, including `Powered by Stability AI` for the supplied music and
ambience, as recorded in `legal/LICENSES.txt`.

The legal documents are preserved source records. Their description of 26 audio
files and no images describes the upstream media inventory; the additional 45
modular derivative sprites are recorded by the visual catalog and the visual-kit
entry in `legal/LICENSES.txt`. Source notices do not supply the original game's
implementation and are not an instruction to obtain additional source material.

`ASSET_CONTACT_SHEET.png` is the exact same inventory image as the visual kit's
`CONTACT_SHEET.png`, copied to the project root for convenient viewing.
Catalog `runtime_assets[*].path` values are relative to the visual-kit root;
audio manifest paths are relative to the Unity project root.
