--!strict
-- Public constants only. This module contains no gameplay or scoring logic.

local Schema = {
	ContractVersion = "dockline-dispatch-v1",
	Tags = {
		CentralSpawn = "DD_CentralSpawn",
		GameState = "DD_GameState",
		Interactable = "DD_Interactable",
		CarryItem = "DD_CarryItem",
		Package = "DD_Package",
		ItemStation = "DD_ItemStation",
		StagingBay = "DD_StagingBay",
		Hazard = "DD_Hazard",
		SafeZone = "DD_SafeZone",
		NavNode = "DD_NavNode",
		NavLink = "DD_NavLink",
		HUDField = "DD_HUDField",
	},
	InteractionIds = {
		"Manifest.StartShift",
		"Inbound.Pickup.Glass", "Inbound.Pickup.Cold", "Inbound.Pickup.Cipher",
		"Inspection.Scanner", "Process.FragileWrap", "Process.ColdCondition",
		"Secure.AuthStart", "Secure.Key.Delta", "Secure.Key.Alpha", "Secure.Key.Charlie",
		"Measure.Scale", "Label.Printer", "Conveyor.Load",
		"Routing.Diverter.One", "Routing.Diverter.Two", "Conveyor.Dispatch", "Reject.Return",
		"Staging.Pickup.A", "Staging.Pickup.B", "Staging.Pickup.C",
		"Pallet.Slot.Cipher", "Pallet.Slot.Glass", "Pallet.Slot.Cold", "Pallet.SealPickup",
		"Checkpoint.SealShelf", "Truck.SealSocket", "Final.Code.2", "Final.Code.4", "Final.Code.1",
	},
	ItemIds = { "GlassCrate", "ColdCase", "CipherBox", "DispatchSeal" },
	PackageIds = { "GlassCrate", "ColdCase", "CipherBox" },
	CarryItemAttributes = {
		ItemId = "DD_ItemId", ItemState = "DD_ItemState", HolderUserId = "DD_HolderUserId",
		HomeStationId = "DD_HomeStationId", ApproachNodeId = "DD_ApproachNodeId",
	},
	ItemStationIds = {
		"InboundGlass", "InboundCold", "InboundCipher", "ScannerPad", "FragileWrapPad",
		"ColdConditionPad", "SecureAuthPad", "ScalePad", "LabelPad", "ConveyorLoadPad",
		"RejectBuffer", "PalletSealOutput", "SealShelf",
	},
	HUDFieldIds = {
		"Objective", "Shift", "Packages", "CarryItem", "Scanner", "Auth", "Routing",
		"Conveyor", "Pallet", "Hazard", "Checkpoint", "Timer", "Feedback",
	},
	Packages = {
		GlassCrate = { RequiredProcess = "FragileWrap", ExpectedWeight = 3, RouteId = "B", BayId = "B" },
		ColdCase = { RequiredProcess = "ColdCondition", ExpectedWeight = 5, RouteId = "C", BayId = "C" },
		CipherBox = { RequiredProcess = "SecureAuth", ExpectedWeight = 8, RouteId = "A", BayId = "A" },
	},
	Orders = {
		SecureAuth = { "Delta", "Alpha", "Charlie" },
		PalletLoad = { "CipherBox", "GlassCrate", "ColdCase" },
		FinalCode = { "2", "4", "1" },
	},
	Routes = {
		A = { DiverterOne = "Left", DiverterTwo = "Left" },
		B = { DiverterOne = "Left", DiverterTwo = "Right" },
		C = { DiverterOne = "Right", DiverterTwo = "Right" },
	},
	Attributes = {
		ProtocolVersion = "DD_ProtocolVersion", RunId = "DD_RunId", RunStatus = "DD_RunStatus",
		Phase = "DD_Phase", CarryItemId = "DD_CarryItemId", GlassState = "DD_GlassState",
		ColdState = "DD_ColdState", CipherState = "DD_CipherState", AuthState = "DD_AuthState",
		AuthProgress = "DD_AuthProgress", DiverterOne = "DD_DiverterOne", DiverterTwo = "DD_DiverterTwo",
		ConveyorState = "DD_ConveyorState", ConveyorPackageId = "DD_ConveyorPackageId",
		StagedCount = "DD_StagedCount", RejectCount = "DD_RejectCount", PalletState = "DD_PalletState",
		PalletProgress = "DD_PalletProgress", CheckpointId = "DD_CheckpointId",
		HazardState = "DD_HazardState", HazardEpoch = "DD_HazardEpoch", SealInstalled = "DD_SealInstalled",
		FinalCodeProgress = "DD_FinalCodeProgress", FinalCodeDeadline = "DD_FinalCodeDeadline",
		ObjectiveId = "DD_ObjectiveId", DeathCount = "DD_DeathCount", RunStart = "DD_RunStart",
		FinalTime = "DD_FinalTime", EventSeq = "DD_EventSeq", LastEvent = "DD_LastEvent",
		LastSourceId = "DD_LastSourceId", LastRejectCode = "DD_LastRejectCode", FeedbackText = "DD_FeedbackText",
	},
	Timing = {
		ReadyTimeout = 12, FeedbackVisible = 1.5, WrapHold = 1.5, ColdHold = 2.0,
		ConveyorResultTimeout = 3.0, HazardDeathTimeout = 1.0, RestartTimeout = 2.0,
		HazardPeriod = 7.0, HazardSafe = 3.0, FinalCodeWindow = 20.0,
	},
	Movement = { NormalWalkSpeed = 16, SealCarryWalkSpeed = 13 },
	NavLinkClass = "Configuration",
}

return table.freeze(Schema)
