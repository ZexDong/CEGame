--!strict
-- Separate clean-process lifecycle check. It performs no business interaction.

local function runReopenSuite(Driver:any, emitCheckpoint:any)
	local d=Driver.new()
	local ready,readyTrace=d:waitReady(12)
	if not ready then
		local snapshot=d:degradedSnapshot()
		local trace=d:trace("reopen_bootstrap_failure","observed",d:compactDegradedSnapshot(snapshot))
		emitCheckpoint("d4.reopen_clean_session","fail","A separately reopened clean Studio/PlayClient session again failed to publish the required ready/initial state.",{readyTrace,trace})
		return
	end
	local state=d:stateMap()
	local hud=d:hudMap()
	local clean=state.DR_RunStatus=="InProgress"
		and state.DR_PowerState=="NeedFuse"
		and state.DR_CoolantPressure==0
		and state.DR_AuthState=="Offline"
		and state.DR_AssemblyProgress==0
		and state.DR_CarryItemId=="None"
		and state.DR_AirlockState=="OpenOuter"
		and state.DR_CheckpointId=="Central"
		and state.DR_CoreInstalled==false
		and state.DR_DeathCount==0
		and state.DR_FinalTime==0
	local hudPresent=hud.Objective~=nil and hud.Timer~=nil and hud.Feedback~=nil
	local trace=d:trace("reopen_initial_state",clean and "clean" or "dirty",{state=state,hud_present=hudPresent})
	emitCheckpoint("d4.reopen_clean_session",clean and hudPresent and "pass" or "fail","A separately reopened Studio/PlayClient session was checked before any gameplay input.",{readyTrace,trace})
end
