# Asset manifest

| File | Format and size | Intended use | Required |
|---|---|---|---|
| `textures/urban_tiles.png` | RGBA PNG, 224 × 96; 16 × 16 grid | Player, building/climbing elements, flowerpot and bird egg | Yes, `UC-ASSET-01` |
| `textures/helicopter.png` | RGBA PNG, 76 × 38 | Rooftop extraction | Yes, `UC-ASSET-01` |
| `textures/urban_tiles24.png` | RGBA PNG, 120 × 72; 24 × 24 grid | Optional climbing, bird, and character animation source | No |
| `textures/city_bg.png` | RGBA PNG, 96 × 144 | Optional near city background | No |
| `textures/city_bg_far.png` | RGBA PNG, 96 × 144 | Optional far city background | No |

## Usage

Crop semantic sprites/frames; do not display the whole sheet as a game object. Atlas creation,
scaling, tinting, and composition are allowed. The starter already uses nearest texture filtering.

Copy used files into `starter_project/` so the completed project is self-contained. Do not edit
the supplied originals. There is no prescribed atlas name, scene structure, or animation naming.
The rescue beacon and temporary closure may use simple original, recognizable artwork.

No font or audio is supplied. The built-in Defold font is available. Audio is optional; any added
audio must have clear usage rights.

## Source and license

Textures come from `Urban Climber/assets/png/` in
[benjames-171/defold-games](https://github.com/benjames-171/defold-games), source commit
`8a7d7b759b4448db472c0ae2cad69218cba0fe1f`. This is a source reference, not a runtime check.
Copyright 2022 Ben James; MIT license text is in
[../legal/UPSTREAM_MIT_LICENSE.txt](../legal/UPSTREAM_MIT_LICENSE.txt).

Upstream credits name music author Roberto Ricioppo but do not provide a per-audio license, so no
upstream music/sound is included. The upstream font is also excluded.
