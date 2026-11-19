--!strict
-- Passive Tide Lock observer. It reads live state and never changes candidate state.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local startedAt = os.clock()
local sequence = 0
local characterSerial = 0
local deathSerial = 0
local attached: { [BasePart]: boolean } = {}

local TAGS = {
	"TL_CentralSpawn", "TL_OrderDisplay", "TL_RoutingNode", "TL_PressurePump",
	"TL_CoreRack", "TL_CarryCore", "TL_CoreSocket", "TL_TransferCheckpoint",
	"TL_Hazard", "TL_TransferWaypoint", "TL_FinalLever", "TL_FinalConsole", "TL_ApproachPoint",
}
local ATTRIBUTES = {
	"TL_RunId", "TL_RunState", "TL_RoutingComplete", "TL_RoutingProgress", "TL_RoutingNext",
	"TL_PressureComplete", "TL_PumpPortState", "TL_PumpStarboardState",
	"TL_CoreTransferComplete", "TL_CarryingCore", "TL_Checkpoint", "TL_FinalStage",
	"TL_CompletionState", "TL_DeathCount", "TL_RetryCount", "TL_RunStart", "TL_FinalTime",
	"TL_EventSerial", "TL_LastEvent", "TL_EventDetail", "TL_FeedbackText",
}

local function vector(value: Vector3)
	return { x = value.X, y = value.Y, z = value.Z }
end

local function emit(kind: string, data: { [string]: any }?)
	sequence += 1
	local record = data or {}
	record.kind = kind
	record.sequence = sequence
	record.elapsed_s = os.clock() - startedAt
	print("TIDE_LOCK_OBSERVER " .. HttpService:JSONEncode(record))
end

local function playerAttributes(): { [string]: any }
	local result: { [string]: any } = {}
	for _, name in ATTRIBUTES do
		result[name] = player:GetAttribute(name)
	end
	return result
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

local function hudFields(): { [string]: any }
	local result: { [string]: any } = {}
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then return result end
	for _, item in CollectionService:GetTagged("TL_HUDField") do
		if item:IsDescendantOf(gui) and (item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox")) then
			local role = item:GetAttribute("TL_HudRole")
			if type(role) == "string" then
				result[role] = {
					text = item.Text,
					visible = actuallyVisible(item) and item.TextTransparency < 1 and item.AbsoluteSize.X > 1 and item.AbsoluteSize.Y > 1,
					x = item.AbsolutePosition.X, y = item.AbsolutePosition.Y,
					w = item.AbsoluteSize.X, h = item.AbsoluteSize.Y,
				}
			end
		end
	end
	return result
end

local function tagsFor(instance: Instance): { string }
	local result = {}
	for _, tagName in TAGS do
		if CollectionService:HasTag(instance, tagName) then table.insert(result, tagName) end
	end
	return result
end

local function attachPart(part: BasePart)
	if attached[part] then return end
	attached[part] = true
	part.Touched:Connect(function(hit)
		local character = player.Character
		if character and hit:IsDescendantOf(character) then
			emit("tagged_part_touched", {
				tags = tagsFor(part), semantic_id = part:GetAttribute("TL_SemanticId"),
				position = vector(part.Position), character_serial = characterSerial,
				death_serial = deathSerial, player_attributes = playerAttributes(),
			})
		end
	end)
end

local function refreshParts()
	for _, tagName in TAGS do
		for _, instance in CollectionService:GetTagged(tagName) do
			if instance:IsA("BasePart") then attachPart(instance) end
		end
	end
end

local function attachCharacter(character: Model)
	characterSerial += 1
	emit("character_added", { character_serial = characterSerial, player_attributes = playerAttributes() })
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			deathSerial += 1
			emit("humanoid_died", {
				death_serial = deathSerial, character_serial = characterSerial,
				player_attributes = playerAttributes(),
			})
		end)
	end
end

player.CharacterAdded:Connect(attachCharacter)
if player.Character then task.spawn(attachCharacter, player.Character) end
UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Keyboard or string.find(input.UserInputType.Name, "Mouse") then
		emit("input_began", { key = input.KeyCode.Name, input_type = input.UserInputType.Name, processed = processed })
	end
end)
UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Keyboard or string.find(input.UserInputType.Name, "Mouse") then
		emit("input_ended", { key = input.KeyCode.Name, input_type = input.UserInputType.Name, processed = processed })
	end
end)

refreshParts()
for _, tagName in TAGS do
	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance)
		if instance:IsA("BasePart") then attachPart(instance) end
	end)
end

task.spawn(function()
	local telemetry = ReplicatedStorage:WaitForChild("TL_PublicTelemetry", 15)
	if telemetry and telemetry:IsA("RemoteEvent") then
		telemetry.OnClientEvent:Connect(function(payload)
			emit("public_telemetry", { payload = payload })
		end)
	end
end)

local accumulator = 0
RunService.RenderStepped:Connect(function(delta)
	accumulator += delta
	if accumulator < 0.25 then return end
	accumulator = 0
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local camera = workspace.CurrentCamera
	if root and root:IsA("BasePart") and humanoid and camera then
		emit("sample", {
			character_serial = characterSerial, death_serial = deathSerial,
			position = vector(root.Position), velocity = vector(root.AssemblyLinearVelocity),
			health = humanoid.Health, floor_material = humanoid.FloorMaterial.Name,
			camera_look = vector(camera.CFrame.LookVector), viewport = vector(Vector3.new(camera.ViewportSize.X, camera.ViewportSize.Y, 0)),
			workspace_ready = workspace:GetAttribute("TL_Ready"),
			contract_version = workspace:GetAttribute("TL_ContractVersion"),
			player_attributes = playerAttributes(), hud_fields = hudFields(),
		})
	end
end)

emit("observer_ready", { observer_version = "tide-lock-passive-v1" })
