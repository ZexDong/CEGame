# Unity project and public service tools

Exact project paths, tool paths, writable areas, and test filters are declared in `BENCHMARK_MANIFEST.json`. This document describes their use; it does not add game rules.

## Project delivery

- Use the supplied locked Unity, URP, Input System, uGUI and Test Framework packages. No additional packages or downloaded content are required or allowed.
- Save the manifest's final scene and enable it first in Build Settings. The starter scene contains no game implementation.
- Use the New Input System for the normal keyboard and pointer controls in the GDD. Legacy `UnityEngine.Input` polling is disabled. The supplied Input Actions are available but do not prescribe an implementation.
- Player-facing UI must be visible and operable through normal keyboard and pointer input. Its runtime rendering framework, layout and object hierarchy are implementation choices; Editor-only interfaces do not constitute a playable UI. Supplied uGUI and the Input System are available, not a mandated screen architecture.
- Runtime assemblies must not depend on `UnityEditor`. Authoring-only code belongs in an Editor-only assembly or an Editor folder outside a runtime assembly.
- Supplied/imported fonts, valid TMP fonts, and Unity 6 `LegacyRuntime.ttf` are available. The removed built-in `Arial.ttf` name is not a valid fallback.
- Keep development outputs and explicit Unity `-logFile` logs under the project. Optional public checks may be used or replaced with other reasonable development checks.
- The completed project must run as a standalone Windows player without Editor-only dependencies. A process exit code alone does not establish complete gameplay.

## One public state surface

Implement `GameCreate.Session.IGameSession` using the protected types in `Packages/com.gamecreate.game-session`. Common behavior is authoritative in `GAME_SESSION_SPEC.md`; game-specific fields and relationships are authoritative in `SESSION_MODEL.json`.

The service captures the same state that drives the real game. Its entry, restore, capture, description, object lookup, and simulation-suspension semantics must agree with the game. The public numeric model is not a replacement for any additional state needed to resume the complete game.

Public type and validator source is a development aid, not a gameplay implementation. Protected contracts and checks may not be changed to make an implementation appear compliant. Implement the service in the writable game area.

No Dashboard and no old Driftfolk Probe are enabled. Conditional Dashboard baseline item `CB-18` is therefore not applicable. Capture is the only public state-reporting surface.

## Optional public checks

The manifest records the exact filters and modes. The common CLI tool guide shows how to select a filter and save NUnit XML and logs.

- The three EditMode smoke checks cover a loadable starter, the asset inventory, and supplied service/model files.
- The one PlayMode smoke check loads the saved final scene when present, otherwise the starter, and observes real frames with a Camera. It does not require the starter to remain the final Build Settings entry.
- The unchanged common service suite contains four post-implementation checks: entry completion and suspension; detached capture and round-trip restoration; rejection of basic invalid requests without partial changes; and correspondence to real scene objects.
- The four Stormbound checks cover capture detachment and own-save round trips, legal resource/pause edits, atomic rejection of invalid identities/ownership, and real-object queries. They exercise the published model, not a private gameplay route, and do not certify opaque history or every relationship.

Entry smoke supports both the unimplemented starter and the completed scene. Service checks require your implementation. None of these checks certifies the complete game, supplies a private action sequence, or imposes a required development workflow.
