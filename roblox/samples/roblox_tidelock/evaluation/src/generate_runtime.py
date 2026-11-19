#!/usr/bin/env python3
"""Assemble the private Tide Lock engine-resident evaluator."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    runtime = args.runtime_dir.resolve()
    driver = (runtime / "engine_driver.lua").read_text(encoding="utf-8")
    suite = (runtime / "formal_suite.lua").read_text(encoding="utf-8")
    rendered = f'''--!strict
-- Generated private Tide Lock evaluator. It requests ordinary OS input and
-- judges D2-D5 only from live Roblox engine state.
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local commandSequence = 0
local traceSequence = 0

local function emitCommand(action: string, data: {{ [string]: any }}?)
    commandSequence += 1
    local payload = data or {{}}
    payload.action = action
    payload.sequence = commandSequence
    print("TIDE_LOCK_COMMAND " .. HttpService:JSONEncode(payload))
end

local inputAdapter = {{}}
function inputAdapter.sendKeyEvent(isDown: boolean, key: Enum.KeyCode)
    emitCommand(if isDown then "key_down" else "key_up", {{ key = key.Name }})
end
function inputAdapter.dragMouse(dx: number, dy: number)
    emitCommand("mouse_drag", {{ dx = dx, dy = dy }})
end
function inputAdapter.centerMouse()
    emitCommand("mouse_center", {{}})
end
function inputAdapter.moveMouseRelative(dx: number, dy: number)
    emitCommand("mouse_move_relative", {{ dx = dx, dy = dy }})
end
function inputAdapter.clickLeft()
    emitCommand("mouse_left_click", {{}})
end

local function emitTrace(payload: {{ [string]: any }}): string
    traceSequence += 1
    local traceId = string.format("tl-trace-%06d", traceSequence)
    payload.trace_id = traceId
    payload.engine_time = Workspace:GetServerTimeNow()
    print("TIDE_LOCK_TRACE " .. HttpService:JSONEncode(payload))
    return traceId
end

local function emitCheckpoint(id: string, status: string, detail: string, traceIds: {{ string }})
    local unique = {{}}
    local seen: {{ [string]: boolean }} = {{}}
    for _, traceId in traceIds do
        if type(traceId) == "string" and traceId ~= "" and not seen[traceId] then
            seen[traceId] = true
            table.insert(unique, traceId)
        end
    end
    local total = #unique
    while #unique > 12 do table.remove(unique, 2) end
    print("TIDE_LOCK_CHECKPOINT " .. HttpService:JSONEncode({{
        checkpoint_id = id, status = status, detail = detail,
        trace_ids = unique, trace_id_count_total = total,
        engine_time = Workspace:GetServerTimeNow(),
    }}))
end

{driver}

{suite}

print("TIDE_LOCK_EVAL_READY " .. HttpService:JSONEncode({{
    evaluator_version = "tide-lock-v1.0-engine-state",
    judgment_backend = "Roblox Luau live engine state",
}}))

local finished = false
local ok = false
local message: any = "suite worker did not finish"
task.spawn(function()
    ok, message = pcall(function()
        local Driver = buildEngineDriver(inputAdapter, emitTrace)
        runFormalSuite(Driver, emitCheckpoint)
    end)
    finished = true
end)

local deadline = os.clock() + 900
repeat task.wait(0.1) until finished or os.clock() >= deadline
for _, key in {{ Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.E, Enum.KeyCode.R }} do
    inputAdapter.sendKeyEvent(false, key)
end
if not finished then ok = false; message = "engine suite exceeded declared 900 second watchdog" end
print("TIDE_LOCK_EVAL_DONE " .. HttpService:JSONEncode({{
    evaluator_version = "tide-lock-v1.0-engine-state",
    status = if ok then "completed" else "aborted",
    detail = if ok then "" else tostring(message),
    trace_count = traceSequence, command_count = commandSequence,
}}))
'''
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"Generated: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
