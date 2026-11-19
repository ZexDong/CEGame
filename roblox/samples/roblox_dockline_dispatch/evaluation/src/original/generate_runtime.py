#!/usr/bin/env python3
"""Assemble one private Dockline Dispatch engine-resident evaluator runner."""

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
-- Generated private Dockline Dispatch {args.mode} evaluator. It requests ordinary OS
-- input when needed and judges only from live Roblox engine state.
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local commandSequence = 0
local traceSequence = 0
local inputBeganCounts: {{ [string]: number }} = {{}}
local acknowledgedPressedKeys: {{ [string]: boolean }} = {{}}

UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
    local keyName = input.KeyCode.Name
    inputBeganCounts[keyName] = (inputBeganCounts[keyName] or 0) + 1
end)
local function emitCommand(action: string, data: {{ [string]: any }}?)
    commandSequence += 1
    local payload = data or {{}}
    payload.action = action
    payload.sequence = commandSequence
    print("DOCKLINE_DISPATCH_COMMAND " .. HttpService:JSONEncode(payload))
end

local inputAdapter = {{}}
function inputAdapter.sendKeyEvent(isDown: boolean, key: Enum.KeyCode)
    -- Studio reliably publishes InputBegan for accepted SendInput key-downs,
    -- but both InputEnded and IsKeyDown have proved unreliable for releases.
    -- A release is therefore issued without a synthetic edge requirement; the
    -- following navigation/state observation remains the functional evidence.
    if isDown and acknowledgedPressedKeys[key.Name] then
        return
    end
    if not isDown and not acknowledgedPressedKeys[key.Name] then
        return
    end
    local beganBefore = inputBeganCounts[key.Name] or 0
    emitCommand(if isDown then "key_down" else "key_up", {{ key = key.Name }})
    if not isDown then
        acknowledgedPressedKeys[key.Name] = false
        task.wait(0.04)
        return
    end
    local deadline = os.clock() + 1.5
    repeat task.wait() until (inputBeganCounts[key.Name] or 0) > beganBefore or os.clock() >= deadline
    if (inputBeganCounts[key.Name] or 0) <= beganBefore then
        -- One bounded delivery retry is a controller recovery, not a second
        -- gameplay trajectory.
        emitCommand("key_down", {{ key = key.Name, retry = true }})
        deadline = os.clock() + 1.5
        repeat task.wait() until (inputBeganCounts[key.Name] or 0) > beganBefore or os.clock() >= deadline
    end
    if (inputBeganCounts[key.Name] or 0) <= beganBefore then
        error(string.format(
            "controller input ACK timeout: InputBegan %s was not observed by UserInputService",
            key.Name
        ))
    end
    acknowledgedPressedKeys[key.Name] = true
end
function inputAdapter.releaseKeyWithoutAck(key: Enum.KeyCode)
    emitCommand("key_up", {{ key = key.Name }})
    acknowledgedPressedKeys[key.Name] = false
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
    local traceId = string.format("dd-trace-%06d", traceSequence)
    payload.trace_id = traceId
    payload.engine_time = Workspace:GetServerTimeNow()
    -- Emit a compact record before the payload. Studio may truncate a long
    -- output line, but the literal trace id must remain recoverable without
    -- inferring it from sequence order.
    print("DOCKLINE_DISPATCH_TRACE_ANCHOR " .. HttpService:JSONEncode({{
        trace_id = traceId, action = payload.action, outcome = payload.outcome,
        engine_time = payload.engine_time,
    }}))
    -- Studio truncates long CreatorOutput lines. Emit a complete compact
    -- engine-state record rather than an unusable prefix of the full scene.
    local state = payload.game_state or {{}}
    local compactState = {{
        run_id = state.DD_RunId, run = state.DD_RunStatus, phase = state.DD_Phase,
        carry = state.DD_CarryItemId, glass = state.DD_GlassState,
        cold = state.DD_ColdState, cipher = state.DD_CipherState,
        auth = state.DD_AuthState, auth_n = state.DD_AuthProgress,
        div1 = state.DD_DiverterOne, div2 = state.DD_DiverterTwo,
        conveyor = state.DD_ConveyorState, conveyor_item = state.DD_ConveyorPackageId,
        staged = state.DD_StagedCount, rejects = state.DD_RejectCount,
        pallet = state.DD_PalletState, pallet_n = state.DD_PalletProgress,
        checkpoint = state.DD_CheckpointId, hazard = state.DD_HazardState,
        seal = state.DD_SealInstalled, code_n = state.DD_FinalCodeProgress,
        deaths = state.DD_DeathCount, final_time = state.DD_FinalTime,
        event_n = state.DD_EventSeq, event = state.DD_LastEvent,
        source = state.DD_LastSourceId, reject = state.DD_LastRejectCode,
    }}
    local function compactVector(value: any): any
        if type(value) ~= "table" then return nil end
        local function rounded(number: any): any
            if type(number) ~= "number" then return nil end
            return math.round(number * 1000) / 1000
        end
        return {{ x = rounded(value.x), y = rounded(value.y), z = rounded(value.z) }}
    end
    local compact = {{
        trace_id = traceId, engine_time = payload.engine_time,
        action = payload.action, outcome = payload.outcome,
        position = compactVector(payload.position),
        velocity = compactVector(payload.velocity),
        health = payload.health, walk_speed = payload.walk_speed,
        state_present = payload.game_state_present, state = compactState,
        ready = payload.workspace_ready, protocol = payload.contract_version,
        interaction_id = payload.interaction_id, target = payload.target,
        distance = payload.distance, attribute = payload.attribute, value = payload.value,
        duration_s = payload.duration_s, prompt_enabled = payload.prompt_enabled,
        observed_source = payload.observed_source, event_confirmed = payload.event_confirmed,
        counts = payload.counts,
    }}
    if payload.action == "schema_snapshot" or payload.action == "hud_initial" then
        compact.position = nil
        compact.velocity = nil
    elseif payload.action ~= "walk_to" and payload.action ~= "real_key_input" and payload.action ~= "wait_respawn" then
        compact.velocity = nil
    end
    if type(payload.hud) == "table" then
        local total = 0
        local visible = 0
        local sized = 0
        local nonempty = 0
        for _, field in payload.hud do
            total += 1
            if field.visible == true then visible += 1 end
            if (field.w or 0) > 0 and (field.h or 0) > 0 then sized += 1 end
            if type(field.text) == "string" and #field.text > 0 then nonempty += 1 end
        end
        compact.hud = {{ total = total, visible = visible, sized = sized, nonempty = nonempty }}
    end
    print("DOCKLINE_DISPATCH_TRACE " .. HttpService:JSONEncode(compact))
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
    print("DOCKLINE_DISPATCH_CHECKPOINT " .. HttpService:JSONEncode({{
        checkpoint_id = id, status = status, detail = detail,
        trace_ids = unique, trace_id_count_total = total,
        engine_time = Workspace:GetServerTimeNow(),
    }}))
end

{driver}

{suite}

print("DOCKLINE_DISPATCH_EVAL_READY " .. HttpService:JSONEncode({{
    evaluator_version = "dockline-dispatch-v1.1-{args.mode}-engine-state",
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
    inputAdapter.releaseKeyWithoutAck(key)
end
if not finished then ok = false; message = "engine suite exceeded declared {watchdog} second watchdog" end
print("DOCKLINE_DISPATCH_EVAL_DONE " .. HttpService:JSONEncode({{
    evaluator_version = "dockline-dispatch-v1.1-{args.mode}-engine-state",
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
