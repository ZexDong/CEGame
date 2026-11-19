--!strict
-- Separate clean-session probe. It does not execute the gameplay trajectory.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function emit(kind: string, payload: { [string]: any })
	print("TIDE_LOCK_" .. kind .. " " .. HttpService:JSONEncode(payload))
end

emit("EVAL_READY", { evaluator_version = "tide-lock-reopen-v1", judgment_backend = "Roblox Luau live engine state" })
local player = Players.LocalPlayer
local deadline = os.clock() + 12
repeat task.wait(0.08) until (Workspace:GetAttribute("TL_Ready") == true and player:GetAttribute("TL_RunState") ~= nil) or os.clock() >= deadline

local traceId = "tl-trace-900001"
local state = {
	TL_RunId = player:GetAttribute("TL_RunId"), TL_RunState = player:GetAttribute("TL_RunState"),
	TL_RoutingComplete = player:GetAttribute("TL_RoutingComplete"), TL_RoutingProgress = player:GetAttribute("TL_RoutingProgress"),
	TL_PressureComplete = player:GetAttribute("TL_PressureComplete"), TL_CoreTransferComplete = player:GetAttribute("TL_CoreTransferComplete"),
	TL_CarryingCore = player:GetAttribute("TL_CarryingCore"), TL_Checkpoint = player:GetAttribute("TL_Checkpoint"),
	TL_FinalStage = player:GetAttribute("TL_FinalStage"), TL_CompletionState = player:GetAttribute("TL_CompletionState"),
	TL_DeathCount = player:GetAttribute("TL_DeathCount"), TL_RetryCount = player:GetAttribute("TL_RetryCount"),
	TL_FinalTime = player:GetAttribute("TL_FinalTime"), TL_LastEvent = player:GetAttribute("TL_LastEvent"),
}
local clean = Workspace:GetAttribute("TL_Ready") == true and Workspace:GetAttribute("TL_ContractVersion") == "tide-lock-v1"
	and state.TL_RunState == "Active" and state.TL_RoutingComplete == false and state.TL_RoutingProgress == 0
	and state.TL_PressureComplete == false and state.TL_CoreTransferComplete == false and state.TL_CarryingCore == false
	and state.TL_Checkpoint == "Central" and state.TL_FinalStage == "Locked" and state.TL_CompletionState == "InProgress"
	and state.TL_DeathCount == 0 and state.TL_RetryCount == 0 and state.TL_FinalTime == 0 and state.TL_LastEvent == "RunStarted"
emit("TRACE", { trace_id = traceId, action = "reopen_clean_state", outcome = if clean then "clean" else "dirty", player_attributes = state, engine_time = Workspace:GetServerTimeNow() })
emit("CHECKPOINT", {
	checkpoint_id = "d4.reopen_clean_session", status = if clean then "pass" else "fail",
	detail = "a fresh Studio Play session must begin with no prior-session progress", trace_ids = { traceId }, trace_id_count_total = 1,
})
emit("CHECKPOINT", {
	checkpoint_id = "aux.reopen_clean", status = if clean then "pass" else "fail",
	detail = "fresh-session clean-state component for restart-and-reopen scoring", trace_ids = { traceId }, trace_id_count_total = 1,
})
emit("EVAL_DONE", { evaluator_version = "tide-lock-reopen-v1", status = "completed", detail = "", trace_count = 1, command_count = 0 })
