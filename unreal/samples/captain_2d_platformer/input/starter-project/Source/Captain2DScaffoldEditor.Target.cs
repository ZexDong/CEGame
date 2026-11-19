using UnrealBuildTool;

public class Captain2DScaffoldEditorTarget : TargetRules
{
    public Captain2DScaffoldEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("Captain2DScaffold");
    }
}
