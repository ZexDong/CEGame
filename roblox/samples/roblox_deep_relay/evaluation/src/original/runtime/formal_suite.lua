--!strict
-- Deep Relay single formal dynamic journey. No candidate coordinates or business calls.

local function runFormalSuite(Driver:any,emitCheckpoint:any)
	local d=Driver.new(); local emitted:{[string]:boolean}={}; local allTraces={}
	local IDS={
		"d2.world_and_protocol","d2.power_system","d2.coolant_system","d2.auth_system","d2.carry_items","d2.assembly_system","d2.airlock_system","d2.hazard_checkpoint","d2.final_system","d2.completion_content",
		"d3.initial_state","d3.rejection_rules","d3.power_rules","d3.coolant_rules","d3.auth_rules","d3.assembly_rules","d3.airlock_rules","d3.hazard_rules","d3.final_order_rules","d3.completion_condition",
		"d4.start_to_play","d4.restart_midrun","d4.systems_to_core","d4.airlock_to_checkpoint","d4.death_recovery","d4.complete_success_flow","d4.restart_after_complete",
		"d5.input_and_hud","d5.hud_state_sync","d5.rejection_feedback","d5.stage_feedback","d5.completion_feedback",
	}
	local function add(ts:{string}?) if ts then for _,t in ts do table.insert(allTraces,t) end end end
	local function cp(id:string,status:string,detail:string,traces:{string}?) emitted[id]=true; emitCheckpoint(id,status,detail,traces or allTraces) end
	local function oneTrace(t:string) table.insert(allTraces,t); return {t} end
	local function interact(id:string,hold:number?): (boolean,{[string]:any},{[string]:any},{string})
		local ok,ts,b,a=d:interact(id,hold); add(ts); return ok,b,a,ts[#ts] or ""
	end
	local ready,t=d:waitReady(12); add({t})
	if not ready then
		-- Bootstrap-failure degradation path. Normal Play and the passive QA client
		-- are alive, so independently observable content must still be exercised.
		local degraded=d:degradedSnapshot()
		local snapshotEvidence=d:compactDegradedSnapshot(degraded)
		local snapshotTrace=d:trace("bootstrap_failure_snapshot","observed",snapshotEvidence); add({snapshotTrace})
		local counts=degraded.counts
		local protocolPublished=degraded.workspace_ready==true and degraded.contract_version=="deep-relay-v1" and degraded.state_present==true
		cp("d2.world_and_protocol",protocolPublished and "pass" or "fail","Normal Play was live, but the required ready/game-state protocol was not fully published.",{t,snapshotTrace})

		local wObserved,wTrace=d:pulseKey(Enum.KeyCode.W,0.65); add({wTrace})
		local rObserved,rTrace=d:pulseKey(Enum.KeyCode.R,0.16); add({rTrace})
		local movementTrace=d:trace("bootstrap_input_summary","observed",{w_observed=wObserved,r_observed=rObserved}); add({movementTrace})
		cp("d4.start_to_play",wObserved and protocolPublished and "pass" or "fail","A live character received real W input, but normal Play did not enter the required ready gameplay state.",{wTrace,movementTrace,snapshotTrace})

		local requiredHud={"Objective","Systems","PowerProgress","CoolantPressure","AuthProgress","CarryItem","AssemblyProgress","Airlock","Hazard","Checkpoint","Timer","Feedback"}
		local hud=degraded.hud; local hudOk=true
		for _,id in requiredHud do local field=hud[id]; if not field or not field.visible or field.w<=0 or field.h<=0 or field.text=="" then hudOk=false end end
		cp("d5.input_and_hud",wObserved and rObserved and hudOk and "pass" or "fail","Real W/R input reception and all twelve live HUD fields were independently checked.",{wTrace,rTrace,snapshotTrace})
		cp("d5.hud_state_sync",hudOk and degraded.state_present and "pass" or "fail","HUD/state synchronization was unavailable in normal Play because the candidate client never created its HUD.",{snapshotTrace})

		local interactions=d:interactionSchema({
			"Power.FusePickup","Coolant.Inlet","Auth.Scanner.Beta","Assembly.Slot.Coolant",
			"Airlock.OuterControl","Checkpoint.CoreShelf","Final.CoreSocket","Final.Stabilizer.2",
		})
		local interactionTrace=d:trace("bootstrap_interaction_schema","observed",d:compactInteractionSchema(interactions)); add({interactionTrace})
		local function schemaPresent(id:string): boolean
			local object=interactions[id]
			return object and object.present==true and type(object.prompts)=="table" and #object.prompts==1
		end

		-- Reachable representatives are independently attempted with real E input.
		local earlyResults={}; local earlyEvidence={}
		for _,id in {"Power.FusePickup","Coolant.Inlet","Auth.Scanner.Beta","Assembly.Slot.Coolant"} do
			local inputSeen,traces,before,after=d:attemptInteractionSafe(id,if id=="Coolant.Inlet" then 0.6 else nil)
			add(traces); earlyResults[id]={input_seen=inputSeen,before=before,after=after,traces=traces}
			earlyEvidence[id]={input_seen=inputSeen,trace_id=traces[#traces] or "",before_event=before.DR_EventSeq,after_event=after.DR_EventSeq}
		end
		local earlyTrace=d:trace("bootstrap_reachable_interactions","observed",{results=earlyEvidence}); add({earlyTrace})
		local function inputSeen(id:string): boolean return earlyResults[id] and earlyResults[id].input_seen==true end

		local itemRuntimeOk=counts.DR_CarryItem==5 and counts.DR_ItemStation==11 and schemaPresent("Power.FusePickup")
		local powerUsable=protocolPublished and inputSeen("Power.FusePickup")
		local coolantUsable=protocolPublished and inputSeen("Coolant.Inlet")
		local authUsable=protocolPublished and inputSeen("Auth.Scanner.Beta")
		local assemblyUsable=protocolPublished and inputSeen("Assembly.Slot.Coolant")
		cp("d2.power_system",powerUsable and "pass" or "fail","The Power prompt existed and was attempted with real E input, but no initialized gameplay state or response was published.",{interactionTrace,earlyTrace})
		cp("d2.coolant_system",coolantUsable and "pass" or "fail","The Coolant prompt existed and was attempted with real held E input, but no initialized gameplay state or pressure response was published.",{interactionTrace,earlyTrace})
		cp("d2.auth_system",authUsable and "pass" or "fail","The Auth prompt existed and was attempted with real E input, but no initialized gameplay state or rejection response was published.",{interactionTrace,earlyTrace})
		cp("d2.carry_items",itemRuntimeOk and powerUsable and "pass" or "fail","Five carry objects and eleven stations were observed, but a reachable pickup produced no live carry state.",{snapshotTrace,interactionTrace,earlyTrace})
		cp("d2.assembly_system",assemblyUsable and "pass" or "fail","An assembly prompt existed and was attempted independently, but no assembly state or response was available.",{interactionTrace,earlyTrace})

		local doorsOk=counts.DR_AirlockDoor==2 and schemaPresent("Airlock.OuterControl")
		local initialOuterOpen=false
		for _,door in degraded.doors do if door.attributes and door.attributes.DR_DoorId=="Outer" and door.can_collide==false then initialOuterOpen=true end end
		cp("d2.airlock_system",doorsOk and initialOuterOpen and protocolPublished and "pass" or "fail","Both authority doors/control content were observed; the required initial OpenOuter behavior was not established.",{snapshotTrace,interactionTrace})
		local hazardTrace=d:observeHazardWindow(3.2); add({hazardTrace})
		local hazardContentOk=counts.DR_Hazard==1 and counts.DR_SafeZone==1 and schemaPresent("Checkpoint.CoreShelf")
		local hazardRunning=protocolPublished
		cp("d2.hazard_checkpoint",hazardContentOk and hazardRunning and "pass" or "fail","Hazard, safe-zone and checkpoint content were observed over time, but the gameplay phase/checkpoint system never initialized.",{snapshotTrace,interactionTrace,hazardTrace})
		local finalContentOk=schemaPresent("Final.CoreSocket") and schemaPresent("Final.Stabilizer.2")
		cp("d2.final_system",finalContentOk and protocolPublished and "pass" or "fail","Final socket/stabilizer content existed, but the final gameplay system never became live in normal Play.",{snapshotTrace,interactionTrace})
		cp("d2.completion_content",protocolPublished and hudOk and "pass" or "fail","No live completion state or completion interface was available after the candidate bootstrap failure.",{snapshotTrace})

		local state=degraded.state
		local initialOk=degraded.state_present and state.DR_RunStatus=="InProgress" and state.DR_PowerState=="NeedFuse" and state.DR_CoolantPressure==0 and state.DR_AuthState=="Offline" and state.DR_AssemblyProgress==0 and state.DR_AirlockState=="OpenOuter" and state.DR_CheckpointId=="Central"
		cp("d3.initial_state",initialOk and "pass" or "fail","Normal Play reached a live character, but the required public initial gameplay state was absent or incomplete.",{snapshotTrace})
		cp("d3.rejection_rules",authUsable and "pass" or "fail","A reachable wrong-stage Auth action received real E input but produced no public rejection event/state.",{earlyTrace})
		cp("d3.power_rules",powerUsable and "pass" or "fail","Power rule processing was unavailable after a real input at its reachable first-stage prompt.",{earlyTrace})
		cp("d3.coolant_rules",coolantUsable and "pass" or "fail","Coolant rule processing was unavailable after real held input at the inlet.",{earlyTrace})
		cp("d3.auth_rules",authUsable and "pass" or "fail","Authorization rule processing was unavailable after a real wrong-stage scanner input.",{earlyTrace})
		cp("d3.assembly_rules",assemblyUsable and "pass" or "fail","Assembly rule processing was unavailable after a real input at the reachable first slot.",{earlyTrace})
		cp("d3.airlock_rules",doorsOk and initialOuterOpen and protocolPublished and "pass" or "fail","Door collision and protocol state contradicted the required initial OpenOuter interlock state.",{snapshotTrace,interactionTrace})
		cp("d3.hazard_rules",hazardContentOk and hazardRunning and "pass" or "fail","The authority hazard remained without an initialized public phase state during the observation window.",{snapshotTrace,hazardTrace})
		cp("d3.final_order_rules","fail","Normal Play never initialized the prerequisite state machine required to accept and order final stabilizer input.",{t,snapshotTrace,interactionTrace})
		cp("d3.completion_condition","fail","Normal Play never published a completion-capable game state; completion could not occur through player actions.",{t,snapshotTrace})

		cp("d4.restart_midrun","fail","Real R input was observed, but the candidate never initialized a run or published a clean restarted run state.",{rTrace,snapshotTrace})
		cp("d4.systems_to_core","fail","Independent real inputs at Power, Coolant, Auth and Assembly prompts produced no initialized progression to a core.",{earlyTrace})
		cp("d4.airlock_to_checkpoint","fail","The required public run/carry state was absent and the initially colliding outer door prevented a live airlock-to-checkpoint flow.",{snapshotTrace,interactionTrace})
		cp("d4.death_recovery","fail","The hazard/checkpoint lifecycle never initialized in normal Play, so the required death recovery behavior was unavailable.",{snapshotTrace,hazardTrace})
		cp("d4.complete_success_flow","fail","Normal Play remained controllable at the character level, but the candidate bootstrap failure prevented the gameplay flow from starting or completing.",{t,wTrace,earlyTrace,snapshotTrace})
		cp("d4.restart_after_complete","fail","No completion state existed and therefore the required completed-state R lifecycle was unavailable.",{rTrace,snapshotTrace})

		cp("d5.rejection_feedback",authUsable and hudOk and "pass" or "fail","The wrong-stage Auth input produced neither public feedback state nor a visible HUD response.",{earlyTrace,snapshotTrace})
		cp("d5.stage_feedback",powerUsable and hudOk and "pass" or "fail","The reachable first-stage pickup input produced neither live stage state nor visible HUD feedback.",{earlyTrace,snapshotTrace})
		cp("d5.completion_feedback",protocolPublished and hudOk and "pass" or "fail","No completion HUD/feedback content was created in the live PlayClient.",{snapshotTrace})

		for _,id in IDS do if not emitted[id] then cp(id,"fail","Checkpoint was independently adjudicated under the normal-Play bootstrap-failure path.",{t,snapshotTrace}) end end
		return
	end

	local schema=d:schemaSnapshot(); local c=schema.counts
	local schemaOk=c.DR_CentralSpawn==1 and c.DR_GameState==1 and c.DR_Interactable==28 and c.DR_CarryItem==5 and c.DR_ItemStation==11 and c.DR_AirlockDoor==2 and c.DR_Hazard==1 and c.DR_SafeZone==1 and c.DR_HUDField==12 and c.DR_NavNode>=16 and c.DR_NavLink>=15
	cp("d2.world_and_protocol",schemaOk and "pass" or "fail","Live tagged object counts checked after Ready.",oneTrace(d:trace("schema_snapshot",schemaOk and "valid" or "invalid",schema)))
	local s=d:stateMap(); local initialOk=s.DR_RunStatus=="InProgress" and s.DR_PowerState=="NeedFuse" and s.DR_CoolantPressure==0 and s.DR_AuthState=="Offline" and s.DR_AssemblyProgress==0 and s.DR_AirlockState=="OpenOuter" and s.DR_CheckpointId=="Central" and s.DR_CoreInstalled==false
	cp("d3.initial_state",initialOk and "pass" or "fail","Initial live state checked.",oneTrace(d:trace("initial_state",initialOk and "correct" or "incorrect",{})))
	cp("d4.start_to_play","pass","Normal Play entry reached a controllable live character and ready game state.",{t})
	local hud=schema.hud; local hudOk=true; for _,id in {"Objective","Systems","PowerProgress","CoolantPressure","AuthProgress","CarryItem","AssemblyProgress","Airlock","Hazard","Checkpoint","Timer","Feedback"} do local f=hud[id]; if not f or not f.visible or f.w<=0 or f.h<=0 or f.text=="" then hudOk=false end end
	cp("d5.input_and_hud",hudOk and "pass" or "fail","All twelve live HUD fields were checked for visibility, size and text.",oneTrace(d:trace("hud_initial",hudOk and "visible" or "invalid",{hud=hud})))

	-- Necessary invalid actions.
	local ok1,b1,a1,tr1=interact("Auth.Scanner.Beta")
	local reject1=ok1 and a1.DR_AuthScanProgress==0 and a1.DR_LastRejectCode=="WrongStage"
	local ok2,b2,a2,tr2=interact("Airlock.InnerControl")
	local reject2=ok2 and a2.DR_AirlockState=="OpenOuter" and a2.DR_LastEvent=="Airlock.InnerLocked"
	if ok1 and ok2 then cp("d3.rejection_rules",reject1 and reject2 and "pass" or "fail","Wrong-stage scanner and un-equalized inner-door actions were exercised.",{tr1,tr2}) else cp("d3.rejection_rules","inconclusive","Controller did not establish both invalid-action prompt preconditions.",{tr1,tr2}) end
	local feedback=d:stateMap().DR_FeedbackText
	cp("d5.rejection_feedback",ok2 and type(feedback)=="string" and #feedback>0 and "pass" or (ok2 and "fail" or "inconclusive"),"Rejected action feedback was read from live state/HUD.",{tr2})

	local restarted,rts,rb,ra=d:pressR(); add(rts)
	local clean=restarted and ra.DR_PowerState=="NeedFuse" and ra.DR_CoolantPressure==0 and ra.DR_AuthState=="Offline" and ra.DR_AssemblyProgress==0 and ra.DR_CheckpointId=="Central" and ra.DR_DeathCount==0
	cp("d4.restart_midrun",restarted and (clean and "pass" or "fail") or "inconclusive","R input and clean-state result checked.",rts)

	-- Power: wrong breaker resets, then B-C-A and real hold.
	local powerControl=true; local pOk=true; local navFuse,_,a=interact("Power.FusePickup"); powerControl=powerControl and navFuse; pOk=pOk and a.DR_CarryItemId=="PowerFuse"
	local navSocketPower,_,a=interact("Power.FuseSocket"); powerControl=powerControl and navSocketPower; pOk=pOk and a.DR_PowerState=="Breakers" and a.DR_CarryItemId=="None"
	local navWrong,bw,aw=interact("Power.Breaker.A"); local wrongPower=navWrong and aw.DR_PowerBreakerProgress==0 and aw.DR_LastEvent=="Power.BreakerReset"
	powerControl=powerControl and navWrong
	for _,id in {"Power.Breaker.B","Power.Breaker.C","Power.Breaker.A"} do local nav,_,after=interact(id); powerControl=powerControl and nav end
	local navCharge,_,afterCharge=interact("Power.Charger",2.25); powerControl=powerControl and navCharge; pOk=pOk and afterCharge.DR_PowerState=="Complete"
	cp("d2.power_system",powerControl and (pOk and "pass" or "fail") or "inconclusive","Power fuse, breaker and charger content was used in Play.",allTraces)
	cp("d3.power_rules",powerControl and (wrongPower and afterCharge.DR_PowerState=="Complete" and "pass" or "fail") or "inconclusive","Wrong-order reset and B-C-A completion were observed.",allTraces)

	-- Coolant continuous input: stop inside target and lock after stability.
	local navIn,_,afterIn=interact("Coolant.Inlet",4.2)
	local pressure=tonumber(afterIn.DR_CoolantPressure) or -1
	local stable,st=d:waitState("DR_CoolantState",function(v:any) return v=="Stable" end,2.0); add({st})
	local navLock,_,afterLock=interact("Coolant.Lock")
	local coolantControl=navIn and navLock; local coolOk=coolantControl and pressure>=43 and pressure<=58 and stable and afterLock.DR_CoolantState=="Complete"
	cp("d2.coolant_system",coolantControl and (coolOk and "pass" or "fail") or "inconclusive","Inlet, live pressure and lock content exercised.",allTraces)
	cp("d3.coolant_rules",coolantControl and (coolOk and "pass" or "fail") or "inconclusive","Continuous pressure reached the public target window and locked only after stability.",allTraces)

	-- Authorization.
	local authControl=true; for _,id in {"Auth.Controller","Auth.Scanner.Gamma","Auth.Scanner.Alpha","Auth.Scanner.Beta"} do local nav,_,after=interact(id); authControl=authControl and nav end
	local authOk=authControl and d:stateMap().DR_AuthState=="Complete" and d:stateMap().DR_AuthScanProgress==3
	cp("d2.auth_system",authControl and (authOk and "pass" or "fail") or "inconclusive","Authorization controller and three scanners were used.",allTraces)
	cp("d3.auth_rules",authControl and (authOk and "pass" or "fail") or "inconclusive","Gamma-Alpha-Beta completion was observed after an earlier wrong-stage rejection.",allTraces)

	-- Carry and ordered assembly.
	local assemblyControl=true; local assemblyOk=true
	for _,pair in {{"Coolant.CanisterPickup","Assembly.Slot.Coolant"},{"Power.CellPickup","Assembly.Slot.Cell"},{"Auth.TokenPickup","Assembly.Slot.Auth"}} do
		local nav,_,picked=interact(pair[1]); assemblyControl=assemblyControl and nav; assemblyOk=assemblyOk and picked.DR_CarryItemId~="None"
		local nav2,_,installed=interact(pair[2]); assemblyControl=assemblyControl and nav2; assemblyOk=assemblyOk and installed.DR_CarryItemId=="None"
	end
	assemblyOk=assemblyOk and d:stateMap().DR_AssemblyProgress==3 and d:stateMap().DR_AssemblyState=="Complete"
	cp("d2.carry_items",assemblyControl and (assemblyOk and "pass" or "fail") or "inconclusive","Three outputs were physically picked up and installed one at a time.",allTraces)
	cp("d2.assembly_system",assemblyControl and (assemblyOk and "pass" or "fail") or "inconclusive","All three assembly slots and core output were reached.",allTraces)
	cp("d3.assembly_rules",assemblyControl and (assemblyOk and "pass" or "fail") or "inconclusive","Coolant-Cell-Auth ordered assembly and carry clearing were observed.",allTraces)
	local systemsControl=powerControl and coolantControl and authControl and assemblyControl
	cp("d4.systems_to_core",systemsControl and (pOk and coolOk and authOk and assemblyOk and "pass" or "fail") or "inconclusive","Three independently restored systems converged into a completed core assembly.",allTraces)

	local navCore,_,corePicked=interact("Assembly.CorePickup"); local coreCarry=navCore and corePicked.DR_CarryItemId=="RelayCore" and math.abs((d:scene({}).walk_speed or 0)-12)<=0.6
	cp("d5.stage_feedback",navCore and (coreCarry and type(corePicked.DR_FeedbackText)=="string" and #corePicked.DR_FeedbackText>0 and "pass" or "fail") or "inconclusive","Core pickup state and player feedback were live-readable.",allTraces)

	-- Airlock interlock and checkpoint.
	local airControl=true; local airOk=coreCarry
	for _,step in {{"Airlock.OuterControl",nil},{"Airlock.Equalizer",2.25},{"Airlock.InnerControl",nil}} do local nav,_,after=interact(step[1],step[2]); airControl=airControl and nav end
	local doors=d:tagged("DR_AirlockDoor"); local openCount=0; for _,door in doors do if door:IsA("BasePart") and not door.CanCollide then openCount+=1 end end
	airOk=airOk and d:stateMap().DR_AirlockState=="OpenInner" and openCount==1
	cp("d2.airlock_system",airControl and (airOk and "pass" or "fail") or "inconclusive","Outer control, equalizer and inner control were used.",allTraces)
	cp("d3.airlock_rules",airControl and (airOk and "pass" or "fail") or "inconclusive","Equalized OpenInner state and exactly one non-colliding authority door were observed.",allTraces)
	local navShelf,_,shelfState=interact("Checkpoint.CoreShelf"); local shelfOk=navShelf and shelfState.DR_CheckpointId=="CoreShelf" and shelfState.DR_CarryItemId=="None"
	cp("d4.airlock_to_checkpoint",airControl and navShelf and (airOk and shelfOk and "pass" or "fail") or "inconclusive","Core moved through the airlock and activated the shelf checkpoint.",allTraces)

	-- Real Active hazard death, preserved progress, and respawn.
	local deaths=tonumber(d:stateMap().DR_DeathCount) or 0; local active,at=d:waitState("DR_HazardState",function(v:any) return v=="Active" end,7); add({at})
	local walked=false; local wts={}; if active then walked,wts=d:walkToPart(d:onePart("DR_Hazard"),1.2,15); add(wts) end
	local resp,rt=d:waitForRespawn(deaths,12); add({rt}); local post=d:stateMap()
	local contactObserved=(tonumber(post.DR_DeathCount) or 0)>deaths or post.DR_LastEvent=="HazardTriggered.ArcField"
	local deathOk=active and contactObserved and resp and post.DR_CheckpointId=="CoreShelf" and post.DR_AssemblyProgress==3 and post.DR_AirlockState=="OpenInner"
	local hazardVerdict=if not active then "fail" elseif not contactObserved then "inconclusive" elseif deathOk then "pass" else "fail"
	cp("d2.hazard_checkpoint",hazardVerdict,"Active authority hazard and checkpoint respawn were exercised.",allTraces)
	cp("d3.hazard_rules",hazardVerdict,"Active contact increased DeathCount while preserving completed systems.",allTraces)
	cp("d4.death_recovery",hazardVerdict,"Death recovery returned to CoreShelf state without losing progression.",allTraces)

	-- Continue after death, cross only Safe phase, install and stabilize.
	local navRepick,_,repick=interact("Checkpoint.CoreShelf"); local repickOk=navRepick and repick.DR_CarryItemId=="RelayCore"
	local safe,safet=d:waitState("DR_HazardState",function(v:any) return v=="Safe" end,7); add({safet})
	local crossed=false; local crossTs={}; if safe then crossed,crossTs=d:navigate(d:node("HazardExitHub").Position,3,12); add(crossTs) end
	local navSocket,_,socketState=interact("Final.CoreSocket"); local installed=navSocket and socketState.DR_CoreInstalled==true
	cp("d2.final_system",navSocket and (installed and "pass" or "fail") or "inconclusive","Final socket and stabilization area were reached after Safe-window transit.",allTraces)
	local finalOk=installed
	local finalControl=navSocket
	for _,id in {"Final.Stabilizer.2","Final.Stabilizer.1","Final.Stabilizer.3"} do local nav,_,after=interact(id); finalControl=finalControl and nav end
	local final=d:stateMap(); finalOk=finalOk and final.DR_RunStatus=="Completed" and (tonumber(final.DR_FinalTime) or 0)>0
	cp("d3.final_order_rules",finalControl and (finalOk and "pass" or "fail") or "inconclusive","2-1-3 stabilization was executed within the live deadline.",allTraces)
	cp("d3.completion_condition",finalControl and (finalOk and final.DR_CoreInstalled==true and "pass" or "fail") or "inconclusive","Completed appeared only after core installation and three stabilizers.",allTraces)
	cp("d2.completion_content",finalControl and (finalOk and "pass" or "fail") or "inconclusive","Completion state and final time appeared in live Play.",allTraces)
	local fullControl=systemsControl and airControl and navShelf and contactObserved and navRepick and safe and crossed and finalControl
	cp("d4.complete_success_flow",fullControl and (pOk and coolOk and authOk and assemblyOk and airOk and shelfOk and deathOk and repickOk and finalOk and "pass" or "fail") or "inconclusive","A complete player-visible flow reached Completed after recovery from death.",allTraces)
	local finalHud=d:hudMap()
	local objectiveComplete=finalHud.Objective~=nil and string.find(string.lower(finalHud.Objective.text),"complete")~=nil
	local feedbackComplete=finalHud.Feedback~=nil and string.find(string.lower(finalHud.Feedback.text),"complete")~=nil
	local completeHud=objectiveComplete or feedbackComplete
	cp("d5.completion_feedback",finalOk and (completeHud and "pass" or "fail") or "inconclusive","Completion HUD and final feedback were inspected.",oneTrace(d:trace("hud_completed",completeHud and "visible" or "missing",{hud=finalHud})))

	local hsync=d:hudMap(); local syncOk=hsync.Systems and string.find(hsync.Systems.text,"Complete")~=nil and hsync.AssemblyProgress and string.find(hsync.AssemblyProgress.text,"3/3")~=nil
	cp("d5.hud_state_sync",finalOk and (syncOk and "pass" or "fail") or "inconclusive","HUD system and assembly text was cross-checked against completed engine state.",oneTrace(d:trace("hud_state_sync",syncOk and "matched" or "mismatch",{hud=hsync})))
	local r2,r2ts,_,r2after=d:pressR(); add(r2ts); local r2clean=r2 and r2after.DR_RunStatus=="InProgress" and r2after.DR_AssemblyProgress==0 and r2after.DR_DeathCount==0 and r2after.DR_CheckpointId=="Central" and r2after.DR_FinalTime==0
	cp("d4.restart_after_complete",r2clean and "pass" or (r2 and "fail" or "inconclusive"),"Completed-state R reset was observed.",r2ts)

	for _,id in IDS do if not emitted[id] then cp(id,"not_run","Formal suite omitted this checkpoint due to an evaluator defect.",{}) end end
end
