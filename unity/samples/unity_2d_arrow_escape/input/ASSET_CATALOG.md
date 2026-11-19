# Arrow Escape supplied asset catalog

This public catalog describes the supplied source media without prescribing the final board layout, level solution, implementation classes, or target composition. Read it with `ASSET_CONTACT_SHEET.png`, `ASSET_CATALOG.json`, and `ASSET_COVERAGE.json`.

## Important handling facts

- The contact sheet is an inventory preview, not a finished background.
- Files under `Assets/BenchmarkStarter/Art/` are protected **Texture Type Default** imports, not ready Sprite importers. Create project-owned derived copies under `Assets/ArrowEscapeBenchmark/**` if Sprite settings or crops are needed.
- `TaskAssets/badges/key_badge.png` and `lock_badge.png` are protected files outside `Assets/`; copy them to the required writable destinations before runtime use.
- The key image means key state; the lock image means locked state.
- The dependency JSON is a data-shape example only and must not be loaded at runtime.

## Image inventory

| Semantic role | Source path | Pixels | Visible alpha bounds | Runtime handling |
|---|---|---:|---|---|
| `arrow_body` | `Assets/BenchmarkStarter/Art/arrow_body.png` | 128x128 | 45x125 at (42,2) | derive under writable root |
| `arrow_head` | `Assets/BenchmarkStarter/Art/arrow_head.png` | 128x128 | 105x113 at (12,8) | derive under writable root |
| `board_grid` | `Assets/BenchmarkStarter/Art/grid_dot.png` | 128x128 | 45x45 at (42,42) | derive under writable root |
| `hearts_budget` | `Assets/BenchmarkStarter/Art/heart.png` | 128x128 | 93x93 at (18,24) | derive under writable root |
| `hint_control` | `Assets/BenchmarkStarter/Art/hint_button.png` | 128x128 | 113x113 at (8,8) | derive under writable root |
| `next_level_control` | `Assets/BenchmarkStarter/Art/next_button.png` | 128x128 | 113x113 at (8,8) | derive under writable root |
| `restart_control` | `Assets/BenchmarkStarter/Art/restart_button.png` | 128x128 | 113x113 at (8,8) | derive under writable root |
| `status_panel` | `Assets/BenchmarkStarter/Art/ui_panel.png` | 128x128 | 119x105 at (5,12) | derive under writable root |
| `dependency_key` | `TaskAssets/badges/key_badge.png` | 128x128 | 113x113 at (8,8) | copy to writable runtime destination |
| `dependency_lock` | `TaskAssets/badges/lock_badge.png` | 128x128 | 113x113 at (8,8) | copy to writable runtime destination |

Exact hashes, bytes, padding, and importer fields are in `ASSET_CATALOG.json`. The final assembled screen must still satisfy the player-visible GDD; the catalog does not prescribe hidden implementation or acceptance behavior.
