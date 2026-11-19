#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "BomberStarterGameMode.generated.h"

UCLASS()
class BOMBERSTARTER_API ABomberStarterGameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    ABomberStarterGameMode();
    virtual void StartPlay() override;
};
