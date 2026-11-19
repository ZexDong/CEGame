--!strict
local HttpService=game:GetService("HttpService")
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local p=Players.LocalPlayer
local function trace(data) data.trace_id="ccp-reopen-000001"; data.engine_time=Workspace:GetServerTimeNow(); print("CCP_TRACE "..HttpService:JSONEncode(data)); return data.trace_id end
print("CCP_EVAL_READY "..HttpService:JSONEncode({evaluator_version="coolant-cargo-v1-reopen",mode="reopen"}))
local deadline=os.clock()+12 repeat task.wait(.1) until type(p:GetAttribute("CCP_RunId"))=="number" or os.clock()>deadline
local clean=Workspace:GetAttribute("CCP_Ready")==true and p:GetAttribute("CCP_CoolantStep")==0 and p:GetAttribute("CCP_CellState")=="Rack" and p:GetAttribute("CCP_CellCharged")==false and p:GetAttribute("CCP_ReactorStable")==false and p:GetAttribute("CCP_AirlockStage")=="Locked" and p:GetAttribute("CCP_Checkpoint")=="Central" and p:GetAttribute("CCP_DeathCount")==0 and p:GetAttribute("CCP_Completed")==false and p:GetAttribute("CCP_FinalTime")==0
local id=trace({action="reopen_initial_state",outcome=clean and "clean" or "dirty",state={run_id=p:GetAttribute("CCP_RunId"),coolant=p:GetAttribute("CCP_CoolantStep"),cell=p:GetAttribute("CCP_CellState"),airlock=p:GetAttribute("CCP_AirlockStage"),completed=p:GetAttribute("CCP_Completed")}})
print("CCP_CHECKPOINT "..HttpService:JSONEncode({checkpoint_id="d4.reopen_clean_session",status=clean and "pass" or "fail",detail="A separately reopened PlayClient was checked before gameplay input.",trace_ids={id}}))
print("CCP_EVAL_DONE "..HttpService:JSONEncode({evaluator_version="coolant-cargo-v1-reopen",mode="reopen",status="completed",trace_count=1,command_count=0}))
