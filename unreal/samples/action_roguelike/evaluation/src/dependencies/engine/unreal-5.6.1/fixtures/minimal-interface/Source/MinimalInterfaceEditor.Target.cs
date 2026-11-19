using UnrealBuildTool;

public class MinimalInterfaceEditorTarget : TargetRules
{
    public MinimalInterfaceEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_6;
        ExtraModuleNames.Add("MinimalInterface");
    }
}
