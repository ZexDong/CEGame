#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "MinimalInterfaceGameMode.generated.h"

UCLASS()
class MINIMALINTERFACE_API AMinimalInterfaceGameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    AMinimalInterfaceGameMode();
    virtual void StartPlay() override;
};
