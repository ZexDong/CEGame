using UnrealBuildTool;

public class MinimalInterfaceTarget : TargetRules
{
    public MinimalInterfaceTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_6;
        ExtraModuleNames.Add("MinimalInterface");
    }
}
