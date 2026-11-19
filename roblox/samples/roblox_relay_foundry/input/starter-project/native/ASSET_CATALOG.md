# Relay Foundry asset catalog

No external binary art or audio is required. The supplied asset surface is Roblox Studio itself plus the clean Rojo starter.

| Path or interface | Intended use |
|---|---|
| `project/default.project.json` | Blank DataModel and source mappings; add gameplay under `project/src/**` |
| `project/src/shared/RelayFoundrySchema.luau` | Public `RFP_*` constants shared by client and server; do not replace protocol strings |
| `Assets/README.md` | Declares available built-in asset classes and restrictions |
| `BasePart` subclasses | Floors, machines, docks, physical gate, checkpoint, hazard, evacuation zone and decoration |
| `Enum.Material`, Color and Lighting | Visual differentiation and foundry presentation |
| `ProximityPrompt` | Real nearby `E` and `Q` player interactions |
| `ScreenGui` and standard GUI instances | HUD, recipe, state, timer, feedback and completion result |
| Default character and `Humanoid` | Walking, jumping, real health/death and respawn |
| CollectionService Tags and Attributes | Truthful public semantic discovery and observation |

This catalog gives paths and semantic roles only. It does not define a secret layout, fixed coordinates, implementation algorithm, or evaluator trajectory.

