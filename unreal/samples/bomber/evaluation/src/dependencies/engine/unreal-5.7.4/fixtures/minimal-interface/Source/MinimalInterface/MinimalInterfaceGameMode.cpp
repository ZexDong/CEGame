#include "MinimalInterfaceGameMode.h"

#include "MinimalInterfaceController.h"
#include "MinimalInterfaceHUD.h"
#include "MinimalInterfaceState.h"
#include "Engine/World.h"

AMinimalInterfaceGameMode::AMinimalInterfaceGameMode()
{
    DefaultPawnClass = nullptr;
    PlayerControllerClass = AMinimalInterfaceController::StaticClass();
    HUDClass = AMinimalInterfaceHUD::StaticClass();
}

void AMinimalInterfaceGameMode::StartPlay()
{
    Super::StartPlay();

    FActorSpawnParameters Parameters;
    Parameters.Name = TEXT("MinimalInterfaceState");
    Parameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    GetWorld()->SpawnActor<AMinimalInterfaceState>(AMinimalInterfaceState::StaticClass(), FTransform::Identity, Parameters);
}
