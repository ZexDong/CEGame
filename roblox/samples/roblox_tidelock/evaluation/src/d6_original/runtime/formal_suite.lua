--!strict
-- One bounded Tide Lock formal Play run. Candidate-caused blocking is recorded only
-- for directly dependent checkpoints; actuator uncertainty remains inconclusive.

local function runFormalSuite(Driver: any, emitCheckpoint: any)
	local driver = Driver.new()
	local emitted: { [string]: boolean } = {}
	local allDynamic = {
		"d2.hub_and_three_sectors", "d2.routing_system_usable", "d2.pressure_system_usable",
		"d2.core_transfer_system_usable", "d2.checkpoint_and_hazards_usable", "d2.final_controls_usable",
		"d2.failure_retry_content_usable", "d2.restart_and_reopen_content", "d2.hud_content_complete",
		"d2.world_feedback_content", "d3.routing_correct_order", "d3.routing_rejections",
		"d3.pump_wave_and_safe_lock", "d3.pump_reject_and_reset", "d3.core_pickup_carry_install",
		"d3.hazard_phase_damage_rules", "d3.death_checkpoint_preservation", "d3.final_gate_and_order",
		"d3.final_timeout_and_retry", "d3.completion_prerequisites_and_timer",
		"d4.entry_to_active_play", "d4.complete_success_flow", "d4.failure_retry_flow",
		"d4.death_respawn_flow", "d4.restart_across_states", "d4.reopen_clean_session",
		"d5.hud_visible_readable_synced", "d5.world_displays_and_gauges", "d5.interactions_discoverable",
		"d5.rejection_and_failure_feedback", "d5.result_overlays_and_retry_button",
	}

	local function record(id: string, status: string, detail: string, traces: { string })
		if emitted[id] then return end
		emitted[id] = true
		emitCheckpoint(id, status, detail, traces)
	end

	local function mergedTraces(...: { string }): { string }
		local merged = {}
		for _, list in { ... } do
			for _, traceId in list do table.insert(merged, traceId) end
		end
		return merged
	end

	local function verdict(id: string, condition: boolean, detail: string, traces: { string })
		record(id, if condition then "pass" else "fail", detail, traces)
	end

	local function controllerDependent(id: string, established: boolean, condition: boolean, detail: string, traces: { string })
		if not established then
			record(id, "inconclusive", "controller did not establish physical precondition: " .. detail, traces)
		else verdict(id, condition, detail, traces) end
	end

	local function candidateBlocked(id: string, blocked: boolean, detail: string, traces: { string })
		if blocked then record(id, "fail", "candidate world blocked the documented prerequisite: " .. detail, traces)
		else record(id, "inconclusive", "navigation did not establish prerequisite and no candidate blocker was proven: " .. detail, traces) end
	end

	local function eventChanged(before: { [string]: any }, after: { [string]: any }, expected: string): boolean
		return type(before.TL_EventSerial) == "number" and type(after.TL_EventSerial) == "number"
			and after.TL_EventSerial > before.TL_EventSerial and after.TL_LastEvent == expected
	end

	local function hudAllVisible(hud: { [string]: any }): boolean
		for _, role in {
			"Objective", "Timer", "Feedback", "RoutingStatus", "RoutingOrder", "PressureStatus",
			"GaugePort", "GaugeStarboard", "CoreStatus", "FinalStatus",
		} do
			if not hud[role] or hud[role].visible ~= true or type(hud[role].text) ~= "string" or hud[role].text == "" then return false end
		end
		return true
	end

	local function worldHasText(part: BasePart): boolean
		for _, descendant in part:GetDescendants() do
			if descendant:IsA("TextLabel") and descendant.Text ~= "" then return true end
		end
		return false
	end

	local function waitEventVisible(expectedEvent: string, timeout: number): (boolean, string)
		local deadline = os.clock() + timeout
		repeat
			local state = driver:playerState()
			local hud = driver:hudMap()
			if state.TL_LastEvent == expectedEvent and hud.Feedback and hud.Feedback.visible
				and string.find(string.upper(hud.Feedback.text), string.upper(tostring(state.TL_FeedbackText)), 1, true) then
				return true, driver:trace("feedback_sync", "visible", { expected_event = expectedEvent })
			end
			task.wait(0.05)
		until os.clock() >= deadline
		return false, driver:trace("feedback_sync", "not_visible", { expected_event = expectedEvent })
	end

	local function feedbackVisibleFor(expectedEvent: string, duration: number): (boolean, string)
		local started = os.clock()
		repeat
			local state = driver:playerState()
			local hud = driver:hudMap()
			local feedback = hud.Feedback
			if state.TL_LastEvent ~= expectedEvent or not feedback or feedback.visible ~= true
				or type(feedback.text) ~= "string" or feedback.text == ""
				or not string.find(string.upper(feedback.text), string.upper(tostring(state.TL_FeedbackText)), 1, true) then
				return false, driver:trace("feedback_duration", "lost", { expected_event = expectedEvent, elapsed = os.clock() - started })
			end
			task.wait(0.05)
		until os.clock() - started >= duration
		return true, driver:trace("feedback_duration", "held", { expected_event = expectedEvent, duration = duration })
	end

	print("TIDE_LOCK_TRACK_START startup")
	local ready, readyTrace = driver:waitReady(12)
	if not ready then
		record("d4.entry_to_active_play", "fail", "candidate did not reach documented ready state in 12 seconds", { readyTrace })
		for _, id in allDynamic do
			if not emitted[id] then record(id, "fail", "candidate never reached playable startup prerequisite", { readyTrace }) end
		end
		return
	end

	local schemaOk, schemaTrace, schemaProblems = driver:runtimeSchema()
	local initialState = driver:playerState()
	local initialHud = driver:hudMap()
	local initialTrace = driver:trace("initial_state", "observed", { schema_problems = schemaProblems })
	local initialCorrect = driver:cleanState(initialState)
	local inputOk = true
	local inputTraces = {}
	for _, key in { Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.A, Enum.KeyCode.D } do
		local character, _, root = driver:character()
		local before = root.Position
		table.insert(inputTraces, driver:press(key, 0.3))
		local afterCharacter, _, afterRoot = driver:character()
		inputOk = inputOk and afterCharacter == character
			and Vector3.new(afterRoot.Position.X - before.X, 0, afterRoot.Position.Z - before.Z).Magnitude > 0.2
	end
	local _, _, jumpRoot = driver:character()
	local baseY = jumpRoot.Position.Y
	local jumpInput = driver:press(Enum.KeyCode.Space, 0.1)
	local maxRise = 0
	local jumpDeadline = os.clock() + 1.2
	while os.clock() < jumpDeadline do maxRise = math.max(maxRise, jumpRoot.Position.Y - baseY); task.wait(0.03) end
	table.insert(inputTraces, jumpInput)
	local mouseOk, mouseTrace = driver:mouseLook(); table.insert(inputTraces, mouseTrace)
	inputOk = inputOk and maxRise > 0.8 and mouseOk
	verdict("d4.entry_to_active_play", initialCorrect and inputOk,
		"ready, clean initial state, WASD, jump and mouse camera must form a playable entry", mergedTraces({ readyTrace, initialTrace }, inputTraces))

	local timerTextA = if initialHud.Timer then initialHud.Timer.text else ""
	task.wait(0.8)
	local laterHud = driver:hudMap()
	local timerTextB = if laterHud.Timer then laterHud.Timer.text else ""
	local hudTrace = driver:trace("hud_initial", "observed", { timer_before = timerTextA, timer_after = timerTextB })
	verdict("d2.hud_content_complete", hudAllVisible(initialHud), "all ten public HUD roles must appear in live play", { initialTrace, hudTrace })
	verdict("d5.hud_visible_readable_synced", hudAllVisible(initialHud) and timerTextA ~= timerTextB
		and string.find(initialHud.RoutingStatus.text, "0/3", 1, true) ~= nil
		and string.find(string.upper(initialHud.FinalStatus.text), "LOCKED", 1, true) ~= nil,
		"HUD fields must be visible, readable, advancing, and synchronized with initial engine state", { initialTrace, hudTrace })

	local orderDisplay = driver:onePart("TL_OrderDisplay")
	local portPump = driver:semantic("Pump.Port")
	local starboardPump = driver:semantic("Pump.Starboard")
	local displaysOk = worldHasText(orderDisplay) and worldHasText(portPump) and worldHasText(starboardPump)
	local displayTrace = driver:trace("world_displays", if displaysOk then "present" else "missing", {
		order = driver:targetSnapshot(orderDisplay), port = driver:targetSnapshot(portPump), starboard = driver:targetSnapshot(starboardPump),
	})
	verdict("d5.world_displays_and_gauges", displaysOk, "order board and both physical pump displays must exist in live play", { displayTrace })

	-- Final gate is reachable independently and must reject an early console interaction.
	local console = driver:semantic("Final.Console")
	local consoleDelivered, consoleTrace, consoleBefore, consoleAfter = driver:interact(console)
	local earlyLeft = driver:semantic("Final.Left")
	local leftLockedDelivered, leftLockedTrace, leftLockedBefore, leftLockedAfter = driver:interact(earlyLeft)
	local earlyRight = driver:semantic("Final.Right")
	local rightLockedDelivered, rightLockedTrace, rightLockedBefore, rightLockedAfter = driver:interact(earlyRight)
	local earlyFinalTraces = { consoleTrace, leftLockedTrace, rightLockedTrace }
	local earlyFinalOk = consoleDelivered and leftLockedDelivered and rightLockedDelivered
		and consoleAfter.TL_FinalStage == "Locked" and leftLockedAfter.TL_FinalStage == "Locked" and rightLockedAfter.TL_FinalStage == "Locked"
		and eventChanged(consoleBefore, consoleAfter, "FinalNotReady")
		and eventChanged(leftLockedBefore, leftLockedAfter, "FinalNotReady")
		and eventChanged(rightLockedBefore, rightLockedAfter, "FinalNotReady")
	controllerDependent("d2.final_controls_usable", consoleDelivered and leftLockedDelivered and rightLockedDelivered, earlyFinalOk,
		"both final levers and Final.Console must be normally reachable and reject while locked", earlyFinalTraces)
	local earlyFeedback, earlyFeedbackTrace = feedbackVisibleFor("FinalNotReady", 1.5)
	local feedbackOk = earlyFeedback
	local feedbackTraces = { earlyFeedbackTrace }
	-- The final controls live in their own sector.  Every later sector probe
	-- must begin from a fresh Central spawn, otherwise a wall between Final and
	-- another sector would be incorrectly attributed to the destination system.
	local postFinalRestart, postFinalRestartTrace, _, postFinalAfter = driver:restart()
	local postFinalClean = postFinalRestart and driver:cleanState(postFinalAfter)

	print("TIDE_LOCK_TRACK_START negative_and_restart")
	local nodes = {}
	local ordered = {}
	for _, node in driver:parts("TL_RoutingNode") do
		local id = node:GetAttribute("TL_RoutingId")
		local index = node:GetAttribute("TL_OrderIndex")
		if type(id) == "string" and type(index) == "number" then nodes[id] = node; ordered[index] = node end
	end
	local first = ordered[1]
	local second = ordered[2]
	local third = ordered[3]
	local wrong = third or second
	local routingSetup = postFinalClean and first ~= nil and second ~= nil and third ~= nil and wrong ~= nil
	local routingTraces = { displayTrace }
	local wrongOk, duplicateOk, secondWrongOk = false, false, false
	local firstOk, allRoutingOk = false, false
	local routingBlocked = false
	if routingSetup and postFinalClean then
		local deliveredWrong, wrongTrace, wrongBefore, wrongAfter = driver:interact(wrong)
		table.insert(routingTraces, wrongTrace)
		routingBlocked = routingBlocked or driver:navigationBlocked()
		wrongOk = deliveredWrong and wrongAfter.TL_RoutingProgress == 0 and wrongAfter.TL_RoutingNext == first:GetAttribute("TL_RoutingId")
			and eventChanged(wrongBefore, wrongAfter, "RoutingWrongOrder")
		local wrongFeedback, wrongFeedbackTrace = feedbackVisibleFor("RoutingWrongOrder", 1.5)
		table.insert(routingTraces, wrongFeedbackTrace)
		table.insert(feedbackTraces, wrongFeedbackTrace)
		feedbackOk = feedbackOk and wrongFeedback
		local firstColor, firstMaterial = first.Color, first.Material
		local deliveredFirst, firstTrace, firstBefore, firstAfter = driver:interact(first)
		table.insert(routingTraces, firstTrace)
		routingBlocked = routingBlocked or driver:navigationBlocked()
		firstOk = deliveredFirst and firstAfter.TL_RoutingProgress == 1 and first:GetAttribute("TL_Activated") == true
			and (first.Color ~= firstColor or first.Material ~= firstMaterial) and eventChanged(firstBefore, firstAfter, "RoutingAccepted")
		local deliveredDuplicate, duplicateTrace, duplicateBefore, duplicateAfter = driver:interact(first)
		table.insert(routingTraces, duplicateTrace)
		routingBlocked = routingBlocked or driver:navigationBlocked()
		duplicateOk = deliveredDuplicate and duplicateAfter.TL_RoutingProgress == duplicateBefore.TL_RoutingProgress
			and eventChanged(duplicateBefore, duplicateAfter, "RoutingAlreadyActive")
		local deliveredThirdWrong, thirdWrongTrace, thirdWrongBefore, thirdWrongAfter = driver:interact(third)
		table.insert(routingTraces, thirdWrongTrace)
		routingBlocked = routingBlocked or driver:navigationBlocked()
		secondWrongOk = deliveredThirdWrong and thirdWrongAfter.TL_RoutingProgress == 1
			and eventChanged(thirdWrongBefore, thirdWrongAfter, "RoutingWrongOrder")
		for _, node in { second, third } do
			local delivered, traceId = driver:interact(node)
			table.insert(routingTraces, traceId)
			routingBlocked = routingBlocked or driver:navigationBlocked()
			if not delivered then break end
		end
		local finalRouting = driver:playerState()
		allRoutingOk = finalRouting.TL_RoutingComplete == true and finalRouting.TL_RoutingProgress == 3
			and finalRouting.TL_RoutingNext == "Complete"
	end
	if routingBlocked then
		candidateBlocked("d2.routing_system_usable", true, "routing nodes are physically blocked from the Central spawn", routingTraces)
		candidateBlocked("d3.routing_rejections", true, "required routing inputs cannot be reached through normal play", routingTraces)
		candidateBlocked("d3.routing_correct_order", true, "runtime-displayed routing order cannot be completed through normal play", routingTraces)
	else
		controllerDependent("d2.routing_system_usable", routingSetup and firstOk, allRoutingOk,
			"routing nodes must support a basic visible activation through completion", routingTraces)
		controllerDependent("d3.routing_rejections", routingSetup, wrongOk and duplicateOk and secondWrongOk,
			"wrong-order and repeat input must be rejected without losing valid progress", routingTraces)
		controllerDependent("d3.routing_correct_order", routingSetup, allRoutingOk,
			"the runtime-displayed order must advance exactly 0 through 3", routingTraces)
	end

	-- Pressure: deliberately reject Port, then lock Port and Starboard inside the public safe band.
	local pressureTraces = {}
	local portStartDelivered, portStartTrace = false, driver:trace("pressure_setup", "skipped_after_failed_central_restart", { restart_trace_id = postFinalRestartTrace })
	if postFinalClean then portStartDelivered, portStartTrace = driver:interact(portPump) end
	table.insert(pressureTraces, portStartTrace)
	local pressureBlocked = driver:navigationBlocked()
	local sampleA = portPump:GetAttribute("TL_GaugeValue"); task.wait(0.45); local sampleB = portPump:GetAttribute("TL_GaugeValue")
	local outsideReady, outsideTrace = driver:waitPumpWindow(portPump, false, 2); table.insert(pressureTraces, outsideTrace)
	local rejectDelivered, rejectTrace, rejectBefore, rejectAfter = driver:interact(portPump); table.insert(pressureTraces, rejectTrace); pressureBlocked = pressureBlocked or driver:navigationBlocked()
	local rejected = outsideReady and rejectDelivered and rejectAfter.TL_PumpPortState == "Rejected"
		and eventChanged(rejectBefore, rejectAfter, "PumpRejected")
	local rejectFeedback, rejectFeedbackTrace = feedbackVisibleFor("PumpRejected", 1.5); table.insert(pressureTraces, rejectFeedbackTrace)
	table.insert(feedbackTraces, rejectFeedbackTrace)
	feedbackOk = feedbackOk and rejectFeedback
	local resetIdle, resetIdleTrace = driver:waitForAttribute("TL_PumpPortState", "Idle", 1.5); table.insert(pressureTraces, resetIdleTrace)
	local rejectResetOk = rejected and resetIdle and portPump:GetAttribute("TL_GaugeValue") == 0
	-- Start both independent 8-second pump waves before waiting.  This is the
	-- same real-player E interaction as the sequential path, but both clocks run
	-- concurrently while the avatar walks between pumps.  No candidate state is
	-- written by QA and every lock is still accepted by the public safe band.
	local portStart2, portStart2Trace = driver:interact(portPump); table.insert(pressureTraces, portStart2Trace); pressureBlocked = pressureBlocked or driver:navigationBlocked()
	local starStart, starStartTrace = driver:interact(starboardPump); table.insert(pressureTraces, starStartTrace); pressureBlocked = pressureBlocked or driver:navigationBlocked()
	local starSafe, starSafeTrace = driver:waitPumpWindow(starboardPump, true, 4); table.insert(pressureTraces, starSafeTrace)
	local starLock, starLockTrace = driver:interact(starboardPump); table.insert(pressureTraces, starLockTrace); pressureBlocked = pressureBlocked or driver:navigationBlocked()
	local portSafe, portSafeTrace = driver:waitPumpWindow(portPump, true, 4); table.insert(pressureTraces, portSafeTrace)
	local portLock, portLockTrace = driver:interact(portPump); table.insert(pressureTraces, portLockTrace); pressureBlocked = pressureBlocked or driver:navigationBlocked()
	local pressureState = driver:playerState()
	local pressureComplete = portStart2 and portSafe and portLock and starStart and starSafe and starLock
		and pressureState.TL_PressureComplete == true and pressureState.TL_PumpPortState == "Locked"
		and pressureState.TL_PumpStarboardState == "Locked"
	local waveOk = portStartDelivered and type(sampleA) == "number" and type(sampleB) == "number" and sampleB > sampleA
		and portPump:GetAttribute("TL_CycleSeconds") == 8 and portPump:GetAttribute("TL_SafeMin") == 40 and portPump:GetAttribute("TL_SafeMax") == 60
	if pressureBlocked then
		candidateBlocked("d2.pressure_system_usable", true, "both pumps are physically blocked from the Central spawn", pressureTraces)
		candidateBlocked("d3.pump_reject_and_reset", true, "required pump interaction cannot be reached through normal play", pressureTraces)
		candidateBlocked("d3.pump_wave_and_safe_lock", true, "pump timing and safe-band lock cannot be reached through normal play", pressureTraces)
	else
		controllerDependent("d2.pressure_system_usable", portStartDelivered, pressureComplete,
			"both pumps must be usable and finish calibration", pressureTraces)
		controllerDependent("d3.pump_reject_and_reset", portStartDelivered and outsideReady, rejectResetOk,
			"out-of-band lock must reject and locally reset to Idle/0", pressureTraces)
		controllerDependent("d3.pump_wave_and_safe_lock", portStartDelivered, waveOk and pressureComplete,
			"gauge must change continuously and both pumps must lock only in 40-60", pressureTraces)
	end

	local routingVisual = first and first:GetAttribute("TL_Activated") == true and first.Material == Enum.Material.Neon
	local pressureVisual = portPump.Color ~= Color3.fromRGB(76,92,105) and starboardPump.Color ~= Color3.fromRGB(76,92,105)
	local worldFeedbackTrace = driver:trace("world_feedback", "observed", {
		routing_visual = routingVisual, pressure_visual = pressureVisual,
	})
	verdict("d2.world_feedback_content", routingVisual and pressureVisual,
		"successful routing and pressure actions must visibly change authoritative world objects", { worldFeedbackTrace })

	-- Reach the transfer sector independently before R. This prevents a deeper
	-- corridor defect from incorrectly claiming that the entire sector entrance
	-- or rack is absent/inaccessible.
	local earlyRack = driver:semantic("Core.Rack")
	local earlyRackDelivered, earlyRackTrace = false, driver:trace("core_setup", "skipped_after_failed_central_restart", { restart_trace_id = postFinalRestartTrace })
	if postFinalClean then earlyRackDelivered, earlyRackTrace = driver:interact(earlyRack) end
	local earlyCore = driver:onePart("TL_CarryCore")
	local earlyCoreReach = earlyRackDelivered and driver:playerState().TL_CarryingCore == true
		and earlyCore:GetAttribute("TL_CoreState") == "Carried"

	local activeRestart, activeRestartTrace, activeBefore, activeAfter = driver:restart()
	local activeRestartOk = activeRestart and type(activeBefore.TL_RunId) == "number"
		and activeAfter.TL_RunId == activeBefore.TL_RunId + 1 and driver:cleanState(activeAfter)
	verdict("aux.active_r_clean", activeRestartOk, "R from Active must create a clean new run", { activeRestartTrace })

	print("TIDE_LOCK_TRACK_START complete_attempt")
	local hubReached = { routing = routingSetup, pressure = portStartDelivered, final = consoleDelivered, core = earlyCoreReach }
	local interactionPromptOk = schemaOk
	local function completeRouting(): (boolean, { string })
		local traces = {}
		local currentOrder = {}
		for _, node in driver:parts("TL_RoutingNode") do
			local index = node:GetAttribute("TL_OrderIndex")
			if type(index) == "number" then currentOrder[index] = node end
		end
		for index = 1, 3 do
			local node = currentOrder[index]
			if not node then return false, traces end
			local delivered, traceId = driver:interact(node); table.insert(traces, traceId)
			if not delivered then return false, traces end
		end
		return driver:playerState().TL_RoutingComplete == true, traces
	end

	local function completePressure(): (boolean, { string })
		local traces = {}
		local port = driver:semantic("Pump.Port")
		local starboard = driver:semantic("Pump.Starboard")
		local portStarted, portStartTrace = driver:interact(port); table.insert(traces, portStartTrace)
		if not portStarted then return false, traces end
		local starboardStarted, starboardStartTrace = driver:interact(starboard); table.insert(traces, starboardStartTrace)
		if not starboardStarted then return false, traces end
		for _, pump in { starboard, port } do
			local safe, safeTrace = driver:waitPumpWindow(pump, true, 4.5); table.insert(traces, safeTrace)
			if not safe then return false, traces end
			local locked, lockTrace = driver:interact(pump); table.insert(traces, lockTrace)
			if not locked then return false, traces end
		end
		return driver:playerState().TL_PressureComplete == true, traces
	end

	local function completeCore(testRules: boolean): ({ [string]: any }, { string })
		local traces = {}
		local result: { [string]: any } = {
			checkpoint = false, picked = false, followed = false, installed = false,
			inactive_safe = false, active_death = false, preserved = false,
			candidate_blocked = false, respawned = false, core_returned = false,
		}
		local checkpoint = driver:onePart("TL_TransferCheckpoint")
		local checkpointTouched, checkpointTrace = driver:touchPart(checkpoint, 18); table.insert(traces, checkpointTrace)
		result.checkpoint = checkpointTouched and driver:playerState().TL_Checkpoint == "Transfer"
		if not result.checkpoint then
			local blocker = driver:blockerToward(checkpoint.Position)
			result.candidate_blocked = blocker ~= nil and blocker.can_collide == true
				and type(blocker.distance) == "number" and type(blocker.target_distance) == "number"
				and blocker.distance < blocker.target_distance - 3
			table.insert(traces, driver:trace("candidate_barrier_check", if result.candidate_blocked then "proven" else "not_proven", {
				target = driver:targetSnapshot(checkpoint), blocker = blocker,
			}))
			return result, traces
		end
		local rack = driver:semantic("Core.Rack")
		local picked, pickTrace = driver:interact(rack); table.insert(traces, pickTrace)
		result.picked = picked and driver:playerState().TL_CarryingCore == true
		local core = driver:onePart("TL_CarryCore")
		if result.picked then
			local _, _, root = driver:character(); task.wait(0.25)
			result.followed = core:GetAttribute("TL_CoreState") == "Carried" and (core.Position - root.Position).Magnitude < 8
		end
		for index = 0, 3 do
			local waypoint = driver:semantic("Waypoint." .. tostring(index))
			if index > 0 then
				local hazard = driver:semantic("Hazard." .. ({ "ArcA", "ArcB", "ArcC" })[index])
				local inactive, inactiveTrace = driver:waitHazard(hazard, false, 6); table.insert(traces, inactiveTrace)
				if not inactive then return result, traces end
			end
			local reached, waypointTraces = driver:followPath(waypoint.Position, 2.5, 16)
			for _, traceId in waypointTraces do table.insert(traces, traceId) end
			if not reached then
				local blocker = driver:blockerToward(waypoint.Position)
				result.candidate_blocked = blocker ~= nil and blocker.can_collide == true
					and type(blocker.distance) == "number" and type(blocker.target_distance) == "number"
					and blocker.distance < blocker.target_distance - 3
				table.insert(traces, driver:trace("candidate_barrier_check", if result.candidate_blocked then "proven" else "not_proven", {
					target = driver:targetSnapshot(waypoint), blocker = blocker,
				}))
				return result, traces
			end
		end
		local socket = driver:semantic("Core.Socket")
		if testRules then
			-- Test both arc phases while carrying. Active death must return the
			-- physical core to the rack, preserve prior systems, and respawn at Transfer.
			local hazard = driver:semantic("Hazard.ArcC")
			local staging = driver:semantic("Waypoint.2")
			local inactive, inactiveTrace = driver:waitHazard(hazard, false, 6); table.insert(traces, inactiveTrace)
			local staged = false
			if inactive then
				local stageTraces
				staged, stageTraces = driver:followPath(staging.Position, 2.5, 16)
				for _, traceId in stageTraces do table.insert(traces, traceId) end
				local _, humanoid = driver:character(); local healthBefore = humanoid.Health
				local touched, touchTrace = false, driver:trace("inactive_hazard_touch", "staging_failed", {})
				if staged then touched, touchTrace = driver:touchPart(hazard, 16) end
				table.insert(traces, touchTrace)
				task.wait(0.35)
				local _, humanoidAfter = driver:character()
				result.inactive_safe = touched and humanoidAfter.Health == healthBefore
			end
			local returned, returnTraces = driver:followPath(staging.Position, 2.5, 16)
			for _, traceId in returnTraces do table.insert(traces, traceId) end
			local active, activeTrace = driver:waitHazard(hazard, true, 6); table.insert(traces, activeTrace)
			if active and returned then
				local oldCharacter, oldHumanoid = driver:character()
				local before = driver:playerState(); local touchedAt: number? = nil; local diedAt: number? = nil
				local touchConnection = hazard.Touched:Connect(function(hit) if hit:IsDescendantOf(oldCharacter) and not touchedAt then touchedAt = os.clock() end end)
				local diedConnection = oldHumanoid.Died:Connect(function() diedAt = os.clock() end)
				local touched, touchTrace = driver:touchPart(hazard, 16); table.insert(traces, touchTrace)
				local deadline = os.clock() + 1
				while not diedAt and os.clock() < deadline do task.wait(0.03) end
				touchConnection:Disconnect(); diedConnection:Disconnect()
				local respawned, position, respawnTrace = driver:waitRespawn(oldCharacter, 8); table.insert(traces, respawnTrace)
				local after = driver:playerState()
				result.active_death = touched and touchedAt ~= nil and diedAt ~= nil and diedAt - touchedAt <= 0.75
				local transferSpawn = driver:semantic("Waypoint.0")
				local respawnDistance = if position then Vector3.new(position.X - transferSpawn.Position.X, 0, position.Z - transferSpawn.Position.Z).Magnitude else math.huge
				result.respawned = respawned and position ~= nil and respawnDistance <= 18 and after.TL_Checkpoint == "Transfer"
				local returnDeadline = os.clock() + 2
				repeat
					result.core_returned = core:GetAttribute("TL_CoreState") == "AtRack"
						and core:GetAttribute("TL_CarrierUserId") == 0 and after.TL_CarryingCore == false
					if not result.core_returned then task.wait(0.05) end
				until result.core_returned or os.clock() >= returnDeadline
				result.preserved = result.respawned and after.TL_RunId == before.TL_RunId and after.TL_RunStart == before.TL_RunStart
					and after.TL_RoutingComplete == true and after.TL_PressureComplete == true and after.TL_CoreTransferComplete == false
					and after.TL_DeathCount == before.TL_DeathCount + 1 and result.core_returned
			end
			if not result.preserved then return result, traces end

			local pickedAgain, pickedAgainTrace = driver:interact(rack); table.insert(traces, pickedAgainTrace)
			if not pickedAgain or driver:playerState().TL_CarryingCore ~= true then return result, traces end
			for index = 0, 3 do
				local waypoint = driver:semantic("Waypoint." .. tostring(index))
				if index > 0 then
					local nextHazard = driver:semantic("Hazard." .. ({ "ArcA", "ArcB", "ArcC" })[index])
					local safe, safeTrace = driver:waitHazard(nextHazard, false, 6); table.insert(traces, safeTrace)
					if not safe then return result, traces end
				end
				local reached, waypointTraces = driver:followPath(waypoint.Position, 2.5, 16)
				for _, traceId in waypointTraces do table.insert(traces, traceId) end
				if not reached then return result, traces end
			end
		end
		local installed, installTrace = driver:interact(socket); table.insert(traces, installTrace)
		result.installed = installed and driver:playerState().TL_CoreTransferComplete == true
		return result, traces
	end

	local routingCycle1, routingCycle1Traces = completeRouting()
	local pressureCycle1, pressureCycle1Traces = completePressure()
	local coreResult1, coreTraces1 = completeCore(true)
	local cycle1Traces = {}
	for _, list in { routingCycle1Traces, pressureCycle1Traces, coreTraces1 } do for _, traceId in list do table.insert(cycle1Traces, traceId) end end
	hubReached.core = hubReached.core or coreResult1.picked or coreResult1.checkpoint

	if coreResult1.candidate_blocked then
		candidateBlocked("d2.core_transfer_system_usable", true, "normal Transfer checkpoint/waypoint route is physically obstructed", coreTraces1)
		candidateBlocked("d2.checkpoint_and_hazards_usable", true, "checkpoint and hazard corridor cannot be reached through the documented route", coreTraces1)
		candidateBlocked("d3.core_pickup_carry_install", true, "core cannot be transported to the socket", coreTraces1)
		candidateBlocked("d3.hazard_phase_damage_rules", true, "required hazard contacts are inaccessible", coreTraces1)
		candidateBlocked("d3.death_checkpoint_preservation", true, "Transfer checkpoint/death precondition is inaccessible", coreTraces1)
		candidateBlocked("d4.death_respawn_flow", true, "documented checkpoint-to-hazard journey is inaccessible", coreTraces1)
	else
		controllerDependent("d2.core_transfer_system_usable", coreResult1.checkpoint and coreResult1.picked,
			coreResult1.followed and coreResult1.installed, "core pickup, visible carry and installation must be usable", coreTraces1)
		controllerDependent("d2.checkpoint_and_hazards_usable", coreResult1.checkpoint,
			coreResult1.inactive_safe and coreResult1.active_death, "checkpoint and both hazard phases must be usable", coreTraces1)
		controllerDependent("d3.core_pickup_carry_install", coreResult1.picked,
			coreResult1.followed and coreResult1.installed, "one physical core must follow and install at the socket", coreTraces1)
		controllerDependent("d3.hazard_phase_damage_rules", coreResult1.checkpoint,
			coreResult1.inactive_safe and coreResult1.active_death, "inactive contact is safe and active contact kills within 0.75 seconds", coreTraces1)
		controllerDependent("d3.death_checkpoint_preservation", coreResult1.active_death,
			coreResult1.respawned and coreResult1.preserved, "death must respawn at Transfer and preserve completed systems", coreTraces1)
		controllerDependent("d4.death_respawn_flow", coreResult1.active_death,
			coreResult1.respawned and coreResult1.preserved, "physical death-to-checkpoint lifecycle must complete", coreTraces1)
	end

	local allSystems1 = routingCycle1 and pressureCycle1 and coreResult1.installed and driver:playerState().TL_FinalStage == "Ready"
	local failureRetryOk = false
	local failedRestartOk = false
	local finalGateOk = earlyFinalOk
	local finalTraces = mergedTraces(earlyFinalTraces)
	if allSystems1 then
		local right = driver:semantic("Final.Right")
		local rightDelivered, rightTrace, rightBefore, rightAfter = driver:interact(right); table.insert(finalTraces, rightTrace)
		finalGateOk = finalGateOk and rightDelivered and eventChanged(rightBefore, rightAfter, "FinalWrongLever") and rightAfter.TL_FinalStage == "Ready"
		local left = driver:semantic("Final.Left")
		local leftDelivered, leftTrace = driver:interact(left); table.insert(finalTraces, leftTrace)
		task.wait(10.6)
		local failed1, failedTrace1 = driver:waitForAttribute("TL_RunState", "Failed", 1); table.insert(finalTraces, failedTrace1)
		local retryOk, retryTrace = driver:clickRetry(); table.insert(finalTraces, retryTrace)
		failureRetryOk = leftDelivered and failed1 and retryOk
		local left2, leftTrace2 = driver:interact(left); table.insert(finalTraces, leftTrace2)
		task.wait(10.6)
		local failed2, failedTrace2 = driver:waitForAttribute("TL_RunState", "Failed", 1); table.insert(finalTraces, failedTrace2)
		local restarted, restartTrace = driver:restart(); table.insert(finalTraces, restartTrace)
		failedRestartOk = left2 and failed2 and restarted and driver:cleanState(driver:playerState())
	end

	if not allSystems1 and coreResult1.candidate_blocked then
		for _, pair in {
			{ "d2.failure_retry_content_usable", "final failure/Retry cannot be entered because a required system is physically inaccessible" },
			{ "d3.final_gate_and_order", "correct final order cannot be established because a required system is physically inaccessible" },
			{ "d3.final_timeout_and_retry", "final timeout/Retry prerequisite is blocked by the candidate world" },
			{ "d3.completion_prerequisites_and_timer", "completion prerequisite chain is blocked by the candidate world" },
			{ "d4.failure_retry_flow", "failure-to-Retry flow cannot be reached through normal play" },
			{ "d4.complete_success_flow", "normal complete flow is blocked before the final controls" },
			{ "d5.result_overlays_and_retry_button", "failure/completion overlays cannot be reached through normal play" },
		} do candidateBlocked(pair[1], true, pair[2], coreTraces1) end
	else
		controllerDependent("d2.failure_retry_content_usable", allSystems1, failureRetryOk,
			"timeout overlay and mouse Retry must be enterable and usable", finalTraces)
		controllerDependent("d3.final_gate_and_order", allSystems1, finalGateOk,
			"Locked gate and Right-before-Left must reject while valid order is accepted", finalTraces)
		controllerDependent("d3.final_timeout_and_retry", allSystems1, failureRetryOk,
			"10-second timeout must fail and real mouse Retry must preserve systems", finalTraces)
		controllerDependent("d4.failure_retry_flow", allSystems1, failureRetryOk,
			"normal failure overlay to Retry continuation must complete", finalTraces)
		controllerDependent("d5.result_overlays_and_retry_button", allSystems1, failureRetryOk,
			"failure overlay and tagged Retry button must be visible and usable", finalTraces)
	end

	-- If Failed-R succeeded, rebuild all systems and perform the one complete success journey.
	local completed = false
	local completedRestartOk = false
	local completionTraces = {}
	if failedRestartOk then
		local routingCycle2, routingTraces2 = completeRouting()
		local pressureCycle2, pressureTraces2 = completePressure()
		local coreResult2, coreTraces2 = completeCore(false)
		for _, list in { routingTraces2, pressureTraces2, coreTraces2 } do for _, traceId in list do table.insert(completionTraces, traceId) end end
		if routingCycle2 and pressureCycle2 and coreResult2.installed and driver:playerState().TL_FinalStage == "Ready" then
			local left = driver:semantic("Final.Left"); local right = driver:semantic("Final.Right")
			local leftOk, leftTrace = driver:interact(left); table.insert(completionTraces, leftTrace)
			local rightOk, rightTrace = driver:interact(right); table.insert(completionTraces, rightTrace)
			local completeDelivered, completeTrace = driver:interact(console); table.insert(completionTraces, completeTrace)
			local state = driver:playerState()
			completed = leftOk and rightOk and completeDelivered and state.TL_RunState == "Completed"
				and state.TL_CompletionState == "Completed" and state.TL_FinalTime >= 0 and state.TL_LastEvent == "Completed"
			local finalTime = state.TL_FinalTime; task.wait(1); local frozen = driver:playerState().TL_FinalTime == finalTime
			completed = completed and frozen
			local restarted, restartTrace = driver:restart(); table.insert(completionTraces, restartTrace)
			completedRestartOk = restarted and driver:cleanState(driver:playerState())
		end
	end

	if not emitted["d3.completion_prerequisites_and_timer"] then
		controllerDependent("d3.completion_prerequisites_and_timer", failedRestartOk, completed,
			"completion must require all systems, Left, Right and Console, then freeze FinalTime", completionTraces)
	end
	if not emitted["d4.complete_success_flow"] then
		controllerDependent("d4.complete_success_flow", failedRestartOk, completed,
			"one complete normal player journey must reach Completed", completionTraces)
	end

	local restartAcross = activeRestartOk and failedRestartOk and completedRestartOk
	controllerDependent("d4.restart_across_states", activeRestartOk, restartAcross,
		"R must clean Active, Failed and Completed states", mergedTraces({ activeRestartTrace }, finalTraces, completionTraces))

	-- Reopen is executed by the desktop orchestrator in a fresh session.
	record("d4.reopen_clean_session", "not_run", "desktop orchestrator will replace this after a clean Reopen session", {})
	record("d2.restart_and_reopen_content", "not_run", "desktop orchestrator will combine active R and clean Reopen evidence", { activeRestartTrace })

	verdict("d2.hub_and_three_sectors", hubReached.routing and hubReached.pressure and hubReached.core and hubReached.final,
		"central hub must expose normally reachable routing, pressure, core and final areas", mergedTraces(earlyFinalTraces, { earlyRackTrace }, routingTraces, pressureTraces, coreTraces1))
	verdict("d5.interactions_discoverable", interactionPromptOk and consoleDelivered and routingSetup and portStartDelivered,
		"public prompts and semantic approach objects must make interactions discoverable", mergedTraces({ schemaTrace }, earlyFinalTraces, routingTraces, pressureTraces))
	verdict("d5.rejection_and_failure_feedback", feedbackOk and wrongOk and rejected and earlyFinalOk,
		"wrong route, bad pump timing and locked final control must provide synchronized visible feedback for the documented duration", mergedTraces({ earlyFeedbackTrace }, feedbackTraces, routingTraces, pressureTraces))

	for _, id in allDynamic do
		if not emitted[id] then record(id, "not_run", "formal suite did not produce a verdict", {}) end
	end

	print("TIDE_LOCK_SUITE_FINISHED")
end
