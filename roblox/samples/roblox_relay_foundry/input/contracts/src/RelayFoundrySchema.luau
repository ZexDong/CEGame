--!strict
-- Public interoperability constants only. This module intentionally has no gameplay or scoring implementation.

local Schema = {
	ContractVersion = "relay-foundry-v1",
	Tags = {
		CentralSpawn = "RFP_CentralSpawn",
		CoreDock = "RFP_CoreDock",
		ProductionBay = "RFP_ProductionBay",
		PurgeBay = "RFP_PurgeBay",
		DeliveryDock = "RFP_DeliveryDock",
		SafetyCheckpoint = "RFP_SafetyCheckpoint",
		Hazard = "RFP_Hazard",
		ExitConsole = "RFP_ExitConsole",
		ExitDoor = "RFP_ExitDoor",
		EvacuationZone = "RFP_EvacuationZone",
	},
	Recipes = {
		{ Charge = "Pulse", Stabilize = "Brace", Encode = "Cipher" },
		{ Charge = "Arc", Stabilize = "Float", Encode = "Key" },
		{ Charge = "Flux", Stabilize = "Lock", Encode = "Mark" },
	},
	PlayerAttributes = {
		RunId = "RFP_RunId", OrderIndex = "RFP_OrderIndex", CorePhase = "RFP_CorePhase",
		ChargeMode = "RFP_ChargeMode", StabilizeMode = "RFP_StabilizeMode", EncodeMode = "RFP_EncodeMode",
		DeliveredCount = "RFP_DeliveredCount", FaultCount = "RFP_FaultCount", Checkpoint = "RFP_Checkpoint",
		Powered = "RFP_Powered", Completed = "RFP_Completed", RunStart = "RFP_RunStart",
		FinalTime = "RFP_FinalTime", DeathCount = "RFP_DeathCount", EventSerial = "RFP_EventSerial",
		LastEvent = "RFP_LastEvent", FeedbackText = "RFP_FeedbackText",
	},
	Phases = { "Absent", "Raw", "Charged", "Stabilized", "Encoded", "Faulted" },
	Events = {
		RunStarted = "RunStarted", CoreCollected = "CoreCollected", CorePurged = "CorePurged",
		CoreDelivered = "CoreDelivered", WrongPhase = "Rejected.WrongPhase", WrongMode = "Rejected.WrongMode",
		Checkpoint = "CheckpointActivated.Safety", Hazard = "HazardTriggered.Safety",
		Respawn = "Respawned.Safety", ExitLocked = "ExitLocked", ExitPowered = "ExitPowered",
		Completed = "Completed", Restarted = "Restarted",
		Processed = { Charge = "Processed.Charge", Stabilize = "Processed.Stabilize", Encode = "Processed.Encode" },
	},
	Timing = { ReadyTimeout = 12, HazardDeathTimeout = 1.5, DoorOpenTimeout = 2, RestartTimeout = 3, MinimumFeedbackVisible = 1.5 },
}

return table.freeze(Schema)
