#pragma once
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
class UWorld;
namespace ARCandidateAdapter
{
    const TCHAR* Identity();
    bool Apply(UWorld* World, const TSharedPtr<FJsonObject>& Request, TSharedRef<FJsonObject> Receipt);
}
