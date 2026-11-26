# Night Sky Duel Unreal Starter Project

This is an Unreal Engine Blank project with the required Manny skeletal mesh, Skeleton, and animation sequences preimported under `Content/Provided/Manny/`. It deliberately contains no Night Sky Duel gameplay.

The default entry draws a stable English starter screen and publishes two physically separate read-only snapshots when their paths are supplied:

- EvalStatePath receives the engine-level health snapshot used by the public Unreal executor.
- EvalGameStatePath receives a task-level bridge snapshot. The unmodified starter reports bridge_ready=true, provider_ready=false, and game_state=null.

The built-in Paper2D plugin is enabled for future implementation. Engine primitives and implementation-created materials are also allowed. No Marketplace plugin is required.

The preimported art packages are available at `/Game/Provided/Manny/SKM_Manny` and `/Game/Provided/Manny/Animations/`. They contain no gameplay state, input mapping, combat data, or result logic.

## Deliberately absent

- player fighter, rival, arena, movement, or jump;
- gameplay input mappings;
- strikes, bolts, blocking, health, rival cadence, KO, or gameplay restart;
- gameplay Blueprint, Widget, save data, or cheat entry;
- gameplay maps or assembled gameplay assets.

The health publisher reads process arguments and writes UTF-8 snapshots through sibling temporary files followed by atomic replacement. It exposes no gameplay command, mutation, teleport, spawn, result, or restart API. It never invents missing gameplay truth.
