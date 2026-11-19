#!/usr/bin/env python3
"""Assemble one private Deep Relay engine-resident evaluator runner."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--mode", choices=("formal", "reopen"), default="formal")
    args = parser.parse_args()
    runtime = args.runtime_dir.resolve()
    driver = (runtime / "engine_driver.lua").read_text(encoding="utf-8")
    suite_name = "formal_suite.lua" if args.mode == "formal" else "reopen_suite.lua"
    suite_function = "runFormalSuite" if args.mode == "formal" else "runReopenSuite"
    watchdog = 1200 if args.mode == "formal" else 120
    suite = (runtime / suite_name).read_text(encoding="utf-8")
    rendered = f'''--!strict
-- Generated private Deep Relay {args.mode} evaluator. It requests ordinary OS
-- input when needed and judges only from live Roblox engine state.
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local commandSequence = 0
local traceSequence = 0

local function emitCommand(action: string, data: {{ [string]: any }}?)
    commandSequence += 1
    local payload = data or {{}}
    payload.action = action
    payload.sequence = commandSequence
    print("DEEP_RELAY_COMMAND " .. HttpService:JSONEncode(payload))
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
    local traceId = string.format("dr-trace-%06d", traceSequence)
    payload.trace_id = traceId
    payload.engine_time = Workspace:GetServerTimeNow()
    -- Emit a compact record before the payload. Studio may truncate a long
    -- output line, but the literal trace id must remain recoverable without
    -- inferring it from sequence order.
    print("DEEP_RELAY_TRACE_ANCHOR " .. HttpService:JSONEncode({{
        trace_id = traceId, action = payload.action, outcome = payload.outcome,
        engine_time = payload.engine_time,
    }}))
    print("DEEP_RELAY_TRACE " .. HttpService:JSONEncode(payload))
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
    print("DEEP_RELAY_CHECKPOINT " .. HttpService:JSONEncode({{
        checkpoint_id = id, status = status, detail = detail,
        trace_ids = unique, trace_id_count_total = total,
        engine_time = Workspace:GetServerTimeNow(),
    }}))
end

{driver}

{suite}

print("DEEP_RELAY_EVAL_READY " .. HttpService:JSONEncode({{
    evaluator_version = "deep-relay-v1.1-{args.mode}-engine-state",
    mode = "{args.mode}",
    judgment_backend = "Roblox Luau live engine state",
}}))

local finished = false
local ok = false
local message: any = "suite worker did not finish"
task.spawn(function()
    ok, message = pcall(function()
        local Driver = buildEngineDriver(inputAdapter, emitTrace)
        {suite_function}(Driver, emitCheckpoint)
    end)
    finished = true
end)

local deadline = os.clock() + {watchdog}
repeat task.wait(0.1) until finished or os.clock() >= deadline
for _, key in {{ Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.E, Enum.KeyCode.R }} do
    inputAdapter.sendKeyEvent(false, key)
end
if not finished then ok = false; message = "engine suite exceeded declared {watchdog} second watchdog" end
print("DEEP_RELAY_EVAL_DONE " .. HttpService:JSONEncode({{
    evaluator_version = "deep-relay-v1.1-{args.mode}-engine-state",
    mode = "{args.mode}",
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
