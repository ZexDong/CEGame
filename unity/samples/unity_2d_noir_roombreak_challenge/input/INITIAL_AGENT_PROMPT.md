# Task

Complete the Unity project in this directory according to `GDD.md`.

Before editing, read `README.md`, `TOOLCHAIN.md`,
`UNITY_BENCHMARK_TOOL_GUIDE.md`, `BENCHMARK_MANIFEST.json`,
`ASSET_MANIFEST.json`, `ASSET_CATALOG.md`, `ASSET_CATALOG.json`, and the
public read-only Probe contract. `ASSET_CONTACT_SHEET.png` is attached to this
initial request as the supplied visual inventory. Use the catalogs for exact
Player, Anda, Obser, room-geometry, VFX/lighting, and audio paths and for the
published transparent-padding and importer facts.

Create and save `Assets/NoirChallenge/Scenes/NoirRoombreak.unity`, make it the
first enabled Build Settings Scene, and implement the complete menu-to-success
journey. Use Unity `6000.0.80f1`, New Input System `1.19.0`, uGUI, and normal
player-facing keyboard and pointer input. Put all implementation and derived
media under `Assets/NoirChallenge/**`; do not modify protected source assets or
their importers.

Pass a new project-local `-logFile` to every Unity command. Compile the project,
inspect the new project-local log, and run both public smoke filters. The Probe is
read-only observation and must never drive gameplay or results.

Work only in this copied project. Do not inspect sibling projects, host-global
Editor logs, user-profile data, or network services. Do not install another
Unity Editor or use legacy `UnityEngine.Input`.

