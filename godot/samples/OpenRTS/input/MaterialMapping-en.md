# Open RTS material mapping

Source models are self-contained GLB PackedScenes. Assets/material-index.json lists exact paths, byte hashes, mesh accessor bounds, source, licenses and import facts. These are source parts, not completed gameplay scenes.

| Role | Project model files |
|---|---|
| Worker | `assets/models/rover.glb` |
| Tank | `assets/models/craft_cargoB.glb`, `assets/models/craft_miner.glb` |
| Helicopter | `assets/models/craft_racer.glb` |
| Drone | `assets/models/craft_speederA.glb` |
| CommandCenter | `assets/models/corridor_cross.glb`, `assets/models/corridor.glb`, `assets/models/machine_generator.glb`, `assets/models/machine_wireless.glb` |
| VehicleFactory | `assets/models/hangar_smallA.glb` |
| AircraftFactory | `assets/models/hangar_smallA.glb`, `assets/models/supports_low.glb`, `assets/models/platform_small.glb` |
| AntiGroundTurret | `assets/models/turret_single.glb` |
| AntiAirTurret | `assets/models/turret_double.glb` |
| ResourceA | `assets/models/rock_crystalsLargeA.glb` |
| ResourceB | `assets/models/rock_crystalsLargeB.glb` |

Terrain, fog, selection, UI and projectiles are procedural. Preserve model proportions; unit/world scale, composition and team tint are free. Models have embedded materials and no external files. Source PNG icons under Assets/source-icons are documentation previews licensed under the upstream MIT notice. Catalog bounds are source accessor bounds, not game collision dimensions.
