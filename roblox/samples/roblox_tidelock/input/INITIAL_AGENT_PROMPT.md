# Tide Lock development assignment

Implement the single-player Roblox game specified in `GDD.md`. You have a maximum of **3600 seconds** for implementation. Stop when that limit is reached and retain the current project; no extension or second development window is part of this assignment.

Read `GDD.md`, `CONTENT.json`, `contracts/GAME_SESSION_SPEC.md`, `contracts/SESSION_MODEL.json`, `tools/TOOL_GUIDE.md`, and `assets/ASSET_CATALOG.json`. Use the blank place and Rojo configuration in `starter-project/`. The public Luau constants are in `contracts/src/`. Also read `self-check/PLAY_CHECKLIST.md` and `tools/DEVELOPMENT_REPORT_REQUIREMENTS.md`. Use only a working copy of this input directory during generation. Do not access sibling evaluation materials, reference implementations, historical submissions or results.

The GDD is the authority for gameplay. The contract defines observable identity and state, not an alternate implementation or completion shortcut. Keep normal input, physical world, HUD, tags, attributes and telemetry consistent. Public self-checks verify only their stated scope and do not prove gameplay completion.

Return a complete candidate directory (or one ZIP containing it): `project/default.project.json`, all mapped source/assets, `project/build.ps1`, and a cleanly built `TideLockCandidate.rbxlx`. Keep the public schema in the submission dependency closure. Include `RUN_REPORT.txt` recording actual commands, Play sessions, observations, failures and untested items. Include `DEVELOPMENT_TRACE.txt` recording development actions and tool use. These reports are submission artifacts; this input contains no model trajectory. Do not report source inspection, a successful build or Edit-mode opening as successful Play.
