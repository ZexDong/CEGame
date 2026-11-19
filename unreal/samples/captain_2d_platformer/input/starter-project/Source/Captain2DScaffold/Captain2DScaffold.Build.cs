using UnrealBuildTool;

public class Captain2DScaffold : ModuleRules
{
    public Captain2DScaffold(ReadOnlyTargetRules Target) : base(Target)
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
