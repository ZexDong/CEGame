--!strict
-- Public constants only. This module contains no gameplay or scoring logic.

local Schema = {
	ContractVersion = "deep-relay-v1",
	Tags = {
		CentralSpawn = "DR_CentralSpawn",
		GameState = "DR_GameState",
		Interactable = "DR_Interactable",
		CarryItem = "DR_CarryItem",
		ItemStation = "DR_ItemStation",
		AirlockDoor = "DR_AirlockDoor",
		Hazard = "DR_Hazard",
		SafeZone = "DR_SafeZone",
		NavNode = "DR_NavNode",
		NavLink = "DR_NavLink",
		HUDField = "DR_HUDField",
	},
	Orders = {
		PowerBreakers = { "B", "C", "A" },
		AuthorizationScanners = { "Gamma", "Alpha", "Beta" },
		AssemblyItems = { "CoolantCanister", "ChargedCell", "AuthToken" },
		FinalStabilizers = { "2", "1", "3" },
	},
	InteractionIds = {
		"Power.FusePickup", "Power.FuseSocket", "Power.Breaker.A", "Power.Breaker.B",
		"Power.Breaker.C", "Power.Charger", "Power.CellPickup", "Coolant.Inlet",
		"Coolant.Pump", "Coolant.Lock", "Coolant.CanisterPickup", "Auth.Controller",
		"Auth.Scanner.Alpha", "Auth.Scanner.Beta", "Auth.Scanner.Gamma", "Auth.TokenPickup",
		"Assembly.Slot.Coolant", "Assembly.Slot.Cell", "Assembly.Slot.Auth", "Assembly.CorePickup",
		"Airlock.OuterControl", "Airlock.Equalizer", "Airlock.InnerControl", "Checkpoint.CoreShelf",
		"Final.CoreSocket", "Final.Stabilizer.1", "Final.Stabilizer.2", "Final.Stabilizer.3",
	},
	ItemIds = { "PowerFuse", "ChargedCell", "CoolantCanister", "AuthToken", "RelayCore" },
	ItemStationIds = {
		"PowerFuseRack", "PowerFuseSocket", "PowerOutput", "CoolantOutput", "AuthOutput",
		"AssemblyCoolant", "AssemblyCell", "AssemblyAuth", "AssemblyCoreOutput", "CoreShelf", "FinalCoreSocket",
	},
	HUDFieldIds = {
		"Objective", "Systems", "PowerProgress", "CoolantPressure", "AuthProgress", "CarryItem",
		"AssemblyProgress", "Airlock", "Hazard", "Checkpoint", "Timer", "Feedback",
	},
	Attributes = {
		ProtocolVersion = "DR_ProtocolVersion", RunId = "DR_RunId", RunStatus = "DR_RunStatus",
		Phase = "DR_Phase", PowerState = "DR_PowerState", PowerBreakerProgress = "DR_PowerBreakerProgress",
		CoolantState = "DR_CoolantState", CoolantPressure = "DR_CoolantPressure",
		AuthState = "DR_AuthState", AuthScanProgress = "DR_AuthScanProgress",
		AssemblyState = "DR_AssemblyState", AssemblyProgress = "DR_AssemblyProgress",
		CarryItemId = "DR_CarryItemId", AirlockState = "DR_AirlockState",
		CheckpointId = "DR_CheckpointId", HazardState = "DR_HazardState",
		CoreInstalled = "DR_CoreInstalled", StabilizerProgress = "DR_StabilizerProgress",
		StabilizerDeadline = "DR_StabilizerDeadline", ObjectiveId = "DR_ObjectiveId",
		DeathCount = "DR_DeathCount", RunStart = "DR_RunStart", FinalTime = "DR_FinalTime",
		EventSeq = "DR_EventSeq", LastEvent = "DR_LastEvent", LastSourceId = "DR_LastSourceId",
		LastRejectCode = "DR_LastRejectCode", FeedbackText = "DR_FeedbackText",
	},
	Timing = {
		ReadyTimeout = 12, FeedbackVisible = 1.5, DoorCollisionTimeout = 1.5,
		HazardDeathTimeout = 1.0, RestartTimeout = 2.0, ChargerHold = 2.0,
		EqualizerHold = 2.0, StabilizationWindow = 30.0,
	},
	Coolant = {
		InitialPressure = 0, TargetMinimum = 45, TargetMaximum = 55, StableSeconds = 1.0,
		InletRate = 12, PumpRate = -5, OverpressureThreshold = 65, PostOverpressurePressure = 20,
	},
	Movement = { NormalWalkSpeed = 16, CoreCarryWalkSpeed = 12 },
}

return table.freeze(Schema)
