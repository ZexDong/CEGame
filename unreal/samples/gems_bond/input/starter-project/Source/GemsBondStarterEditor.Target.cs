using UnrealBuildTool;
public class GemsBondStarterEditorTarget : TargetRules {
    public GemsBondStarterEditorTarget(TargetInfo Target) : base(Target) {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V6;
        IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
        ExtraModuleNames.Add("GemsBondStarter");
    }
}
