# Provided Manny Art Catalog

`assets/ASSET_CATALOG.json` is the authority for asset identity, dependencies, license facts, and package paths. `GDD.md` Section 6 defines mandatory use (`ASSET-01`, `ASSET-02`); `ASSET_MANIFEST.json` summarizes delivery and replacement policy.

The Manny model and all eight animation clips are mandatory. Both visible fighters use the model, and each animation is used for its listed presentation role. The protected FBX reference filenames and the preimported Unreal object paths are listed below.

| Asset ID | Meaning / Visible Role | FBX Reference | Preimported Object |
|---|---|---|---|
| `SKM_Manny` | Both visible fighter bodies | `assets/files/Manny/SKM_Manny.fbx` | `/Game/Provided/Manny/SKM_Manny.SKM_Manny` |
| `AS_manny_stand` | Idle presentation | `assets/files/Manny/AS_manny_stand.fbx` | `/Game/Provided/Manny/Animations/AS_manny_stand.AS_manny_stand` |
| `AS_manny_fwalk` | Player movement toward the rival | `assets/files/Manny/AS_manny_fwalk.fbx` | `/Game/Provided/Manny/Animations/AS_manny_fwalk.AS_manny_fwalk` |
| `AS_manny_bwalk` | Player movement away from the rival | `assets/files/Manny/AS_manny_bwalk.fbx` | `/Game/Provided/Manny/Animations/AS_manny_bwalk.AS_manny_bwalk` |
| `AS_manny_jump` | Player jump presentation | `assets/files/Manny/AS_manny_jump.fbx` | `/Game/Provided/Manny/Animations/AS_manny_jump.AS_manny_jump` |
| `AS_manny_5a` | Player close-strike presentation | `assets/files/Manny/AS_manny_5a.fbx` | `/Game/Provided/Manny/Animations/AS_manny_5a.AS_manny_5a` |
| `AS_manny_fireball` | Player energy-bolt casting presentation | `assets/files/Manny/AS_manny_fireball.fbx` | `/Game/Provided/Manny/Animations/AS_manny_fireball.AS_manny_fireball` |
| `AS_manny_standblock` | Player standing-block presentation | `assets/files/Manny/AS_manny_standblock.fbx` | `/Game/Provided/Manny/Animations/AS_manny_standblock.AS_manny_standblock` |
| `AS_manny_hitstun` | Either fighter receiving a hit | `assets/files/Manny/AS_manny_hitstun.fbx` | `/Game/Provided/Manny/Animations/AS_manny_hitstun.AS_manny_hitstun` |

## Package facts

- The mesh package, Skeleton package, and eight animation packages are already saved in `starter-project/Content/Provided/Manny/`.
- `SKM_Manny` contains the skinned 3D mesh, bind Skeleton, skin weights, and material slots. No separate Skeleton download is needed.
- Every animation sequence references the Skeleton created for `SKM_Manny` and retains its listed asset ID.
- The FBX references are provided for identity, inspection, and reproducible asset checks. They do not need to be imported during implementation.
- Materials and textures are not required for the packages. The mesh has material slots; candidate-authored colors are allowed.
- Clip durations describe the supplied animation data. They do not define gameplay timing, damage, collision, or cooldown.

## Asset scope

The packages contain mesh, Skeleton, and bone-transform animation data only. They do not contain input handling, combat state, result logic, maps, or gameplay orchestration. Use the packages for the numbered GDD requirements; create arena geometry, HUD, bolt graphics, and supplemental feedback independently within those requirements.

## Package index

`ASSET_PACKAGE_INDEX.json` lists package paths, FBX hashes, Skeleton dependencies and clip properties. FBX references omit smoothing groups; imported or computed normals may be used.

## Licenses

See `assets/legal/LICENSE_SCOPE.md` and the included license notices. License identifiers and per-asset notices are recorded in `assets/ASSET_CATALOG.json`.
