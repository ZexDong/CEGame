# Chomp public implementation input

Build the complete neon 3D maze chase described in `GDD.md` from `starter-project/ChompStarter.uproject`. This input targets Unreal Engine **Unreal, CL configured-build**, desktop, independent editor-game mode.

Read in this order: `INITIAL_AGENT_PROMPT.md`, this file, `GDD.md`, `assets/ASSET_CATALOG.md`, `contracts/GAME_SESSION_SPEC.md`, `tools/TOOLCHAIN.md`, then the interface guide as needed. GDD Section 6 is the sole gameplay acceptance authority, including the six quality requirements. The observation contract translates those requirements into read-only data; it adds no hidden gameplay rules.

The starter is deliberately an inert Blank project. Its welcome view and honest unavailable-state transport establish project health. The full 30x28 maze, movement, four ghost personalities, timed power/fruit systems, mouth animation, camera/effects, menus, settings and persistence remain to be implemented. The supplied static art is mandatory under ASSET-01..05 and remains unassembled; it contains no gameplay solution.

| File or directory | Purpose |
|---|---|
| GDD.md | Player outcomes, exact rules, full board and boundaries |
| BENCHMARK_MANIFEST.json | Portable paths and file integrity hashes |
| starter-project/ | Sole writable implementation root |
| starter-project/Content/Art/ | Mandatory UE meshes, materials, textures and HUD icon |
| starter-project/SourceArt/ | Editable project-local OBJ/PNG/SVG source copies |
| assets/files/ | Protected reference copies of those sources |
| ASSET_MANIFEST.json / ASSET_CATALOG.* / ASSET_COVERAGE.json | Per-resource paths, use terms, dependencies, hashes and roles |
| contracts/ | Read-only observation schema and machine-readable board mirror |
| tools/TOOLCHAIN.md | Build/run entry, viewport and workspace policy |
| tools/TOOL_GUIDE.md | Single-interface tool reference |
| UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.* | Complete available engine/plugin symbol catalog; validation status is explicit |
| tools/ | Engine discovery, catalog lookup, structural checks and observation self-check |
| self-check/PublicSmoke/ | Untouched-starter health check, not a gameplay test |
| assets/legal/ | Resource-use terms |

Start with engine discovery using `tools/Resolve-Unreal57.ps1`. The concrete build and launch commands are in `tools/TOOLCHAIN.md`. A machine with the stated engine and compiler is required; this package does not install them.

Section 6.4 defines timing/contact boundaries, permitted route choices, death-overlay Restart and presentation variation; read it together with the numbered rows.
