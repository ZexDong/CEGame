You have a single implementation turn with a one-hour limit (3600 seconds).

Read the entire supplied public package and implement the adventure described by `GDD-en.md`. Use `README-en.md` to locate the documents and understand the unfinished starter. Inspect `MaterialMapping-en.md`, `Assets/material-index.json`, and `Assets/asset-contact-sheet.png` before choosing artwork; retain the supplied licenses and credits.

Work from `sp/project.godot` with Godot 4.7.1. Preserve the five supplied opening lines and the starting forest/town tile arrangement, paths, clearings, and Gobot artwork. Complete the numbered player outcomes, including exploration and objectives, inventory and wand progression, turn-based encounters, the ending, and the specified save, Retry, Restart and Reopen behavior. The GDD defines the requirements; this handoff adds no gameplay requirements.

Use `BENCHMARK_MANIFEST.json` and `TOOLCHAIN-en.md` for the required `res://src/main.tscn` entry, controls, viewport, editable boundaries, save location and dashboard transport. Read `COMMON_BASELINE.md`, `DASHBOARD_SPEC.md`, `GODOT_BENCHMARK_TOOL_GUIDE.md`, and the canonical `sp/benchmark/naming-tables.json`. Integrate truthful read-only reporting of actual game state. Do not add a dashboard action or state-mutation interface.

Implement within the manifest's writable project paths and preserve protected contracts, vocabulary, source art and notices. Use the supplied package and local engine; network downloads, external packages and engine migration are outside this task. Keep generated caches, logs, screenshots and runtime state out of the delivered package.

All supplied tools, including public smoke and dashboard self-check, are optional feedback. They check package/reporting health and do not establish that the adventure is complete. In your final handoff, describe the implementation, checks actually performed, and any known limitations.
