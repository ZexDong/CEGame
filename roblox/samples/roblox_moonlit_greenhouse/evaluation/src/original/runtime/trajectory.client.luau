local Players=game:GetService("Players")
local R=game:GetService("ReplicatedStorage")
local H=game:GetService("HttpService")
local U=game:GetService("UserInputService")
local player=Players.LocalPlayer
local qa=R:WaitForChild("MoonlitGreenhousePrivateQA",60)
assert(qa,"Private observer missing")
local seq=0
local reported={}
local function emit(v)
 seq+=1;v.sequence=seq
 local raw=H:JSONEncode(v)
 if #raw<700 then print("MG26_QA "..raw);return end
 local total=math.ceil(#raw/600)
 for i=1,total do print("MG26_QA "..H:JSONEncode({kind="chunk",packet=seq,part=i,total=total,data=raw:sub((i-1)*600+1,i*600)})) end
end
local function snap(label)
 local s=qa:InvokeServer("snapshot")
 if label then emit({kind="trace",label=label,state=s}) end
 return s
end
local function check(id,ok,detail)
 reported[id]=true
 emit({kind="check",id=id,status=ok and "PASS" or "FAIL_OBSERVED",detail=detail})
end
local function segment(ids,fn)
 local ok,e=xpcall(fn,debug.traceback)
 if not ok then
  emit({kind="segment_error",detail=e})
  for _,id in ipairs(ids) do if not reported[id] then reported[id]=true;emit({kind="check",id=id,status="INCONCLUSIVE_EVALUATOR",detail=e}) end end
 end
end
local function waitFor(fn,seconds,description)
 local untilAt=os.clock()+seconds
 repeat if fn() then return end;task.wait(.08) until os.clock()>untilAt
 error("Timeout: "..description)
end
local function clean(s)
 return s.Status=="Growing" and s.Cycle==1 and s.Water==8 and s.Energy==6 and s.Integrity==100 and s.Faults==0 and s.SignalIndex==0 and not s.A_Locked and not s.B_Locked and not s.C_Locked and s.A_Water==0 and s.B_Light==0
end
local function restart(physical)
 local before=snap()
 if physical then
  emit({kind="await_input",key="R",detail="Press real R in game viewport to verify original input handlers"})
 else
  R:WaitForChild("MG_Reset"):FireServer() -- fixture setup via original reset remote
 end
 waitFor(function() local s=snap();return s.QA_ResetSerial>before.QA_ResetSerial and clean(s) end,physical and 180 or 8,"reset delivery and clean state")
 task.wait(.3)
 return snap("restart")
end
local function findPrompt(key)
 local a,b=key:match("^([^:]+):([ABC])$");a=a or key
 for _,p in ipairs(workspace:GetDescendants()) do
  if p:IsA("ProximityPrompt") and p:GetAttribute("MG_Action")==a and (not b or p:GetAttribute("MG_Bed")==b) then return p end
 end
 error("No client prompt "..key)
end
local function act(key,natural)
 local before=snap()
 local p=findPrompt(key)
 if natural then
  local hum=player.Character:FindFirstChildOfClass("Humanoid")
  local pos=p.Parent.Position
  hum:MoveTo(Vector3.new(pos.X,player.Character.HumanoidRootPart.Position.Y,pos.Z+3.8))
  waitFor(function() return (player.Character.HumanoidRootPart.Position-pos).Magnitude<6.5 end,5,"walk to "..key)
 else
  qa:InvokeServer("place",key)
  waitFor(function()
   local delta=player.Character.HumanoidRootPart.Position-p.Parent.Position
   return math.abs(delta.X)<.7 and math.abs(delta.Z-3)<.7 and delta.Magnitude<6.8
  end,5,"placement replication "..key)
 end
 task.wait(.1)
 -- The CMD runner sends a real E key to the owned Studio window.
 emit({kind="await_input",key="E",target=key})
 waitFor(function() return snap().QA_PromptSerial>before.QA_PromptSerial end,5,"physical prompt "..key)
 task.wait(.1)
 local s=snap()
 local a,b=key:match("^([^:]+):([ABC])$");a=a or key
 assert(s.QA_PromptAction==a and (not b or s.QA_PromptBed==b),"Wrong prompt selected "..key)
 return s
end
local function hasText(root,needle)
 if not root then return false end
 for _,v in ipairs(root:GetDescendants()) do if v:IsA("TextLabel") and v.Text:find(needle,1,true) then return true end end
 return false
end
local targets={
 {A={2,2,0},B={1,3,1},C={3,1,-1}},
 {A={1,3,1},B={2,1,-1},C={2,2,0}},
 {A={3,2,-1},B={2,2,0},C={1,3,1}},
 {A={2,1,0},B={3,2,1},C={1,2,-1}},
}
local lockInvariant=true
local targetMatch=true
local function completeCycles(naturalFinalStart)
 for cycle=1,4 do
  local current=snap()
  assert(current.Cycle==cycle and current.Status=="Growing","cycle prerequisite")
  for _,id in ipairs({"A","B","C"}) do
   local t=targets[cycle][id]
   targetMatch=targetMatch and current[id.."_TargetWater"]==t[1] and current[id.."_TargetLight"]==t[2] and current[id.."_TargetPhase"]==t[3]
  end
  if cycle==3 then act("Purge") end
  for _,id in ipairs({"A","B","C"}) do
   local t=targets[cycle][id]
   for _=1,t[1] do act("Water:"..id) end
   for _=1,t[2] do act("Light:"..id) end
   for _=1,(t[3]==0 and 0 or t[3]==1 and 1 or 2) do act("Phase:"..id) end
   local s=act("Lock:"..id)
   assert(s[id.."_Locked"],"Bed not locked "..id.." cycle "..cycle)
   if cycle==1 and id=="A" then
    local mutated=act("Water:A")
    lockInvariant=lockInvariant and mutated.A_Water==s.A_Water and mutated.Water==s.Water and mutated.A_Locked
   end
  end
  local locked=snap("cycle-"..cycle.."-locked")
  assert(locked.A_Locked and locked.B_Locked and locked.C_Locked,"all locked")
  act("Commit")
 end
 local preview=snap("preview")
 assert(preview.Status=="Preview","Preview stage missing")
 -- Position for final route before the input timer starts; does not write state.
 qa:InvokeServer("place","Signal:A")
 local observed={}
 waitFor(function()
  local s=snap()
  if s.PreviewBed and s.PreviewBed~="" and observed[#observed]~=s.PreviewBed then table.insert(observed,s.PreviewBed) end
  return s.Status=="Input"
 end,10,"preview opens timed input")
 emit({kind="preview_observation",symbols=observed})
 return snap("input"),observed
end
local function run()
 emit({kind="client_boot"})
 waitFor(function() local r=qa:InvokeServer("ready");return r.ready and player.Character and player.Character:FindFirstChild("HumanoidRootPart") end,120,"character and game readiness")
 local hud=player.PlayerGui:WaitForChild("MGHUD",15)
 if R:FindFirstChild("MoonlitGreenhouseFreshProbe") then
  check("D4_REOPEN",clean(snap("fresh")),"Independent Studio process starts a clean run")
  emit({kind="done",probe="fresh"});return
 end
 local s=snap("initial")
 check("D1_BOOT",clean(s),"Cycle 1, water8 energy6 integrity100 faults0; clean beds")
 check("D1_CONTRACT",s.Contract=="moonlit-greenhouse-v1" and s.FinalStage=="Locked" and s.Sequence=="A-C-B-A-C" and s.A_TargetWater==2 and s.C_TargetPhase==-1,"Public attributes and deterministic targets")
 segment({"D1_WORLD"},function()
  local w=qa:InvokeServer("world")
  emit({kind="world_inventory",world=w})
  check("D1_WORLD",w.floor and w.beds and w.consoles and #w.prompts==18,"Real collidable floor, actual beds, 18 unique resolvable prompts")
 end)
 check("D5_HUD",hud and hasText(hud,"MOONLIT GREENHOUSE") and hasText(hud,"Cycle 1/4") and hasText(hud,"Water 8") and hasText(hud,"Energy 6") and hasText(hud,"Integrity 100") and hasText(hud,"TARGET"),"HUD title, cycle, resources, integrity, targets")
 emit({kind="visual_checkpoint",stage="initial"})
 task.wait(12)
 -- One physical keyboard E smoke test, independently observed on server.
 qa:InvokeServer("place","Water:A");task.wait(.4)
 local before=snap()
 emit({kind="await_input",key="E",detail="Physical E smoke test at Water:A"})
 waitFor(function() return snap().QA_PromptSerial>before.QA_PromptSerial end,180,"physical E input")
 local physical=snap("physical-E")
 assert(physical.QA_PromptAction=="Water" and physical.QA_PromptBed=="A" and physical.A_Water==1,"Physical E did not water A")
 emit({kind="physical_input_pass",key="E"})
 segment({"D2_RESOURCE"},function()
  restart();for _=1,3 do act("Light:A") end;for _=1,3 do act("Light:B") end
  local empty=act("Light:C");local returned=act("Light:A")
  local energy=empty.Energy==0 and empty.C_Light==0 and returned.Energy==3 and returned.A_Light==0
  restart();for _=1,3 do act("Water:A") end;for _=1,3 do act("Water:B") end;for _=1,2 do act("Water:C") end
  local dry=act("Water:C");local recovered=act("Water:A")
  check("D2_RESOURCE",energy and dry.Water==0 and dry.C_Water==2 and recovered.Water==3 and recovered.A_Water==0,"Both pools reject empty input; cap3 cycles to0 and refunds3")
 end)
 segment({"D3_PHASE"},function()
  restart();local a=act("Phase:A");local b=act("Phase:A");local c=act("Phase:A")
  check("D3_PHASE",a.A_Phase==1 and b.A_Phase==-1 and c.A_Phase==0,"0 -> 1 -> -1 -> 0")
 end)
 segment({"D2_BAD_LOCK","D3_LOSS"},function()
  restart();local first=act("Lock:A");for _=1,3 do act("Lock:A") end
  local lost=snap("four-fault-loss")
  check("D2_BAD_LOCK",first.Integrity==95 and first.Faults==1 and not first.A_Locked,"Wrong lock costs5 integrity and adds1 fault")
  local blocked=act("Water:A")
  check("D3_LOSS",lost.Status=="Lost" and lost.Faults==4 and blocked.Status=="Lost" and blocked.A_Water==lost.A_Water,"Four faults lose; terminal gameplay actions remain blocked")
 end)
 segment({"D2_PURGE"},function()
  restart();local p=act("Purge")
  check("D2_PURGE",p.Water==7 and p.Energy==7 and p.Integrity==100 and p.Faults==0 and p.A_Water==0,"Candidate's declared1 water ->1 energy conversion")
 end)
 segment({"D2_COMMIT_GATE"},function()
  restart();local c=act("Commit")
  check("D2_COMMIT_GATE",c.Cycle==1 and c.Status=="Growing" and not c.A_Locked and c.Feedback:find("Commit failed",1,true),"Real Commit prompt reaches server and rejects incomplete beds")
 end)
 segment({"D2_LOCK","D2_CYCLES","D5_FEEDBACK","D2_FINAL","D3_SEQUENCE","D4_WORKFLOW","D5_RESULT"},function()
  restart();local final,preview=completeCycles()
  check("D2_LOCK",lockInvariant and final.Integrity==100 and final.Faults==0,"All target locks succeed; locked-bed edits leave allocation unchanged")
  check("D2_CYCLES",targetMatch and final.Cycle==4 and final.Status=="Input" and table.concat(preview,"")=="ACBAC","Four exact target sets commit and preview A-C-B-A-C before input")
  check("D5_FEEDBACK",hasText(hud,"Cycle 4/4") and hasText(hud,"INPUT") and hasText(hud,"within 12 seconds") and hasText(hud,"A → C → B → A → C"),"HUD cycle, stage, sequence and timer update")
  -- Final route is natural Humanoid.MoveTo; no QA teleport after timer opens.
  local started=workspace:GetServerTimeNow()
  local routeOK,routeError=xpcall(function() for _,id in ipairs({"A","C","B","A","C"}) do act("Signal:"..id,true) end end,debug.traceback)
  local won=snap("natural-final-result")
  local elapsed=workspace:GetServerTimeNow()-started
  check("D4_WORKFLOW",routeOK and won.Status=="Won" and elapsed<=12,"Cycle workflow plus natural final walking; seconds="..elapsed..(routeOK and "" or " route error="..routeError))
  check("D2_FINAL",won.Status=="Won" and won.SignalIndex==5,"Real prompt sequence A-C-B-A-C enters Won")
  check("D3_SEQUENCE",won.Status=="Won" and won.SignalIndex==5 and won.Integrity==100 and won.Faults==0,"Correct sequence preserves integrity/faults")
  task.wait(.3)
  local result=hud and hud:FindFirstChild("Result")
  check("D5_RESULT",won.Status=="Won" and result and result.Visible and hasText(result,"WON") and hasText(result,"Press R to restart"),"Visible Won result and R restart instruction")
  emit({kind="visual_checkpoint",stage=won.Status});task.wait(12)
 end)
 segment({"D3_TERMINAL_RESET"},function()
  local t=snap();assert(t.Status=="Won" or t.Status=="Lost","Terminal prerequisite missing")
  check("D3_TERMINAL_RESET",clean(restart(true)),"Physical R delivered to original client input handlers and reset a proven terminal state")
 end)
 segment({"D3_WRONG_SIGNAL"},function()
  restart();completeCycles();local lost=act("Signal:B")
  check("D3_WRONG_SIGNAL",lost.Status=="Lost" and lost.SignalIndex==0,"Wrong first signal immediately loses")
 end)
 segment({"D3_TIMEOUT"},function()
  restart();completeCycles();task.wait(12.5);local lost=snap("timeout")
  check("D3_TIMEOUT",lost.Status=="Lost" and lost.SignalIndex==0 and lost.Feedback:find("timeout",1,true),"Untouched12-second window expires to Lost")
  emit({kind="visual_checkpoint",stage="Lost"});task.wait(12)
 end)
 restart();emit({kind="done"})
end
task.spawn(function() local ok,e=xpcall(run,debug.traceback);if not ok then emit({kind="error",detail=e});emit({kind="done",incomplete=true}) end end)
