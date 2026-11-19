# Arrow Escape public read-only contract 3.0

Namespace: `OmniGame.Benchmark.ArrowEscape.V2`.

The saved main scene must expose exactly one active `MonoBehaviour` implementing
`IArrowEscapeReadOnlyProbe`. `CaptureBenchmarkSnapshot()` is read-only: it reports only the
level, budget, arrow/badge, Hint, terminal, and target information already represented by
the running game. It must not load levels, change state, simulate input, restart, force an
outcome, or expose an action shortcut.

Runtime arrows expose real visible `LineRenderer` or `SpriteRenderer` geometry with
Collider2D. Hint, Restart, and Next Level expose visible runtime uGUI controls.
`IArrowEscapeInputTarget` and `IArrowEscapeUiInputTarget` may identify the real GameObjects;
they contain no player-action method.

`ArrowEscapeGameSnapshot.VisibleTargets` is a complete current registry:

- exactly one visible `Kind = Arrow` entry for every arrow not in `Exited` state;
- exactly one visible entry each for Hint, Restart, and Next Level;
- unique `Kind + Id` pairs and non-empty `VisualState` values;
- finite bottom-left-origin Unity screen rectangles at least `2 x 2` pixels that intersect
  the current `1280 x 720` Game view;
- `Interactable = true` implies `Visible = true`.

During `Playing`, active non-moving arrows are interactable, including blocked and locked
arrows whose click produces a failed attempt. Moving arrows are not interactable; exited
arrows have no arrow entry; arrow targets after win/loss are not interactable.
`ArrowEscapeVisibleTargetUtility.Capture(...)` provides normal conversion for GameObject-
backed world and uGUI targets. Registry data must match the real visible runtime surfaces.

Player input uses an ordinary Unity Input System Mouse route over real visible targets.
One left-click commits at most one matching action; press-only, cross-target, and blank
interactions commit nothing. Valid implementations may consume Mouse state through
`Mouse.current`, enabled `InputAction` or `PlayerInput`, or an Input-System-compatible
EventSystem route. Pure IMGUI, UI Toolkit, or a reported rectangle without a matching
visible runtime target cannot be the only required player route.

Fixed paths and versions:

```text
Contract version: 3.0
Benchmark: unity.arrow_escape_reconstruction.v2
Main scene: Assets/ArrowEscapeBenchmark/Scenes/ArrowEscape.unity
Runtime root: Assets/ArrowEscapeBenchmark/Runtime/
Levels: Assets/ArrowEscapeBenchmark/Levels/
```
