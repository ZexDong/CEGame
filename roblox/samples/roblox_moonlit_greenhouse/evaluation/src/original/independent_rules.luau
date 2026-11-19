local S=require("./source/MoonlitGreenhouse/src/shared/Schema")
local R=require("./source/MoonlitGreenhouse/src/server/Rules")
local count=0
local function eq(a,b,label) count+=1;assert(a==b,label..": expected "..tostring(b).." got "..tostring(a)) end
local function act(s,a,b) return R.apply(s,S,a,b) end
local function lockedState()
 local s=R.newState(S)
 for cycle=1,4 do
  eq(s.water,8,"cycle water reset");eq(s.energy,6,"cycle energy reset")
  if cycle==3 then act(s,"Purge") end
  for _,id in ipairs({"A","B","C"}) do
   local t=S.Targets[cycle][id]
   for _=1,t.Water do act(s,"Water",id) end
   for _=1,t.Light do act(s,"Light",id) end
   for _=1,(t.Phase==0 and 0 or t.Phase==1 and 1 or 2) do act(s,"Phase",id) end
   act(s,"Lock",id)
   eq(s.beds[id].locked,true,"stable lock")
   local w,e=s.water,s.energy
   local bw,bl,bp=s.beds[id].water,s.beds[id].light,s.beds[id].phase
   for _,a in ipairs({"Water","Light","Phase","Lock"}) do act(s,a,id) end
   eq(s.water,w,"locked water immutable");eq(s.energy,e,"locked energy immutable")
   eq(s.beds[id].water,bw,"locked bed water");eq(s.beds[id].light,bl,"locked bed light");eq(s.beds[id].phase,bp,"locked phase")
  end
  act(s,"Commit")
 end
 return s
end
local s=R.newState(S)
for _=1,3 do act(s,"Water","A") end
eq(s.beds.A.water,3,"cap3");eq(s.water,5,"water use")
act(s,"Water","A");eq(s.beds.A.water,0,"fourth water wraps");eq(s.water,8,"water refund")
for _=1,8 do act(s,"Purge") end
eq(s.water,0,"purge exhausts water");eq(s.energy,14,"purge converts all water")
act(s,"Purge");eq(s.water,0,"purge no negative water");eq(s.energy,14,"purge rejected when dry")
s=R.newState(S);s.integrity=5
act(s,"Lock","A");eq(s.status,"Lost","integrity0 loses before fault4");eq(s.integrity,0,"integrity floor")
s=lockedState();eq(s.status,"Preview","preview first")
act(s,"Signal","A");eq(s.status,"Preview","early signal ignored");eq(s.signalIndex,0,"early index0")
eq(R.beginInput(s,S,123),true,"opens input");eq(s.deadline,135,"exact12s")
for _,id in ipairs({"A","C","B","A","C"}) do act(s,"Signal",id) end
eq(s.status,"Won","wins")
local w,e,i,f=s.water,s.energy,s.integrity,s.faults
for _,a in ipairs({"Water","Light","Phase","Lock","Commit","Purge","Signal","Scan","Reset"}) do act(s,a,"A") end
eq(s.status,"Won","Won absorbing");eq(s.water,w,"terminal water unchanged");eq(s.energy,e,"terminal energy unchanged");eq(s.integrity,i,"terminal integrity unchanged");eq(s.faults,f,"terminal faults unchanged")
eq(R.timeout(s,S),false,"expired Won timer ignored");eq(s.status,"Won","Won survives timeout")
s=lockedState();R.beginInput(s,S,0);act(s,"Signal","B")
eq(s.status,"Lost","wrong first loses");eq(s.signalIndex,0,"wrong first index")
act(s,"Signal","A");eq(s.status,"Lost","Lost absorbing")
s=lockedState();R.beginInput(s,S,0);eq(R.timeout(s,S),true,"input timeout");eq(s.status,"Lost","timeout Lost")
print("INDEPENDENT_RULES_PASS assertions="..count)
