--!strict
-- Tide Lock engine-state driver. It reads public semantics and requests only OS input.

local function buildEngineDriver(inputAdapter: any, emitTrace: any)
	local CollectionService = game:GetService("CollectionService")
	local PathfindingService = game:GetService("PathfindingService")
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local Workspace = game:GetService("Workspace")

	local Driver = {}
	Driver.__index = Driver
	local PLAYER_ATTRIBUTES = {
		"TL_RunId", "TL_RunState", "TL_RoutingComplete", "TL_RoutingProgress", "TL_RoutingNext",
		"TL_PressureComplete", "TL_PumpPortState", "TL_PumpStarboardState",
		"TL_CoreTransferComplete", "TL_CarryingCore", "TL_Checkpoint", "TL_FinalStage",
		"TL_CompletionState", "TL_DeathCount", "TL_RetryCount", "TL_RunStart", "TL_FinalTime",
		"TL_EventSerial", "TL_LastEvent", "TL_EventDetail", "TL_FeedbackText",
	}
	local EXPECTED_TAG_COUNTS = {
		TL_GameStateRoot = 1, TL_CentralSpawn = 1, TL_OrderDisplay = 1, TL_RoutingNode = 3,
		TL_PressurePump = 2, TL_CoreRack = 1, TL_CarryCore = 1, TL_CoreSocket = 1,
		TL_TransferCheckpoint = 1, TL_Hazard = 3, TL_TransferWaypoint = 4,
		TL_FinalLever = 2, TL_FinalConsole = 1, TL_ApproachPoint = 10,
	}
	local INTERACTION_IDS = {
		"Routing.Delta", "Routing.Nova", "Routing.Echo", "Pump.Port", "Pump.Starboard",
		"Core.Rack", "Core.Socket", "Final.Left", "Final.Right", "Final.Console",
	}
	local HUD_ROLES = {
		"Objective", "Timer", "Feedback", "RoutingStatus", "RoutingOrder", "PressureStatus",
		"GaugePort", "GaugeStarboard", "CoreStatus", "FinalStatus",
	}

	local function vector(value: Vector3)
		return { x = value.X, y = value.Y, z = value.Z }
	end

	local function horizontalDistance(left: Vector3, right: Vector3): number
		return Vector3.new(left.X - right.X, 0, left.Z - right.Z).Magnitude
	end

	local function actuallyVisible(item: GuiObject): boolean
		local current: Instance? = item
		while current do
			if current:IsA("GuiObject") and not current.Visible then return false end
			if current:IsA("LayerCollector") and not current.Enabled then return false end
			current = current.Parent
		end
		return true
	end

	function Driver.new()
		local self = setmetatable({}, Driver)
		self.player = Players.LocalPlayer
		self.cache = {}
		self.lastNavigation = { candidate_blocked = false }
		return self
	end

	function Driver:character(): (Model, Humanoid, BasePart)
		-- Character replacement is asynchronous after a real death. Never retain
		-- a dying Model or fail the whole suite during the short replication gap.
		local deadline = os.clock() + 12
		repeat
			local character = self.player.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local root = character:FindFirstChild("HumanoidRootPart")
				if humanoid and root and root:IsA("BasePart") then
					return character, humanoid, root
				end
			end
			task.wait(0.05)
		until os.clock() >= deadline
		error("character model/HumanoidRootPart was unavailable for 12 seconds")
	end

	function Driver:playerState(): { [string]: any }
		local result: { [string]: any } = {}
		for _, name in PLAYER_ATTRIBUTES do result[name] = self.player:GetAttribute(name) end
		return result
	end

	function Driver:hudMap(): { [string]: any }
		local result: { [string]: any } = {}
		local gui = self.player:FindFirstChildOfClass("PlayerGui")
		if not gui then return result end
		for _, instance in CollectionService:GetTagged("TL_HUDField") do
			if instance:IsDescendantOf(gui) and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
				local role = instance:GetAttribute("TL_HudRole")
				if type(role) == "string" then
					result[role] = {
						text = instance.Text, visible = actuallyVisible(instance),
						x = instance.AbsolutePosition.X, y = instance.AbsolutePosition.Y,
						w = instance.AbsoluteSize.X, h = instance.AbsoluteSize.Y,
					}
				end
			end
		end
		return result
	end

	function Driver:tagged(tagName: string): { Instance }
		return CollectionService:GetTagged(tagName)
	end

	function Driver:parts(tagName: string): { BasePart }
		local result = {}
		for _, instance in self:tagged(tagName) do
			if instance:IsA("BasePart") then table.insert(result, instance) end
		end
		return result
	end

	function Driver:onePart(tagName: string): BasePart
		local cacheKey = "tag:" .. tagName
		local cached = self.cache[cacheKey]
		if cached and cached.Parent and cached:IsA("BasePart") then return cached end
		local found = self:parts(tagName)
		assert(#found == 1, string.format("%s expected one BasePart, found %d", tagName, #found))
		self.cache[cacheKey] = found[1]
		return found[1]
	end

	function Driver:semantic(semanticId: string): BasePart
		local cached = self.cache[semanticId]
		if cached and cached.Parent and cached:IsA("BasePart") then return cached end
		local found = {}
		for _, instance in Workspace:GetDescendants() do
			if instance:IsA("BasePart") and instance:GetAttribute("TL_SemanticId") == semanticId then
				table.insert(found, instance)
			end
		end
		assert(#found == 1, string.format("semantic %s expected one BasePart, found %d", semanticId, #found))
		self.cache[semanticId] = found[1]
		return found[1]
	end

	function Driver:approachFor(semanticId: string): BasePart?
		local found = {}
		for _, instance in self:parts("TL_ApproachPoint") do
			if instance:GetAttribute("TL_TargetSemanticId") == semanticId then table.insert(found, instance) end
		end
		return if #found == 1 then found[1] else nil
	end

	function Driver:prompt(part: BasePart): ProximityPrompt
		local prompts = {}
		for _, descendant in part:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then table.insert(prompts, descendant) end
		end
		assert(#prompts == 1, "interaction target must own exactly one ProximityPrompt")
		return prompts[1]
	end

	function Driver:promptPosition(prompt: ProximityPrompt, fallback: BasePart): Vector3
		local parent = prompt.Parent
		if parent and parent:IsA("Attachment") then return parent.WorldPosition end
		if parent and parent:IsA("BasePart") then return parent.Position end
		local ancestor = prompt:FindFirstAncestorWhichIsA("BasePart")
		return if ancestor then ancestor.Position else fallback.Position
	end

	function Driver:targetSnapshot(part: BasePart): { [string]: any }
		local tags = {}
		for tagName in EXPECTED_TAG_COUNTS do
			if CollectionService:HasTag(part, tagName) then table.insert(tags, tagName) end
		end
		return {
			semantic_id = part:GetAttribute("TL_SemanticId"), tags = tags,
			position = vector(part.Position), size = vector(part.Size),
			color = { r = part.Color.R, g = part.Color.G, b = part.Color.B },
			material = part.Material.Name, can_collide = part.CanCollide, transparency = part.Transparency,
			attributes = part:GetAttributes(),
		}
	end

	function Driver:scene(extra: { [string]: any }?): { [string]: any }
		local _, humanoid, root = self:character()
		local record = extra or {}
		record.position = vector(root.Position)
		record.velocity = vector(root.AssemblyLinearVelocity)
		record.health = humanoid.Health
		record.floor_material = humanoid.FloorMaterial.Name
		record.player_attributes = self:playerState()
		record.hud = self:hudMap()
		return record
	end

	function Driver:trace(action: string, outcome: string, data: { [string]: any }?): string
		local record = self:scene(data)
		record.action = action
		record.outcome = outcome
		return emitTrace(record)
	end

	function Driver:waitReady(timeout: number): (boolean, string)
		local deadline = os.clock() + timeout
		local stableSince: number? = nil
		repeat
			local ok = pcall(function()
				local _, humanoid, root = self:character()
				assert(humanoid.Health > 0 and root.Parent ~= nil)
			end)
			if ok and Workspace:GetAttribute("TL_Ready") == true and Workspace:GetAttribute("TL_ContractVersion") == "tide-lock-v1" then
				stableSince = stableSince or os.clock()
				if os.clock() - stableSince >= 0.6 then
					return true, self:trace("wait_ready", "ready", { timeout_s = timeout })
				end
			else stableSince = nil end
			task.wait(0.08)
		until os.clock() >= deadline
		return false, self:trace("wait_ready", "timeout", { timeout_s = timeout })
	end

	function Driver:press(key: Enum.KeyCode, duration: number?): string
		inputAdapter.sendKeyEvent(true, key)
		task.wait(duration or 0.12)
		inputAdapter.sendKeyEvent(false, key)
		task.wait(0.10)
		return self:trace("key_press", "completed", { key = key.Name, duration_s = duration or 0.12 })
	end

	function Driver:releaseMovement()
		for _, key in { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space } do
			inputAdapter.sendKeyEvent(false, key)
		end
	end

	function Driver:pulseToward(target: Vector3, duration: number)
		local _, humanoid, root = self:character()
		if humanoid.Health <= 0 then return end
		local camera = Workspace.CurrentCamera
		assert(camera, "CurrentCamera unavailable")
		local desired = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if desired.Magnitude < 0.05 then return end
		desired = desired.Unit
		local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		if forward.Magnitude < 0.05 then forward = Vector3.new(0, 0, -1) else forward = forward.Unit end
		local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
		if right.Magnitude < 0.05 then right = Vector3.new(1, 0, 0) else right = right.Unit end
		local f = desired:Dot(forward)
		local r = desired:Dot(right)
		local keys = {}
		if math.abs(f) > 0.12 then table.insert(keys, if f >= 0 then Enum.KeyCode.W else Enum.KeyCode.S) end
		if math.abs(r) > 0.12 then table.insert(keys, if r >= 0 then Enum.KeyCode.D else Enum.KeyCode.A) end
		for _, key in keys do inputAdapter.sendKeyEvent(true, key) end
		task.wait(duration)
		for _, key in keys do inputAdapter.sendKeyEvent(false, key) end
	end

	function Driver:blockerToward(target: Vector3): any
		local character, _, root = self:character()
		-- Cast horizontally at avatar torso height. A sloped cast toward a floor
		-- checkpoint otherwise reports the floor itself as a false blocker.
		local horizontalTarget = Vector3.new(target.X, root.Position.Y, target.Z)
		local direction = horizontalTarget - root.Position
		if direction.Magnitude < 0.1 then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true
		local hit = Workspace:Raycast(root.Position, direction, params)
		if not hit then return nil end
		local instance = hit.Instance
		return {
			name = instance.Name, class_name = instance.ClassName,
			position = vector(hit.Position), distance = hit.Distance, target_distance = direction.Magnitude,
			can_collide = if instance:IsA("BasePart") then instance.CanCollide else nil,
			size = if instance:IsA("BasePart") then vector(instance.Size) else nil,
			semantic_id = instance:GetAttribute("TL_SemanticId"),
		}
	end

	function Driver:driveTo(target: Vector3, radius: number?, timeout: number?): (boolean, string)
		local goalRadius = radius or 3
		local deadline = os.clock() + (timeout or 15)
		local best = math.huge
		local improvedAt = os.clock()
		local detours = 0
		while os.clock() < deadline do
			local _, humanoid, root = self:character()
			if humanoid.Health <= 0 then
				self:releaseMovement()
				return false, self:trace("walk_to", "character_died", { target = vector(target) })
			end
			local distance = horizontalDistance(root.Position, target)
			if distance <= goalRadius then
				self:releaseMovement()
				return true, self:trace("walk_to", "reached", { target = vector(target), final_distance = distance })
			end
			if distance + 0.2 < best then best = distance; improvedAt = os.clock()
			elseif os.clock() - improvedAt > 1.2 then
				if detours < 4 then
					detours += 1
					local toward = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
					if toward.Magnitude > 0.1 then
						toward = toward.Unit
						local side = Vector3.new(-toward.Z, 0, toward.X) * (if detours % 2 == 1 then 1 else -1)
						self:pulseToward(root.Position + side * 5 + toward * 2, 0.4)
					end
					best = distance; improvedAt = os.clock()
				else
					self:releaseMovement()
					local blocker = self:blockerToward(target)
					self.lastNavigation = {
						candidate_blocked = blocker ~= nil and blocker.can_collide == true
							and type(blocker.distance) == "number" and type(blocker.target_distance) == "number"
							and blocker.distance < blocker.target_distance - 2,
						blocker = blocker,
					}
					return false, self:trace("walk_to", "stalled", {
						target = vector(target), final_distance = distance, blocker = blocker, detours = detours,
					})
				end
			end
			self:pulseToward(target, if distance > 15 then 0.22 elseif distance > 7 then 0.14 else 0.07)
			task.wait(0.015)
		end
		self:releaseMovement()
		local _, _, root = self:character()
		local blocker = self:blockerToward(target)
		self.lastNavigation = {
			candidate_blocked = blocker ~= nil and blocker.can_collide == true
				and type(blocker.distance) == "number" and type(blocker.target_distance) == "number"
				and blocker.distance < blocker.target_distance - 2,
			blocker = blocker,
		}
		return false, self:trace("walk_to", "timeout", {
			target = vector(target), final_distance = horizontalDistance(root.Position, target), blocker = blocker,
		})
	end

	function Driver:navigationBlocked(): boolean
		return self.lastNavigation ~= nil and self.lastNavigation.candidate_blocked == true
	end

	function Driver:groundNavigationTarget(target: Vector3): (Vector3, { [string]: any })
		-- Navigation targets must be locations an avatar can stand beside, rather
		-- than a point embedded in a console, a marker, or (as in this candidate)
		-- below its floor.  This is a read-only physics query based solely on the
		-- semantic target's relative X/Z position; it never changes the world.
		local character, _, root = self:character()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true
		local originY = math.max(root.Position.Y + 14, target.Y + 14)
		local hit = Workspace:Raycast(Vector3.new(target.X, originY, target.Z), Vector3.yAxis * -80, params)
		if hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
			-- HumanoidRootPart rides roughly 2.5 studs above a flat floor.  Path
			-- finding consumes this as a regular navigation destination, while
			-- driveTo below still checks horizontal arrival only.
			local grounded = Vector3.new(target.X, hit.Position.Y + 2.5, target.Z)
			return grounded, { projected = true, floor = self:targetSnapshot(hit.Instance), floor_y = hit.Position.Y }
		end
		return target, { projected = false }
	end

	function Driver:followPath(target: Vector3, radius: number?, timeout: number?): (boolean, { string })
		local traces = {}
		self.lastNavigation = { candidate_blocked = false }
		local _, _, root = self:character()
		local navigationTarget, navigationData = self:groundNavigationTarget(target)
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 })
		local computed, detail = pcall(function() path:ComputeAsync(root.Position, navigationTarget) end)
		if computed and path.Status == Enum.PathStatus.Success then
			table.insert(traces, self:trace("path_compute", "success", { waypoint_count = #path:GetWaypoints(), target = vector(target), navigation_target = vector(navigationTarget), navigation = navigationData }))
			local deadline = os.clock() + (timeout or 24)
			for _, waypoint in path:GetWaypoints() do
				if os.clock() >= deadline then break end
				local reached, traceId = self:driveTo(waypoint.Position, 3, math.min(6, math.max(0.2, deadline - os.clock())))
				table.insert(traces, traceId)
				if not reached then return false, traces end
			end
			local reached, traceId = self:driveTo(target, radius or 3, math.min(6, math.max(0.2, deadline - os.clock())))
			table.insert(traces, traceId)
			return reached, traces
		end
		table.insert(traces, self:trace("path_compute", "unavailable", {
			status = path.Status.Name, detail = tostring(detail), target = vector(target), navigation_target = vector(navigationTarget), navigation = navigationData, blocker = self:blockerToward(target),
		}))
		local reached, traceId = self:driveTo(target, radius or 3, timeout or 15)
		table.insert(traces, traceId)
		return reached, traces
	end

	function Driver:interactionPoint(part: BasePart): (Vector3, { [string]: any })
		local semanticId = part:GetAttribute("TL_SemanticId")
		local prompt = self:prompt(part)
		local promptPosition = self:promptPosition(prompt, part)
		local approach = if type(semanticId) == "string" then self:approachFor(semanticId) else nil
		local rejectedPublicApproach = false
		if approach then
			-- Approach points are public navigation hints, not authority. Confirm the
			-- point lies on a standable surface before walking to it. This prevents a
			-- malformed point embedded below a floor from making the real avatar fall.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { self.player.Character }
			params.RespectCanCollide = true
			local origin = approach.Position + Vector3.new(0, 6, 0)
			local hit = Workspace:Raycast(origin, Vector3.yAxis * -12, params)
			local approachFootY = approach.Position.Y + approach.Size.Y / 2
			if hit and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
				and math.abs(hit.Position.Y - approachFootY) <= 0.25 then
				return approach.Position, { source = "public_approach", approach = self:targetSnapshot(approach) }
			end
			-- Preserve the malformed point in engine evidence, then use only the
			-- prompt-relative fallback defined by the public evaluator contract.
			rejectedPublicApproach = true
		end
		local _, _, root = self:character()
		local away = Vector3.new(root.Position.X - promptPosition.X, 0, root.Position.Z - promptPosition.Z)
		if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) else away = away.Unit end
		local extent = math.abs(away.X) * part.Size.X / 2 + math.abs(away.Z) * part.Size.Z / 2
		local standoff = math.max(2, math.min(prompt.MaxActivationDistance - 1.2, extent + 1.5))
		return promptPosition + away * standoff, {
			source = "relative_prompt_standoff", standoff = standoff,
			public_approach_rejected = rejectedPublicApproach,
		}
	end

	function Driver:interact(part: BasePart): (boolean, string, { [string]: any }, { [string]: any })
		local prompt = self:prompt(part)
		local target, approachData = self:interactionPoint(part)
		local reached, pathTraces = self:followPath(target, 2.2, 20)
		if not reached then
			-- A malformed public ApproachPoint must not make the controller give up.
			local promptPosition = self:promptPosition(prompt, part)
			local _, _, root = self:character()
			local away = Vector3.new(root.Position.X - promptPosition.X, 0, root.Position.Z - promptPosition.Z)
			if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) else away = away.Unit end
			local fallback = promptPosition + away * math.max(2, math.min(prompt.MaxActivationDistance - 1.5, 5))
			local fallbackReached, fallbackTraces = self:followPath(fallback, 1.8, 14)
			for _, traceId in fallbackTraces do table.insert(pathTraces, traceId) end
			reached = fallbackReached
			approachData.fallback_used = true
		end
		self:releaseMovement()
		task.wait(0.2)
		local _, _, root = self:character()
		local promptPosition = self:promptPosition(prompt, part)
		local distance = (root.Position - promptPosition).Magnitude
		local physicalReady = reached and prompt.Enabled and distance <= prompt.MaxActivationDistance + 0.15
		if not physicalReady then
			local state = self:playerState()
			return false, self:trace("prompt_interaction", "physical_precondition_not_met", {
				target = self:targetSnapshot(part), approach = approachData,
				avatar_distance = distance, prompt_enabled = prompt.Enabled,
				max_activation_distance = prompt.MaxActivationDistance, path_trace_ids = pathTraces,
			}), state, state
		end
		local before = self:playerState()
		local beforeTarget = self:targetSnapshot(part)
		local keyTrace = self:press(Enum.KeyCode.E, math.max(0.12, prompt.HoldDuration + 0.1))
		local oldSerial = before.TL_EventSerial
		local deadline = os.clock() + 1.2
		repeat
			if type(oldSerial) == "number" and (self.player:GetAttribute("TL_EventSerial") or 0) > oldSerial then break end
			task.wait(0.04)
		until os.clock() >= deadline
		local after = self:playerState()
		return true, self:trace("prompt_interaction", "input_delivered", {
			target_before = beforeTarget, target_after = self:targetSnapshot(part),
			state_before = before, state_after = after, input_trace_id = keyTrace,
			avatar_distance = distance, approach = approachData,
		}), before, after
	end

	function Driver:touchPart(part: BasePart, timeout: number?): (boolean, string, number?)
		local character = self.player.Character
		assert(character, "Character unavailable")
		local touchedAt: number? = nil
		local connection = part.Touched:Connect(function(hit)
			if hit:IsDescendantOf(character) and touchedAt == nil then touchedAt = os.clock() end
		end)
		local reached, traces = self:followPath(part.Position, 2.2, timeout or 18)
		local deadline = os.clock() + 2
		while touchedAt == nil and os.clock() < deadline do
			local _, humanoid = self:character()
			if humanoid.Health <= 0 then break end
			self:pulseToward(part.Position, 0.08)
		end
		self:releaseMovement()
		connection:Disconnect()
		return touchedAt ~= nil, self:trace("touch_target", if touchedAt then "touched" elseif reached then "not_touched" else "not_reached", {
			target = self:targetSnapshot(part), path_trace_ids = traces, touched_at_clock = touchedAt,
		}), touchedAt
	end

	function Driver:waitForAttribute(name: string, expected: any, timeout: number): (boolean, string)
		local deadline = os.clock() + timeout
		repeat
			if self.player:GetAttribute(name) == expected then
				return true, self:trace("wait_attribute", "matched", { name = name, expected = expected })
			end
			task.wait(0.04)
		until os.clock() >= deadline
		return false, self:trace("wait_attribute", "timeout", { name = name, expected = expected, actual = self.player:GetAttribute(name) })
	end

	function Driver:waitPumpWindow(pump: BasePart, inside: boolean, timeout: number): (boolean, string)
		local deadline = os.clock() + timeout
		repeat
			local value = pump:GetAttribute("TL_GaugeValue")
			if type(value) == "number" and ((inside and value >= 44 and value <= 56) or (not inside and (value < 25 or value > 75))) then
				return true, self:trace("wait_pump_window", "matched", { pump = pump:GetAttribute("TL_PumpId"), value = value, inside = inside })
			end
			task.wait(0.025)
		until os.clock() >= deadline
		return false, self:trace("wait_pump_window", "timeout", { pump = pump:GetAttribute("TL_PumpId"), inside = inside })
	end

	function Driver:waitHazard(hazard: BasePart, active: boolean, timeout: number): (boolean, string)
		local deadline = os.clock() + timeout
		repeat
			if hazard:GetAttribute("TL_Active") == active then
				return true, self:trace("wait_hazard_phase", "matched", { hazard = hazard:GetAttribute("TL_HazardId"), active = active })
			end
			task.wait(0.05)
		until os.clock() >= deadline
		return false, self:trace("wait_hazard_phase", "timeout", { hazard = hazard:GetAttribute("TL_HazardId"), active = active })
	end

	function Driver:waitRespawn(oldCharacter: Model, timeout: number): (boolean, Vector3?, string)
		local deadline = os.clock() + timeout
		repeat
			local character = self.player.Character
			if character and character ~= oldCharacter then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local root = character:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
					task.wait(0.25)
					return true, root.Position, self:trace("wait_respawn", "respawned", {})
				end
			end
			task.wait(0.08)
		until os.clock() >= deadline
		return false, nil, self:trace("wait_respawn", "timeout", {})
	end

	function Driver:restart(): (boolean, string, { [string]: any }, { [string]: any })
		local before = self:playerState()
		local oldRunId = before.TL_RunId
		local inputTrace = self:press(Enum.KeyCode.R, 0.12)
		local deadline = os.clock() + 2.2
		local success = false
		local central = self:onePart("TL_CentralSpawn")
		local finalDistance = math.huge
		repeat
			local state = self:playerState()
			local _, humanoid, root = self:character()
			finalDistance = horizontalDistance(root.Position, central.Position)
			if type(oldRunId) == "number" and state.TL_RunId == oldRunId + 1 and humanoid.Health > 0 and finalDistance <= 24 then
				success = true; break
			end
			task.wait(0.05)
		until os.clock() >= deadline
		local after = self:playerState()
		return success, self:trace("restart_episode", if success then "clean_and_central" else "timeout", {
			input_trace_id = inputTrace, state_before = before, state_after = after, central_distance = finalDistance,
		}), before, after
	end

	function Driver:clickRetry(): (boolean, string, { [string]: any }, { [string]: any })
		local gui = self.player:FindFirstChildOfClass("PlayerGui")
		local found = {}
		if gui then
			for _, instance in CollectionService:GetTagged("TL_RetryButton") do
				if instance:IsDescendantOf(gui) and (instance:IsA("TextButton") or instance:IsA("ImageButton")) then table.insert(found, instance) end
			end
		end
		if #found ~= 1 then
			local state = self:playerState()
			return false, self:trace("retry_mouse_click", "button_not_unique", { count = #found }), state, state
		end
		local button = found[1]
		local before = self:playerState()
		inputAdapter.centerMouse()
		task.wait(0.35)
		local current = UserInputService:GetMouseLocation()
		local desired = button.AbsolutePosition + button.AbsoluteSize / 2
		inputAdapter.moveMouseRelative(math.round(desired.X - current.X), math.round(desired.Y - current.Y))
		task.wait(0.25)
		inputAdapter.clickLeft()
		task.wait(0.6)
		local after = self:playerState()
		local success = after.TL_RunState == "Active" and after.TL_FinalStage == "Ready" and (after.TL_RetryCount or 0) == (before.TL_RetryCount or 0) + 1
		return success, self:trace("retry_mouse_click", if success then "accepted" else "no_state_change", {
			button_visible = actuallyVisible(button), desired = { x = desired.X, y = desired.Y },
			mouse_after = vector(Vector3.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y, 0)),
			state_before = before, state_after = after,
		}), before, after
	end

	function Driver:mouseLook(): (boolean, string)
		local camera = Workspace.CurrentCamera
		assert(camera, "CurrentCamera unavailable")
		local before = camera.CFrame.LookVector
		inputAdapter.dragMouse(120, -15)
		task.wait(0.5)
		local angle = math.acos(math.clamp(before:Dot(camera.CFrame.LookVector), -1, 1))
		return angle > math.rad(1), self:trace("mouse_look", if angle > math.rad(1) then "changed" else "unchanged", { angle = angle })
	end

	function Driver:runtimeSchema(): (boolean, string, { string })
		local problems = {}
		local function problem(text: string) table.insert(problems, text) end
		if Workspace:GetAttribute("TL_ContractVersion") ~= "tide-lock-v1" then problem("bad contract version") end
		if Workspace:GetAttribute("TL_Ready") ~= true then problem("TL_Ready is not true") end
		for tagName, count in EXPECTED_TAG_COUNTS do
			if #self:tagged(tagName) ~= count then problem(string.format("%s count != %d", tagName, count)) end
		end
		for _, name in PLAYER_ATTRIBUTES do if self.player:GetAttribute(name) == nil then problem("missing " .. name) end end
		for _, semanticId in INTERACTION_IDS do
			local ok, target = pcall(function() return self:semantic(semanticId) end)
			if not ok then problem(tostring(target)) else
				local prompt = self:prompt(target)
				if prompt.KeyboardKeyCode ~= Enum.KeyCode.E or prompt.MaxActivationDistance < 6 or prompt.MaxActivationDistance > 12
					or prompt.HoldDuration > 0.4 or prompt.RequiresLineOfSight then problem("invalid prompt " .. semanticId) end
				local approach = self:approachFor(semanticId)
				if not approach then problem("missing approach " .. semanticId)
				elseif not approach.Anchored or approach.CanCollide or approach.CanTouch then problem("invalid approach physics " .. semanticId) end
			end
		end
		local hud = self:hudMap()
		for _, role in HUD_ROLES do if not hud[role] then problem("missing HUD role " .. role) end end
		return #problems == 0, self:trace("runtime_schema", if #problems == 0 then "valid" else "invalid", { problems = problems }), problems
	end

	function Driver:cleanState(state: { [string]: any }): boolean
		return state.TL_RunState == "Active" and state.TL_RoutingComplete == false and state.TL_RoutingProgress == 0
			and state.TL_PressureComplete == false and state.TL_CoreTransferComplete == false
			and state.TL_CarryingCore == false and state.TL_Checkpoint == "Central"
			and state.TL_FinalStage == "Locked" and state.TL_CompletionState == "InProgress"
			and state.TL_DeathCount == 0 and state.TL_RetryCount == 0 and state.TL_FinalTime == 0
	end

	return Driver
end
