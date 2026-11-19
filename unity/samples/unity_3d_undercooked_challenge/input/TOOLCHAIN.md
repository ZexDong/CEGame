# Unity delivery and development tools

Technical requirement: `DELIVERY-TECH` in `GDD.md`. Exact tool, project, asset and test paths are defined by `BENCHMARK_MANIFEST.json`.

## Delivered project

- Use the supplied locked Unity, URP, Input System, uGUI and Test Framework packages. Do not add external packages or content.
- Save the declared final Scene and enable it first in Build Settings. The supplied starter is empty source material, not the final game.
- Runtime gameplay uses the New Input System and the normal bindings published in GDD Section 5. `UnityEngine.Input` legacy polling is disabled. The supplied `.inputactions` asset is optional to use; direct `Keyboard.current` polling is also accepted.
- Deliver player-facing UI with uGUI `Graphic` and `Text`/`TMP_Text`. The number of Canvases and their layout are implementation choices. OnGUI, GUI, GUILayout, UI Toolkit and editor-only interfaces are not accepted as the player UI in this task.
- Runtime assemblies must not depend on `UnityEditor`; authoring-only scripts may be placed in an Editor subfolder of the writable area.
- Use supplied/imported fonts, valid TMP fonts or Unity 6 `LegacyRuntime.ttf`, not the removed built-in `Arial.ttf` name.
- File permissions and allowed content changes are exactly the manifest writable/protected paths. The common session types, kitchen validator, public model and checks are protected; implement the service in your own game code, not by altering those contracts.
- Use project-local logs and outputs, passing explicit project-local `-logFile` paths to Unity invocations. Do not depend on host-global Editor logs or user-profile files. Process exit alone is not proof of a complete game.

## Service code index

The manifest enables `GameCreate.Session.IGameSession`. Common behavior is specified only in `GAME_SESSION_SPEC.md`; kitchen state semantics are specified only in `SESSION_MODEL.json`.

`GameCreate.Kitchen.KitchenSessionRules.Validate(save, description)` is an optional pure validation aid. It returns null for the public numeric/identity/ownership/phase rules it accepts, or an error string. Passing data validation cannot establish real-object correspondence, input behavior, rendering, atomic restoration or correct gameplay. Non-editable fields are additionally checked against the current game when restoring; a standalone save validator cannot determine whether a caller changed them.

No Dashboard or legacy task-specific Probe is enabled, avoiding multiple state reports for the same game. The conditional Dashboard item `CB-18` is therefore not applicable here.

## Optional public development checks

Public suites are registered in the manifest with their modes, filters and exact test counts. They can be run with the common CLI test command described in `UNITY_BENCHMARK_TOOL_GUIDE.md`.

- Entry smoke checks saved-scene loading, primary model availability, excluded content absence, and advancing real PlayMode frames with a Camera. It does not exercise game actions.
- The four unchanged common session checks cover entry completion and suspension, detached capture and round-trip restore, basic invalid-request rejection, and declared real-object correspondence.
- The kitchen development checks additionally exercise legal editable state round-trips, ownership rejection and progression timing while service-suspended.

These are post-implementation development aids except entry smoke, which also supports the empty starter. They do not supply gameplay implementation, action sequences or complete-game certification. You may choose other reasonable verification methods as well.
