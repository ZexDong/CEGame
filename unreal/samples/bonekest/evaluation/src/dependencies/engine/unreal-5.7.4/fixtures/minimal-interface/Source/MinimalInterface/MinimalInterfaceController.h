#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "MinimalInterfaceController.generated.h"

UCLASS()
class MINIMALINTERFACE_API AMinimalInterfaceController : public APlayerController
{
    GENERATED_BODY()

public:
    AMinimalInterfaceController();

protected:
    virtual void BeginPlay() override;
    virtual void SetupInputComponent() override;
    virtual void PlayerTick(float DeltaTime) override;

private:
    class AMinimalInterfaceState* GetFixtureState() const;
    FVector2D ReadNormalizedPointer() const;
    void OnDiscretePressed();
    void OnMovePressed();
    void OnMoveReleased();
    void OnPointerPressed();
    void OnPointerReleased();
    void OnRestartPressed();
};
