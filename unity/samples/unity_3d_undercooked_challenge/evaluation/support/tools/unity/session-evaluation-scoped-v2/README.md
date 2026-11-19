# Scoped public-session evaluator client v2

Versioned client for public-session evaluation. Install this client or
`session-evaluation` in a project, one at a time: the Unity package ID,
assembly and namespace are compatible.

`SessionDriver` adds two optional final constructor arguments:
`Func<ActorSave,bool> actorObservationFilter` and
`Func<string,bool> landmarkObservationFilter`. Freeze these dependencies before
seeing a candidate; do not derive exemptions from a candidate failure. Null
preserves the original all-actor/all-landmark validation. An explicit empty
landmark selection does not call `DescribeCurrentEntry`; a nonempty selection
checks exactly those declared landmarks, not unrelated layout data. Actor
queries and real-pose checks are likewise limited to selected present actors.

Complete captured-save shape, public relation validation, full public-state
restore/commit equivalence and the preparation/action write barrier remain
mandatory. A malformed unrelated serialized field is not excused by a query
filter. Filters are author code: exceptions in them remain evaluator failures.
The complete object/layout delivery obligation must still be tested separately.

`PlayerInputDriver` additionally exposes `Move(Vector2)`,
`Click(Vector2, MouseButton = MouseButton.Left)` and
`Scroll(Vector2 position, Vector2 delta)`. These enqueue normal virtual mouse
states across real frames and release/reset the input; no gameplay/UI callbacks
are called.

`Tests/SessionDriverTests.cs` contains the shared driver tests. Run them in a
project with this package and the matching Unity version. Driver tests do
not replace candidate-specific gameplay checks.
