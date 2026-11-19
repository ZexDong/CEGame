using UnrealBuildTool;

public class NightSkyDuelScaffold : ModuleRules
{
    public NightSkyDuelScaffold(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(new[]
        {
            "Core",
            "CoreUObject",
            "Engine",
            "InputCore",
            "Json",
            "Paper2D"
        });
    }
}
