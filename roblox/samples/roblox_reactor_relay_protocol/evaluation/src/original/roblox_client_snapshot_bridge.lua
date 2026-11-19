-- Evaluator-only read bridge. It observes public RR tags/Attributes and live GUI geometry.
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local probeId = 0
local probeMouse = {0, 0}
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        local p = UserInputService:GetMouseLocation()
        probeMouse = {p.X, p.Y}
        probeId += 1
    end
end)

local relay = ReplicatedStorage:WaitForChild("ReactorRelayEvaluatorSnapshotRelay")
local phaseMap = {Menu="menu", Cycle="cycle", Preview="preview", Sequence="sequence", Won="won", Lost="lost"}
local selectedMap = {None=0, A=1, B=2, C=3}
local incidentMap = {None=0, ["CoolantLeak.B"]=1, ["PhaseDrift.C"]=2, ["PowerSurge.A"]=3, ["DualLeak.AC"]=4, ["Crossfeed.BC"]=5}

local function one(tag)
    local rows = CollectionService:GetTagged(tag)
    return #rows == 1 and rows[1] or nil
end

local function snapshot()
    local gs = one("RR_GameState")
    if not gs then return nil end
    local bays = {}
    for _, b in CollectionService:GetTagged("RR_BayState") do
        local id = b:GetAttribute("RR_BayId")
        table.insert(bays, {
            kind="bay_" .. string.lower(tostring(id)), state=b:GetAttribute("RR_Status"),
            power=b:GetAttribute("RR_CurrentPower"), target_power=b:GetAttribute("RR_TargetPower"),
            coolant=b:GetAttribute("RR_CurrentCoolant"), target_coolant=b:GetAttribute("RR_TargetCoolant"),
            phase=b:GetAttribute("RR_CurrentPhase"), target_phase=b:GetAttribute("RR_TargetPhase"),
            locked=b:GetAttribute("RR_Locked"), overloads=b:GetAttribute("RR_Overloads"),
        })
    end
    table.sort(bays, function(a,b) return a.kind < b.kind end)
    table.insert(bays, {
        kind="game", state=phaseMap[gs:GetAttribute("RR_Phase")] or "not_ready",
        last_event=tostring(gs:GetAttribute("RR_LastEvent")),
        last_source=tostring(gs:GetAttribute("RR_LastSourceId")),
        reject_code=tostring(gs:GetAttribute("RR_LastRejectCode")),
        feedback=tostring(gs:GetAttribute("RR_FeedbackText")),
    })
    local targets = {}
    local controls = CollectionService:GetTagged("RR_Control")
    local rootGui = nil
    for _, c in controls do
        rootGui = rootGui or c:FindFirstAncestorWhichIsA("ScreenGui")
        local p, s = c.AbsolutePosition, c.AbsoluteSize
        table.insert(targets, {kind=tostring(c:GetAttribute("RR_TargetId")), rect={p.X,p.Y,s.X,s.Y},
            visible=c.Visible and c:GetAttribute("RR_VisibleToPlayer") == true,
            interactable=c.Visible and c.Active and c:GetAttribute("RR_Enabled") == true})
    end
    local mouse = UserInputService:GetMouseLocation()
    local camera = workspace.CurrentCamera
    local inset = GuiService:GetGuiInset()
    return {
        revision=gs:GetAttribute("RR_Revision") or 0,
        _evaluator_probe={id=probeId, mouse=probeMouse},
        phase=phaseMap[gs:GetAttribute("RR_Phase")] or "not_ready",
        slots={cycle=gs:GetAttribute("RR_Cycle") or 0, time_remaining=gs:GetAttribute("RR_TimeRemaining") or 0,
            integrity=gs:GetAttribute("RR_Integrity") or 0, faults=gs:GetAttribute("RR_Faults") or 0,
            power_pool=gs:GetAttribute("RR_UnallocatedPower") or 0, coolant_pool=gs:GetAttribute("RR_UnallocatedCoolant") or 0,
            scan_charges=gs:GetAttribute("RR_ScanCharges") or 0, purge_available=gs:GetAttribute("RR_PurgeAvailable") and 1 or 0,
            selected_bay=selectedMap[gs:GetAttribute("RR_SelectedBay")] or 0,
            incident=incidentMap[gs:GetAttribute("RR_IncidentId")] or -1,
            sequence_index=gs:GetAttribute("RR_SequenceIndex") or 0, event_seq=gs:GetAttribute("RR_EventSeq") or 0,
            run_id=gs:GetAttribute("RR_RunId") or 0},
        entities=bays, targets=targets, _evaluator_channel="client", _evaluator_mouse={mouse.X,mouse.Y},
        _evaluator_viewport_size=camera and {camera.ViewportSize.X,camera.ViewportSize.Y} or nil,
        _evaluator_gui_inset={inset.X,inset.Y}, _evaluator_ignore_gui_inset=rootGui and rootGui.IgnoreGuiInset == true or false,
    }
end

while true do
    local ok, value = pcall(snapshot)
    if ok and value then pcall(relay.FireServer, relay, value) end
    task.wait(0.05)
end
