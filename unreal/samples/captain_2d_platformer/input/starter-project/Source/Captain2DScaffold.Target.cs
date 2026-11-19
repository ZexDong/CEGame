using UnrealBuildTool;

public class Captain2DScaffoldTarget : TargetRules
{
    public Captain2DScaffoldTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("Captain2DScaffold");
    }
}
