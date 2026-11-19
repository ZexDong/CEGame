You are implementing the Sign Circuit extension inside the current Unity project.
Work only in this project and use only the pinned local Unity tools and supplied
assets. Network access and package installation are unavailable.

Read these English files before editing:

1. `GDD.md` - the sole player-facing acceptance specification;
2. `BENCHMARK_MANIFEST.json` - engine version, public test filters, writable paths,
   and protected paths;
3. `TOOLCHAIN.md` - the Sign Circuit Unity, normal-input, visible-UI, and read-only
   observation contract;
4. `UNITY_BENCHMARK_TOOL_GUIDE.md` - reusable Unity 6 tool facts;
5. `ASSET_MANIFEST.json` - supplied asset inventory and use boundary;
6. `UNITY_OFFLINE_AGENT_MANUAL.md` - concise command reference.

Implement the complete player journey described by `GDD.md` in Unity
`6000.0.80f1`. Add the visible `SIGN CIRCUIT` menu entry, preserve the existing
menu functions and `Level1+2`, assemble the supplied hand-drawn street, school,
character, sign, and interface art into the finished challenge, and save real
Unity scenes and assets. Write only to paths allowed by
`BENCHMARK_MANIFEST.json`; keep every protected path unchanged.

The required runtime input boundary is Input System 1.19. Use
`Keyboard.current`/`Mouse.current`, enabled Input Actions, or `PlayerInput`.
Required controls must not depend on legacy `UnityEngine.Input`, `Event.current`,
`GUI.Button`, or IMGUI-only events. Connect the documented keyboard and pointer controls to
the real visible runtime surfaces through this player-facing Input System route.

Required runtime controls and required state text must be real visible uGUI/TMP
surfaces. Use an active `Canvas`, `GraphicRaycaster`, `EventSystem`, and an
Input-System-compatible UI module. Required pointer controls use uGUI `Button`
semantics. Use an imported font, `LegacyRuntime.ttf`, or a serialized TMP font
asset; do not request `Arial.ttf` at runtime.

Runtime scripts must not reference `UnityEditor`. Optional one-shot authoring
helpers may use `UnityEditor` only under `Assets/Benchmark/Editor/**`, and the
saved game must work without those helpers in Play Mode. Keep an enabled camera,
valid saved references, compatible 2D physics, valid material properties, and
usable audio sources. Save the challenge scene, the permitted Menu change, and
Build Settings while leaving `Assets/Scenes/Levels/Level1+2.unity` unchanged.

The pinned Unity CLI commands in `TOOLCHAIN.md` expose public EditMode (`2/2 Passed`) and
PlayMode (`1/1 Passed`) startup feedback through fresh NUnit XML and project-local logs.
The PlayMode smoke loads the saved scene, advances real frames, checks for a camera, and
rejects blocking runtime errors; it does not complete the game.

Keep `Assets/BenchmarkContract/**` unchanged. During Menu, Sign Circuit, and
preserved legacy play, publish a fresh `SignCircuitSnapshot` plus the required
action and observation targets through
`SignCircuitProbePublisher.Publish(...)`. The contract is read-only: publication
must mirror the real visible and gameplay state and must never perform a player
action or replace gameplay logic. Use the exact fields, semantic IDs, rectangle
coordinates, visibility rules, and real uGUI/TMP overlap rules in `TOOLCHAIN.md`.

Continue until the numbered GDD requirements are satisfied as far as possible.
State only saved work and checks that were actually performed.

