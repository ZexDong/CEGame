-- Evaluator-only, read-only client bridge. The candidate owns all gameplay
-- state and GUI objects in this client context, so the public Dashboard must
-- also be sampled here (sampling it on the server returns "not_ready").
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local dashboardOk, Dashboard = pcall(require, ReplicatedStorage:WaitForChild("BenchmarkDashboard"))
local prefix = "__PG_SNAPSHOT__"
local clientRelay = ReplicatedStorage:WaitForChild("PocketGreenhouseEvaluatorSnapshotRelay")
local lastFallbackPayload = nil

-- Read-only fallback for candidates whose submitted BenchmarkDashboard does
-- not compile.  D1 still records that candidate defect; this observer only
-- keeps the real-input D2-D5 run measurable and never mutates gameplay.
local function fallbackSnapshot()
    local state = ReplicatedStorage:FindFirstChild("PocketGreenhouseState")
    local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local root = playerGui and playerGui:FindFirstChild("PocketGreenhouse")
    if not state or not root then
        return {revision = 0, phase = "not_ready", slots = {}, entities = {}, targets = {}}
    end

    local function value(name, default)
        local object = state:FindFirstChild(name)
        return object and object.Value or default
    end
    local function target(name, kind)
        local object = root:FindFirstChild(name, true)
        local visible = object ~= nil and object:IsA("GuiObject") and object.Visible
        local parent = object and object.Parent
        while visible and parent and parent ~= playerGui do
            if parent:IsA("GuiObject") and not parent.Visible then
                visible = false
            end
            parent = parent.Parent
        end
        if not object or not visible then
            return {kind = kind, rect = {0, 0, 0, 0}, visible = false, interactable = false}
        end
        local position, size = object.AbsolutePosition, object.AbsoluteSize
        return {
            kind = kind,
            rect = {math.floor(position.X), math.floor(position.Y), math.floor(size.X), math.floor(size.Y)},
            visible = true,
            interactable = object:IsA("GuiButton") and object.Active,
        }
    end
    local gameFrame = root:FindFirstChild("Game")
    local function plotState(index)
        local plot = gameFrame and gameFrame:FindFirstChild("Plot" .. index)
        if not plot then return "empty" end
        local crop = plot:GetAttribute("crop") or "Empty"
        local growth = plot:GetAttribute("growth") or 0
        local watered = plot:GetAttribute("watered") or false
        if crop == "Empty" then return "empty" end
        if crop == "Sunberry" then
            if growth >= 2 then return "sunberry_ripe" end
            return "sunberry_stage" .. growth .. "_" .. (watered and "watered" or "dry")
        end
        if growth >= 1 then return "moonleaf_ripe" end
        return "moonleaf_stage0_" .. (watered and "watered" or "dry")
    end

    local targetSpecs = {
        {"Plot1", "plot_1"}, {"Plot2", "plot_2"}, {"Plot3", "plot_3"},
        {"Start", "start_button"}, {"PlantSunberry", "plant_sunberry_button"},
        {"PlantMoonleaf", "plant_moonleaf_button"}, {"Water", "water_button"},
        {"Harvest", "harvest_button"}, {"EndDay", "end_day_button"},
        {"Deliver", "deliver_button"}, {"Restart", "restart_button"},
    }
    local targets = {}
    for _, spec in ipairs(targetSpecs) do
        table.insert(targets, target(spec[1], spec[2]))
    end
    return {
        revision = value("Revision", 0),
        phase = value("Phase", "not_ready"),
        slots = {
            day = value("Day", 0), coins = value("Coins", 0), water = value("Water", 0),
            sunberry_inventory = value("Sunberry", 0), moonleaf_inventory = value("Moonleaf", 0),
            selected_plot = value("SelectedPlot", 0),
        },
        entities = {
            {kind = "plot_1", state = plotState(1)},
            {kind = "plot_2", state = plotState(2)},
            {kind = "plot_3", state = plotState(3)},
        },
        targets = targets,
    }
end

while true do
    local ok, snapshot
    if dashboardOk and type(Dashboard) == "table" and type(Dashboard.GetSnapshot) == "function" then
        ok, snapshot = pcall(Dashboard.GetSnapshot)
    else
        ok, snapshot = pcall(fallbackSnapshot)
    end
    if ok and type(snapshot) == "table" then
        local mouse = UserInputService:GetMouseLocation()
        local camera = workspace.CurrentCamera
        snapshot._evaluator_channel = "client"
        snapshot._evaluator_mouse = {mouse.X, mouse.Y}
        snapshot._evaluator_viewport_size = camera and {
            camera.ViewportSize.X,
            camera.ViewportSize.Y,
        } or nil
        local topLeftInset = GuiService:GetGuiInset()
        snapshot._evaluator_gui_inset = {topLeftInset.X, topLeftInset.Y}
        local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gameGui = playerGui and playerGui:FindFirstChild("PocketGreenhouse")
        snapshot._evaluator_ignore_gui_inset = gameGui and gameGui.IgnoreGuiInset == true or false

        local relayed = pcall(clientRelay.FireServer, clientRelay, snapshot)
        if not relayed then
            local payload = HttpService:JSONEncode(snapshot)
            if payload ~= lastFallbackPayload then
                -- Last-resort fallback; normally the evaluator-owned relay
                -- carries this without relying on long Studio log lines.
                print(prefix .. payload)
                lastFallbackPayload = payload
            end
        end
    end
    task.wait(0.05)
end
