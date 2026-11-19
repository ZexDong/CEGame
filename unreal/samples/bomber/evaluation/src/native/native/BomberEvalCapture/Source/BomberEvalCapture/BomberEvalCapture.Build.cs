using UnrealBuildTool;
public class BomberEvalCapture : ModuleRules
{
    public BomberEvalCapture(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PrivateDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "Json", "ImageWrapper", "GameplayTags", "UMG", "SlateCore" });
    }
}
