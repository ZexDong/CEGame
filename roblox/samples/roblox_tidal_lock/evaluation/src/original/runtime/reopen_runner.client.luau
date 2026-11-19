--!strict
local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local p=Players.LocalPlayer
local function trace(data) data.trace_id="tld-reopen-000001"; data.engine_time=Workspace:GetServerTimeNow(); print("TLD_TRACE "..HttpService:JSONEncode(data)); return data.trace_id end
print("TLD_EVAL_READY "..HttpService:JSONEncode({evaluator_version="tidal-lock-v2-reopen",mode="reopen"}))
local deadline=os.clock()+12 repeat task.wait(.1) until type(p:GetAttribute("TLD_RunId"))=="number" or os.clock()>deadline
local clean=Workspace:GetAttribute("TLD_Ready")==true and Workspace:GetAttribute("TLD_ContractVersion")=="tidal-lock-v1" and p:GetAttribute("TLD_PumpStep")==0 and p:GetAttribute("TLD_NextPump")=="Prime" and p:GetAttribute("TLD_PumpOnline")==false and p:GetAttribute("TLD_Lock1Level")=="Low" and p:GetAttribute("TLD_Lock2Level")=="Low" and p:GetAttribute("TLD_BargeLocation")=="Upstream" and p:GetAttribute("TLD_Checkpoint")=="Central" and p:GetAttribute("TLD_DeathCount")==0 and p:GetAttribute("TLD_Completed")==false and p:GetAttribute("TLD_FinalTime")==0
local id=trace({action="reopen_initial_state",outcome=clean and "clean" or "dirty",state={run_id=p:GetAttribute("TLD_RunId"),pump=p:GetAttribute("TLD_PumpStep"),lock1=p:GetAttribute("TLD_Lock1Level"),lock2=p:GetAttribute("TLD_Lock2Level"),barge=p:GetAttribute("TLD_BargeLocation"),completed=p:GetAttribute("TLD_Completed")}})
print("TLD_CHECKPOINT "..HttpService:JSONEncode({checkpoint_id="d4.reopen_clean",status=clean and "pass" or "fail",detail="A separately reopened PlayClient was checked before gameplay input.",trace_ids={id}}))
print("TLD_EVAL_DONE "..HttpService:JSONEncode({evaluator_version="tidal-lock-v2-reopen",mode="reopen",status="completed",trace_count=1,command_count=0}))
