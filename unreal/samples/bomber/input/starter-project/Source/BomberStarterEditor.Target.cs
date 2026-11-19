using UnrealBuildTool;

public class BomberStarterEditorTarget : TargetRules
{
    public BomberStarterEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        ExtraModuleNames.Add("BomberStarter");
    }
}
