# Chomp asset catalog

All supplied UE art has mandatory visible roles under GDD ASSET-01..05. Unrelated replacements are prohibited; specified transformations and derived resources are allowed. Source copies need no separate runtime import.

Runtime assets are ready to use in `starter-project/Content/Art/`; editable sources are also inside `starter-project/SourceArt/`. The copies in `assets/files/` are protected references. All art is static and unassembled. GDD Section 6 is the acceptance authority; JSON supplies paths, hashes, source-copy links, dimensions and dependency facts. Geometry units are centimeters.

| Resource | Exact path | Use | Requirements |
|---|---|---|---|
| SM_Eye-reference-obj | `starter-project/SourceArt/Meshes/SM_Eye.obj` | Editing source for SM_Eye | ASSET-01, VISUAL-02 |
| SM_FruitBody-reference-obj | `starter-project/SourceArt/Meshes/SM_FruitBody.obj` | Editing source for SM_FruitBody | ASSET-03, FRUIT-01 |
| SM_FruitCrown-reference-obj | `starter-project/SourceArt/Meshes/SM_FruitCrown.obj` | Editing source for SM_FruitCrown | ASSET-03, FRUIT-01 |
| SM_GhostBody-reference-obj | `starter-project/SourceArt/Meshes/SM_GhostBody.obj` | Editing source for SM_GhostBody | ASSET-02, VISUAL-03 |
| SM_GhostHead-reference-obj | `starter-project/SourceArt/Meshes/SM_GhostHead.obj` | Editing source for SM_GhostHead | ASSET-02, VISUAL-03 |
| SM_Jaw-reference-obj | `starter-project/SourceArt/Meshes/SM_Jaw.obj` | Editing source for SM_Jaw | ASSET-01, VISUAL-02 |
| SM_Tooth-reference-obj | `starter-project/SourceArt/Meshes/SM_Tooth.obj` | Editing source for SM_Tooth | ASSET-01, VISUAL-02 |
| T_WallEdge-reference-png | `starter-project/SourceArt/Textures/T_WallEdge.png` | Editing source for T_WallEdge | ASSET-04, VISUAL-01 |
| life-icon-reference-svg | `starter-project/SourceArt/UI/life-icon.svg` | Editing source for T_LifeIcon | ASSET-05, HUD-01 |
| T_LifeIcon-reference-png | `starter-project/SourceArt/UI/T_LifeIcon.png` | Editing source for T_LifeIcon | ASSET-05, HUD-01 |
| M_Neon | `starter-project/Content/Art/Materials/M_Neon.uasset` | Required visible shared color material | ASSET-01, ASSET-02, ASSET-03, ASSET-04 |
| M_Wall | `starter-project/Content/Art/Materials/M_Wall.uasset` | Required visible maze appearance | ASSET-04, VISUAL-01 |
| MI_Crown | `starter-project/Content/Art/Materials/MI_Crown.uasset` | Required visible pineapple | ASSET-03, FRUIT-01 |
| MI_Cyan | `starter-project/Content/Art/Materials/MI_Cyan.uasset` | Required visible ghosts | ASSET-02, VISUAL-03 |
| MI_Dot | `starter-project/Content/Art/Materials/MI_Dot.uasset` | Required visible teeth and pickups | ASSET-01, ASSET-04, VISUAL-01, VISUAL-02 |
| MI_Eye | `starter-project/Content/Art/Materials/MI_Eye.uasset` | Required visible player | ASSET-01, VISUAL-02 |
| MI_Floor | `starter-project/Content/Art/Materials/MI_Floor.uasset` | Required visible maze appearance | ASSET-04, VISUAL-01 |
| MI_Frightened | `starter-project/Content/Art/Materials/MI_Frightened.uasset` | Required visible ghosts | ASSET-02, VISUAL-03 |
| MI_Fruit | `starter-project/Content/Art/Materials/MI_Fruit.uasset` | Required visible pineapple | ASSET-03, FRUIT-01 |
| MI_Gate | `starter-project/Content/Art/Materials/MI_Gate.uasset` | Required visible maze appearance | ASSET-04, VISUAL-01 |
| MI_Orange | `starter-project/Content/Art/Materials/MI_Orange.uasset` | Required visible ghosts | ASSET-02, VISUAL-03 |
| MI_Pink | `starter-project/Content/Art/Materials/MI_Pink.uasset` | Required visible ghosts | ASSET-02, VISUAL-03 |
| MI_Player | `starter-project/Content/Art/Materials/MI_Player.uasset` | Required visible player | ASSET-01, VISUAL-02 |
| MI_Red | `starter-project/Content/Art/Materials/MI_Red.uasset` | Required visible ghosts | ASSET-02, VISUAL-03 |
| SM_Eye | `starter-project/Content/Art/Meshes/SM_Eye.uasset` | Required visible player | ASSET-01, VISUAL-02 |
| SM_FruitBody | `starter-project/Content/Art/Meshes/SM_FruitBody.uasset` | Required visible pineapple | ASSET-03, FRUIT-01 |
| SM_FruitCrown | `starter-project/Content/Art/Meshes/SM_FruitCrown.uasset` | Required visible pineapple | ASSET-03, FRUIT-01 |
| SM_GhostBody | `starter-project/Content/Art/Meshes/SM_GhostBody.uasset` | Required visible ghosts | ASSET-02, VISUAL-03 |
| SM_GhostHead | `starter-project/Content/Art/Meshes/SM_GhostHead.uasset` | Required visible ghosts | ASSET-02, VISUAL-03 |
| SM_Jaw | `starter-project/Content/Art/Meshes/SM_Jaw.uasset` | Required visible player | ASSET-01, VISUAL-02 |
| SM_Tooth | `starter-project/Content/Art/Meshes/SM_Tooth.uasset` | Required visible player | ASSET-01, VISUAL-02 |
| T_WallEdge | `starter-project/Content/Art/Textures/T_WallEdge.uasset` | Required visible maze appearance | ASSET-04, VISUAL-01 |
| T_LifeIcon | `starter-project/Content/Art/UI/T_LifeIcon.uasset` | Required visible life icon | ASSET-05, HUD-01 |
| SM_Eye-source-obj | `starter-project/SourceArt/Meshes/SM_Eye.obj` | Editing source for SM_Eye | ASSET-01, VISUAL-02 |
| SM_FruitBody-source-obj | `starter-project/SourceArt/Meshes/SM_FruitBody.obj` | Editing source for SM_FruitBody | ASSET-03, FRUIT-01 |
| SM_FruitCrown-source-obj | `starter-project/SourceArt/Meshes/SM_FruitCrown.obj` | Editing source for SM_FruitCrown | ASSET-03, FRUIT-01 |
| SM_GhostBody-source-obj | `starter-project/SourceArt/Meshes/SM_GhostBody.obj` | Editing source for SM_GhostBody | ASSET-02, VISUAL-03 |
| SM_GhostHead-source-obj | `starter-project/SourceArt/Meshes/SM_GhostHead.obj` | Editing source for SM_GhostHead | ASSET-02, VISUAL-03 |
| SM_Jaw-source-obj | `starter-project/SourceArt/Meshes/SM_Jaw.obj` | Editing source for SM_Jaw | ASSET-01, VISUAL-02 |
| SM_Tooth-source-obj | `starter-project/SourceArt/Meshes/SM_Tooth.obj` | Editing source for SM_Tooth | ASSET-01, VISUAL-02 |
| T_WallEdge-source-png | `starter-project/SourceArt/Textures/T_WallEdge.png` | Editing source for T_WallEdge | ASSET-04, VISUAL-01 |
| life-icon-source-svg | `starter-project/SourceArt/UI/life-icon.svg` | Editing source for T_LifeIcon | ASSET-05, HUD-01 |
| T_LifeIcon-source-png | `starter-project/SourceArt/UI/T_LifeIcon.png` | Editing source for T_LifeIcon | ASSET-05, HUD-01 |

The jaw and ghost head have a flat base at local Z=0; the ghost body extends below it. Assemble and animate these independent pieces. Color instances share M_Neon; M_Wall uses T_WallEdge on UV-mapped faces. T_LifeIcon is a 128x128 RGBA UI texture without mipmaps. The raw triangle UVs support solid-color meshes rather than a character atlas. Character assembly, maze geometry, collisions, animation logic, camera rigs, UI layout, effects and all gameplay remain implementation work.
