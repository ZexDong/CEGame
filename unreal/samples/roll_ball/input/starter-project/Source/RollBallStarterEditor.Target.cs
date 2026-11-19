using UnrealBuildTool;

public class RollBallStarterEditorTarget : TargetRules
{
    public RollBallStarterEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("RollBallStarter");
    }
}
