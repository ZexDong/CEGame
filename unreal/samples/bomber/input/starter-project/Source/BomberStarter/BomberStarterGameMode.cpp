#include "BomberStarterGameMode.h"

#include "BomberStarterHUD.h"
#include "BomberStarterHealthState.h"
#include "Engine/World.h"

ABomberStarterGameMode::ABomberStarterGameMode()
{
    DefaultPawnClass = nullptr;
    HUDClass = ABomberStarterHUD::StaticClass();
}

void ABomberStarterGameMode::StartPlay()
{
    Super::StartPlay();

    FActorSpawnParameters Parameters;
    Parameters.Name = TEXT("BomberReadOnlyHealthPublisher");
    Parameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    GetWorld()->SpawnActor<ABomberStarterHealthState>(
        ABomberStarterHealthState::StaticClass(), FTransform::Identity, Parameters);
}
