--!strict
-- Passive read-only observer. It never mutates candidate state.
local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local function emit(kind:string,data:{[string]:any}?) local x=data or {}; x.kind=kind; print("TLD_OBSERVER "..HttpService:JSONEncode(x)) end
UIS.InputBegan:Connect(function(i,p) emit("input_began",{key=i.KeyCode.Name,processed=p}) end)
emit("observer_ready",{version="tidal-lock-v2-passive-v1"})
task.spawn(function()
 while true do
  local p=Players.LocalPlayer; local c=p.Character; local r=c and c:FindFirstChild("HumanoidRootPart"); local h=c and c:FindFirstChildOfClass("Humanoid")
  if r and r:IsA("BasePart") and h then emit("sample",{x=r.Position.X,y=r.Position.Y,z=r.Position.Z,health=h.Health,event_serial=p:GetAttribute("TLD_EventSerial"),last_event=p:GetAttribute("TLD_LastEvent")}) end
  task.wait(.5)
 end
end)
