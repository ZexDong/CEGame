# Public engine/tool interfaces — Moonlit Greenhouse

Use Roblox Studio, Rojo and Luau in the declared environment. Keep the original input tools/API documentation in starter-project/native/ as the detailed interface catalog. Only configuration and public schema exist in the starting project; implement the game from GDD.md.

Build command: `rojo build starter-project/native/project/default.project.json -o <candidate-place.rbxlx>`.
Use F5/Stop in Studio to inspect actual runtime behavior. Default player movement, ordinary prompt inputs, GUI events, CollectionService and public attributes follow the original game contract; no new gameplay API is introduced. A successful Rojo/Luau build proves assembly/syntax, not Play.

Tool binaries are not bundled. Install official rojo-rbx/rojo v7.7.0 and luau-lang/luau configured version tools, put them on PATH or pass absolute executable paths. For legacy public helper scripts that expect tools/ executables, copy the installed binaries into the working copy's expected folder before choosing to run those helpers. The original source text and helper paths are preserved.
