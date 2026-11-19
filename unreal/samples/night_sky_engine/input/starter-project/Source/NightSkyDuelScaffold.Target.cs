using UnrealBuildTool;

public class NightSkyDuelScaffoldTarget : TargetRules
{
    public NightSkyDuelScaffoldTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("NightSkyDuelScaffold");
    }
}
