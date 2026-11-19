--!strict
-- Private controller diagnostic.  This is deliberately not a scoring trajectory.
-- It proves the exact previously failing chain: wrong mode -> Faulted -> Purge -> Raw.
local HS=game:GetService("HttpService") local P=game:GetService("Players").LocalPlayer
local seq=0 local function out(kind:string,x:any) seq+=1;x=x or {};x.seq=seq;warn("RFP_RUNNER_"..kind.." "..HS:JSONEncode(x)) end
local function cmd(action:string,data:any?) data=data or {};data.action=action;out("COMMAND",data) end
local function waitFor(f:()->boolean,seconds:number):boolean local untilAt=os.clock()+seconds;repeat if f() then return true end;task.wait(.1) until os.clock()>untilAt;return false end
task.spawn(function()
 local ok,err=pcall(function()
  cmd("navigate_use",{tag="RFP_CoreDock",key="E",arrival_distance=9.5})
  local picked=waitFor(function()return P:GetAttribute("RFP_CorePhase")=="Raw"end,80)
  out("CHECK",{id="debug.core_dock_pickup",status=if picked then "pass" else "inconclusive",detail=if picked then "E changed CorePhase Absent→Raw" else "core dock was not reached or E was not accepted"})
  if not picked then return end
  local initialMode=P:GetAttribute("RFP_ChargeMode")
  cmd("navigate_use",{tag="RFP_ProductionBay:Charge",key="Q",arrival_distance=9.5})
  local cycled=waitFor(function()return P:GetAttribute("RFP_ChargeMode")~=initialMode end,80)
  if not cycled then out("CHECK",{id="debug.wrong_mode_purge",status="inconclusive",detail="Q was not accepted at Charge"});return end
  cmd("navigate_use",{tag="RFP_ProductionBay:Charge",key="E",arrival_distance=9.5})
  local faulted=waitFor(function()return P:GetAttribute("RFP_CorePhase")=="Faulted" and P:GetAttribute("RFP_LastEvent")=="Rejected.WrongMode"end,80)
  if not faulted then out("CHECK",{id="debug.wrong_mode_purge",status="inconclusive",detail="wrong-mode rejection was not established"});return end
  cmd("navigate_use",{tag="RFP_PurgeBay",key="E",arrival_distance=9.5})
  local purged=waitFor(function()return P:GetAttribute("RFP_CorePhase")=="Raw" and P:GetAttribute("RFP_LastEvent")=="CorePurged"end,80)
  out("CHECK",{id="debug.wrong_mode_purge",status=if purged then "pass" else "inconclusive",detail=if purged then "real E input established WrongMode→Faulted→CorePurged→Raw" else "Purge E did not restore Faulted core to Raw"})
  if not purged then return end
  for _=1,3 do
   if P:GetAttribute("RFP_ChargeMode")=="Pulse" then break end
   local before=P:GetAttribute("RFP_ChargeMode");cmd("navigate_use",{tag="RFP_ProductionBay:Charge",key="Q",arrival_distance=9.5})
   if not waitFor(function()return P:GetAttribute("RFP_ChargeMode")~=before end,80) then break end
  end
  local serial=P:GetAttribute("RFP_EventSerial") or 0
  cmd("navigate_use",{tag="RFP_ProductionBay:Charge",key="E",arrival_distance=9.5})
  local charged=waitFor(function()return P:GetAttribute("RFP_CorePhase")=="Charged"end,80)
  task.wait(1)
  local single=charged and P:GetAttribute("RFP_CorePhase")=="Charged" and (P:GetAttribute("RFP_EventSerial") or 0)==serial+1
  out("CHECK",{id="debug.correct_charge_single_fire",status=if single then "pass" else "inconclusive",detail=if single then "one real E produced exactly one Processed.Charge event" else "correct Charge E did not remain a single Charged transition"})
 end)
 out("DONE",{status=if ok then "completed" else "aborted",detail=if ok then "" else tostring(err)})
end)
