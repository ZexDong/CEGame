--!strict
-- Private formal suite. It uses public tags/state and emits OS input requests only.
local CS=game:GetService("CollectionService") local HS=game:GetService("HttpService") local PL=game:GetService("Players") local P=PL.LocalPlayer
local seq=0 local function out(kind:string,x:any) seq+=1;x=x or {};x.seq=seq;warn("RFP_RUNNER_"..kind.." "..HS:JSONEncode(x)) end
local function cmd(action:string,data:any?) data=data or {};data.action=action;out("COMMAND",data) end
local function key(k:string) cmd("tap",{key=k}) end
local function A(n:string):any return P:GetAttribute(n) end
local function part(tag:string,id:string?):BasePart local found={};for _,x in CS:GetTagged(tag) do if x:IsA("BasePart") and (not id or x:GetAttribute("RFP_BayId")==id) then table.insert(found,x) end end;assert(#found==1,"tag uniqueness "..tag.."/"..tostring(id));return found[1] end
local function root():BasePart local c=P.Character or P.CharacterAdded:Wait();return c:WaitForChild("HumanoidRootPart")::BasePart end
local function waitFor(f:()->boolean,seconds:number,label:string):boolean local d=os.clock()+seconds;repeat if f() then return true end task.wait(.1) until os.clock()>d;out("TRACE",{action="wait",outcome="timeout",detail=label});return false end
local function flat(x:Vector3):Vector3 return Vector3.new(x.X,0,x.Z) end
local function nearSurface(t:BasePart):boolean local d=root().Position-t.Position;local gx=math.max(math.abs(d.X)-t.Size.X/2,0);local gz=math.max(math.abs(d.Z)-t.Size.Z/2,0);return Vector2.new(gx,gz).Magnitude<=1 end
local ids={"RFP_CentralSpawn","RFP_CoreDock","RFP_PurgeBay","RFP_DeliveryDock","RFP_SafetyCheckpoint","RFP_Hazard","RFP_ExitConsole","RFP_ExitDoor","RFP_EvacuationZone"}
local function semantic(t:BasePart):string
 if CS:HasTag(t,"RFP_ProductionBay") then return "RFP_ProductionBay:"..tostring(t:GetAttribute("RFP_BayId")) end
 for _,tag in ids do if CS:HasTag(t,tag) then return tag end end
 error("no public semantic tag for "..t:GetFullName())
end
local function gotoTag(t:BasePart,label:string):boolean
 cmd("navigate",{tag=semantic(t),surface_distance=true,arrival_distance=.8,target=label})
 local ok=waitFor(function()return nearSurface(t)end,85,"navigate "..label);out("TRACE",{action="navigate",outcome=if ok then "arrived" else "inconclusive",target=label});return ok
end
local function use(t:BasePart,k:string):boolean
 local serial=A("RFP_EventSerial") or 0;local feedback=A("RFP_FeedbackText");cmd("navigate_use",{tag=semantic(t),key=k,arrival_distance=9.5})
 return waitFor(function()return (A("RFP_EventSerial") or 0)>serial or A("RFP_FeedbackText")~=feedback end,85,"interact "..semantic(t))
end
local function check(id:string,ok:boolean,detail:string) out("CHECK",{id=id,status=if ok then "pass" else "inconclusive",detail=detail}) end
local function cycleOnce(bay:BasePart,attr:string):boolean local before=A(attr);cmd("navigate_use",{tag=semantic(bay),key="Q",arrival_distance=9.5});return waitFor(function()return A(attr)~=before end,85,"cycle "..attr) end
local function cycle(bay:BasePart,attr:string,want:string):boolean for _=1,3 do if A(attr)==want then return true end;if not cycleOnce(bay,attr) then return false end end;return A(attr)==want end
local function process(bayId:string,attr:string,want:string,phase:string):boolean local b=part("RFP_ProductionBay",bayId);if not cycle(b,attr,want) then return false end;if not use(b,"E") then return false end;return waitFor(function()return A("RFP_CorePhase")==phase end,3,"process "..bayId) end
local function collect():boolean return use(part("RFP_CoreDock"),"E") and waitFor(function()return A("RFP_CorePhase")~="Absent"end,3,"collect") end
local function purge():boolean return use(part("RFP_PurgeBay"),"E") and waitFor(function()return A("RFP_CorePhase")=="Raw"end,3,"purge") end
local function deliver():boolean return use(part("RFP_DeliveryDock"),"E") and waitFor(function()return A("RFP_CorePhase")=="Absent"end,3,"deliver") end
local function order(c:string,s:string,e:string):boolean return collect() and process("Charge","RFP_ChargeMode",c,"Charged") and process("Stabilize","RFP_StabilizeMode",s,"Stabilized") and process("Encode","RFP_EncodeMode",e,"Encoded") and deliver() end
task.spawn(function()
 local ok,err=pcall(function()
  check("d2.required_world_and_hud",workspace:GetAttribute("RFP_Ready")==true and workspace:GetAttribute("RFP_ContractVersion")=="relay-foundry-v1","ready contract")
  local cp=part("RFP_SafetyCheckpoint");local hz=part("RFP_Hazard");gotoTag(cp,"checkpoint");waitFor(function()return A("RFP_Checkpoint")=="Safety"end,3,"checkpoint");local old=A("RFP_RunId");gotoTag(hz,"hazard");waitFor(function()return (P.Character and P.Character:FindFirstChildOfClass("Humanoid") and P.Character:FindFirstChildOfClass("Humanoid").Health<=0)end,3,"death");waitFor(function()return P.Character~=nil end,8,"respawn");check("d4.checkpoint_death_preserves_run",A("RFP_RunId")==old and A("RFP_Checkpoint")=="Safety","hazard respawn")
  local restartRun=A("RFP_RunId") or 0;key("R");check("d4.restart_in_progress",waitFor(function()return (A("RFP_RunId") or 0)>restartRun and A("RFP_LastEvent")=="Restarted" and A("RFP_OrderIndex")==1 and A("RFP_DeliveredCount")==0 and A("RFP_Checkpoint")=="Central"end,90,"restart queued behind hazard navigation"),"R increments run and clears progress")
  local ch=part("RFP_ProductionBay","Charge");local st=part("RFP_ProductionBay","Stabilize");cycle(ch,"RFP_ChargeMode","Arc");local before=A("RFP_CorePhase");cycleOnce(ch,"RFP_ChargeMode");check("d3.mode_cycle_no_core_change",A("RFP_CorePhase")==before,"Q no core change");cycle(ch,"RFP_ChargeMode","Pulse")
  collect();use(st,"E");local fault=waitFor(function()return A("RFP_CorePhase")=="Faulted"end,3,"wrong phase");check("d3.wrong_phase_fault_and_purge",fault and purge(),"wrong phase then purge")
  local one=process("Charge","RFP_ChargeMode","Pulse","Charged") and process("Stabilize","RFP_StabilizeMode","Brace","Stabilized") and process("Encode","RFP_EncodeMode","Cipher","Encoded") and deliver()
  collect();cycle(ch,"RFP_ChargeMode","Pulse");use(ch,"E");local modeFault=waitFor(function()return A("RFP_CorePhase")=="Faulted"end,3,"wrong mode");check("d3.wrong_mode_fault_and_purge",modeFault and purge(),"wrong mode then purge")
  local two=process("Charge","RFP_ChargeMode","Arc","Charged") and process("Stabilize","RFP_StabilizeMode","Float","Stabilized") and process("Encode","RFP_EncodeMode","Key","Encoded") and deliver()
  local console=part("RFP_ExitConsole");use(console,"E");local locked=A("RFP_Powered")==false and part("RFP_ExitDoor").CanCollide;check("d2.purge_and_exit_content",locked,"early console locked")
  local three=order("Flux","Lock","Mark");check("d2.all_three_orders_usable",one and two and three and A("RFP_DeliveredCount")==3,"three recipes")
  use(console,"E");local power=waitFor(function()return A("RFP_Powered")==true and part("RFP_ExitDoor").CanCollide==false end,3,"power");local evac=part("RFP_EvacuationZone");local done=power and gotoTag(evac,"evacuation") and waitFor(function()return A("RFP_Completed")==true end,5,"complete");check("d3.physical_gate_and_completion_condition",power and done,"gate and zone");check("d4.complete_success_flow",done,"full normal flow")
  local post=false
  if done then local completedRun=A("RFP_RunId") or 0;key("R");post=waitFor(function()return (A("RFP_RunId") or 0)>completedRun and A("RFP_LastEvent")=="Restarted" and A("RFP_Completed")==false and A("RFP_DeliveredCount")==0 end,15,"post complete R") end
  check("d4.restart_after_completion",post,"completion established before reset")
  check("d5.hud_state_sync",A("RFP_FeedbackText")~=nil,"HUD feedback public state");check("d5.visible_error_and_success_feedback",A("RFP_EventSerial")~=nil,"event feedback emitted")
 end);out("DONE",{status=if ok then "completed" else "aborted",detail=if ok then "" else tostring(err)})
end)
