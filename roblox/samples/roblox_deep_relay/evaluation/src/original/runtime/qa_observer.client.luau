--!strict
-- Passive observer: emits compact live samples and never mutates candidate state.
local CollectionService=game:GetService("CollectionService")
local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local function emit(kind:string,data:{[string]:any}?) local x=data or {}; x.kind=kind; print("DEEP_RELAY_OBSERVER "..HttpService:JSONEncode(x)) end
UserInputService.InputBegan:Connect(function(i,p) if not p then emit("input_began",{key=i.KeyCode.Name}) end end)
emit("observer_ready",{version="deep-relay-passive-v1"})
task.spawn(function()
	while true do
		local p=Players.LocalPlayer; local c=p.Character; local r=c and c:FindFirstChild("HumanoidRootPart"); local h=c and c:FindFirstChildOfClass("Humanoid")
		local state=CollectionService:GetTagged("DR_GameState")[1]
		if r and r:IsA("BasePart") and h and state then emit("sample",{x=r.Position.X,y=r.Position.Y,z=r.Position.Z,health=h.Health,event_seq=state:GetAttribute("DR_EventSeq"),last_event=state:GetAttribute("DR_LastEvent")}) end
		task.wait(0.5)
	end
end)
