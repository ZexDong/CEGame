--!strict
-- Dockline Dispatch formal journey. All actuation goes through ordinary OS input.
local function runFormalSuite(Driver:any,emitCheckpoint:any)
	local d=Driver.new()
	local emitted:{[string]:boolean}={}
	local function cp(id:string,status:string,detail:string,traces:{string}) emitted[id]=true; emitCheckpoint(id,status,detail,traces) end
	local IDS={
		"d2.world_and_protocol","d2.package_processing","d2.routing_and_recovery","d2.pallet_checkpoint","d2.hazard_and_final",
		"d3.initial_and_rejection","d3.processing_routing_rules","d3.pallet_hazard_rules","d3.final_rules",
		"d4.start_and_restart","d4.packages_to_staging","d4.complete_success_flow",
		"d5.input_and_hud","d5.stage_and_rejection_feedback","d5.completion_feedback",
	}
	local allTraces:{string}={}
	local function add(values:{string}) for _,v in values do table.insert(allTraces,v) end end
	local function interact(id:string,hold:number?): (boolean,{[string]:any},{[string]:any},string)
		local ok,traces,before,after=d:interact(id,hold); add(traces); return ok,before,after,traces[#traces] or ""
	end

	local ready,readyTrace=d:waitReady(12); add({readyTrace})
	if not ready then
		local snapshot=d:degradedSnapshot(); local snapshotTrace=d:trace("bootstrap_failure_snapshot","observed",d:compactDegradedSnapshot(snapshot))
		local schema=d:interactionSchema({"Manifest.StartShift","Inbound.Pickup.Glass","Inspection.Scanner","Process.FragileWrap","Conveyor.Load","Pallet.SealPickup","Truck.SealSocket","Final.Code.2"})
		local schemaTrace=d:trace("bootstrap_failure_interactions","observed",d:compactInteractionSchema(schema))
		local wObserved,wTrace=d:pulseKey(Enum.KeyCode.W,0.45); local rObserved,rTrace=d:pulseKey(Enum.KeyCode.R,0.15)
		local eObserved,eTraces=d:attemptInteractionSafe("Manifest.StartShift"); local eTrace=eTraces[#eTraces] or schemaTrace
		local hazardTrace=d:observeHazardWindow(7.5)
		local c=snapshot.counts; local protocolPublished=snapshot.workspace_ready==true and snapshot.contract_version=="dockline-dispatch-v1"
		local worldOk=protocolPublished and c.DD_GameState==1 and c.DD_Interactable==30 and c.DD_CarryItem==4 and c.DD_Package==3 and c.DD_HUDField==13
		local hudCount=0; for _ in snapshot.hud do hudCount+=1 end
		local hudOk=c.DD_HUDField==13 and hudCount==13
		cp("d2.world_and_protocol",worldOk and "pass" or "fail","Live Play checked the required public world, protocol and tagged objects.",{readyTrace,snapshotTrace,schemaTrace})
		cp("d4.start_and_restart","fail","A controllable PlayClient existed, but the candidate never published a playable initial state or resettable run.",{readyTrace,wTrace,rTrace,snapshotTrace})
		cp("d5.input_and_hud",wObserved and hudOk and "pass" or "fail","Real W input and the thirteen live HUD fields were checked.",{wTrace,snapshotTrace})
		for _,id in {"d2.package_processing","d2.routing_and_recovery","d2.pallet_checkpoint","d2.hazard_and_final","d3.initial_and_rejection","d3.processing_routing_rules","d3.pallet_hazard_rules","d3.final_rules","d4.packages_to_staging","d4.complete_success_flow"} do cp(id,"fail","The required gameplay system was absent because candidate bootstrap failed in live Play.",{snapshotTrace,schemaTrace,hazardTrace}) end
		cp("d5.stage_and_rejection_feedback",eObserved and hudOk and protocolPublished and "pass" or "fail","Live stage/rejection feedback was checked after real input.",{eTrace,snapshotTrace})
		cp("d5.completion_feedback",protocolPublished and hudOk and "pass" or "fail","No completion content was created in live Play.",{snapshotTrace})
		for _,id in IDS do if not emitted[id] then cp(id,"fail","Checkpoint independently adjudicated under candidate bootstrap failure.",{snapshotTrace}) end end
		return
	end

	local schema=d:schemaSnapshot(); local c=schema.counts
	local schemaOk=c.DD_CentralSpawn==1 and c.DD_GameState==1 and c.DD_Interactable==30 and c.DD_CarryItem==4 and c.DD_Package==3 and c.DD_ItemStation==13 and c.DD_StagingBay==3 and c.DD_Hazard==1 and c.DD_SafeZone==1 and c.DD_HUDField==13 and c.DD_NavNode>=18 and c.DD_NavLink>=20
	cp("d2.world_and_protocol",schemaOk and "pass" or "fail","Required live tagged object counts and protocol were checked.",{d:trace("schema_snapshot",schemaOk and "valid" or "invalid",schema)})
	local s=d:stateMap(); local initialOk=s.DD_RunStatus=="AwaitingStart" and s.DD_CarryItemId=="None" and s.DD_GlassState=="Inbound" and s.DD_ColdState=="Inbound" and s.DD_CipherState=="Inbound" and s.DD_StagedCount==0 and s.DD_PalletProgress==0 and s.DD_CheckpointId=="Start"
	local initialTrace=d:trace("initial_state",initialOk and "correct" or "incorrect",{})
	local hud=schema.hud; local hudOk=true; for _,id in {"Objective","Shift","Packages","CarryItem","Scanner","Auth","Routing","Conveyor","Pallet","Hazard","Checkpoint","Timer","Feedback"} do local f=hud[id]; if not f or not f.visible or f.w<=0 or f.h<=0 or f.text=="" then hudOk=false end end
	cp("d5.input_and_hud",hudOk and "pass" or "fail","All thirteen live HUD fields were checked for visibility, size and text.",{d:trace("hud_initial",hudOk and "visible" or "invalid",{hud=hud})})

	local badOk,_,badAfter,badTrace=interact("Inspection.Scanner")
	local rejectionOk=badOk and badAfter.DD_LastRejectCode~="None" and badAfter.DD_RunStatus=="AwaitingStart"
	local rejectionFeedback=badOk and type(badAfter.DD_FeedbackText)=="string" and #badAfter.DD_FeedbackText>0
	cp("d3.initial_and_rejection",badOk and (initialOk and rejectionOk and "pass" or "fail") or "inconclusive","Initial state and one wrong-stage rejection were checked as one rules checkpoint.",{initialTrace,badTrace})

	local startOk,_,started,startTrace=interact("Manifest.StartShift")
	local startState=startOk and started.DD_RunStatus=="InProgress"
	local rOk,rTraces,_,rAfter=d:pressR(); add(rTraces)
	local clean=rOk and rAfter.DD_RunStatus=="AwaitingStart" and rAfter.DD_GlassState=="Inbound" and rAfter.DD_StagedCount==0 and rAfter.DD_PalletProgress==0 and rAfter.DD_DeathCount==0
	local start2,_,started2,start2Trace=interact("Manifest.StartShift")
	local manifestOk=startState and start2 and started2.DD_RunStatus=="InProgress"
	cp("d4.start_and_restart",startOk and rOk and start2 and (manifestOk and clean and "pass" or "fail") or "inconclusive","Play start, mid-run R cleanup and a fresh second start were checked.",{readyTrace,startTrace,rTraces[#rTraces] or "",start2Trace})

	local staged:{[string]:boolean}={}
	local packageSpecs={
		{pid="GlassCrate",pickup="Inbound.Pickup.Glass",process={"Process.FragileWrap"},route={false,true}},
		{pid="ColdCase",pickup="Inbound.Pickup.Cold",process={"Process.ColdCondition"},route={true,true}},
		{pid="CipherBox",pickup="Inbound.Pickup.Cipher",process={"Secure.AuthStart","Secure.Key.Delta","Secure.Key.Alpha","Secure.Key.Charlie"},route={false,false}},
	}
	local contentControl=manifestOk; local scannerOk=true; local processOk=true; local measureOk=true; local routingOk=true
	local packageEntryControl=false; local rootPackageFailure=false
	local holdInterrupted=false; local authReset=false; local labelRejected=false
	local recoveryControl=false; local recoveryOk=false; local rejectTrace=""; local recoverTrace=""
	for _,spec in packageSpecs do
		local okPick,_,pick=interact(spec.pickup); contentControl=contentControl and okPick; scannerOk=scannerOk and pick.DD_CarryItemId==spec.pid
		if spec.pid=="GlassCrate" then
			packageEntryControl=okPick
			if okPick and pick.DD_CarryItemId~="GlassCrate" then
				-- The controller established the public semantic prerequisite and
				-- delivered real E. Do not spend minutes visiting disabled downstream
				-- prompts after the candidate failed the first mandatory transition.
				rootPackageFailure=true; processOk=false; measureOk=false; routingOk=false; recoveryOk=false
				break
			end
		end
		local okScan,_,scan=interact("Inspection.Scanner"); contentControl=contentControl and okScan; scannerOk=scannerOk and scan.DD_LastEvent=="Package.Scanned."..spec.pid
		if spec.pid=="GlassCrate" then
			local early,_,earlyAfter=interact("Process.FragileWrap",0.4); holdInterrupted=early and earlyAfter.DD_ProcessComplete~=true and earlyAfter.DD_LastEvent=="Process.WrapInterrupted"
			local ok,_,after=interact("Process.FragileWrap"); contentControl=contentControl and ok; processOk=processOk and after.DD_GlassState=="Processed"
		elseif spec.pid=="ColdCase" then
			local ok,_,after=interact("Process.ColdCondition"); contentControl=contentControl and ok; processOk=processOk and after.DD_ColdState=="Processed"
			local badLabel,_,badLabelAfter=interact("Label.Printer"); labelRejected=badLabel and badLabelAfter.DD_LastRejectCode=="WrongStage" and badLabelAfter.DD_ColdState=="Processed"
		else
			local authStart=select(1,interact("Secure.AuthStart")); local wrong,_,wrongAfter=interact("Secure.Key.Alpha"); authReset=wrong and wrongAfter.DD_AuthProgress==0 and wrongAfter.DD_LastEvent=="Secure.Reset"
			contentControl=contentControl and authStart and wrong
			for _,id in {"Secure.Key.Delta","Secure.Key.Alpha","Secure.Key.Charlie"} do local ok=select(1,interact(id)); contentControl=contentControl and ok end
			processOk=processOk and d:stateMap().DD_CipherState=="Processed"
		end
		local okScale,_,scaled=interact("Measure.Scale"); local okLabel,_,labeled=interact("Label.Printer"); contentControl=contentControl and okScale and okLabel; measureOk=measureOk and scaled.DD_LastEvent=="Package.Weighed."..spec.pid and labeled.DD_LastEvent=="Package.Labeled."..spec.pid
		if spec.pid=="GlassCrate" then
			-- Cover wrong-route rejection and recovery inside the one successful
			-- package journey, avoiding a second full package run.
			local state=d:stateMap(); if state.DD_DiverterOne~="Right" then contentControl=select(1,interact("Routing.Diverter.One")) and contentControl end
			state=d:stateMap(); if state.DD_DiverterTwo~="Right" then contentControl=select(1,interact("Routing.Diverter.Two")) and contentControl end
			local wrongLoad=select(1,interact("Conveyor.Load")); local wrongDispatch=select(1,interact("Conveyor.Dispatch"))
			local rejected,rejectedTrace=d:waitState("DD_GlassState",function(v:any) return v=="Rejected" end,3.2); add({rejectedTrace}); rejectTrace=rejectedTrace
			local recoveredInput,_,recovered,recoveredTrace=interact("Reject.Return"); recoverTrace=recoveredTrace
			recoveryControl=wrongLoad and wrongDispatch and recoveredInput
			recoveryOk=rejected and recoveredInput and recovered.DD_CarryItemId=="GlassCrate" and (tonumber(recovered.DD_RejectCount) or 0)>=1
			contentControl=contentControl and recoveryControl
			state=d:stateMap(); if state.DD_DiverterOne~="Left" then contentControl=select(1,interact("Routing.Diverter.One")) and contentControl end
			state=d:stateMap(); if state.DD_DiverterTwo~="Right" then contentControl=select(1,interact("Routing.Diverter.Two")) and contentControl end
		else
			local state=d:stateMap(); if (state.DD_DiverterOne=="Right")~=spec.route[1] then contentControl=select(1,interact("Routing.Diverter.One")) and contentControl end
			state=d:stateMap(); if (state.DD_DiverterTwo=="Right")~=spec.route[2] then contentControl=select(1,interact("Routing.Diverter.Two")) and contentControl end
		end
		local routeState=d:stateMap(); local routeConfigured=(routeState.DD_DiverterOne=="Right")==spec.route[1] and (routeState.DD_DiverterTwo=="Right")==spec.route[2]
		local okLoad=select(1,interact("Conveyor.Load")); local okDispatch=select(1,interact("Conveyor.Dispatch")); contentControl=contentControl and okLoad and okDispatch
		local stateKey=if spec.pid=="GlassCrate" then "DD_GlassState" elseif spec.pid=="ColdCase" then "DD_ColdState" else "DD_CipherState"
		local arrived,arriveTrace=d:waitState(stateKey,function(v:any) return v=="Staged" end,3.2); add({arriveTrace}); staged[spec.pid]=arrived; routingOk=routingOk and routeConfigured and arrived
	end
	-- Once the evaluator has started the shift, reached the first semantic pickup
	-- and sent acknowledged E input, a missing candidate state transition is a
	-- gameplay failure. It must not turn every dependent checkpoint inconclusive.
	local journeyControl=manifestOk and packageEntryControl
	cp("d2.package_processing",journeyControl and (scannerOk and processOk and measureOk and "pass" or "fail") or "inconclusive","Three package pickup, scan, specialized process, weigh and label chains were checked.",allTraces)
	cp("d3.processing_routing_rules",journeyControl and (holdInterrupted and authReset and labelRejected and routingOk and recoveryOk and "pass" or "fail") or "inconclusive","Processing, label, route and recovery rules were checked as one gameplay checkpoint.",allTraces)
	cp("d2.routing_and_recovery",journeyControl and (routingOk and recoveryOk and "pass" or "fail") or "inconclusive","Three semantic routes plus one wrong-route recovery were exercised.",allTraces)
	cp("d4.packages_to_staging",journeyControl and (routingOk and "pass" or "fail") or "inconclusive","All three independent package chains reached staging.",allTraces)
	if rootPackageFailure then
		local deaths=tonumber(d:stateMap().DD_DeathCount) or 0
		local active,activeTrace=d:waitState("DD_HazardState",function(v:any) return v=="Active" end,7.5); add({activeTrace})
		local contact=false; local contactTraces={}; if active then contact,contactTraces=d:walkToPart(d:onePart("DD_Hazard"),1.2,15); add(contactTraces) end
		local resp,respTrace=d:waitForRespawn(deaths,12); add({respTrace})
		local post=d:stateMap(); local hazardObserved=active and contact and resp and (tonumber(post.DD_DeathCount) or 0)>deaths
		local feedbackNow=post.DD_FeedbackText
		local rootDetail="Acknowledged E at the first semantic package pickup produced no carry transition; downstream mandatory segments were therefore unavailable."
		cp("d2.pallet_checkpoint","fail",rootDetail,allTraces)
		cp("d2.hazard_and_final","fail",rootDetail.." Hazard was checked independently (observed="..tostring(hazardObserved)..").",allTraces)
		cp("d3.pallet_hazard_rules","fail",rootDetail.." Hazard was checked independently (observed="..tostring(hazardObserved)..").",allTraces)
		cp("d3.final_rules","fail",rootDetail,allTraces)
		cp("d4.complete_success_flow","fail",rootDetail,allTraces)
		local stageFeedback=rejectionFeedback and type(feedbackNow)=="string" and #feedbackNow>0
		cp("d5.stage_and_rejection_feedback",stageFeedback and "pass" or "fail","Rejected-action and live stage feedback were checked before the short-circuit.",allTraces)
		cp("d5.completion_feedback","fail","Completion feedback could not be produced because the acknowledged first mandatory pickup did not transition candidate state.",allTraces)
		for _,id in IDS do if not emitted[id] then cp(id,"not_run","Formal evaluator omitted this checkpoint.",{}) end end
		return
	end

	local fullControl=contentControl
	local cipherPickup=select(1,interact("Staging.Pickup.A")); fullControl=fullControl and cipherPickup
	local wrongSlotOk,_,wrongSlot,wrongSlotTrace=interact("Pallet.Slot.Glass"); local wrongRejected=wrongSlotOk and wrongSlot.DD_PalletProgress==0 and wrongSlot.DD_CarryItemId=="CipherBox"
	local correctCipher=select(1,interact("Pallet.Slot.Cipher")); fullControl=fullControl and correctCipher
	for _,pair in {{"Staging.Pickup.B","Pallet.Slot.Glass"},{"Staging.Pickup.C","Pallet.Slot.Cold"}} do for _,id in pair do fullControl=select(1,interact(id)) and fullControl end end
	local palletOrderOk=wrongRejected
	local pallet=d:stateMap(); local palletOk=pallet.DD_PalletProgress==3 and pallet.DD_PalletState=="Complete"
	local sealPick=select(1,interact("Pallet.SealPickup")); local shelfOk,_,shelf,shelfTrace=interact("Checkpoint.SealShelf"); local checkpointOk=sealPick and shelfOk and shelf.DD_CheckpointId=="SealShelf"
	cp("d2.pallet_checkpoint",journeyControl and (palletOk and checkpointOk and "pass" or "fail") or "inconclusive","Ordered pallet assembly, seal pickup and checkpoint were checked together.",allTraces)
	local deaths=tonumber(d:stateMap().DD_DeathCount) or 0; local active,activeTrace=d:waitState("DD_HazardState",function(v:any) return v=="Active" end,7.5); add({activeTrace}); local contact=false; local contactTraces={}; if active then contact,contactTraces=d:walkToPart(d:onePart("DD_Hazard"),1.2,15); add(contactTraces) end
	local resp,respTrace=d:waitForRespawn(deaths,12); add({respTrace}); local post=d:stateMap(); local deathObserved=(tonumber(post.DD_DeathCount) or 0)>deaths; local deathOk=active and deathObserved and resp and post.DD_CheckpointId=="SealShelf" and post.DD_PalletProgress==3
	local hazardVerdict=if not active then "fail" elseif deathObserved then "pass" elseif contact then "fail" else "inconclusive"
	local recoveryVerdict=if not checkpointOk then "inconclusive" elseif not deathObserved then (contact and "fail" or "inconclusive") elseif deathOk then "pass" else "fail"
	local repick=select(1,interact("Checkpoint.SealShelf")); local safe,safeTrace=d:waitState("DD_HazardState",function(v:any) return v=="Safe" end,7.5); add({safeTrace})
	local socket=false; if safe then socket=select(1,interact("Truck.SealSocket")) end; local crossed=socket
	local wrongCode,_,wrongAfter,wrongTrace=interact("Final.Code.4"); local wrongCodeOk=wrongCode and wrongAfter.DD_FinalCodeProgress==0
	local finalControl=repick and safe and crossed and socket
	for _,id in {"Final.Code.2","Final.Code.4","Final.Code.1"} do finalControl=select(1,interact(id)) and finalControl end
	local final=d:stateMap(); local completed=final.DD_RunStatus=="Completed" and final.DD_SealInstalled==true and (tonumber(final.DD_FinalTime) or 0)>0
	local hazardControl=active and (contact or deathObserved)
	cp("d2.hazard_and_final",journeyControl and hazardControl and (hazardVerdict=="pass" and completed and "pass" or "fail") or "inconclusive","Physical hazard behavior and the final seal/code completion were checked.",allTraces)
	cp("d3.pallet_hazard_rules",journeyControl and hazardControl and (palletOrderOk and hazardVerdict=="pass" and checkpointOk and deathOk and "pass" or "fail") or "inconclusive","Wrong pallet order, hazard death and checkpoint preservation were checked together.",allTraces)
	cp("d3.final_rules",journeyControl and (wrongCodeOk and completed and "pass" or "fail") or "inconclusive","Wrong-code reset, 2-4-1 order and guarded completion were checked.",{wrongTrace})
	cp("d4.complete_success_flow",journeyControl and hazardControl and (routingOk and palletOk and checkpointOk and deathOk and completed and "pass" or "fail") or "inconclusive","One full visible package-to-dispatch journey, including death recovery, was attempted.",allTraces)
	local finalHud=d:hudMap(); local completionHud=finalHud.Feedback and string.find(string.lower(finalHud.Feedback.text),"complete")~=nil
	local syncHud=d:hudMap(); local syncOk=syncHud.Pallet and string.find(syncHud.Pallet.text,"3/3")~=nil and syncHud.Shift and string.find(syncHud.Shift.text,"Completed")~=nil
	local finalFeedback=type(final.DD_FeedbackText)=="string" and #final.DD_FeedbackText>0
	cp("d5.stage_and_rejection_feedback",badOk and (rejectionFeedback and finalFeedback and "pass" or "fail") or "inconclusive","Rejected action and later stage feedback were checked in live HUD/state.",allTraces)
	cp("d5.completion_feedback",journeyControl and (completed and completionHud and syncOk and "pass" or "fail") or "inconclusive","Completion feedback and completed-state HUD synchronization were inspected.",{d:trace("hud_completed",completionHud and "visible" or "missing",{hud=finalHud}),d:trace("hud_state_sync",syncOk and "matched" or "mismatch",{hud=syncHud})})
	for _,id in IDS do if not emitted[id] then cp(id,"not_run","Formal evaluator omitted this checkpoint.",{}) end end
end
