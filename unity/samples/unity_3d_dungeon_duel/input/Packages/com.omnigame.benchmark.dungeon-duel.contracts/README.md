# Dungeon Duel public read-only contract v2

Namespace: `OmniGame.Benchmark.DungeonDuel.V2`

Exactly one active gameplay `MonoBehaviour` implements
`IDungeonDuelBenchmarkProbe` and reports:

- contract version `2.0`;
- the truthful current Player, Imp, Boss, gate, Dash, audio, and phase snapshot;
- the real visible Player, both Imp, Boss, and gate target GameObjects;
- three finite reachable world positions used to aim normal input.

The interface is read-only and contains no fixture loader, player-action method, reset, or
result shortcut. Its state and target references must match the visible actor Transforms,
gate Collider, runtime UI, and native AudioSources used by the game. Normal Input System
mouse and keyboard events remain the only player-action route. The public UI and target
eligibility rules are in project-root `TOOLCHAIN.md`; player behavior is defined only by
`GDD.md` Section 6.
