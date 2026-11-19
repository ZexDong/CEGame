#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "NightSkyDuelScaffoldGameMode.generated.h"

UCLASS()
class NIGHTSKYDUELSCAFFOLD_API ANightSkyDuelScaffoldGameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    ANightSkyDuelScaffoldGameMode();
    virtual void StartPlay() override;
};
