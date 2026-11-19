#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "RollBallStarterController.generated.h"

UCLASS()
class ROLLBALLSTARTER_API ARollBallStarterController : public APlayerController
{
    GENERATED_BODY()

protected:
    virtual void SetupInputComponent() override;

private:
    void QuitStarter();
};
