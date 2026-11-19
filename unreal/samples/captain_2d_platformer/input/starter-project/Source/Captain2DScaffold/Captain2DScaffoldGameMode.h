#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "Captain2DScaffoldGameMode.generated.h"

UCLASS()
class CAPTAIN2DSCAFFOLD_API ACaptain2DScaffoldGameMode : public AGameModeBase
{
    GENERATED_BODY()

public:
    ACaptain2DScaffoldGameMode();
    virtual void StartPlay() override;
};
