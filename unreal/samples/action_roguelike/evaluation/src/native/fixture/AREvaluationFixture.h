#pragma once
#include "CoreMinimal.h"
class UWorld;
namespace AREvaluationFixture
{
    // Private instrumentation: compiled only into the evaluator's staged copy.
    void Tick(UWorld* World);
    bool Protected(const UObject* Object);
}
