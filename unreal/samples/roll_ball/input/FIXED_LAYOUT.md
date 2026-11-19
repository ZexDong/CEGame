# Fixed Layout Reference

This file is a human-readable view of `starter-project/Config/FixedRollBallLayout.json`. It does not add gameplay requirements. `GDD.md` Section 6 defines acceptance, and the JSON file supplies the exact machine layout required there.

## Identity and coordinates

| Field | Value |
|---|---|
| Layout ID | `rollball-fixed-maze-10x10-v2` |
| Grid | 10 x 10 cells |
| Cell size | 400 Unreal units |
| Origin | Bottom-left |
| Positive X | Right |
| Positive Y | Up |
| Start | (0,0) |
| Exit | (9,9) |
| Trap count | 16 |

## Diagram

S is the start, E is the exit, and X marks a fixed trap tile. The supplied trap-hole mesh provides the visible center opening; the gameplay boundary for that opening is defined only by `GDD.md` Section 6.

```
+---+---+---+---+---+---+---+---+---+---+
|               | X |               | E |
+   +   +---+   +   +   +   +---+   +   +
| X |   |   |       |   | X |       |   |
+---+   +   +---+   +   +   +   +---+   +
| X     |   | X |   |   | X |           |
+   +---+   +   +---+   +   +---+---+---+
|       |   |   |       |         X     |
+   +   +   +   +   +---+---+---+---+   +
|   | X |       |           |           |
+   +   +---+   +   +   +---+---+---+   +
|   |           | X |       | X     |   |
+   +---+---+   +   +   +   +   +   +---+
|           |       |   | X |   |       |
+---+---+---+---+---+   +   +---+   +   +
|           |           |       |   |   |
+   +---+   +   +---+---+---+   +---+   +
|   | X |   |   |           |     X | X |
+   +   +   +   +   +---+   +---+   +   +
| S |           |       | X   X         |
+---+---+---+---+---+---+---+---+---+---+
```

## Fixed trap cells

| Index | Cell |
|---:|---|
| `1` | `(4,9)` |
| `2` | `(6,8)` |
| `3` | `(0,8)` |
| `4` | `(8,6)` |
| `5` | `(0,7)` |
| `6` | `(3,7)` |
| `7` | `(6,7)` |
| `8` | `(1,5)` |
| `9` | `(4,4)` |
| `10` | `(7,4)` |
| `11` | `(6,3)` |
| `12` | `(1,1)` |
| `13` | `(8,1)` |
| `14` | `(9,1)` |
| `15` | `(6,0)` |
| `16` | `(7,0)` |

## Wall encoding

- `vertical_walls`: 67 segments. `{x,y}` identifies the vertical boundary at grid line `x` for cell row `y`.
- `horizontal_walls`: 54 segments. `{x,y}` identifies the horizontal boundary at grid line `y` for cell column `x`.
- Perimeter walls are included explicitly.
- The internal openings form one connected perfect maze with exactly 99 passages.
- The unique start-to-exit route contains no trap cell; traps remain reachable on side branches.
- Restart and reopen never change this data.
