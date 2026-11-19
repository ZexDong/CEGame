using UnrealBuildTool;
public class GemsBondStarter : ModuleRules {
    public GemsBondStarter(ReadOnlyTargetRules Target) : base(Target) {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine", "InputCore", "Json" });
    }
}
