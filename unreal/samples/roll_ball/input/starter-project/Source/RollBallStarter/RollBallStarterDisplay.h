#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "RollBallStarterDisplay.generated.h"

class UStaticMeshComponent;

/** A small, inert 3D material and lighting display for the public starter. */
UCLASS()
class ROLLBALLSTARTER_API ARollBallStarterDisplay : public AActor
{
    GENERATED_BODY()

public:
    ARollBallStarterDisplay();

    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;

private:
    UPROPERTY()
    UStaticMeshComponent* RollingSphere;

    float SphereSpin = 0.0f;
};
