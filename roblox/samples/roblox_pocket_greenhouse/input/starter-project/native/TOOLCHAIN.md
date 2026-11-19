# Roblox Toolchain Notes

## Delivery and launch

- Target engine: Roblox Studio (current stable release).
- Primary artifact: one editable `.rbxlx` place.
- Also deliver reproducible source; a Rojo project is recommended.
- The place must start from Roblox Studio's normal **Play** action without plugins, cloud services, HTTP access, DataStore access, or a published Roblox experience.
- No account-specific asset may be required for core gameplay.

## Input

Core gameplay must use normal left mouse clicks. The evaluator uses Windows SendInput and never calls gameplay RemoteEvents directly.

## Dashboard transport

The public read-only entry point is:

`ReplicatedStorage/BenchmarkDashboard`

It is a ModuleScript returning a table with exactly one public function:

`GetSnapshot() -> table`

The returned table must be serializable by `HttpService:JSONEncode`. A private QA copy may inject an observer which calls this function and writes JSON snapshots to Studio logs. The candidate's original files are not modified during formal evaluation.

Target rectangles use Roblox viewport pixel coordinates `[x, y, width, height]`, measured from the top-left of the playable viewport. They must follow the actual current GUI position and size; do not assume 1280×720.

## Randomness

This task has no gameplay randomness. Decorative randomness is allowed only if it cannot affect rules, target rectangles, readability, timing, or outcomes.
