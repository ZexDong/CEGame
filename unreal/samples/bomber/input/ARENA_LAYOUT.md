# Fixed Duel Arena

`starter-project/Config/BomberArenaLayout.json` is the authoritative machine-readable layout referenced by `CONTENT-01` and the crate/power-up requirements in `GDD.md`.

## Coordinate Space

- Origin: top-left cell `(0,0)`.
- Positive X: right.
- Positive Y: down.
- Size: 11 by 9 cells.

## Symbols

| Symbol | Meaning |
|---|---|
| `#` | Indestructible wall |
| `.` | Floor |
| `C` | Destructible crate |
| `1` | Player 1 start floor |
| `2` | Player 2 start floor |

```text
###########
#1.C.C.C.2#
#.#.#.#.#.#
#..C.C.C..#
#.#.#.#.#.#
#C.C.C.C.C#
#.#.#.#.#.#
#..C.C.C.C#
###########
```

The open vertical lanes below both start cells let either player leave the initial Fire 2 blast footprint before a first bomb detonates. The JSON file also identifies the three crates that contain the original Bomb, Fire, and Skate power-up types. This document does not add acceptance rules; `GDD.md` Section 6 is authoritative.
