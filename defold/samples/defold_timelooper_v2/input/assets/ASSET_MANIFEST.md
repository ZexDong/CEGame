# Asset manifest

| File | Format and size | Intended use | Required by GDD |
|---|---|---|---:|
| `textures/timelooper_tiles.png` | RGBA PNG, 96 × 96; 8 × 8 grid | Player, echo source, platforms, gems, and spikes | Yes |
| `textures/mechanisms.png` | RGBA PNG, 96 × 48; 24 × 24 grid | Pressure button, door, and exit | Yes |
| `textures/collision_reference.png` | RGBA PNG, 96 × 96 | Optional upstream collision-shape reference | No |
| `textures/echo_smoke.png` | RGBA PNG, 16 × 16 | Optional echo spawn/despawn particle source | No |
| `textures/timelooper_bg.png` | RGB PNG, 32 × 24 | Optional level background | No |

## Usage rules

- Use `timelooper_tiles.png` and `mechanisms.png` in the actual game view as required by the GDD.
  You do not need to reproduce upstream atlas names, animation names, coordinates, collision shapes,
  or level layout.
- Cropping, Defold atlases/tilesources, scaling, tinting, and composition are allowed. The player
  image may be tinted red or made translucent for the time echo.
- `collision_reference.png` is visual reference only; implement and verify collision for the final
  level independently.
- Copy needed files into `starter_project/`. Do not reference this source directory directly and do
  not modify the provided originals.
- No font or audio is supplied. Defold's built-in font and legally clear custom/equivalent sound may
  be used; sound is not required.

## Source and license

These assets come from `Timelooper/assets/png/` in `benjames-171/defold-games`, fixed at commit
`8a7d7b759b4448db472c0ae2cad69218cba0fe1f`. The repository is MIT licensed; the complete license is
in `../legal/UPSTREAM_MIT_LICENSE.txt`.

Upstream Credits separately name music author AcidDose but do not give per-audio licensing, so no
upstream music or sound is redistributed here. The upstream font is also omitted.

