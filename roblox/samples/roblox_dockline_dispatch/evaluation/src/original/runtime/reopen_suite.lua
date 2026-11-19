--!strict
-- Separate clean-process lifecycle check; no business input.
local function runReopenSuite(Driver:any,emitCheckpoint:any)
	local d=Driver.new()
	local ready,readyTrace=d:waitReady(12)
	if not ready then
		local snapshot=d:degradedSnapshot()
		local trace=d:trace("reopen_bootstrap_failure","observed",d:compactDegradedSnapshot(snapshot))
		emitCheckpoint("d4.reopen_clean_session","fail","A separately reopened PlayClient again lacked the required DD_Ready initial game state.",{readyTrace,trace})
		return
	end
	local s=d:stateMap(); local hud=d:hudMap()
	local clean=s.DD_RunStatus=="AwaitingStart" and s.DD_Phase=="AwaitingStart" and s.DD_CarryItemId=="None"
		and s.DD_GlassState=="Inbound" and s.DD_ColdState=="Inbound" and s.DD_CipherState=="Inbound"
		and s.DD_AuthProgress==0 and s.DD_StagedCount==0 and s.DD_RejectCount==0 and s.DD_PalletProgress==0
		and s.DD_CheckpointId=="Start" and s.DD_SealInstalled==false and s.DD_DeathCount==0 and s.DD_FinalTime==0
	local hudPresent=hud.Objective~=nil and hud.Timer~=nil and hud.Feedback~=nil
	local trace=d:trace("reopen_initial_state",clean and "clean" or "dirty",{hud_present=hudPresent})
	emitCheckpoint("d4.reopen_clean_session",clean and hudPresent and "pass" or "fail","A new Studio/PlayClient process was checked before gameplay input.",{readyTrace,trace})
end
