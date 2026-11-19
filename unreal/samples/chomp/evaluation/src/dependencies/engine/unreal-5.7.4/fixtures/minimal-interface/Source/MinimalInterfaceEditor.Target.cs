using UnrealBuildTool;

public class MinimalInterfaceEditorTarget : TargetRules
{
    public MinimalInterfaceEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("MinimalInterface");
    }
}
