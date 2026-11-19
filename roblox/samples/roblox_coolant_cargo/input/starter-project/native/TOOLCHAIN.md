# Coolant Cargo task-local tool paths

This file lists individual tools and task files. It does not prescribe an implementation workflow.

| Path | Individual purpose |
|---|---|
| `tools/luau-compile.exe` | Parse/compile one Luau source file and return diagnostics/exit code |
| `tools/rojo.exe` | Build a Rojo project JSON into an RBXLX place |
| `tools/PUBLIC_SMOKE.ps1` | Public compile/build smoke for the supplied starter or a compatible project path |
| `Starter/CoolantCargoStart.rbxlx` | Open the blank starter place in Roblox Studio |
| `Starter/project/default.project.json` | Rojo DataModel mapping |
| `Starter/project/src/shared/CoolantCargoSchema.luau` | Public constants shared by server/client code |
| `PUBLIC_SCHEMA.json` | Machine-readable Tags, Attributes, enums, timing and geometry contract |
| `TaskAssets/VISUAL_PALETTE.json` | Procedural material/color/style input |

Roblox Studio is discovered from the installed `%LOCALAPPDATA%/Roblox/Versions/*/RobloxStudioBeta.exe`; do not hardcode a version directory into the submission.
