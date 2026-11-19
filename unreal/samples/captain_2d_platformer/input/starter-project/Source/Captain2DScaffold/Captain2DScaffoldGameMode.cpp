#include "Captain2DScaffoldGameMode.h"

#include "Captain2DHealthState.h"
#include "Captain2DScaffoldHUD.h"
#include "Engine/World.h"

ACaptain2DScaffoldGameMode::ACaptain2DScaffoldGameMode()
{
    DefaultPawnClass = nullptr;
    HUDClass = ACaptain2DScaffoldHUD::StaticClass();
}

void ACaptain2DScaffoldGameMode::StartPlay()
{
    Super::StartPlay();

    FActorSpawnParameters Parameters;
    Parameters.Name = TEXT("Captain2DReadOnlyHealthPublisher");
    Parameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    GetWorld()->SpawnActor<ACaptain2DHealthState>(ACaptain2DHealthState::StaticClass(), FTransform::Identity, Parameters);
}
