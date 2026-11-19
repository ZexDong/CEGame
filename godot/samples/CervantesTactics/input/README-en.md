# Cervantes Tactics Chapter One Public Project

This package is intended for building the English edition of *Cervantes Tactics: Chapter One*. The sole acceptance criteria for player-facing requirements are the uniquely numbered items in Section 6 of `GDD-en.md`.

## Contents

```text
input/
├─ GDD-en.md
├─ TOOLCHAIN-en.md
├─ GODOT_BENCHMARK_TOOL_GUIDE.md
├─ MaterialMapping-en.md

├─ legal/
├─ sp/
└─ Asserts/
```

`sp/project.godot` is a minimal runnable Godot 4.7.1 starter with a fixed `1280×720` window. The target menu, save slots, chapter flow, battle, results, progression, and settings are requirements to implement; they are not pre-completed in this Input.

`Asserts/` provides the logo, Chapter One maps, portraits, battlefield standees, 3D dungeon assets, and foliage source assets. Use them according to `MaterialMapping-en.md` and `legal/LICENSES.md`.

The public package does not contain scoring rules, private trajectories, a Reference directory, reference source code, correct/incorrect variants, or historical scores. Do not modify the GDD to lower its requirements, and do not add private material or cheating interfaces to a submission.
