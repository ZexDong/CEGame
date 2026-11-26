# Defold Engine Tool Guide

```text
common_tool_guide_id: defold-common-tool-guide-v4-20260828
build_route: bundled-jdk-plus-bob
```

This guide contains verified, reusable Defold tools and engine facts for the current environment.
Each task's own public documents define its gameplay, assets, controls, and delivery requirements.

Every tool here is optional unless a task document explicitly requires it. This is not a development
pipeline and does not prescribe a tool order, number of iterations, private evaluation trajectory,
or answer state.

## 1. Fixed local toolchain

The installed Defold application supplies both Bob and a matching JDK:

```bash
DEFOLD_JAR="${DEFOLD_BOB_JAR:?Set DEFOLD_BOB_JAR to the installed Bob JAR}"
: "${DEFOLD_JAVA:?Set DEFOLD_JAVA to the installed Java executable}"
```

Check the version:

```bash
"$DEFOLD_JAVA" -cp "$DEFOLD_JAR" com.dynamo.bob.Bob --version
```

Keep the selected tool installation read-only.

## 2. Project files and resource paths

A project root contains `game.project`. Common source resources are:

| File | Purpose |
|---|---|
| `game.project` | Bootstrap, display, input, dependencies, and engine settings |
| `.collection` | Scene containing Game Object or Collection instances |
| `.go` | Game Object and its components |
| `.script` | Game Object Lua script |
| `.gui` / `.gui_script` | GUI scene and GUI Lua script |
| `.input_binding` | Keyboard, mouse, touch, and gamepad action bindings |
| `.atlas` | Images and flipbook animations for Sprite or GUI use |
| `.tilesource` / `.tilemap` | Tile definitions and tile map |
| `.collisionobject` | Collision type, groups, masks, and shapes |
| `.font` | GUI font resource |
| `.factory` / `.collectionfactory` | Runtime Game Object or Collection creation |
| `.model` / `.mesh` / `.material` | 3D model, mesh, and rendering material |

Resource paths are rooted at the project, for example `/main/main.collection`. File-name case must
match disk case.

Compiled references in `game.project` use compiled suffixes:

```ini
[bootstrap]
main_collection = /main/main.collectionc

[input]
game_binding = /main/game.input_bindingc
```

Source resources such as `.collection`, `.go`, and `.gui` normally refer to source suffixes such as
`.script`, `.sprite`, or `.atlas`. Do not mechanically add `c` to every resource reference.

## 3. Bob builds

Run Bob from the directory containing `game.project`. A clean build is:

```bash
"$DEFOLD_JAVA" -cp "$DEFOLD_JAR" com.dynamo.bob.Bob \
  --root . \
  --platform arm64-macos \
  --variant debug \
  --archive \
  resolve distclean build bundle
```

An incremental build is:

```bash
"$DEFOLD_JAVA" -cp "$DEFOLD_JAR" com.dynamo.bob.Bob \
  --root . \
  --platform arm64-macos \
  --variant debug \
  --archive \
  build bundle
```

- `resolve` downloads declared dependencies.
- `distclean` clears Bob output.
- `build` compiles project resources.
- `bundle` creates a native desktop App Bundle.
- `--variant debug` retains useful runtime diagnostics.
- `--archive` produces the archive required by the bundle.

A nonzero Bob exit code or an `ERROR` in its output is a build failure. A zero exit code proves only
that resources compiled; Lua initialization and the first runtime frame still need a launch check.

## 4. Launch, logs, and exact-process shutdown

The bundle normally appears below `build/default/`. Find its executable instead of guessing the
project-derived name:

```bash
find build/default -type f -path '*/Contents/native desktop/*' -perm -u+x -print
```

Launch from the project root and retain that exact process id:

```bash
GAME_BIN="$(find build/default -type f -path '*/Contents/native desktop/*' -perm -u+x -print -quit)"
"$GAME_BIN" > runtime.log 2>&1 &
GAME_PID=$!
```

