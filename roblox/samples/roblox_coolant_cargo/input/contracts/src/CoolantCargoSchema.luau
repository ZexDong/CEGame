--!strict
-- Public constants only. No gameplay, scoring, evaluator path, or reference answer.

local Schema = {
	ContractVersion = "coolant-cargo-v1",
	Tags = {
		CentralSpawn = "CCP_CentralSpawn", Valve = "CCP_Valve", EnergyRack = "CCP_EnergyRack",
		EnergyCell = "CCP_EnergyCell", ChargeDock = "CCP_ChargeDock", ChargeConsole = "CCP_ChargeConsole",
		CoreSocket = "CCP_CoreSocket", ReactorConsole = "CCP_ReactorConsole",
		SafetyCheckpoint = "CCP_SafetyCheckpoint", Hazard = "CCP_Hazard", OuterDoor = "CCP_OuterDoor",
		InnerDoor = "CCP_InnerDoor", AirlockZone = "CCP_AirlockZone", DeconConsole = "CCP_DeconConsole",
		EvacuationZone = "CCP_EvacuationZone",
	},
	ValveOrder = { "Intake", "Bypass", "Outlet" },
	CellStates = { "Rack", "Carried", "Docked", "Charging", "Installed" },
	AirlockStages = { "Locked", "OuterOpen", "Occupied", "Decontaminating", "InnerOpen" },
	PlayerAttributes = {
		RunId = "CCP_RunId", CoolantStep = "CCP_CoolantStep", NextValve = "CCP_NextValve",
		IntakeOpen = "CCP_IntakeOpen", BypassOpen = "CCP_BypassOpen", OutletOpen = "CCP_OutletOpen",
		CoolantReady = "CCP_CoolantReady", CellState = "CCP_CellState", CellCharged = "CCP_CellCharged",
		ChargeProgress = "CCP_ChargeProgress", PowerReady = "CCP_PowerReady", ReactorStable = "CCP_ReactorStable",
		AirlockStage = "CCP_AirlockStage", Checkpoint = "CCP_Checkpoint", DeathCount = "CCP_DeathCount",
		Completed = "CCP_Completed", RunStart = "CCP_RunStart", FinalTime = "CCP_FinalTime",
		EventSerial = "CCP_EventSerial", LastEvent = "CCP_LastEvent", FeedbackText = "CCP_FeedbackText",
	},
	Geometry = {
		MaxHorizontalDistanceFromCentral = 145, MaxTargetHeightDelta = 2, MinimumWalkWidth = 12,
		MinimumHeadroom = 8, MinimumValveSeparation = 16, RespawnRadiusFromCheckpoint = 16,
		CentralRestartRadius = 24, CarriedCellRadius = 8, PlacedCellRadius = 8,
	},
	Timing = {
		ReadyTimeout = 10, ChargeMinimum = 3, ChargeMaximum = 6, DeconMinimum = 3, DeconMaximum = 6,
		HazardDeathTimeout = 1, DoorTransitionTimeout = 2, RestartTimeout = 2, MinimumFeedbackVisible = 1.5,
	},
	Events = {
		RunStarted = "RunStarted", Restarted = "Restarted", CellDocked = "CellDocked",
		CellPickedUpRack = "CellPickedUp.Rack", CellPickedUpDock = "CellPickedUp.Dock",
		CellPlaceRejectedNotCarrying = "CellPlaceRejected.NotCarrying",
		CellInstallRejectedUncharged = "CellInstallRejected.Uncharged",
		CellPickupRejectedCharging = "CellPickupRejected.Charging",
		ChargeStarted = "ChargeStarted", ChargeCompleted = "ChargeCompleted", CellInstalled = "CellInstalled",
		ReactorStabilized = "ReactorStabilized", AirlockOuterOpened = "AirlockOuterOpened",
		AirlockOccupied = "AirlockOccupied", DeconStarted = "DeconStarted", DeconCompleted = "DeconCompleted",
		Completed = "Completed", CheckpointSafety = "CheckpointActivated.Safety",
		HazardSafety = "HazardTriggered.Safety", RespawnedSafety = "Respawned.Safety",
		CellRecoveredRack = "CellRecovered.Rack", AirlockRecoveredOuterOpen = "AirlockRecovered.OuterOpen",
		DeconRejectedNotInside = "DeconRejected.NotInside",
		ValveOpened = { Intake = "ValveOpened.Intake", Bypass = "ValveOpened.Bypass", Outlet = "ValveOpened.Outlet" },
		ValveAlreadyOpen = { Intake = "ValveAlreadyOpen.Intake", Bypass = "ValveAlreadyOpen.Bypass", Outlet = "ValveAlreadyOpen.Outlet" },
		ValveWrong = { Intake = "ValveWrong.Expected.Intake", Bypass = "ValveWrong.Expected.Bypass", Outlet = "ValveWrong.Expected.Outlet" },
		ReactorLocked = { Coolant = "ReactorLocked.Coolant", Power = "ReactorLocked.Power", Both = "ReactorLocked.Both" },
	},
}

return table.freeze(Schema)
