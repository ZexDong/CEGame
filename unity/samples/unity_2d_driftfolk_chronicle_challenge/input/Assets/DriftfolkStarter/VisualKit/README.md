# Driftfolk Modular Visual Starter Kit

This protected folder supplies isolated, import-ready pixel-art components for the
Driftfolk Chronicle challenge. `CONTACT_SHEET.png` is a labeled inventory preview; use it
together with `ASSET_CATALOG.json` and `IMPORT_FACTS.json`.

## What is supplied

- repeatable sea, sand, grass, and four directional shoreline tiles;
- distinct resident job/state sprites;
- settlement buildings and a construction scaffold;
- island decor, weather badges, pressure badges, and resource icons;
- three independent escape-project components;
- simple maritime UI skins, a chronicle icon, and a grounding shadow;
- a palette sheet and an English contact sheet.

## What is intentionally not supplied

There is no final Scene, prefab, object hierarchy, completed island map, screen layout,
HUD layout, event layout, ending layout, or gameplay code. You must decide how to compose
the components and may author reasonable
supplementary visuals. Supplementary art does not replace the required visible supplied-kit
coverage. Do not display the contact sheet or palette as a substitute for a runtime game
screen.

## Import and assembly facts

The individual runtime PNGs are already imported as single Sprites with Point filtering,
no mip maps, no compression, alpha transparency, Full Rect meshes, and 16 pixels per unit.
Terrain uses Repeat wrap mode. Files ending in `_9slice` have a four-pixel border. Preserve
integer scaling where practical and assemble the supplied components into the player-facing
roles required by the GDD.
