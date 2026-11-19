# Public Content Catalog

This catalog describes the content supplied with the task. It does not add gameplay requirements; `GDD.md` Section 6 remains authoritative. The starter includes a self-contained lit material kit so the supplied meshes render with depth and the sphere has a high-contrast surface pattern. No gameplay Blueprint, map, input mapping, save data, or evaluator material is included.

## Fixed layout data

| Field | Value |
|---|---|
| Asset ID | `fixed-layout-data` |
| Path | `starter-project/Config/FixedRollBallLayout.json` |
| Format | JSON |
| Required | Yes |
| Equivalent replacement | Not allowed |
| Requirement mapping | `LAYOUT-01`, `LAYOUT-02` |
| Layout ID | `rollball-fixed-maze-10x10-v2` |
| Grid | 10 x 10 cells |
| Cell size | 400 Unreal units |
| Start | `(0,0)` |
| Exit | `(9,9)` |
| Traps | 16 fixed tiles with supplied center-hole geometry |
| Walls | 67 vertical segments and 54 horizontal segments, including perimeter walls |
| License | `MIT-RollBall`; see `THIRD_PARTY_NOTICES.md` and `assets/legal/MIT-RollBall.txt` |

The file is immutable fixture data. An implementation may parse it directly or convert it into project-authored data, but the final player-facing layout must remain identical.

## Required raw visual mesh kit

| Asset ID | Path | Unreal logical path | Required role | Requirement mapping | Equivalent replacement |
|---|---|---|---|---|---|
| `board-floor-mesh` | `starter-project/Content/StarterContent/Architecture/Floor_400x400.uasset` | `/Game/StarterContent/Architecture/Floor_400x400` | Solid 3D board tile for safe floor cells | `LAYOUT-01` | No |
| `board-hole-mesh` | `starter-project/Content/StarterContent/Architecture/Floor_400x400_Hole.uasset` | `/Game/StarterContent/Architecture/Floor_400x400_Hole` | 3D trap tile with a visible center opening and safe surrounding rim | `LAYOUT-01`, `LAYOUT-02`, `HAZARD-01` | No |
| `board-wall-mesh` | `starter-project/Content/StarterContent/Architecture/Wall_400x200.uasset` | `/Game/StarterContent/Architecture/Wall_400x200` | 3D wall geometry for fixed board boundaries and internal walls | `LAYOUT-01`, `COLLISION-01` | No |
| `ball-sphere-mesh` | `starter-project/Content/StarterContent/Shapes/Shape_Sphere.uasset` | `/Game/StarterContent/Shapes/Shape_Sphere` | 3D sphere used for the player-controlled ball | `MOVEMENT-02` | No |

These exact supplied 3D mesh identities must be used in the playable presentation. A 2D drawing, sprite, flat icon, or primitive replacement is not equivalent. Their material references are documented in `assets/ASSET_CATALOG.json`; candidates may assign project-authored materials when a referenced material is not available, but may not replace the meshes with primitives or unrelated models. The mesh packages are sanitized raw visual copies with no gameplay behavior.

## Supplied lit material kit

| Asset ID | Path | Unreal logical path | Intended use |
|---|---|---|---|
| `material-basic-floor` | `starter-project/Content/StarterContent/Materials/M_Basic_Floor.uasset` | `/Game/StarterContent/Materials/M_Basic_Floor` | Default lit material for solid board tiles |
| `material-basic-wall` | `starter-project/Content/StarterContent/Materials/M_Basic_Wall.uasset` | `/Game/StarterContent/Materials/M_Basic_Wall` | Default lit material for walls |

The starter creates a small checker pattern at runtime from the engine's basic lit material for its inert sphere display. This keeps the sphere surface readable without publishing external texture dependencies.

## Dependencies

- The mesh packages are supplied visual assets released under the `epic-content-terms` boundary described in `assets/legal/ASSET_LICENSE_MAP.json`.
- Mesh import metadata is sanitized; logical Unreal object paths are preserved.
- Material references are content dependencies, not gameplay logic. They may be rebound to project-authored materials without changing the required mesh identity.
- No external Marketplace plugin, gameplay Blueprint, assembled map, sound, or evaluator asset is required.

Before runtime validation, assign every supplied mesh a valid project or engine material. A missing source material is never a reason to accept an invisible required object.

