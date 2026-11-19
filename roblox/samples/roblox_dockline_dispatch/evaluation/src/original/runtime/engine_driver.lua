--!strict
-- Dockline Dispatch read-only engine driver. All actuation is requested as ordinary OS input.

local function buildEngineDriver(inputAdapter: any, emitTrace: any)
	local CollectionService = game:GetService("CollectionService")
	local PathfindingService = game:GetService("PathfindingService")
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local Workspace = game:GetService("Workspace")
	local Driver = {}
	Driver.__index = Driver
	local STATE_NAMES = {
		"DD_ProtocolVersion","DD_RunId","DD_RunStatus","DD_Phase","DD_CarryItemId",
		"DD_GlassState","DD_ColdState","DD_CipherState","DD_AuthState","DD_AuthProgress",
		"DD_DiverterOne","DD_DiverterTwo","DD_ConveyorState","DD_ConveyorPackageId",
		"DD_StagedCount","DD_RejectCount","DD_PalletState","DD_PalletProgress","DD_CheckpointId",
		"DD_HazardState","DD_HazardEpoch","DD_SealInstalled","DD_FinalCodeProgress","DD_FinalCodeDeadline",
		"DD_ObjectiveId","DD_DeathCount",
		"DD_RunStart","DD_FinalTime","DD_EventSeq","DD_LastEvent","DD_LastSourceId","DD_LastRejectCode","DD_FeedbackText",
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
		local found=CollectionService:GetTagged("DD_GameState")
		assert(#found==1 and found[1]:IsA("Configuration"),"DD_GameState must be one Configuration")
		self.state=found[1]
		return self.state
	end

	function Driver:optionalGameState(): Configuration?
		if self.state and self.state.Parent then return self.state end
		local found=CollectionService:GetTagged("DD_GameState")
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
		for _,g in CollectionService:GetTagged("DD_HUDField") do
			if g:IsA("GuiObject") and g:IsDescendantOf(self.player.PlayerGui) then
				local id=g:GetAttribute("DD_FieldId")
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
		x.workspace_ready=Workspace:GetAttribute("DD_Ready"); x.contract_version=Workspace:GetAttribute("DD_ContractVersion")
		return x
	end

	function Driver:trace(action:string,outcome:string,data:{[string]:any}?): string
		local x=self:scene(data); x.action=action; x.outcome=outcome; return emitTrace(x)
	end

	function Driver:waitReady(timeout:number): (boolean,string)
		local deadline=os.clock()+timeout
		repeat
			local ok=pcall(function() self:character(); self:gameState() end)
			if ok and Workspace:GetAttribute("DD_Ready")==true and Workspace:GetAttribute("DD_ContractVersion")=="dockline-dispatch-v1" then
				task.wait(0.5); return true,self:trace("wait_ready","ready",{})
			end
			task.wait(0.1)
		until os.clock()>deadline
		return false,self:trace("wait_ready","timeout",{})
	end

	function Driver:tagged(tag:string): {Instance} return CollectionService:GetTagged(tag) end
	function Driver:findInteraction(id:string): BasePart?
		local found={}
		for _,x in self:tagged("DD_Interactable") do
			if x:IsA("BasePart") and x:GetAttribute("DD_InteractionId")==id then table.insert(found,x) end
		end
		if #found==1 then return found[1] end
		return nil
	end
	function Driver:interaction(id:string): BasePart
		local found={}
		for _,x in self:tagged("DD_Interactable") do if x:IsA("BasePart") and x:GetAttribute("DD_InteractionId")==id then table.insert(found,x) end end
		assert(#found==1,"interaction uniqueness failed: "..id); return found[1]
	end
	function Driver:node(id:string): BasePart
		local found={}
		for _,x in self:tagged("DD_NavNode") do if x:IsA("BasePart") and x:GetAttribute("DD_NodeId")==id then table.insert(found,x) end end
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
		for _,tag in {"DD_CentralSpawn","DD_GameState","DD_Interactable","DD_CarryItem","DD_Package","DD_ItemStation","DD_StagingBay","DD_Hazard","DD_SafeZone","DD_NavNode","DD_NavLink","DD_HUDField"} do tags[tag]=#self:tagged(tag) end
		local state,statePresent=self:safeStateMap()
		local hazards={}; for _,hazard in self:tagged("DD_Hazard") do table.insert(hazards,self:instanceSnapshot(hazard)) end
		return {counts=tags,state=state,state_present=statePresent,hud=self:hudMap(),hazards=hazards,workspace_ready=Workspace:GetAttribute("DD_Ready"),contract_version=Workspace:GetAttribute("DD_ContractVersion")}
	end

	function Driver:compactDegradedSnapshot(snapshot:{[string]:any}): {[string]:any}
		local stateAttributeCount=0; for _ in snapshot.state do stateAttributeCount+=1 end
		local hudIds={}; for id in snapshot.hud do table.insert(hudIds,id) end; table.sort(hudIds)
		local hazards={}
		for _,hazard in snapshot.hazards do table.insert(hazards,{id=hazard.attributes and hazard.attributes.DD_HazardId or "",active=hazard.attributes and hazard.attributes.DD_Active,can_collide=hazard.can_collide}) end
		return {counts=snapshot.counts,state_present=snapshot.state_present,state_attribute_count=stateAttributeCount,hud_ids=hudIds,hazards=hazards,workspace_ready=snapshot.workspace_ready,contract_version=snapshot.contract_version}
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
		local nodeId=part:GetAttribute("DD_ApproachNodeId")
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
			return {event_seq=state.DD_EventSeq,last_event=state.DD_LastEvent,last_reject=state.DD_LastRejectCode,carry=state.DD_CarryItemId,glass=state.DD_GlassState,cold=state.DD_ColdState,cipher=state.DD_CipherState,auth=state.DD_AuthState,staged=state.DD_StagedCount,pallet=state.DD_PalletProgress}
		end
		table.insert(traces,self:trace("safe_prompt_input",observed and "observed" or "not_observed",{interaction_id=id,duration_s=duration,distance=distance,prompt_enabled=prompt.Enabled,input_observed=observed,unprocessed_observed=self:unprocessedInputCount(Enum.KeyCode.E)>beforeUnprocessedE,before_state=stateDigest(beforeState),after_state=stateDigest(afterState),object_present=beforeObject.present}))
		return observed,traces,beforeState,afterState
	end

	function Driver:observeHazardWindow(duration:number): string
		local samples={}; local deadline=os.clock()+duration
		repeat
			local tagged=self:tagged("DD_Hazard"); local active=nil
			if #tagged==1 then active=tagged[1]:GetAttribute("DD_Active") end
			local state,_=self:safeStateMap()
			table.insert(samples,{active=active,state=state.DD_HazardState})
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
			local d=hdist(r.Position,target)
			if d<=radius then
				self:releaseMovement()
				local verticalDelta=math.abs(r.Position.Y-target.Y)
				if verticalDelta<=8 and r.AssemblyLinearVelocity.Y>-25 then
					return true,self:trace("walk_to","reached",{target=vec(target),distance=d,vertical_delta=verticalDelta})
				end
				return false,self:trace("walk_to","vertical_unresolved",{target=vec(target),distance=d,vertical_delta=verticalDelta})
			end
			if d+0.25<best then best=d; improved=os.clock() elseif os.clock()-improved>1.4 then
				detours+=1; if detours>5 then self:releaseMovement(); return false,self:trace("walk_to","stalled",{target=vec(target),distance=d}) end
				local toward=Vector3.new(target.X-r.Position.X,0,target.Z-r.Position.Z); if toward.Magnitude>0.1 then local side=Vector3.new(-toward.Z,0,toward.X).Unit*(if detours%2==0 then 6 else -6); self:pulse(r.Position+side,0.45) end
				best=d; improved=os.clock()
			end
			self:pulse(target,if d>15 then 0.22 elseif d>7 then 0.13 elseif d>3 then 0.07 else 0.025); task.wait(0.015)
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
		local part=self:interaction(id); local prompt=self:prompt(part); local node=self:node(part:GetAttribute("DD_ApproachNodeId"))
		local reached,traces=self:navigate(node.Position,2.5,24)
		if not reached then return false,traces,part,prompt end
		-- Path waypoints use a broad tolerance. Finish tightly on the public node
		-- itself so E is not sent from the edge of MaxActivationDistance.
		local tightened,tightTrace=self:driveTo(node.Position,0.8,4); table.insert(traces,tightTrace)
		if not tightened then return false,traces,part,prompt end
		local p=if prompt.Parent:IsA("Attachment") then prompt.Parent.WorldPosition else part.Position
		-- Prefer a closer prompt stand only when live raycasts prove a generous
		-- support footprint. This keeps edge stations on their public node while
		-- moving interior stations away from the activation-distance boundary.
		local towardNode=Vector3.new(node.Position.X-p.X,0,node.Position.Z-p.Z)
		if towardNode.Magnitude>0.1 then
			local direction=towardNode.Unit
			local localDirection=part.CFrame:VectorToObjectSpace(direction)
			local extent=math.abs(localDirection.X)*part.Size.X*0.5+math.abs(localDirection.Z)*part.Size.Z*0.5
			local desired=math.min(extent+2.2,math.max(2.5,prompt.MaxActivationDistance-2.5))
			local stand=Vector3.new(p.X+direction.X*desired,node.Position.Y,p.Z+direction.Z*desired)
			local character=self.player.Character
			local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances=if character then {character} else {}
			local supported=true
			for _,offset in {Vector3.zero,Vector3.new(3.5,0,0),Vector3.new(-3.5,0,0),Vector3.new(0,0,3.5),Vector3.new(0,0,-3.5)} do
				local hit=Workspace:Raycast(stand+offset+Vector3.yAxis*5,-Vector3.yAxis*14,params)
				if not hit or hit.Normal.Y<0.6 or not hit.Instance:IsA("BasePart") or not hit.Instance.CanCollide then supported=false; break end
			end
			if supported then
				local close,closeTrace=self:driveTo(stand,1.0,4); table.insert(traces,closeTrace)
				if close then table.insert(traces,self:trace("prompt_stand","safe_closer",{interaction_id=id})) end
			else table.insert(traces,self:trace("prompt_stand","kept_semantic_node",{interaction_id=id})) end
		end
		task.wait(0.3)
		local _,_,r=self:character()
		local dist=(r.Position-p).Magnitude
		if dist>prompt.MaxActivationDistance+1 then table.insert(traces,self:trace("establish_prompt","out_of_range",{interaction_id=id,distance=dist,max=prompt.MaxActivationDistance})); return false,traces,part,prompt end
		table.insert(traces,self:trace("establish_prompt","ready_at_semantic_node",{interaction_id=id,distance=dist,enabled=prompt.Enabled})); return true,traces,part,prompt
	end

	function Driver:interact(id:string,hold:number?): (boolean,{string},{[string]:any},{[string]:any})
		local ready,traces,_,prompt=self:atInteraction(id); local before=self:stateMap()
		if not ready then return false,traces,before,self:stateMap() end
		local duration=hold or math.max(0.12,prompt.HoldDuration+0.15)
		-- Input delivery alone does not prove that the intended prompt received
		-- E. Observe every public event edge so a fast hazard update cannot hide
		-- the intended source before polling reads it.
		local beforeSeq=tonumber(before.DD_EventSeq) or 0
		local confirmed=false
		local stateObject=self:gameState()
		local connection=stateObject:GetAttributeChangedSignal("DD_EventSeq"):Connect(function()
			local seq=tonumber(stateObject:GetAttribute("DD_EventSeq")) or 0
			if seq>beforeSeq and stateObject:GetAttribute("DD_LastSourceId")==id then confirmed=true end
		end)
		local function performInput()
			-- A redundant real key-up clears a missed previous release without
			-- mutating game state or invoking the candidate implementation.
			inputAdapter.releaseKeyWithoutAck(Enum.KeyCode.E); task.wait(0.12)
			inputAdapter.sendKeyEvent(true,Enum.KeyCode.E); task.wait(duration); inputAdapter.sendKeyEvent(false,Enum.KeyCode.E); task.wait(0.3)
		end
		performInput()
		local live=self:stateMap(); confirmed=confirmed or ((tonumber(live.DD_EventSeq) or 0)>beforeSeq and live.DD_LastSourceId==id)
		if not confirmed then performInput() end
		local deadline=os.clock()+1.2
		repeat
			live=self:stateMap()
			confirmed=confirmed or ((tonumber(live.DD_EventSeq) or 0)>beforeSeq and live.DD_LastSourceId==id)
			if not confirmed then task.wait(0.05) end
		until confirmed or os.clock()>deadline
		connection:Disconnect()
		local after=self:stateMap()
		table.insert(traces,self:trace("prompt_input",confirmed and "confirmed" or "unconfirmed",{interaction_id=id,duration_s=duration,prompt_enabled=prompt.Enabled,event_confirmed=confirmed,observed_source=after.DD_LastSourceId}))
		-- Reaching the validated semantic stand and observing real InputBegan is
		-- a complete controller prerequisite. Missing/misdirected public events
		-- are candidate behavior evidence, not an evaluator INCONCLUSIVE.
		return true,traces,before,after
	end

	function Driver:pressR(): (boolean,{string},{[string]:any},{[string]:any})
		local traces={}; local before=self:stateMap(); inputAdapter.sendKeyEvent(true,Enum.KeyCode.R); task.wait(0.15); inputAdapter.sendKeyEvent(false,Enum.KeyCode.R)
		local deadline=os.clock()+3; repeat task.wait(0.1) until (self:stateMap().DD_RunId or 0)>(before.DD_RunId or 0) or os.clock()>deadline
		task.wait(0.75)
		table.insert(traces,self:trace("restart_input","observed",{})); local after=self:stateMap(); return (after.DD_RunId or 0)>(before.DD_RunId or 0),traces,before,after
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
			if ok and h.Health>0 and (self:stateMap().DD_DeathCount or 0)>oldDeaths then return true,self:trace("wait_respawn","respawned",{}) end
			task.wait(0.1)
		until os.clock()>deadline
		return false,self:trace("wait_respawn","timeout",{})
	end

	function Driver:schemaSnapshot(): {[string]:any}
		local counts={}; for _,tag in {"DD_CentralSpawn","DD_GameState","DD_Interactable","DD_CarryItem","DD_Package","DD_ItemStation","DD_StagingBay","DD_Hazard","DD_SafeZone","DD_NavNode","DD_NavLink","DD_HUDField"} do counts[tag]=#self:tagged(tag) end
		return {counts=counts,state=self:stateMap(),hud=self:hudMap()}
	end
	return Driver
end
