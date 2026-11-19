-- Private observation/character placement only. Never writes gameplay state.
local R=game:GetService("ReplicatedStorage")
local H=game:GetService("HttpService")
local P=game:GetService("Players")
local seen,resets={},{}
local function emit(v) print("MG26_QA "..H:JSONEncode(v)) end
local function canonical(prompt)
 local a=prompt:GetAttribute("MG_Action") or prompt.Parent:GetAttribute("MG_Action") or prompt.Parent:GetAttribute("Action")
 local b=prompt:GetAttribute("MG_Bed") or prompt.Parent:GetAttribute("MG_Bed") or prompt.Parent:GetAttribute("Bed") or ""
 local aliases={["Water+"]="Water",["Light+"]="Light",["Phase+"]="Phase",Pollinate="Signal"}
 a=aliases[a] or a
 if not a then
  local n=prompt.Name~="Interact" and prompt.Name or prompt.Parent.Name
  if n=="Commit" or n=="Scan" or n=="Purge" or n=="Purify" then a=n=="Purify" and "Purge" or n end
 end
 return a,b
end
local function inventory()
 local out={}
 for _,v in ipairs(workspace:GetDescendants()) do
  if v:IsA("ProximityPrompt") then
   local a,b=canonical(v)
   table.insert(out,{action=a or "MISSING",bed=b,path=v:GetFullName(),enabled=v.Enabled,distance=v.MaxActivationDistance,hold=v.HoldDuration})
  end
 end
 return out
end
local function resolve(key)
 local a,b=key:match("^([^:]+):([ABC])$")
 a=a or key
 local found={}
 for _,v in ipairs(workspace:GetDescendants()) do
  if v:IsA("ProximityPrompt") then local x,y=canonical(v); if x==a and (not b or y==b) then table.insert(found,v) end end
 end
 assert(#found==1,"PROMPT_RESOLUTION "..key.." matches="..#found)
 return found[1]
end
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt,player)
 local a,b=canonical(prompt)
 local prev=seen[player]
 seen[player]={serial=(prev and prev.serial or 0)+1,action=a,bed=b}
end)
task.spawn(function()
 for _,name in ipairs({"MG_Reset","MG_Restart"}) do
  local remote=R:WaitForChild(name,30)
  if remote then remote.OnServerEvent:Connect(function(player) resets[player]=(resets[player] or 0)+1 end) end
 end
end)
local function ready(player)
 local c=player.Character
 local root=c and c:FindFirstChild("HumanoidRootPart")
 local hum=c and c:FindFirstChildOfClass("Humanoid")
 return {ready=root~=nil and hum~=nil and hum.Health>0 and player:GetAttribute("MG_Cycle")~=nil,root=root~=nil,health=hum and hum.Health or -1,contract=player:GetAttribute("MG_Contract") or workspace:GetAttribute("MG_Contract")}
end
local qa=Instance.new("RemoteFunction")
qa.Name="MoonlitGreenhousePrivateQA"
qa.Parent=R
qa.OnServerInvoke=function(player,op,key)
 if op=="ready" then return ready(player) end
 if op=="snapshot" then
  local s={}
  for k,v in pairs(player:GetAttributes()) do if k:sub(1,3)=="MG_" then s[k:sub(4)]=v end end
  s.QA_PromptSerial=seen[player] and seen[player].serial or 0
  s.QA_PromptAction=seen[player] and seen[player].action or ""
  s.QA_PromptBed=seen[player] and seen[player].bed or ""
  s.QA_ResetSerial=resets[player] or 0
  return s
 end
 if op=="inventory" then return inventory() end
 if op=="world" then
  local root=workspace:FindFirstChild("MoonlitGreenhouse")
  local floor=root and root:FindFirstChild("ContinuousFloor")
  local beds=root and root:FindFirstChild("BedA") and root:FindFirstChild("BedB") and root:FindFirstChild("BedC")
  local keys={"Commit","Scan","Purge","Signal:A","Signal:B","Signal:C"}
  local valid=true
  for _,k in ipairs(keys) do if not pcall(resolve,k) then valid=false end end
  return {floor=floor~=nil and floor:IsA("BasePart") and floor.CanCollide,beds=beds~=nil,prompts=inventory(),consoles=valid,walkSpeed=player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed}
 end
 if op=="place" then
  local p=resolve(key)
  local c=player.Character
  assert(c and c:FindFirstChild("HumanoidRootPart"),"No live character")
  local root=c.HumanoidRootPart
  local target=p.Parent
  -- Clear the small console collision volume and keep the requested prompt nearest.
  c:PivotTo(CFrame.new(target.Position+Vector3.new(0,3.2,3),target.Position))
  root.AssemblyLinearVelocity=Vector3.zero
  root.AssemblyAngularVelocity=Vector3.zero
  return {ok=true,path=p:GetFullName(),position={target.Position.X,target.Position.Y,target.Position.Z}}
 end
 error("Unknown observation operation "..tostring(op))
end
emit({kind="server_boot"})
