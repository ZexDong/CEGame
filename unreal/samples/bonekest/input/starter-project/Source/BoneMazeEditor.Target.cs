using UnrealBuildTool;
public class BoneMazeEditorTarget : TargetRules {
    public BoneMazeEditorTarget(TargetInfo Target) : base(Target) {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("BoneMaze");
    }
}
