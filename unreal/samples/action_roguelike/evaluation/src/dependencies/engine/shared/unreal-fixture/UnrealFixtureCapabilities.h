#pragma once
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
class UWorld;
class ACharacter;
namespace UnrealFixtureCapabilities
{
    constexpr const TCHAR* Version = TEXT("ue-fixture-capabilities-1.0.0");
    struct FGeometrySettings
    {
        double AimTraceDistance;
        double EndpointDistance;
    };
    ACharacter* FindPlayer(UWorld* World);
    // Engine-only placement, collision, orientation, entities and viewport focus.
    // No candidate header, semantic state write, result function or observer write.
    bool Apply(UWorld* World, const TSharedPtr<FJsonObject>& Request,
        TSharedRef<FJsonObject> Receipt, const FGeometrySettings& Settings);
}
