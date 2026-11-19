# Captain2D Unreal Starter Project

This is a source-only Unreal Engine 5.7.4 Blank project. It deliberately contains no Captain2D gameplay and no imported game asset.

The default entry draws a stable English starter screen and publishes two physically separate read-only snapshots when their paths are supplied:

- EvalStatePath receives the engine-level health snapshot used by the public Unreal executor.
- EvalGameStatePath receives a task-level bridge snapshot. The unmodified starter reports bridge_ready=true, provider_ready=false, and game_state=null.

The built-in Paper2D plugin is enabled for future implementation. No Marketplace plugin is required.

## Deliberately absent

- player pawn and movement;
- gameplay input mappings;
- keys, exit, hazards, health, combat, enemy patrol, spring, one-way ledges, success, failure, or restart behavior;
- gameplay Blueprint, Widget, save data, or cheat entry;
- assembled maps, source-game code, and unclean source-game assets; and
- PaperZD and TypewriterPlugin.

The health publisher reads process arguments and writes UTF-8 snapshots through sibling temporary files followed by atomic replacement. It exposes no gameplay command, mutation, teleport, spawn, result, or restart API. It never invents missing gameplay truth.
