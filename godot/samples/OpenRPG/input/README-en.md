# OpenRPG forest reconstruction

Public input revision: `dashboard-contract-20261022-r2`.

Start with [INITIAL_AGENT_PROMPT-en.md](INITIAL_AGENT_PROMPT-en.md). Open `sp/project.godot` with Godot 4.7.1; its required entry is `res://src/main.tscn`.

## Public documents

- [GDD-en.md](GDD-en.md): numbered player requirements and public vocabulary.
- [TOOLCHAIN-en.md](TOOLCHAIN-en.md) and [BENCHMARK_MANIFEST.json](BENCHMARK_MANIFEST.json): project entry, controls, editing boundaries, saves and reporting.
- [GODOT_BENCHMARK_TOOL_GUIDE.md](GODOT_BENCHMARK_TOOL_GUIDE.md), [DASHBOARD_SPEC.md](DASHBOARD_SPEC.md), [COMMON_BASELINE.md](COMMON_BASELINE.md): shared public guidance and contracts.
- [Naming table](sp/benchmark/naming-tables.json) and [snapshot schema](sp/benchmark/dashboard-snapshot.schema.json): canonical machine-readable reporting vocabulary and shape.
- [MaterialMapping-en.md](MaterialMapping-en.md), [material index](Assets/material-index.json), [source-art contact sheet](Assets/asset-contact-sheet.png): material roles, source facts and hashes.
- [License notices](legal/LICENSES.md) and [credits](legal/CREDITS.md): redistribution requirements.

## Starter scope

The supplied project contains the five-line opening, Gobot movement, the starting forest/town tiles and static building facades, collision, camera, and truthful read-only starter reporting. Preserve the supplied forest paths, clearings and tree arrangement. Passive art and animation scenes are reusable materials.

House interiors and entrances, NPC objectives, inventory and saves, the wand puzzle, deeper grove, ghost progression, battle encounters/actions, and the ending are implementation work. Their names, coordinates, dialogue and object layout are published in GDD section 6.3. GDD section 6 is the sole game-specific requirement list; this scope summary adds no requirements.

Public smoke and dashboard self-check validate entry/resource/reporting health. A passing smoke does not establish adventure completion. The tools are optional; run them in a working copy to keep generated caches and runtime output out of the public package.

`Assets/` contains discovery metadata and source-art previews; reusable runtime assets are already in `sp/`. Project-level LICENSE and CREDITS remain with the runnable project so its attribution survives redistribution.
