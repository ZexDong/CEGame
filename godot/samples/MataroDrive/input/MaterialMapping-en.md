# MataroDrive Material Mapping

Input revision: `dashboard-contract-20261022-r2`.

The upstream repository has no distribution license. No upstream code, logo, audio, scene, or bitmap is published. The task therefore defines **procedural coverage**: required player-facing roles must be constructed from runtime shapes, gradients, particles, text, and other independently authored local presentation.

| Requirement | Role | Public status | Required visual result |
|---|---|---|---|
| `VISUAL-01` | Car | Procedural | A readable car with wheels, facing, tilt, and color selected by the Garage |
| `VISUAL-01` | Terrain / slope | Procedural | Solid ground that visually agrees with collision |
| `VISUAL-01`–`VISUAL-02` | Sky / weather / scenery | Procedural | Distinct day, dusk, night, sunset, dawn, rain, and snow families |
| `COLLECT-01` | Coin | Procedural | Spinning/glowing collectible distinct from gems |
| `COLLECT-04` | Gem | Procedural | Rare five-cash collectible distinct from coins |
| `COLLECT-05` | Cone | Procedural | Small hazard that launches away when hit |
| `OBJECT-05` | Enemy | Procedural | Patrolling hazard distinct from cones |
| `OBJECT-01` | Boost pad | Procedural | Directional speed-pad marking |
| `OBJECT-02` | Spring | Procedural | Trampoline silhouette distinct from boost |
| `OBJECT-03`–`OBJECT-04` | Shield / magnet power-up | Procedural | Shield and magnet pickups remain visually distinct |
| `OBJECT-06` | Moving platform | Procedural | Support surface with visible movement path |
| `STORY-02` | Goal | Procedural | Finish marker that visibly changes when reached |
| `HUD-01`–`HUD-04` | HUD / menus / results | Procedural | Text, bars, panels, buttons, cards, and stars remain readable |

## Contact sheet

`Assets/asset-contact-sheet.png` is a rendering of `Assets/procedural-role-contact-sheet.svg`. It communicates the permitted procedural visual language; it is not a required pixel-perfect layout.

## Processing freedom

- Implementations may choose any coherent palette, line treatment, shape vocabulary, and motion style.
- World geometry may be scene-authored or generated at runtime.
- Audio is optional. If included, it must be independently created or cleared and must not copy the upstream files.
- Do not download the upstream repository or reconstruct its logo/audio into the submission.

## Licensing

`legal/LICENSES.md` records the unresolved upstream license boundary. Only the public documents, dashboard skeleton, naming table, and the independently created procedural contact sheet are distributed in this Input.