`print()`, Lua tracebacks, missing-resource errors, and engine messages reach standard output/error.
If `game.project` contains:

```ini
[project]
write_log = 1
```

the desktop build also writes `log.txt` relative to its launch working directory. Explicit stdout
redirection remains easier to locate.

Stop only the process id that was saved for this launch:

```bash
kill "$GAME_PID"
wait "$GAME_PID" 2>/dev/null || true
```

Do not use `killall dmengine`, `pkill`, or app-name-wide termination because another Defold project
may be running at the same time.

## 5. Lua callbacks, state, and modules

Game Object scripts commonly implement:

```lua
function init(self) end
function update(self, dt) end
function fixed_update(self, dt) end
function on_input(self, action_id, action) end
function on_message(self, message_id, message, sender) end
function final(self) end
```

- `self` is the persistent table for one script component instance.
- `update()` receives frame time in seconds.
- `fixed_update()` runs only when fixed update is enabled.
- `final()` releases timers, sockets, files, or other external resources created by the script.

Call a local helper as a normal function:

```lua
local function reset_state(self)
    self.elapsed = 0
end

reset_state(self)
```

`self:reset_state()` is different: it looks for a field on `self` and passes `self` implicitly.

Lua modules return a table and are loaded by their resource path:

```lua
-- main/math_helpers.lua
local M = {}
function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
return M

-- another script
local helpers = require "main.math_helpers"
```

Defold identifiers and messages commonly use hashes:

```lua
local JUMP = hash("jump")
msg.post("#sprite", "play_animation", { id = hash("idle") })
```

`.` addresses the current Game Object, `#component` a component on it, and
`/object#component` an absolute component URL.

The verified configured version runtime does not provide `sys.get_config()`. Do not publish or depend on that
function for reading `game.project` or command-line values.

## 6. Normal input

First map a device event to an action in `.input_binding`:

```text
key_trigger {
  input: KEY_A
  action: "left"
}
key_trigger {
  input: KEY_LEFT
  action: "left"
}
mouse_trigger {
  input: MOUSE_BUTTON_1
  action: "click"
}
```

The receiving script or GUI script must acquire input focus:

```lua
function init(self)
    msg.post(".", "acquire_input_focus")
end
```

Input is passed through a focus stack. Returning `true` from `on_input()` consumes the action and
prevents lower receivers from seeing it.

- `action.pressed` is true only on the transition from up to down.
- `action.released` is true only on the transition from down to up.
- `action.repeated` represents keyboard repeat.
- A callback where `pressed` is false is not necessarily a release.

Use a held flag for continuous movement:

```lua
function on_input(self, action_id, action)
    if action_id == hash("right") then
        if action.pressed then self.right_down = true end
        if action.released then self.right_down = false end
        return true
    end
end

function update(self, dt)
    if self.right_down then
        local p = go.get_position()
        p.x = p.x + 180 * dt
        go.set_position(p)
    end
end
```

Discrete actions usually react once to `pressed`; continuous movement uses held state and scales
motion by `dt`. Mouse/touch actions can expose `x`, `y`, `dx`, `dy`, `screen_x`, and `screen_y`.
Screen, GUI, render-viewport, and world coordinates are not interchangeable.

## 7. GUI and fonts

GUI scenes render separately from Game Object world space. Common calls are:

```lua
local node = gui.get_node("score")
gui.set_text(node, "Score: 10")
gui.set_position(node, vmath.vector3(40, 500, 0))
gui.set_enabled(node, true)
gui.set_color(node, vmath.vector4(1, 1, 1, 1))
```

Runtime nodes are also available:

```lua
local panel = gui.new_box_node(vmath.vector3(480, 270, 0), vmath.vector3(400, 220, 0))
local label = gui.new_text_node(vmath.vector3(480, 270, 0), "Paused")
```

