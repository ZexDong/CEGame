# Clean Original Asset Catalog

The public project contains 30 privacy-scanned Unreal asset packages. They are original visual content and dependencies only; no original gameplay Blueprint, map, AI, menu, StateTree, data registry, input mapping, save, or evaluator is included.

## Mandatory Visible Assets

| Requirement | Asset | Unreal logical path | Required role |
|---|---|---|---|
| `ASSET-04` | SM Bomb | `/Game/Bomber/Meshes/SM_Bomb` | Required visible bomb mesh |
| `ASSET-04` | SM PlayerArrowStart | `/Game/Bomber/Meshes/SM_PlayerArrowStart` | Required visible Player 1 start marker mesh |
| `ASSET-01` | MM Manny Idle | `/BlockoutMap/BlockoutMap/Animations/MM_Manny_Idle` | Required character idle animation |
| `ASSET-01` | MI Quinn 01 | `/BlockoutMap/BlockoutMap/Characters/Mannequins/Materials/Quinn/MI_Quinn_01` | Required Player 1 character material |
| `ASSET-01` | MI Quinn 02 | `/BlockoutMap/BlockoutMap/Characters/Mannequins/Materials/Quinn/MI_Quinn_02` | Required Player 2 character material |
| `ASSET-01` | SKM Quinn Simple | `/BlockoutMap/BlockoutMap/Characters/Mannequins/Meshes/SKM_Quinn_Simple` | Required visible character mesh for both players |
| `ASSET-02` | SM BlockoutMap Box | `/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Box` | Required visible destructible-crate mesh |
| `ASSET-03` | SM BlockoutMap Powerup Bomb | `/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Bomb` | Required visible Bomb power-up mesh |
| `ASSET-03` | SM BlockoutMap Powerup Fire | `/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Fire` | Required visible Fire power-up mesh |
| `ASSET-03` | SM BlockoutMap Powerup Skate | `/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Powerup_Skate` | Required visible Skate power-up mesh |
| `ASSET-02` | SM BlockoutMap Wall | `/BlockoutMap/BlockoutMap/Meshes/SM_BlockoutMap_Wall` | Required visible indestructible-wall mesh |

All parent materials, textures, the skeleton, and other exact dependencies are listed in `assets/ASSET_CATALOG.json` with byte lengths and SHA-256 hashes.

## Replacement Policy

Required models and materials cannot be replaced. Supporting floor, lighting, and explosion geometry may use original work or engine content when GDD Section 6 permits it.

## License

All released upstream assets are mapped to the included MIT notice under `assets/legal/`. The notice is legal material and must not be displayed as in-game author/community UI.
