--!strict
-- Public constants only. This module contains no gameplay, scoring, or evaluator logic.

local Schema = {
	ContractVersion = "reactor-relay-v2-hard",
	Tags = {
		GameState = "RR_GameState",
		BayState = "RR_BayState",
		Control = "RR_Control",
		HUDField = "RR_HUDField",
	},
	ControlIds = {
		"start_button", "bay_a", "bay_b", "bay_c", "power_minus", "power_plus",
		"coolant_minus", "coolant_plus", "phase_left", "phase_right", "lock_button",
		"arm_button", "commit_button", "scan_button", "purge_button", "sequence_a", "sequence_b",
		"sequence_c", "restart_button",
	},
	HUDFieldIds = {
		"Cycle", "Timer", "Integrity", "Faults", "PowerPool", "CoolantPool",
		"ScanCharges", "Purge", "SelectedBay", "Incident", "LockProgress", "ExpectedLockBay",
		"CommitArmed", "ArmTimer", "SequenceProgress", "Feedback",
	},
	BayIds = { "A", "B", "C" },
	PhaseValues = { -2, -1, 0, 1, 2 },
	IncidentOrder = { "None", "CoolantLeak.B", "PhaseDrift.C", "PowerSurge.A", "DualLeak.AC", "Crossfeed.BC" },
	LockOrders = { {"A","B","C"}, {"B","C","A"}, {"C","A","B"}, {"B","A","C"}, {"A","C","B"}, {"C","B","A"} },
	FinalSequence = { "A", "C", "B", "A", "C", "B", "C", "A" },
	CycleTargets = {
		{ Base = { A = {2,1,0}, B = {3,2,1}, C = {2,3,-1} }, Effective = { A = {2,1,0}, B = {3,2,1}, C = {2,3,-1} } },
		{ Base = { A = {1,2,-1}, B = {3,1,2}, C = {2,2,0} }, Effective = { A = {1,2,-1}, B = {3,2,2}, C = {2,2,0} } },
		{ Base = { A = {4,1,1}, B = {1,2,-2}, C = {2,3,0} }, Effective = { A = {4,1,1}, B = {1,2,-2}, C = {2,3,1} } },
		{ Base = { A = {2,2,-2}, B = {2,1,1}, C = {2,3,2} }, Effective = { A = {3,2,-2}, B = {2,1,1}, C = {2,3,2} } },
		{ Base = { A = {3,1,2}, B = {2,2,0}, C = {2,1,-1} }, Effective = { A = {3,2,2}, B = {2,2,0}, C = {2,2,-1} } },
		{ Base = { A = {1,2,0}, B = {4,1,-2}, C = {2,3,2} }, Effective = { A = {1,2,0}, B = {2,1,-2}, C = {4,3,2} } },
	},
	LogicalLayout = {
		Canvas = {1600,900}, BayPanels = { A = {60,120,480,400}, B = {560,120,480,400}, C = {1060,120,480,400} },
		Controls = {
			start_button={600,390,400,120}, restart_button={1340,28,180,52}, lock_button={980,560,180,56},
			bay_a={80,145,440,56}, bay_b={580,145,440,56}, bay_c={1080,145,440,56},
			power_minus={80,560,120,56}, power_plus={220,560,120,56}, coolant_minus={380,560,120,56}, coolant_plus={520,560,120,56}, arm_button={1180,560,160,56},
			phase_left={680,560,120,56}, phase_right={820,560,120,56}, commit_button={1360,560,160,56}, scan_button={80,650,260,56}, purge_button={360,650,260,56},
			sequence_a={440,480,200,110}, sequence_b={700,480,200,110}, sequence_c={960,480,200,110},
		},
	},
	Limits = {
		PowerPerBay = { 0, 4 }, CoolantPerBay = { 0, 3 }, Phase = { -2, 2 },
		PowerPool = 7, CoolantPool = 6, FaultLoss = 4, InitialIntegrity = 100,
	},
	Timing = { Ready = 12, Cycle = 18, StableMatch = 0.75, CommitArm = 3, ScanPreview = 4, SequencePreviewSymbol = 0.60, SequencePreviewGap = 0.25, SequenceInput = 6, Feedback = 1, Restart = 2 },
}

return table.freeze(Schema)
