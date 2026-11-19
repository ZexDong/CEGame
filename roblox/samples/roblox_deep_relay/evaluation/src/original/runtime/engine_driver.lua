--!strict
-- Deep Relay read-only engine driver. All actuation is requested as ordinary OS input.

local function buildEngineDriver(inputAdapter: any, emitTrace: any)
	local CollectionService = game:GetService("CollectionService")
	local PathfindingService = game:GetService("PathfindingService")
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local Workspace = game:GetService("Workspace")
	local Driver = {}
	Driver.__index = Driver
	local STATE_NAMES = {
		"DR_ProtocolVersion","DR_RunId","DR_RunStatus","DR_Phase","DR_PowerState","DR_PowerBreakerProgress",
		"DR_CoolantState","DR_CoolantPressure","DR_AuthState","DR_AuthScanProgress","DR_AssemblyState",
		"DR_AssemblyProgress","DR_CarryItemId","DR_AirlockState","DR_CheckpointId","DR_HazardState",
		"DR_CoreInstalled","DR_StabilizerProgress","DR_StabilizerDeadline","DR_ObjectiveId","DR_DeathCount",
		"DR_RunStart","DR_FinalTime","DR_EventSeq","DR_LastEvent","DR_LastSourceId","DR_LastRejectCode","DR_FeedbackText",
	}

	local function vec(v: Vector3) return {x=v.X,y=v.Y,z=v.Z} end
	local function hdist(a: Vector3,b: Vector3) return Vector3.new(a.X-b.X,0,a.Z-b.Z).Magnitude end
	local function visible(g: GuiObject): boolean
		local at: Instance? = g
		while at do
			if at:IsA("GuiObject") and not at.Visible then return false end
			if at:IsA("LayerCollector") and not at.Enabled then return false end
			at=at.Parent
		end
		return true
	end

	function Driver.new()
		local self=setmetatable({},Driver)
		self.player=Players.LocalPlayer
		self.state=nil
		self.inputCounts={}
		self.unprocessedInputCounts={}
		UserInputService.InputBegan:Connect(function(input:any,processed:boolean)
			local name=input.KeyCode.Name
			self.inputCounts[name]=(self.inputCounts[name] or 0)+1
			if not processed then self.unprocessedInputCounts[name]=(self.unprocessedInputCounts[name] or 0)+1 end
		end)
		return self
	end

	function Driver:character(): (Model,Humanoid,BasePart)
		local deadline=os.clock()+15
		repeat
			local c=self.player.Character
			if c then
				local h=c:FindFirstChildOfClass("Humanoid")
				local r=c:FindFirstChild("HumanoidRootPart")
				if h and r and r:IsA("BasePart") then return c,h,r end
			end
			task.wait(0.05)
		until os.clock()>deadline
		error("character unavailable")
	end

	function Driver:gameState(): Configuration
		if self.state and self.state.Parent then return self.state end
		local found=CollectionService:GetTagged("DR_GameState")
		assert(#found==1 and found[1]:IsA("Configuration"),"DR_GameState must be one Configuration")
		self.state=found[1]
		return self.state
	end

	function Driver:optionalGameState(): Configuration?
		if self.state and self.state.Parent then return self.state end
		local found=CollectionService:GetTagged("DR_GameState")
		if #found==1 and found[1]:IsA("Configuration") then
			self.state=found[1]
			return found[1]
		end
		return nil
	end

	function Driver:safeStateMap(): ({[string]:any},boolean)
		local out={}
		local state=self:optionalGameState()
		if not state then return out,false end
		for _,name in STATE_NAMES do out[name]=state:GetAttribute(name) end
		return out,true
	end

	function Driver:stateMap(): {[string]:any}
		local s=self:gameState(); local out={}
		for _,n in STATE_NAMES do out[n]=s:GetAttribute(n) end
		return out
	end

	function Driver:hudMap(): {[string]:any}
		local out={}
		for _,g in CollectionService:GetTagged("DR_HUDField") do
			if g:IsA("GuiObject") and g:IsDescendantOf(self.player.PlayerGui) then
				local id=g:GetAttribute("DR_FieldId")
				if type(id)=="string" then
					out[id]={text=if g:IsA("TextLabel") or g:IsA("TextButton") or g:IsA("TextBox") then g.Text else "",visible=visible(g),x=g.AbsolutePosition.X,y=g.AbsolutePosition.Y,w=g.AbsoluteSize.X,h=g.AbsoluteSize.Y,transparency=if g:IsA("TextLabel") then g.TextTransparency else nil}
				end
			end
		end
		return out
	end

	function Driver:scene(extra: {[string]:any}?): {[string]:any}
		local x=extra or {}
		local ok,result=pcall(function()
			local _,h,r=self:character()
			return {position=vec(r.Position),velocity=vec(r.AssemblyLinearVelocity),health=h.Health,walk_speed=h.WalkSpeed,floor_material=h.FloorMaterial.Name}
		end)
		if ok then
			local characterState=result :: any
			x.position=characterState.position; x.velocity=characterState.velocity; x.health=characterState.health
			x.walk_speed=characterState.walk_speed; x.floor_material=characterState.floor_material
		else
			x.character_error=tostring(result)
		end
		local state,statePresent=self:safeStateMap(); x.game_state=state; x.game_state_present=statePresent
		x.workspace_ready=Workspace:GetAttribute("DR_Ready"); x.contract_version=Workspace:GetAttribute("DR_ContractVersion")
		return x
	end

	function Driver:trace(action:string,outcome:string,data:{[string]:any}?): string
		local x=self:scene(data); x.action=action; x.outcome=outcome; return emitTrace(x)
	end

	function Driver:waitReady(timeout:number): (boolean,string)
		local deadline=os.clock()+timeout
		repeat
			local ok=pcall(function() self:character(); self:gameState() end)
			if ok and Workspace:GetAttribute("DR_Ready")==true and Workspace:GetAttribute("DR_ContractVersion")=="deep-relay-v1" then
				task.wait(0.5); return true,self:trace("wait_ready","ready",{})
			end
			task.wait(0.1)
		until os.clock()>deadline
		return false,self:trace("wait_ready","timeout",{})
	end

	function Driver:tagged(tag:string): {Instance} return CollectionService:GetTagged(tag) end
	function Driver:findInteraction(id:string): BasePart?
		local found={}
		for _,x in self:tagged("DR_Interactable") do
			if x:IsA("BasePart") and x:GetAttribute("DR_InteractionId")==id then table.insert(found,x) end
		end
		if #found==1 then return found[1] end
		return nil
	end
	function Driver:interaction(id:string): BasePart
		local found={}
		for _,x in self:tagged("DR_Interactable") do if x:IsA("BasePart") and x:GetAttribute("DR_InteractionId")==id then table.insert(found,x) end end
		assert(#found==1,"interaction uniqueness failed: "..id); return found[1]
	end
	function Driver:node(id:string): BasePart
		local found={}
		for _,x in self:tagged("DR_NavNode") do if x:IsA("BasePart") and x:GetAttribute("DR_NodeId")==id then table.insert(found,x) end end
		assert(#found==1,"nav node uniqueness failed: "..id); return found[1]
	end
	function Driver:onePart(tag:string): BasePart
		local found={}; for _,x in self:tagged(tag) do if x:IsA("BasePart") then table.insert(found,x) end end
		assert(#found==1,tag.." expected one BasePart"); return found[1]
	end
	function Driver:prompt(part:BasePart): ProximityPrompt
		local found={}; for _,x in part:GetDescendants() do if x:IsA("ProximityPrompt") then table.insert(found,x) end end
		assert(#found==1,"exactly one prompt required"); return found[1]
	end

	function Driver:instanceSnapshot(instance:Instance?): {[string]:any}
		if not instance then return {present=false} end
		local out:{[string]:any}={present=true,name=instance.Name,class=instance.ClassName,attributes=instance:GetAttributes()}
		if instance:IsA("BasePart") then
			out.position=vec(instance.Position); out.size=vec(instance.Size); out.can_collide=instance.CanCollide
			out.can_touch=instance.CanTouch; out.transparency=instance.Transparency
			local prompts={}
			for _,child in instance:GetDescendants() do
				if child:IsA("ProximityPrompt") then
					table.insert(prompts,{enabled=child.Enabled,key=child.KeyboardKeyCode.Name,hold_duration=child.HoldDuration,max_distance=child.MaxActivationDistance,action_text=child.ActionText})
				end
			end
			out.prompts=prompts
		end
		return out
	end

	function Driver:interactionSchema(ids:{string}): {[string]:any}
		local out={}
		for _,id in ids do out[id]=self:instanceSnapshot(self:findInteraction(id)) end
		return out
	end

	function Driver:degradedSnapshot(): {[string]:any}
		local tags={}
		for _,tag in {"DR_CentralSpawn","DR_GameState","DR_Interactable","DR_CarryItem","DR_ItemStation","DR_AirlockDoor","DR_Hazard","DR_SafeZone","DR_NavNode","DR_NavLink","DR_HUDField"} do tags[tag]=#self:tagged(tag) end
		local state,statePresent=self:safeStateMap()
		local doors={}; for _,door in self:tagged("DR_AirlockDoor") do table.insert(doors,self:instanceSnapshot(door)) end
		local hazards={}; for _,hazard in self:tagged("DR_Hazard") do table.insert(hazards,self:instanceSnapshot(hazard)) end
		return {counts=tags,state=state,state_present=statePresent,hud=self:hudMap(),doors=doors,hazards=hazards,workspace_ready=Workspace:GetAttribute("DR_Ready"),contract_version=Workspace:GetAttribute("DR_ContractVersion")}
	end

	function Driver:compactDegradedSnapshot(snapshot:{[string]:any}): {[string]:any}
		local stateAttributeCount=0; for _ in snapshot.state do stateAttributeCount+=1 end
		local hudIds={}; for id in snapshot.hud do table.insert(hudIds,id) end; table.sort(hudIds)
		local doors={}
		for _,door in snapshot.doors do table.insert(doors,{id=door.attributes and door.attributes.DR_DoorId or "",can_collide=door.can_collide}) end
		local hazards={}
		for _,hazard in snapshot.hazards do table.insert(hazards,{id=hazard.attributes and hazard.attributes.DR_HazardId or "",active=hazard.attributes and hazard.attributes.DR_Active,can_collide=hazard.can_collide}) end
		return {counts=snapshot.counts,state_present=snapshot.state_present,state_attribute_count=stateAttributeCount,hud_ids=hudIds,doors=doors,hazards=hazards,workspace_ready=snapshot.workspace_ready,contract_version=snapshot.contract_version}
	end

	function Driver:compactInteractionSchema(snapshot:{[string]:any}): {[string]:any}
		local requestedCount=0; local presentCount=0; local validPromptCount=0; local missingIds={}; local invalidPromptIds={}
		for id,object in snapshot do
			requestedCount+=1
			if object.present==true then presentCount+=1 else table.insert(missingIds,id) end
			local prompts=object.prompts
			if type(prompts)=="table" and #prompts==1 and prompts[1].enabled==true and prompts[1].key=="E" then validPromptCount+=1 else table.insert(invalidPromptIds,id) end
		end
		table.sort(missingIds); table.sort(invalidPromptIds)
		return {requested_count=requestedCount,present_count=presentCount,valid_prompt_count=validPromptCount,missing_ids=missingIds,invalid_prompt_ids=invalidPromptIds}
	end

	function Driver:inputCount(key:Enum.KeyCode): number return self.inputCounts[key.Name] or 0 end
	function Driver:unprocessedInputCount(key:Enum.KeyCode): number return self.unprocessedInputCounts[key.Name] or 0 end

	function Driver:pulseKey(key:Enum.KeyCode,duration:number): (boolean,string)
		local beforeCount=self:inputCount(key)
		local beforeUnprocessed=self:unprocessedInputCount(key)
		local beforePosition:Vector3?=nil
		pcall(function() local _,_,root=self:character(); beforePosition=root.Position end)
		inputAdapter.sendKeyEvent(true,key); task.wait(duration); inputAdapter.sendKeyEvent(false,key); task.wait(0.25)
		local afterPosition:Vector3?=nil
		pcall(function() local _,_,root=self:character(); afterPosition=root.Position end)
		local observed=self:inputCount(key)>beforeCount
		local moved=if beforePosition and afterPosition then (afterPosition-beforePosition).Magnitude else 0
		return observed,self:trace("real_key_input",observed and "observed" or "not_observed",{key=key.Name,duration_s=duration,moved_distance=moved,unprocessed_observed=self:unprocessedInputCount(key)>beforeUnprocessed})
	end

	function Driver:attemptInteractionSafe(id:string,hold:number?): (boolean,{string},{[string]:any},{[string]:any})
		local traces={}
		local part=self:findInteraction(id)
		if not part then
			table.insert(traces,self:trace("safe_interaction","missing",{interaction_id=id}))
			return false,traces,{},{}
		end
		local promptOk,promptResult=pcall(function() return self:prompt(part) end)
		if not promptOk then
			table.insert(traces,self:trace("safe_interaction","invalid_prompt",{interaction_id=id,error=tostring(promptResult),object=self:instanceSnapshot(part)}))
			return false,traces,{},{}
		end
		local prompt=promptResult :: ProximityPrompt
		local nodeId=part:GetAttribute("DR_ApproachNodeId")
		local node:BasePart?=nil
		if type(nodeId)=="string" then
			local okNode,result=pcall(function() return self:node(nodeId) end)
			if okNode then node=result :: BasePart end
		end
		if not node then
			table.insert(traces,self:trace("safe_interaction","missing_approach_node",{interaction_id=id,node_id=nodeId,object=self:instanceSnapshot(part)}))
			return false,traces,{},{}
		end
		local reached,navTraces=self:navigate(node.Position,2.5,24)
		for _,traceId in navTraces do table.insert(traces,traceId) end
		if not reached then
			table.insert(traces,self:trace("safe_interaction","navigation_unresolved",{interaction_id=id,node_id=nodeId}))
			return false,traces,{},{}
		end
		local _,_,root=self:character()
		local promptPosition=if prompt.Parent:IsA("Attachment") then prompt.Parent.WorldPosition else part.Position
		local distance=(root.Position-promptPosition).Magnitude
		if distance>prompt.MaxActivationDistance+1 then
			table.insert(traces,self:trace("safe_interaction","prompt_out_of_range",{interaction_id=id,distance=distance,max_distance=prompt.MaxActivationDistance}))
			return false,traces,{},{}
		end
		local beforeState,_=self:safeStateMap(); local beforeObject=self:instanceSnapshot(part)
		local beforeE=self:inputCount(Enum.KeyCode.E)
		local beforeUnprocessedE=self:unprocessedInputCount(Enum.KeyCode.E)
		local duration=hold or math.max(0.12,prompt.HoldDuration+0.15)
		inputAdapter.sendKeyEvent(true,Enum.KeyCode.E); task.wait(duration); inputAdapter.sendKeyEvent(false,Enum.KeyCode.E); task.wait(0.4)
		local afterState,_=self:safeStateMap(); local observed=self:inputCount(Enum.KeyCode.E)>beforeE
		local function stateDigest(state:any): any
			return {event_seq=state.DR_EventSeq,last_event=state.DR_LastEvent,last_reject=state.DR_LastRejectCode,carry=state.DR_CarryItemId,power=state.DR_PowerState,pressure=state.DR_CoolantPressure,auth=state.DR_AuthState,assembly=state.DR_AssemblyProgress}
		end
		table.insert(traces,self:trace("safe_prompt_input",observed and "observed" or "not_observed",{interaction_id=id,duration_s=duration,distance=distance,prompt_enabled=prompt.Enabled,input_observed=observed,unprocessed_observed=self:unprocessedInputCount(Enum.KeyCode.E)>beforeUnprocessedE,before_state=stateDigest(beforeState),after_state=stateDigest(afterState),object_present=beforeObject.present}))
		return observed,traces,beforeState,afterState
	end

	function Driver:observeHazardWindow(duration:number): string
		local samples={}; local deadline=os.clock()+duration
		repeat
			local tagged=self:tagged("DR_Hazard"); local active=nil
			if #tagged==1 then active=tagged[1]:GetAttribute("DR_Active") end
			local state,_=self:safeStateMap()
			table.insert(samples,{active=active,state=state.DR_HazardState})
			task.wait(0.5)
		until os.clock()>deadline
		return self:trace("hazard_phase_window","observed",{duration_s=duration,samples=samples})
	end

	function Driver:releaseMovement()
		for _,k in {Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Space} do inputAdapter.sendKeyEvent(false,k) end
	end
	function Driver:pulse(target:Vector3,duration:number)
		local _,h,r=self:character(); if h.Health<=0 then return end
		local cam=Workspace.CurrentCamera; assert(cam,"camera unavailable")
		local d=Vector3.new(target.X-r.Position.X,0,target.Z-r.Position.Z); if d.Magnitude<0.05 then return end; d=d.Unit
		local f=Vector3.new(cam.CFrame.LookVector.X,0,cam.CFrame.LookVector.Z); if f.Magnitude<0.05 then f=Vector3.new(0,0,-1) else f=f.Unit end
		local q=Vector3.new(cam.CFrame.RightVector.X,0,cam.CFrame.RightVector.Z); if q.Magnitude<0.05 then q=Vector3.new(1,0,0) else q=q.Unit end
		local keys={}; local fd=d:Dot(f); local rd=d:Dot(q)
		if math.abs(fd)>0.15 then table.insert(keys,if fd>0 then Enum.KeyCode.W else Enum.KeyCode.S) end
		if math.abs(rd)>0.15 then table.insert(keys,if rd>0 then Enum.KeyCode.D else Enum.KeyCode.A) end
		for _,k in keys do inputAdapter.sendKeyEvent(true,k) end; task.wait(duration); for _,k in keys do inputAdapter.sendKeyEvent(false,k) end
	end

	function Driver:driveTo(target:Vector3,radius:number,timeout:number): (boolean,string)
		local deadline=os.clock()+timeout; local best=math.huge; local improved=os.clock(); local detours=0
		while os.clock()<deadline do
			local _,h,r=self:character(); if h.Health<=0 then self:releaseMovement(); return false,self:trace("walk_to","died",{target=vec(target)}) end
			local d=hdist(r.Position,target); if d<=radius then self:releaseMovement(); return true,self:trace("walk_to","reached",{target=vec(target),distance=d}) end
			if d+0.25<best then best=d; improved=os.clock() elseif os.clock()-improved>1.4 then
				detours+=1; if detours>5 then self:releaseMovement(); return false,self:trace("walk_to","stalled",{target=vec(target),distance=d}) end
				local toward=Vector3.new(target.X-r.Position.X,0,target.Z-r.Position.Z); if toward.Magnitude>0.1 then local side=Vector3.new(-toward.Z,0,toward.X).Unit*(if detours%2==0 then 6 else -6); self:pulse(r.Position+side,0.45) end
				best=d; improved=os.clock()
			end
			self:pulse(target,if d>15 then 0.22 elseif d>7 then 0.13 else 0.07); task.wait(0.015)
		end
		self:releaseMovement(); local _,_,r=self:character(); return false,self:trace("walk_to","timeout",{target=vec(target),distance=hdist(r.Position,target)})
	end

	function Driver:navigate(target:Vector3,radius:number?,timeout:number?): (boolean,{string})
		local traces={}; local started=os.clock(); local budget=timeout or 24
		local _,_,r=self:character(); local path=PathfindingService:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=false,WaypointSpacing=6})
		local ok=pcall(function() path:ComputeAsync(r.Position,target) end)
		if ok and path.Status==Enum.PathStatus.Success then
			local waypoints=path:GetWaypoints()
			table.insert(traces,self:trace("path_compute","success",{target=vec(target),waypoints=#waypoints}))
			for index,wp in waypoints do
				if index>40 then table.insert(traces,self:trace("path_follow","waypoint_cap",{count=#waypoints})); return false,traces end
				local remaining=budget-(os.clock()-started)
				if remaining<=0 then table.insert(traces,self:trace("path_follow","timeout",{target=vec(target)})); return false,traces end
				local reached,t=self:driveTo(wp.Position,3,math.min(6,remaining)); table.insert(traces,t); if not reached then return false,traces end
			end
		else table.insert(traces,self:trace("path_compute","unavailable",{target=vec(target),status=path.Status.Name})) end
		local remaining=budget-(os.clock()-started)
		if remaining<=0 then table.insert(traces,self:trace("walk_to","timeout_before_final",{target=vec(target)})); return false,traces end
		local reached,t=self:driveTo(target,radius or 3,remaining); table.insert(traces,t); return reached,traces
	end

	function Driver:atInteraction(id:string): (boolean,{string},BasePart,ProximityPrompt)
		local part=self:interaction(id); local prompt=self:prompt(part); local node=self:node(part:GetAttribute("DR_ApproachNodeId"))
		local reached,traces=self:navigate(node.Position,2.5,24)
		if not reached then return false,traces,part,prompt end
		local _,_,r=self:character(); local p=if prompt.Parent:IsA("Attachment") then prompt.Parent.WorldPosition else part.Position
		local dist=(r.Position-p).Magnitude
		if dist>prompt.MaxActivationDistance+1 then table.insert(traces,self:trace("establish_prompt","out_of_range",{interaction_id=id,distance=dist,max=prompt.MaxActivationDistance})); return false,traces,part,prompt end
		table.insert(traces,self:trace("establish_prompt","ready",{interaction_id=id,distance=dist,enabled=prompt.Enabled})); return true,traces,part,prompt
	end

	function Driver:interact(id:string,hold:number?): (boolean,{string},{[string]:any},{[string]:any})
		local ready,traces,_,prompt=self:atInteraction(id); local before=self:stateMap()
		if not ready then return false,traces,before,self:stateMap() end
		local duration=hold or math.max(0.12,prompt.HoldDuration+0.15)
		inputAdapter.sendKeyEvent(true,Enum.KeyCode.E); task.wait(duration); inputAdapter.sendKeyEvent(false,Enum.KeyCode.E); task.wait(0.35)
		table.insert(traces,self:trace("prompt_input","sent",{interaction_id=id,duration_s=duration,prompt_enabled=prompt.Enabled}))
		return true,traces,before,self:stateMap()
	end

	function Driver:pressR(): (boolean,{string},{[string]:any},{[string]:any})
		local traces={}; local before=self:stateMap(); inputAdapter.sendKeyEvent(true,Enum.KeyCode.R); task.wait(0.15); inputAdapter.sendKeyEvent(false,Enum.KeyCode.R)
		local deadline=os.clock()+3; repeat task.wait(0.1) until (self:stateMap().DR_RunId or 0)>(before.DR_RunId or 0) or os.clock()>deadline
		table.insert(traces,self:trace("restart_input","observed",{})); local after=self:stateMap(); return (after.DR_RunId or 0)>(before.DR_RunId or 0),traces,before,after
	end

	function Driver:waitState(name:string,predicate:any,timeout:number): (boolean,string)
		local deadline=os.clock()+timeout
		repeat local v=self:gameState():GetAttribute(name); if predicate(v) then return true,self:trace("wait_state","matched",{attribute=name,value=v}) end; task.wait(0.08) until os.clock()>deadline
		return false,self:trace("wait_state","timeout",{attribute=name,value=self:gameState():GetAttribute(name)})
	end

	function Driver:walkToPart(part:BasePart,radius:number?,timeout:number?): (boolean,{string}) return self:navigate(part.Position,radius or 2.5,timeout or 20) end
	function Driver:waitForRespawn(oldDeaths:number,timeout:number): (boolean,string)
		local deadline=os.clock()+timeout
		repeat
			local ok,h=pcall(function() local _,hum,_=self:character(); return hum end)
			if ok and h.Health>0 and (self:stateMap().DR_DeathCount or 0)>oldDeaths then return true,self:trace("wait_respawn","respawned",{}) end
			task.wait(0.1)
		until os.clock()>deadline
		return false,self:trace("wait_respawn","timeout",{})
	end

	function Driver:schemaSnapshot(): {[string]:any}
		local counts={}; for _,tag in {"DR_CentralSpawn","DR_GameState","DR_Interactable","DR_CarryItem","DR_ItemStation","DR_AirlockDoor","DR_Hazard","DR_SafeZone","DR_NavNode","DR_NavLink","DR_HUDField"} do counts[tag]=#self:tagged(tag) end
		return {counts=counts,state=self:stateMap(),hud=self:hudMap()}
	end
	return Driver
end
