-- Development-only self-check. Run in Studio and remove this Script from final delivery.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Dashboard = require(ReplicatedStorage:WaitForChild("BenchmarkDashboard"))

local REQUIRED_SLOTS = {"day", "coins", "water", "sunberry_inventory", "moonleaf_inventory", "selected_plot"}
local REQUIRED_PLOTS = {plot_1 = true, plot_2 = true, plot_3 = true}
local REQUIRED_TARGETS = {
	plot_1 = true, plot_2 = true, plot_3 = true, start_button = true,
	plant_sunberry_button = true, plant_moonleaf_button = true, water_button = true,
	harvest_button = true, end_day_button = true, deliver_button = true, restart_button = true,
}
local PHASES = {not_ready = true, menu = true, playing = true, paused = true, won = true, lost = true}

local snapshot = Dashboard.GetSnapshot()
assert(type(snapshot) == "table", "snapshot must be a table")
assert(type(snapshot.revision) == "number" and snapshot.revision >= 0, "invalid revision")
assert(PHASES[snapshot.phase], "invalid phase")
assert(type(snapshot.slots) == "table", "missing slots")
for _, name in ipairs(REQUIRED_SLOTS) do
	assert(type(snapshot.slots[name]) == "number", "missing numeric slot: " .. name)
end

local plots = {}
for _, entity in ipairs(snapshot.entities or {}) do
	if REQUIRED_PLOTS[entity.kind] then
		assert(not plots[entity.kind], "duplicate plot: " .. entity.kind)
		assert(type(entity.state) == "string", "missing plot state")
		plots[entity.kind] = true
	end
end
for kind in pairs(REQUIRED_PLOTS) do assert(plots[kind], "missing plot: " .. kind) end

local targets = {}
for _, item in ipairs(snapshot.targets or {}) do
	if REQUIRED_TARGETS[item.kind] then
		assert(not targets[item.kind], "duplicate target: " .. item.kind)
		assert(type(item.rect) == "table" and #item.rect == 4, "invalid rect: " .. item.kind)
		assert(type(item.visible) == "boolean" and type(item.interactable) == "boolean", "invalid flags")
		targets[item.kind] = true
	end
end
for kind in pairs(REQUIRED_TARGETS) do assert(targets[kind], "missing target: " .. kind) end

print("DASHBOARD_SELF_CHECK_PASS " .. HttpService:JSONEncode(snapshot))
