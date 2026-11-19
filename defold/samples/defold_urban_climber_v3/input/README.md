# Urban Climber v3 — Two-Roof Relay

Status: frozen v3 public input for the two-building scope.

Implement the game in [GDD.md](GDD.md) inside `starter_project/`.

This package is self-contained. The starter is a blank, buildable Defold project with normal input
bindings and the shared read-only Dashboard transport. It deliberately reports `not_ready` with
zero slots and no entities or targets. The empty window is expected: no menu, level, player,
HUD, or gameplay has been implemented.

| File or directory | Purpose |
|---|---|
| [GDD.md](GDD.md) | Numbered game-specific requirements and task observation vocabulary |
| [COMMON_BASELINE.md](COMMON_BASELINE.md) | Shared playable-game requirements |
| [TOOLCHAIN.md](TOOLCHAIN.md) | Project entry, physical keys/action IDs, build and observation notes |
| [DEFOLD_ENGINE_INTERFACE_GUIDE.md](DEFOLD_ENGINE_INTERFACE_GUIDE.md) | Canonical verified Defold tools and API facts |
| [DASHBOARD_SPEC.md](DASHBOARD_SPEC.md) | Shared read-only snapshot contract |
| [naming-tables.json](naming-tables.json) | Exact names, states, controls, and coordinate bounds |
| [naming-tables.schema.json](naming-tables.schema.json), [dashboard-snapshot.schema.json](dashboard-snapshot.schema.json) | Public format schemas |
| [tools/dashboard_self_check.py](tools/dashboard_self_check.py) | Local format checker; does not judge game correctness |
| [starter_project/game.project](starter_project/game.project) | Open/build entry; implement the game within this project |
| [assets/ASSET_MANIFEST.md](assets/ASSET_MANIFEST.md) | Supplied pixel assets, dimensions, usage, and source |
| [reference_images/](reference_images/) | Visual references, not a playable implementation |
| [legal/UPSTREAM_MIT_LICENSE.txt](legal/UPSTREAM_MIT_LICENSE.txt) | License for the supplied upstream material |

The frozen gameplay acceptance boundary is the numbered GDD requirements plus the common baseline.
The remaining documents specify the public tool and observation interface. Task version v3 still
uses the shared Dashboard schema version 2.

Only modify `starter_project/` for a submission; its naming-table copy is supplied for convenience
and has the same contract as the input-root copy. Do not change the public requirements or schemas.
Copy any used assets into the project so it builds independently of its parent directory.
No reference implementation, private test, solution route, or historical result is needed or
included.
