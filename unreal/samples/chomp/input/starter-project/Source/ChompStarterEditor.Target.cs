using UnrealBuildTool;
public class ChompStarterEditorTarget : TargetRules
{
    public ChompStarterEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("ChompStarter");
    }
}
