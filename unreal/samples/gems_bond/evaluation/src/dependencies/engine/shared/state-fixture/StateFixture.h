#pragma once
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
class UWorld;

// Private evaluator extension, compiled only into an isolated assessment copy.
// The engine transport has no knowledge of game classes, fields or verdicts.
namespace StateFixture
{
    constexpr const TCHAR* Version = TEXT("ue-state-fixture-1.0.0");
    TSharedRef<FJsonObject> ReadGame(UWorld* World);
    // Validate the complete request before committing any field. No result calls.
    bool ApplyGame(UWorld* World, const TSharedPtr<FJsonObject>& State, FString& Error);
    const TCHAR* AdapterVersion();
}
