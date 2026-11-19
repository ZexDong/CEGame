-- Exercise the candidate's published HUD and keyboard with native input.
-- No candidate remote calls, virtual Roblox input APIs or character mutation.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local HS=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local GS=game:GetService("GuiService")
local player=Players.LocalPlayer
local qa
local gui
local serial=0
local reported={}
local hovered={}
local activations={}
local mouseDowns=0
UIS.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 then mouseDowns+=1 end
end)
local function emit(packet)
 serial+=1; packet.sequence=serial
 local raw=HS:JSONEncode(packet)
 if #raw<=700 then print("SY_QA "..raw); return end
 for i=1,math.ceil(#raw/600) do
  print("SY_QA "..HS:JSONEncode({kind="chunk",packet=serial,part=i,total=math.ceil(#raw/600),data=raw:sub((i-1)*600+1,i*600)}))
 end
end
local function snapshot() return qa:InvokeServer() end
local function state(label)
 local s=snapshot().state; emit({kind="trace",label=label,state=s}); return s
end
local function check(id,ok,detail)
 reported[id]=true
 emit({kind="check",id=id,status=ok and "PASS" or "FAIL_OBSERVED",detail=detail})
end
local function segment(ids,fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then
  emit({kind="segment_error",detail=err})
  for _,id in ids do
   if not reported[id] then reported[id]=true; emit({kind="check",id=id,status="INCONCLUSIVE_EVALUATOR",detail=err}) end
  end
 end
end
local function key(k,duration,settle)
 emit({kind="input",key=k,down=true}); task.wait(duration or .12)
 emit({kind="input",key=k,down=false}); task.wait(settle or .15)
end
local function clean(s)
 local ok=s.Cycle==1 and s.Battery==6 and s.Fuel==6 and s.Integrity==100 and s.Faults==0
  and s.Delivered==0 and s.TotalDelivered==0 and s.Selected=="A" and s.Switch1=="Left" and s.Switch2=="Left"
  and s.FinalStage=="Locked" and s.FinalIndex==1 and s.FinalDeadline==0 and s.Active==true
 for _,id in {"A","B","C"} do ok=ok and s[id.."_Loaded"]==false and s[id.."_Delivered"]==false end
 return ok
end
local function visible(object)
 local p=object
 while p and p~=player.PlayerGui do
  if p:IsA("GuiObject") and not p.Visible then return false end
  if p:IsA("ScreenGui") and not p.Enabled then return false end
  p=p.Parent
 end
 return true
end
local function text(needle)
 for _,item in gui:GetDescendants() do
  if (item:IsA("TextLabel") or item:IsA("TextButton")) and visible(item)
   and item.Text:gsub("<[^>]*>",""):lower():find(needle:lower(),1,true) then return true end
 end
 return false
end
local function countExact(value)
 local count=0
 for _,item in gui:GetDescendants() do
  if item:IsA("TextLabel") and visible(item) and item.Text==value then count+=1 end
 end
 return count
end
local function hudEvidence(label)
 local out={}
 for _,item in gui:GetDescendants() do
  if item:IsA("TextLabel") or item:IsA("TextButton") then
   table.insert(out,{name=item:GetFullName(),text=item.Text,visible=visible(item),position={item.AbsolutePosition.X,item.AbsolutePosition.Y},size={item.AbsoluteSize.X,item.AbsoluteSize.Y}})
  end
 end
 emit({kind="hud",label=label,texts=out,viewport={workspace.CurrentCamera.ViewportSize.X,workspace.CurrentCamera.ViewportSize.Y}})
end
local function watchButton(item)
 if not item:IsA("GuiButton") then return end
 item.MouseEnter:Connect(function() hovered[item]=true end)
 item.MouseLeave:Connect(function() hovered[item]=nil end)
 item.Activated:Connect(function() activations[item]=(activations[item] or 0)+1 end)
end
local function buttonFor(action)
 local panel=assert(gui:FindFirstChild("DispatchPanel"),"DispatchPanel missing")
 if action:sub(1,7)=="Select:" then return assert(panel:FindFirstChild("Drone"..action:sub(8)),"Drone button missing") end
 local prefix=({Load="LOAD",Scan="SCAN ARRAY",Dispatch="DISPATCH",Switch1="SWITCH 1",Switch2="SWITCH 2",Commit="COMMIT"})[action:match("^[^:]+")]
 assert(prefix,"Unknown HUD action "..action)
 for _,item in panel:GetDescendants() do
  if item:IsA("TextButton") and item.Text:sub(1,#prefix)==prefix then return item end
 end
 error("Missing HUD button "..action)
end
local function pointAt(button,allowBlocked)
 assert(visible(button),"HUD target not visible")
 local center=button.AbsolutePosition+button.AbsoluteSize/2
 local inset=GS:GetGuiInset()
 local viewport=workspace.CurrentCamera.ViewportSize
 assert(center.X>0 and center.Y>0 and center.X<viewport.X and center.Y+inset.Y<viewport.Y,"HUD target clipped by viewport; enlarge Studio")
 for _,offset in {0,inset.Y,-inset.Y} do
  -- A small nudge generates MouseEnter even when the pointer was already nearby.
  local current=UIS:GetMouseLocation()
  emit({kind="pointer_move",dx=math.floor(center.X-current.X-2),dy=math.floor(center.Y+offset-current.Y)})
  task.wait(.18)
  emit({kind="pointer_move",dx=2,dy=0}); task.wait(.18)
  if hovered[button] then
   emit({kind="pointer_target",button=button.Text,hovered=true,offset=offset,localMouse={UIS:GetMouseLocation().X,UIS:GetMouseLocation().Y}})
   return
  end
 end
 if allowBlocked then
  local current=UIS:GetMouseLocation()
  emit({kind="pointer_move",dx=math.floor(center.X-current.X),dy=math.floor(center.Y+inset.Y-current.Y)})
  task.wait(.2)
  emit({kind="pointer_target",button=button.Text,hovered=false,overlayBlocks=true})
  return
 end
 error("Native pointer did not hover requested HUD button; no gameplay failure inferred")
end
local function awaitAction(action,before)
 local deadline=os.clock()+3
 local after=snapshot()
 while (after.actions[action] or 0)==(before.actions[action] or 0) and os.clock()<deadline do task.wait(.05); after=snapshot() end
 emit({kind="action_result",action=action,before=before.actions,after=after.actions,state=after.state})
 assert((after.actions[action] or 0)==(before.actions[action] or 0)+1,"Expected one real candidate action: "..action)
 for other,count in after.actions do assert(other==action or count==(before.actions[other] or 0),"Unexpected action also occurred: "..other) end
 return after.state
end
local function act(action)
 if action:sub(1,5)=="Load:" then assert(snapshot().state.Selected==action:sub(6),"Load requires the selected drone") end
 local button=buttonFor(action)
 pointAt(button,false)
 local before=snapshot()
 local clicks=activations[button] or 0
 emit({kind="mouse_click",target=action}); task.wait(.25)
 local after=awaitAction(action,before)
 assert((activations[button] or 0)==clicks+1,"Native click did not activate the intended HUD button exactly once")
 return after
end
local function keyAction(k,action)
 local before=snapshot(); key(k)
 return awaitAction(action,before)
end
local function restart()
 local s=keyAction("R","Restart")
 assert(clean(s),"Real R setup did not restore complete initial state")
 return s
end
local function setRoute(id)
 local s=state("published-route")
 local wanted=s[id.."_Route"]
 assert(wanted=="Left" or wanted=="Right","Missing published route for drone "..id)
 if s.Switch1~=wanted then act("Switch1") end
end
local function deliver(id)
 act("Select:"..id); act("Load:"..id); setRoute(id)
 local s=act("Dispatch")
 assert(s[id.."_Delivered"]==true,"Delivery prerequisite did not complete")
 return s
end
local function cycles()
 local valid=true
 for cycle=1,3 do
  for _,id in {"A","B","C"} do deliver(id) end
  local s=state("window-complete")
  valid=valid and s.Cycle==cycle and s.Delivered==3 and s.TotalDelivered==cycle*3 and s.Battery==3 and s.Fuel==3 and s.Integrity==100 and s.Faults==0
  s=act("Commit")
  if cycle<3 then
   valid=valid and s.Cycle==cycle+1 and s.Battery==6 and s.Fuel==6 and s.Delivered==0 and s.TotalDelivered==cycle*3
   for _,id in {"A","B","C"} do valid=valid and not s[id.."_Loaded"] and not s[id.."_Delivered"] end
  else assert(s.FinalStage=="Preview","Third Commit did not reach preview") end
 end
 local deadline=os.clock()+6
 local s=snapshot().state
 while s.FinalStage=="Preview" and os.clock()<deadline do task.wait(.1); s=snapshot().state end
 return s,valid
end
local function sameCore(a,b)
 for _,k in {"Cycle","Battery","Fuel","Integrity","Faults","Delivered","TotalDelivered","Selected","Switch1","Switch2","FinalStage","FinalIndex","Active","A_Loaded","B_Loaded","C_Loaded","A_Delivered","B_Delivered","C_Delivered"} do if a[k]~=b[k] then return false end end
 return true
end
local function run()
 emit({kind="client_loaded"})
 qa=RS:WaitForChild("SkylineSwitchyardPrivateQA",25)
 assert(qa,"Passive server observer missing")
 local deadline=os.clock()+30
 while not player:GetAttribute("SY_Ready") and os.clock()<deadline do task.wait(.2) end
 gui=player.PlayerGui:WaitForChild("SY_HUD",15)
 assert(gui,"Candidate HUD missing")
 for _,item in gui:GetDescendants() do watchButton(item) end
 gui.DescendantAdded:Connect(watchButton)
 task.wait(1)
 emit({kind="ready",inputPolicy="real HUD mouse clicks and keyboard only"})
 if RS:FindFirstChild("SkylineSwitchyardFreshProbe") then
  check("D4_REOPEN",clean(state("fresh")),"Independent Studio process has complete initial state")
  emit({kind="done"}); return
 end
 emit({kind="pointer_home"}); task.wait(.5)
 segment({"D1_BOOT","D1_CONTRACT","D1_WORLD","D5_HUD"},function()
  local s=state("initial")
  check("D1_BOOT",clean(s),"Complete deterministic initial state")
  local ok=type(s.Message)=="string" and type(s.RouteMap)=="string" and s.Contract=="skyline-switchyard-v1" and s.Ready==true and workspace:GetAttribute("SY_GameReady")==true
  for _,id in {"A","B","C"} do ok=ok and type(s[id.."_Loaded"])=="boolean" and type(s[id.."_Delivered"])=="boolean" and type(s[id.."_Route"])=="string" end
  ok=ok and s.A_Target=="NORTH" and s.B_Target=="EAST" and s.C_Target=="WEST" and type(s.FinalIndex)=="number" and type(s.FinalDeadline)=="number"
  check("D1_CONTRACT",ok,"Published status, destinations, per-drone routes and readiness")
  local world=workspace:FindFirstChild("SkylineSwitchyard")
  local worldOk=world~=nil
  for _,name in {"ElevatedDeck","Drone_A","Drone_B","Drone_C","SwitchBase1","SwitchBase2","DispatchConsole","CommitConsole","ScanConsole","NORTHHub","EASTHub","WESTHub"} do worldOk=worldOk and world~=nil and world:FindFirstChild(name,true)~=nil end
  check("D1_WORLD",worldOk,"Required deck, drones, switches, consoles and hubs; D6 remains manual")
  hudEvidence("initial")
  check("D5_HUD",text("WINDOW 1 / 3") and text("BATTERY") and text("FUEL") and countExact("6 / 6")>=2 and text("100%") and text("FAULTS") and text("DELIVERIES 0 / 3") and text("NORTH") and text("EAST") and text("WEST") and text("EMPTY"),"Initial battery/fuel values, integrity, faults and drone destination/status labels are present")
 end)
 segment({"D3_GATES","D2_LOAD","D3_DUPLICATE"},function()
  restart(); local a=act("Dispatch"); local b=act("Commit")
  check("D3_GATES",a.Fuel==6 and a.Delivered==0 and b.Cycle==1 and b.FinalStage=="Locked","Empty dispatch and premature Commit blocked")
  local s=act("Load:A")
  check("D2_LOAD",s.A_Loaded and s.Battery==5 and s.Fuel==6,"Real HUD Load costs exactly one battery")
  s=act("Load:A"); check("D3_DUPLICATE",s.A_Loaded and s.Battery==5,"Duplicate Load does not spend a second battery")
 end)
 segment({"D2_SWITCH","D2_SCAN"},function()
  restart(); local a=act("Switch1"); local b=act("Switch2"); local s=act("Switch1")
  check("D2_SWITCH",a.Switch1=="Right" and b.Switch2=="Right" and s.Switch1=="Left" and s.Battery==6 and s.Fuel==6,"Both switches toggle independently at no resource cost")
  s=act("Scan")
  check("D2_SCAN",s.Message:find("NORTH",1,true)~=nil and s.Message:find("EAST",1,true)~=nil and s.Message:find("WEST",1,true)~=nil and s.Message:find("CLEARANCE",1,true)~=nil and s.Battery==6 and s.Fuel==6,"Scan provides safe destinations and current clearance without resource cost")
 end)
 segment({"D2_DELIVERY","D3_REPEAT"},function()
  restart(); local s=deliver("A")
  check("D2_DELIVERY",s.A_Delivered and not s.A_Loaded and s.Delivered==1 and s.TotalDelivered==1 and s.Fuel==5 and s.Battery==5 and s.Integrity==100,"Correct published route delivers once and consumes one fuel")
  s=act("Dispatch"); check("D3_REPEAT",s.Delivered==1 and s.TotalDelivered==1 and s.Fuel==5,"Repeated Dispatch cannot deliver twice")
 end)
 segment({"D2_MISROUTE","D3_LOSS","D3_TERMINAL"},function()
  restart(); act("Switch1"); act("Load:A"); local s=act("Dispatch")
  check("D2_MISROUTE",s.Integrity==80 and s.Faults==1 and s.Fuel==5 and s.Delivered==0 and not s.A_Loaded,"Misroute costs 20 integrity, one fuel and one fault")
  for _=1,3 do act("Load:A"); s=act("Dispatch") end
  check("D3_LOSS",s.Integrity==20 and s.Faults==4 and s.FinalStage=="Lost" and s.Active==false,"Fourth fault ends the run before integrity reaches zero")
  local button=buttonFor("Dispatch")
  pointAt(button,true)
  local before=snapshot(); local inputs=mouseDowns
  emit({kind="mouse_click",target="Dispatch-terminal-attempt"}); task.wait(.5)
  local after=snapshot()
  emit({kind="terminal_attempt",mouseReceived=mouseDowns>inputs,before=before,after=after,overlayVisible=gui.FinalSequenceOverlay.Visible})
  assert(mouseDowns>inputs,"Terminal click was not received by the game")
  for name,count in after.actions do assert(name=="Dispatch" or count==(before.actions[name] or 0),"Terminal attempt hit another active action") end
  check("D3_TERMINAL",sameCore(before.state,after.state) and after.state.FinalStage=="Lost","Real click on Dispatch location leaves terminal gameplay state unchanged; overlay blocking or server rejection both enforce lock")
 end)
 segment({"D2_CYCLES","D4_WORKFLOW","D2_FINAL","D5_FINAL","D5_RESULT","D4_RESET"},function()
  restart(); local s,valid=cycles()
  check("D2_CYCLES",valid,"All three windows account for nine deliveries and refill/reset between windows")
  check("D4_WORKFLOW",s.FinalStage=="Input" and s.TotalDelivered==9 and s.Integrity==100 and s.Faults==0,"Uninterrupted nine-delivery workflow reaches final Input")
  assert(s.FinalStage=="Input","Final input prerequisite unmet")
  task.wait(.15); hudEvidence("final-input")
  check("D5_FINAL",text("ENTER SYNC SEQUENCE") and text("CLICK A / B / C") and text("FIXED SEQUENCE") and countExact("A")==2 and countExact("C")==2 and countExact("B")==1 and gui.FinalSequenceOverlay.Visible,"Final overlay shows input controls, accepted count and five sequence slots")
  assert(s.FinalDeadline-workspace:GetServerTimeNow()>6,"Evaluator input delay left insufficient time; no gameplay failure inferred")
  for _,k in {"A","C","B","A","C"} do s=keyAction(k,"Final:"..k) end
  check("D2_FINAL",s.FinalStage=="Won" and s.FinalIndex==6 and s.TotalDelivered==9,"Five real A-C-B-A-C keyboard actions produce victory")
  task.wait(.2); hudEvidence("result")
  check("D5_RESULT",s.FinalStage=="Won" and text("SKYLINE NETWORK ONLINE") and text("SYNC COMPLETE"),"Victory result is visible")
  s=keyAction("R","Restart")
  check("D4_RESET",clean(s),"Real R after victory restores complete initial state")
 end)
 segment({"D3_WRONG"},function()
  restart(); local s=cycles(); assert(s.FinalStage=="Input","Final input prerequisite unmet")
  s=keyAction("B","Final:B")
  check("D3_WRONG",s.FinalStage=="Lost" and s.FinalIndex==1 and not s.Won,"Wrong first real keyboard input loses without accepting a symbol")
 end)
 segment({"D3_TIMEOUT"},function()
  restart(); local s=cycles(); assert(s.FinalStage=="Input","Final input prerequisite unmet")
  local deadline=s.FinalDeadline
  assert(deadline-workspace:GetServerTimeNow()>2,"Evaluator missed timeout sampling window")
  task.wait(math.max(0,deadline-workspace:GetServerTimeNow()-1))
  local before=state("one-second-before-timeout")
  task.wait(math.max(0,deadline-workspace:GetServerTimeNow()+.3))
  local after=state("after-timeout")
  check("D3_TIMEOUT",before.FinalStage=="Input" and after.FinalStage=="Lost" and after.Message:find("TIMEOUT",1,true)~=nil,"Final stage remains open before its published 12-second deadline and loses after it")
 end)
 restart(); emit({kind="done"})
end
task.spawn(function() while true do task.wait(5); emit({kind="heartbeat"}) end end)
task.spawn(function()
 local ok,err=xpcall(run,debug.traceback)
 if not ok then emit({kind="error",detail=err}); emit({kind="done",incomplete=true}) end
end)
