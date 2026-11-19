# Brick Challenge Tool Contract

- Unity Editor: `6000.0.80f1`
- Unity CLI: `1.0.0-beta.3`
- Input: New Input System package `1.19.0`
- Entry Scene: `Assets/Scenes/BrickChallenge.unity`
- Target resolution: `1280×720`

The submitted project must contain at least one active `MonoBehaviour` implementing `OmniGame.Benchmark.BrickChallenge.Contracts.IBrickChallengeProbe`. The interface is read-only and reports current player-visible state, presentation visibility, active-ball screen positions, and screen-space interaction locations. `TerminalButtonScreenRect` identifies the shared end-of-run control that returns to the menu. `HudScreenRect` must identify a visible HUD region whose pointer interaction is not a gameplay launch. All reported rectangles and positions use bottom-left screen coordinates and must reflect the visible player view. The Probe must not execute gameplay, mutate state, force results, or report its own pass/fail verdict.

`LastAudioCue`, `AudioCueSequence`, and `GetAudioCueCount` are read-only observation fields for supplied runtime audio. Increment the sequence and the matching cumulative cue count exactly once when a normal player event actually requests playback of one of the six supplied clips, and report the matching latest cue. Do not increment them for loading, assigning, previewing, or merely retaining a clip. Counts begin at zero in a fresh process. These fields supplement rather than replace real audible output.

All clicks and key presses must travel through the New Input System. Do not use `UnityEngine.Input` legacy polling. Screen rectangles use bottom-left screen coordinates, matching `UnityEngine.InputSystem.Mouse.position` and `Camera.WorldToScreenPoint`.

The game must work without accounts, network services, cloud APIs, or additional processes.