- A text node needs a font declared by the `.gui` scene.
- Defold has no `gui.set_font_size()`; font resources and `gui.set_scale()` determine size.
- `gui.set_enabled()` controls update and rendering.
- Node order, parenting, and declared layers affect draw order.
- Design size comes from display settings, while anchors and adjust mode affect resized windows.
- GUI hit tests must use the node's actual transformed region, not an assumed design-resolution rect.

### GUI capacity and pointer coordinates (verified on Defold / native host native desktop)

GUI node capacity and font-render batch capacity are separate limits. A scene can run out of nodes,
or retain its nodes while later text stops rendering because the font batch limit was reached.
The engine reports these cases in the runtime log. A `.gui` resource can declare its node budget:

```text
max_nodes: 8192
```

For projects with many separate text draws, `game.project` exposes the font batch budget:

```ini
[graphics]
max_font_batches = 512
```

These are resource settings, not gameplay. Pool or delete runtime nodes that are no longer needed;
raising a budget does not fix an unbounded allocation leak. The bundled default font is 14 points;
`gui.set_scale()` changes its displayed size.

The fit-mode Lua constant is `gui.ADJUST_FIT`, not `gui.ADJUST_MODE_FIT`:

```lua
gui.set_adjust_mode(node, gui.ADJUST_FIT)
local hit = gui.pick_node(node, action.x, action.y)
local local_point = gui.screen_to_local(node,
    vmath.vector3(action.screen_x, action.screen_y, 0))
local client_width, client_height = window.get_size()
```

Use the normal mouse event for these pointer calls. `action.x/y` and `action.screen_x/screen_y`
are not interchangeable on a high-DPI window: the latter are raw screen coordinates consumed by
`gui.screen_to_local`. On the verified host, `window.get_size()` can return twice the design
resolution. Never treat those values as native desktop desktop points without a coordinate conversion.

## 8. Sprites, atlases, and tile maps

A Sprite uses an image or animation id declared by an `.atlas` or `.tilesource`:

```lua
sprite.play_flipbook("#sprite", hash("run"))
sprite.set_hflip("#sprite", true)
```

- Declare semantic images/frames in the atlas; a sheet's full pixel size is not one sprite frame.
- Transparent source pixels still belong to the image rectangle, so visible bounds, pivot, Sprite
  size, and collision shape need separate checks.
- `nearest` min/mag filtering is common for pixel art; smooth art normally uses linear filtering.
- Tint alpha, Game Object scale, z/order, camera, and render predicates can make a valid Sprite
  invisible.

`tilemap.set_tile()` changes a tile. Tile ids, tile-map cells, and world pixels are different units.

## 9. Game Objects, factories, timers, and messages

Transform examples:

```lua
local p = go.get_position()
go.set_position(vmath.vector3(p.x + 10, p.y, p.z))
go.set_rotation(vmath.quat_rotation_z(math.rad(20)))
go.set_scale(vmath.vector3(2, 2, 1))
```

`go.get_position()` is relative to the parent by default. Use the corresponding world-transform API
when world coordinates are required.

Factory creation and deletion:

```lua
local id = factory.create("#factory", position, rotation, properties, scale)
go.delete(id)
```

The returned id becomes invalid after deletion. Factory `properties` apply only to script fields
declared with `go.property()`.

Timers return a handle that can be cancelled:

```lua
local handle = timer.delay(1.0, false, function() print("done") end)
timer.cancel(handle)
```

Store long-lived handles and cancel callbacks that would outlive their state or Game Object.
Use `msg.post()` and `on_message()` for component communication instead of directly coupling
unrelated scripts.

## 10. 2D physics and collision

Collision Objects may be static, dynamic, kinematic, or trigger. A visible Sprite or GUI node does
not automatically create or update a collision shape.

Group/mask settings determine contact. Common messages are:

- `collision_response` — a collision occurred;
- `contact_point_response` — contact point, normal, penetration distance, and other object;
- `trigger_response` — trigger enter/exit, with `message.enter` indicating direction.

