You have a hard limit of 3600 seconds for this implementation turn.

# MataroDrive implementation task

Use only the current `input/` package. Do not inspect or copy sibling `gold/`, `original/`, or `evaluation/` directories.

1. Read `GDD-en.md`, `README-en.md`, `TOOLCHAIN-en.md`, `BENCHMARK_MANIFEST.json`, `COMMON_BASELINE.md`, `DASHBOARD_SPEC.md`, `GODOT_BENCHMARK_TOOL_GUIDE.md`, `MaterialMapping-en.md`, and `legal/`. Use GDD section 6 for gameplay and section 12 for observation vocabulary.
2. Implement the complete car-platforming shell in the project root declared by `BENCHMARK_MANIFEST.json`: fifteen story levels, Level Select, Endless, Hill Climb, Garage, Settings, Trophies, and persistent profile state.
3. Use only the procedural coverage and independently cleared local content described by the material catalog. Do not fetch or reconstruct the unavailable upstream logo, audio, scenes, or scripts.
4. Use normal visible keyboard/mouse input. Keep driving, jumping, collisions, respawn, rewards, power-ups, prices, results, and persistent state consistent with the rendered game.
5. Wire the actual game state into the read-only dashboard and naming table. Never add a dashboard action, cheat entry, direct completion/purchase path, or private state mutation interface.
6. Use Godot `4.7.1`. The supplied tools, public smoke, and dashboard self-check are optional aids. Do not claim checks you did not run.
7. Remove generated caches, logs, screenshots, temporary scripts, and runtime state before delivery. In the final handoff, describe the implementation, checks actually performed, and any known limitations.
