#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/HUD.h"
#include "GameFramework/PlayerController.h"
#include "StarterShell.generated.h"

UCLASS()
class CHOMPSTARTER_API AStarterShellController : public APlayerController
{
    GENERATED_BODY()
public:
    AStarterShellController();
};

UCLASS()
class CHOMPSTARTER_API AStarterShellHUD : public AHUD
{
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
};

UCLASS()
class CHOMPSTARTER_API AStarterShellMode : public AGameModeBase
{
    GENERATED_BODY()
public:
    AStarterShellMode();
    virtual void StartPlay() override;
};
