using UnrealBuildTool;

public class NightSkyDuelScaffoldEditorTarget : TargetRules
{
    public NightSkyDuelScaffoldEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("NightSkyDuelScaffold");
    }
}
