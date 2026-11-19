-- Passive evidence only. Candidate handlers remain the sole gameplay writers.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local counts={}
local promptCounts={}
local wired={}
local function watchRemote(item)
 if item.Name=="SY_Action" and item:IsA("RemoteEvent") and not wired[item] then
  wired[item]=true
  item.OnServerEvent:Connect(function(player,action)
   if type(action)~="string" then return end
   counts[player]=counts[player] or {}
   counts[player][action]=(counts[player][action] or 0)+1
  end)
 end
end
RS.ChildAdded:Connect(watchRemote)
for _,item in RS:GetChildren() do watchRemote(item) end
local function watchPrompt(item)
 if item:IsA("ProximityPrompt") and not wired[item] then
  wired[item]=true
  item.Triggered:Connect(function(player)
   promptCounts[player]=promptCounts[player] or {}
   local name=item:GetFullName()
   promptCounts[player][name]=(promptCounts[player][name] or 0)+1
  end)
 end
end
workspace.DescendantAdded:Connect(watchPrompt)
for _,item in workspace:GetDescendants() do watchPrompt(item) end
Players.PlayerRemoving:Connect(function(player) counts[player]=nil; promptCounts[player]=nil end)
local qa=Instance.new("RemoteFunction")
qa.Name="SkylineSwitchyardPrivateQA"
qa.OnServerInvoke=function(player)
 local state={}
 for k,v in player:GetAttributes() do if k:sub(1,3)=="SY_" then state[k:sub(4)]=v end end
 return {state=state,actions=counts[player] or {},triggered=promptCounts[player] or {},serverTime=workspace:GetServerTimeNow()}
end
qa.Parent=RS
