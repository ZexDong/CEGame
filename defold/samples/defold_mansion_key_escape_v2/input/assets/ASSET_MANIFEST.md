# Asset manifest

| File | Intended use | Required by GDD | Source |
|---|---|---:|---|
| `textures/mansion_tiles.png` | Pixel-art source for the player, floor, walls, furniture, key, and door | Yes | Upstream `Mystery Mansion/assets/png/tiles.png` |
| `textures/shadow_smoke.png` | Shadow body or its main nearby effect | Yes | Upstream `Mystery Mansion/assets/png/smoke.png` |
| `textures/danger_overlay.png` | Optional visible danger-proximity cue; may be cropped or partly used | No | Upstream `Mystery Mansion/assets/png/fear.png` |
| `audio/pickup.ogg` | Optional key-pickup sound | No | Upstream file of the same name |
| `audio/door_open.ogg` | Optional unlock/open sound | No | Upstream file of the same name |
| `audio/heartbeat.ogg` | Optional danger-proximity sound | No | Upstream `Mystery Mansion/assets/ogg/heart.ogg` |

## File information

| File | Format and size |
|---|---|
| `textures/mansion_tiles.png` | RGBA PNG, 384 × 128 |
| `textures/shadow_smoke.png` | RGBA PNG, 64 × 64 |
| `textures/danger_overlay.png` | RGBA PNG, 128 × 128 |
| `audio/pickup.ogg` | Ogg Vorbis, mono, 44.1 kHz |
| `audio/door_open.ogg` | Ogg Vorbis, mono, 44.1 kHz |
| `audio/heartbeat.ogg` | Ogg Vorbis, mono, 44.1 kHz |

## Usage rules

- The GDD requires `mansion_tiles.png` and `shadow_smoke.png`, but does not prescribe one crop,
  tint, scale, or UI arrangement.
- Page layout and UI information structure are governed by `../reference/` and Section 6 of the
  GDD. Reference screenshots are not finished backgrounds that may be imported into the game.
- Audio and `danger_overlay.png` are optional and may be replaced with clear equivalent feedback.
- The upstream third-party font is deliberately omitted because its separate source has not been
  verified. Use Defold's built-in font or another font with a clear license.

## License

Every file was checked against Mystery Mansion in `benjames-171/defold-games` at fixed commit
`8a7d7b759b4448db472c0ae2cad69218cba0fe1f`. They are byte-identical to the listed upstream files
apart from public-package filenames; nothing was re-encoded. The upstream repository is MIT
licensed. Retain `../legal/UPSTREAM_MIT_LICENSE.txt` and its copyright notice when redistributing.

