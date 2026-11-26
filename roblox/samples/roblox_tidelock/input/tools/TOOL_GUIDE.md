# Roblox Studio / Rojo tool guide

This input requires Windows, single-player Roblox Studio Play (configured version) and Rojo. Roblox Studio updates automatically; record the installed version when evaluating a candidate.

Install Rojo 7.7.0 from the official `rojo-rbx/rojo` GitHub release `v7.7.0`; put the executable on PATH or pass it to `starter-project/project/build.ps1 -Rojo <executable>`. Optional evaluator syntax checking uses Luau 0.734's `luau-compile` from the official `luau-lang/luau` release `0.734`. No executables, private endpoints or credentials are embedded. Roblox Studio may require the user's own login/network even though this game requires no external content downloads. Install Studio through Roblox's official distribution; it is proprietary and not included.

## Editor interfaces

- Explorer creates, renames, moves and inspects Instances and ClassName.
- Properties edits properties and attributes. Tag Editor/CollectionService manage semantic tags.
- Script Editor edits Luau Script/LocalScript/ModuleScript source. Script Analyzer and Output expose diagnostics; an editor hint is not proof a runtime API works.
- F5 starts Play. Stop returns to Edit. Use the Studio Stop action or the host's configured stop shortcut. Record whether there was a real Play client, character and runtime log.
- Command Bar may run small API probes during development. It must not be used to fabricate successful gameplay checks.

## Runtime APIs

Workspace holds world parts and public attributes. Players gives characters, Humanoid and HumanoidRootPart. CollectionService:AddTag/HasTag/GetTagged maps identities to instances; Instance:SetAttribute/GetAttribute exposes state mirrors. ProximityPrompt with KeyboardKeyCode E handles nearby interaction. BasePart.Touched receives physical contacts. Humanoid.Health/Died handles life and death. RemoteEvent FireClient publishes server telemetry; adhere to the one-way contract. ScreenGui/Frame/TextLabel/TextButton render HUD and buttons. TweenService animates properties; RunService Heartbeat/RenderStepped provides frame timing. PathfindingService computes paths.

Default controls provide W/A/S/D, mouse and Space. UserInputService.InputBegan can handle R; account for gameProcessedEvent and text focus. TextButton.Activated receives real button activation. ContextActionService must not replace the required player inputs.

## Build and inspect

```powershell
rojo --version
rojo build starter-project/project/default.project.json -o TideLockCandidate.rbxlx
rojo serve starter-project/project/default.project.json
rojo sourcemap starter-project/project/default.project.json -o source-map.json
python self-check/check_input.py
```

Rojo maps `$path` relative to its project JSON: ModuleScripts normally go in ReplicatedStorage, server scripts in ServerScriptService and local scripts in StarterPlayerScripts. The blank source project references the public constants in contracts/src; retain that dependency or copy the constants and update the candidate mapping before submission. A successful build proves assembly only. Open the produced place in Studio and run Play to validate APIs and behavior.

Luau compilation verifies syntax only. Example for release configured version: `luau-compile --null path/to/file.luau`. Confirm unfamiliar Roblox APIs with Creator documentation, Studio metadata or a minimal Play probe. A minimal probe may create a ProximityPrompt, assign Enum.KeyCode.E, tag a Part and read the tag; it does not prove this game works.

shell and Python may create files, run builds, inspect processes and compute SHA-256 hashes. `rg` searches files/text. Windows SendInput sends real input to a focused Studio window; during automated evaluation avoid interacting with the desktop. It cannot replace physics with direct state mutation.
