# Deep Relay public toolchain facts

This file identifies task paths and single-command result surfaces. It does not prescribe a pipeline.

| Surface | Public path or command | Result |
|---|---|---|
| GDD | `GDD.md` | Player rules and lifecycle |
| Contract | `EVALUABILITY_CONTRACT.md` | Public Tags, Attributes, IDs, and navigation facts |
| Schema | `project/src/shared/DeepRelaySchema.luau` | Public constants only |
| Rojo project | `project/default.project.json` | Blank DataModel mapping |
| Starter Place | `DeepRelayStart.rbxlx` | Blank Studio starting file |
| Static input check | `ScaffoldTests/Test-InputScaffold.ps1` | Public package validation only |
| Build | `rojo build project/default.project.json -o DeepRelayCandidate.rbxlx` | Candidate Place serialization |
| Luau parse check | `luau-compile.exe <script.luau>` | Luau compile result for one script |
| Studio Play | Open the candidate Place and press Play | Runtime authority for server/client, physics, UI, input, and lifecycle |

No external asset download is required. The public palette file in `TaskAssets/` describes intended semantic colors and materials; all final geometry and composition remain implementation work.