```lua
function on_message(self, message_id, message, sender)
    if message_id == hash("trigger_response") and message.enter then
        print("entered", message.other_id)
    elseif message_id == hash("contact_point_response") then
        print(message.normal, message.distance, message.other_id)
    end
end
```

The engine solves dynamic bodies. A script-driven kinematic body may need to resolve reported
penetration itself. A trigger reports overlap but does not provide solid blocking.

Disable or enable collision independently of rendering:

```lua
msg.post("#collisionobject", "disable")
msg.post("#collisionobject", "enable")
```

Very fast objects can cross thin shapes between physics steps. Use a suitable fixed step, speed,
shape thickness, or supported continuous-collision approach.

## 11. Camera, render, coordinates, and 3D

Game Objects, Sprites, Tilemaps, Models, and Meshes use world space; GUI uses GUI space. Camera and
render scripts determine how world space reaches the window.

- `[display] width` and `height` are design values, not a guarantee of the current window size.
- Camera movement affects world rendering but does not automatically move GUI.
- Screen mouse coordinates must be projected before comparison with world objects.
- z, render predicates, and render order affect visibility but do not normally change 2D x/y
  collision.
- A custom render script must still draw every required world, model, GUI, and debug predicate.

For 3D, a Model component references a compiled model/mesh and material. Game Object position,
quaternion rotation, and scale place it in world space. A Camera component supplies view and
projection; the render script must draw the model predicate with the intended depth test and
projection. Lights and shadows depend on the chosen material/shader/render setup and are not
created merely by importing a model. If default rendering is sufficient, do not replace the render
script just to change a background color or simple layer.

## 12. JSON and file output

The built-in `json.encode()` and `json.decode()` operate on Lua values and JSON text. Lua has no
distinct empty-array table, so Defold encodes an empty table as the object `{}`. If an external
contract requires `[]`, handle that explicitly in the serialization layer; do not assume
`json.encode({})` produces an array.

Lua file output uses `io.open()`. A relative path is relative to the process launch working
directory:

```lua
local file, err = io.open("trace.jsonl", "w")
assert(file, err)
file:write(json.encode({ ready = true }), "\n")
file:flush()
file:close()
```

Use one complete JSON object per line for JSONL. Flush when an external reader needs current data,
and close the exact handle in `final()`.

## 13. Quick fault lookup

| Symptom | Check first |
|---|---|
| Bob succeeds but the app exits immediately | Lua traceback, bootstrap collection, missing resource |
| `module not found` | Module path, case, and resolved dependency |
| `attempt to call method` | Local function accidentally called as `self:method()` |
| Held key moves only once | `pressed == false` incorrectly treated as release |
| No input at all | Binding, `game.project`, input focus, or a higher receiver consuming it |
| GUI text missing | Declared font, enabled state, alpha, scale, and layer |
| Whole sheet appears as one sprite | Atlas image/animation id or Sprite animation setting |
| Object exists but is invisible | Tint alpha, scale, z/order, camera, and render predicate |
| Visible object cannot collide | Group/mask, shape size/center, transform mismatch |
| Hidden door still blocks | Sprite hidden but Collision Object still enabled |
| JSON requires `[]` but gets `{}` | Empty Lua-table serialization ambiguity |
| Another project was closed | Process-name-wide kill used instead of the saved PID |

## 14. Official references

- [Defold Manual](https://defold.com/manuals/introduction/)
- [Bob build tool](https://defold.com/manuals/bob/)
- [Project settings](https://defold.com/manuals/project-settings/)
- [Input](https://defold.com/manuals/input/)
- [GUI](https://defold.com/manuals/gui/)
- [Atlas](https://defold.com/manuals/atlas/)
- [Physics](https://defold.com/manuals/physics/)
- [Camera](https://defold.com/manuals/camera/)
- [Model](https://defold.com/manuals/model/)
- [Lua API](https://defold.com/ref/stable/lua/)
- [Engine API reference](https://defold.com/ref/stable/)
