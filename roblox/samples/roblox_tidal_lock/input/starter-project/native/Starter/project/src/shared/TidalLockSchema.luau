--!strict
-- Public constants only. This module intentionally contains no gameplay,
-- reference implementation, scoring weights, or evaluator trajectory.

local Schema = {}

Schema.ContractVersion = "tidal-lock-v1"
Schema.WorkspaceAttributes = {
	ContractVersion = "TLD_ContractVersion",
	Ready = "TLD_Ready",
}

Schema.Tags = {
	CentralSpawn = "TLD_CentralSpawn",
	PumpConsole = "TLD_PumpConsole",
	LockChamber = "TLD_LockChamber",
	WaterPlane = "TLD_WaterPlane",
	LevelMarker = "TLD_LevelMarker",
	LevelConsole = "TLD_LevelConsole",
	Gate = "TLD_Gate",
	Barge = "TLD_Barge",
	MooringZone = "TLD_MooringZone",
	AdvanceConsole = "TLD_AdvanceConsole",
	MooringClamp = "TLD_MooringClamp",
	DispatchConsole = "TLD_DispatchConsole",
	Checkpoint = "TLD_Checkpoint",
	Hazard = "TLD_Hazard",
}

Schema.IdentityAttributes = {
	Id = "TLD_Id",
	Lock = "TLD_Lock",
	Level = "TLD_Level",
	Action = "TLD_Action",
	Side = "TLD_Side",
	Segment = "TLD_Segment",
}

Schema.PlayerAttributes = {
	RunId = "TLD_RunId",
	PumpStep = "TLD_PumpStep",
	NextPump = "TLD_NextPump",
	PrimeOn = "TLD_PrimeOn",
	BalanceOn = "TLD_BalanceOn",
	VentOn = "TLD_VentOn",
	PumpOnline = "TLD_PumpOnline",
	Lock1Level = "TLD_Lock1Level",
	Lock1TargetLevel = "TLD_Lock1TargetLevel",
	Lock1Transitioning = "TLD_Lock1Transitioning",
	Lock1Progress = "TLD_Lock1Progress",
	Lock2Level = "TLD_Lock2Level",
	Lock2TargetLevel = "TLD_Lock2TargetLevel",
	Lock2Transitioning = "TLD_Lock2Transitioning",
	Lock2Progress = "TLD_Lock2Progress",
	L1UpstreamOpen = "TLD_L1UpstreamOpen",
	L1DownstreamOpen = "TLD_L1DownstreamOpen",
	L2UpstreamOpen = "TLD_L2UpstreamOpen",
	L2DownstreamOpen = "TLD_L2DownstreamOpen",
	BargeLocation = "TLD_BargeLocation",
	BargeMoving = "TLD_BargeMoving",
	BargeSegment = "TLD_BargeSegment",
	BargeProgress = "TLD_BargeProgress",
	PortClamped = "TLD_PortClamped",
	StarboardClamped = "TLD_StarboardClamped",
	Checkpoint = "TLD_Checkpoint",
	DeathCount = "TLD_DeathCount",
	Completed = "TLD_Completed",
	RunStart = "TLD_RunStart",
	FinalTime = "TLD_FinalTime",
	EventSerial = "TLD_EventSerial",
	LastEvent = "TLD_LastEvent",
	FeedbackText = "TLD_FeedbackText",
}

Schema.PumpOrder = {"Prime", "Balance", "Vent"}
Schema.Levels = {"Low", "Mid", "High"}
Schema.BargeLocations = {"Upstream", "Lock1", "Transfer", "Lock2", "Terminal"}
Schema.Segments = {"S1", "S2", "S3", "S4"}
Schema.ClampOrder = {"Port", "Starboard"}

Schema.Timing = {
	ReadyTimeout = 10,
	LevelMin = 3,
	LevelMax = 5,
	BargeMin = 3,
	BargeMax = 5,
	DoorTimeout = 2,
	RestartTimeout = 2,
	FeedbackMinimum = 1.5,
}

return table.freeze(Schema)
