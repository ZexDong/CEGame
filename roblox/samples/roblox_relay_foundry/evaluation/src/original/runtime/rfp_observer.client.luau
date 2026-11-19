--!strict
-- Passive QA observer: it never mutates candidate state or calls gameplay objects.
local CS=game:GetService("CollectionService") local HS=game:GetService("HttpService") local PPS=game:GetService("ProximityPromptService")
local P=game:GetService("Players").LocalPlayer local RS=game:GetService("RunService")
local tags={"RFP_CentralSpawn","RFP_CoreDock","RFP_ProductionBay","RFP_PurgeBay","RFP_DeliveryDock","RFP_SafetyCheckpoint","RFP_Hazard","RFP_ExitConsole","RFP_ExitDoor","RFP_EvacuationZone"}
local attrs={"RFP_RunId","RFP_OrderIndex","RFP_CorePhase","RFP_ChargeMode","RFP_StabilizeMode","RFP_EncodeMode","RFP_DeliveredCount","RFP_FaultCount","RFP_Checkpoint","RFP_Powered","RFP_Completed","RFP_RunStart","RFP_FinalTime","RFP_DeathCount","RFP_EventSerial","RFP_LastEvent","RFP_FeedbackText"}
local n=0 local function emit(k:string,d:any) n+=1; d=d or {}; d.kind=k; d.n=n; warn("RFP_OBSERVER "..HS:JSONEncode(d)) end
local function state() local x={} for _,a in attrs do x[a]=P:GetAttribute(a) end return x end
local function v(x:Vector3) return {x=x.X,y=x.Y,z=x.Z} end
local seen={} local touchAt={} local function hook(part:BasePart) if seen[part] then return end; seen[part]=true; part.Touched:Connect(function(hit) local c=P.Character if c and hit:IsDescendantOf(c) then local now=os.clock();if (touchAt[part] or 0)+.75<=now then touchAt[part]=now;emit("touched",{tags=CS:GetTags(part),position=v(part.Position),state=state()}) end end end) end
for _,t in tags do for _,x in CS:GetTagged(t) do if x:IsA("BasePart") then hook(x) end end; CS:GetInstanceAddedSignal(t):Connect(function(x) if x:IsA("BasePart") then hook(x) end end) end
P.CharacterAdded:Connect(function(c) emit("character_added",{state=state()}); local h=c:WaitForChild("Humanoid",10); if h and h:IsA("Humanoid") then h.Died:Connect(function() emit("died",{state=state()}) end) end end)
local function targets()
 local r={}
 for _,t in tags do
  local xs=CS:GetTagged(t)
  for _,x in xs do if x:IsA("BasePart") then
   local key=t;if t=="RFP_ProductionBay" then key=t..":"..tostring(x:GetAttribute("RFP_BayId")) end
   r[key]={position=v(x.Position),size=v(x.Size)}
  end end
 end
 return r
end
local function semanticPromptKey(prompt:ProximityPrompt):string?
 local x=prompt.Parent
 if not x or not x:IsA("BasePart") then return nil end
 if CS:HasTag(x,"RFP_ProductionBay") then return "RFP_ProductionBay:"..tostring(x:GetAttribute("RFP_BayId")) end
 for _,tag in tags do if CS:HasTag(x,tag) then return tag end end
 return nil
end
PPS.PromptShown:Connect(function(prompt)
 local key=semanticPromptKey(prompt);if key then emit("prompt",{key=key,keyboard=prompt.KeyboardKeyCode.Name,visible=true}) end
end)
PPS.PromptHidden:Connect(function(prompt)
 local key=semanticPromptKey(prompt);if key then emit("prompt",{key=key,keyboard=prompt.KeyboardKeyCode.Name,visible=false}) end
end)
-- Studio truncates long CreatorWarning JSON records. Emit each semantic target
-- as its own short record, then a small readiness marker that is never cut.
for key,record in targets() do emit("target",{key=key,record=record}) end
emit("ready",{contract=workspace:GetAttribute("RFP_ContractVersion")})
local a=0; RS.RenderStepped:Connect(function(dt) a+=dt;if a<.25 then return end;a=0;local c=P.Character;local r=c and c:FindFirstChild("HumanoidRootPart");local h=c and c:FindFirstChildOfClass("Humanoid");local cam=workspace.CurrentCamera;if r and h then emit("sample",{p=v(r.Position),camera=if cam then v(cam.CFrame.LookVector) else nil,speed=r.AssemblyLinearVelocity.Magnitude,health=h.Health,state=state()}) end end)
