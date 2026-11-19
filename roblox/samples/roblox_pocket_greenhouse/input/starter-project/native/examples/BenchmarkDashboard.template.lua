-- Place this ModuleScript at ReplicatedStorage/BenchmarkDashboard.
-- Replace the adapter calls with reads from your real state and GUI.
-- Do not add public action functions.

local Dashboard = {}

local REQUIRED_TARGETS = {
	"plot_1", "plot_2", "plot_3", "start_button",
	"plant_sunberry_button", "plant_moonleaf_button", "water_button",
	"harvest_button", "end_day_button", "deliver_button", "restart_button",
}

local function target(kind, guiObject)
	if guiObject == nil or not guiObject:IsA("GuiObject") then
		return {kind = kind, rect = {0, 0, 0, 0}, visible = false, interactable = false}
	end
	local p, s = guiObject.AbsolutePosition, guiObject.AbsoluteSize
	local visible = guiObject.Visible and s.X > 0 and s.Y > 0
	return {
		kind = kind,
		rect = {p.X, p.Y, s.X, s.Y},
		visible = visible,
		interactable = visible and guiObject.Active,
	}
end

function Dashboard.GetSnapshot()
	-- Obtain these values from the single authoritative gameplay state.
	local state = error("Replace with your live read-only state adapter")
	local guiByPublicName = error("Replace with your live GUI lookup table")
	local targets = {}
	for _, kind in ipairs(REQUIRED_TARGETS) do
		table.insert(targets, target(kind, guiByPublicName[kind]))
	end

	return {
		revision = state.revision,
		phase = state.phase,
		slots = {
			day = state.day,
			coins = state.coins,
			water = state.water,
			sunberry_inventory = state.sunberryInventory,
			moonleaf_inventory = state.moonleafInventory,
			selected_plot = state.selectedPlot or 0,
		},
		entities = {
			{kind = "plot_1", state = state.plots[1].publicState},
			{kind = "plot_2", state = state.plots[2].publicState},
			{kind = "plot_3", state = state.plots[3].publicState},
		},
		targets = targets,
	}
end

return table.freeze(Dashboard)
