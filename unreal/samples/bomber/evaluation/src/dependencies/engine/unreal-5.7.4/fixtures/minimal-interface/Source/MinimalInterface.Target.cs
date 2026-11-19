using UnrealBuildTool;

public class MinimalInterfaceTarget : TargetRules
{
    public MinimalInterfaceTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("MinimalInterface");
    }
}
