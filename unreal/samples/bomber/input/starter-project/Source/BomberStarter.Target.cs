using UnrealBuildTool;

public class BomberStarterTarget : TargetRules
{
    public BomberStarterTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        ExtraModuleNames.Add("BomberStarter");
    }
}
