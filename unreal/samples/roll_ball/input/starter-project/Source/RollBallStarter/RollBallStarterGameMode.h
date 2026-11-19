#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "RollBallStarterGameMode.generated.h"

UCLASS()
class ROLLBALLSTARTER_API ARollBallStarterGameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    ARollBallStarterGameMode();
    virtual void StartPlay() override;
};
