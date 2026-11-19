--!strict
-- Supplemental adjudication only: routing usability plus four D6 capture states.
-- It uses ordinary player movement and E input and does not mutate candidate state directly.

local function runTwoItemSupplement(Driver: any, emitCheckpoint: any)
	local driver = Driver.new()
	local traces: { string } = {}

	local function add(traceId: string)
		table.insert(traces, traceId)
	end

	local function capture(label: string)
		emitCommand("capture_screenshot", { label = label })
		task.wait(0.8)
	end

	local ready, readyTrace = driver:waitReady(12)
	add(readyTrace)
	if not ready then
		emitCheckpoint("d2.routing_system_usable", "fail", "candidate did not reach the documented ready state", traces)
		return
	end

	capture("01_initial_hub")

	local nodesById: { [string]: BasePart } = {}
	for _, node in driver:parts("TL_RoutingNode") do
		local id = node:GetAttribute("TL_RoutingId")
		if type(id) == "string" then nodesById[id] = node end
	end

	local firstId = driver:playerState().TL_RoutingNext
	local first = if type(firstId) == "string" then nodesById[firstId] else nil
	if not first or #driver:parts("TL_RoutingNode") ~= 3 then
		emitCheckpoint("d2.routing_system_usable", "fail", "three ordered routing nodes were not exposed", traces)
		return
	end

	local point = driver:interactionPoint(first)
	local reached, approachTraces = driver:followPath(point, 2.2, 20)
	for _, traceId in approachTraces do add(traceId) end
	driver:releaseMovement()
	capture("02_routing_sector")

	local physicalEstablished = reached
	local allAdvanced = true
	for expectedProgress = 1, 3 do
		local state = driver:playerState()
		local expectedId = state.TL_RoutingNext
		local node = if type(expectedId) == "string" then nodesById[expectedId] else nil
		if not node then allAdvanced = false; break end

		local advanced = false
		for _ = 1, 3 do
			local delivered, traceId = driver:interact(node)
			add(traceId)
			physicalEstablished = physicalEstablished and delivered
			local after = driver:playerState()
			if after.TL_RoutingProgress == expectedProgress and node:GetAttribute("TL_Activated") == true then
				advanced = true
				break
			end
			task.wait(0.25)
		end
		if not advanced then allAdvanced = false; break end
		if expectedProgress == 1 then capture("03_first_route_active") end
	end

	local finalState = driver:playerState()
	local complete = allAdvanced and finalState.TL_RoutingProgress == 3
		and finalState.TL_RoutingComplete == true and finalState.TL_RoutingNext == "Complete"
	add(driver:trace("routing_supplement_final", if complete then "complete" else "incomplete", {
		state = finalState,
	}))
	capture("04_routing_complete")

	if complete then
		emitCheckpoint("d2.routing_system_usable", "pass", "supplemental real-input run completed all three displayed routing nodes", traces)
	elseif not physicalEstablished then
		emitCheckpoint("d2.routing_system_usable", "inconclusive", "supplemental controller did not establish the physical prompt precondition", traces)
	else
		emitCheckpoint("d2.routing_system_usable", "fail", "routing prompts were reached but the displayed three-step route did not complete", traces)
	end
end
