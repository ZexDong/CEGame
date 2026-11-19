#include "NightSkyDuelScaffoldGameMode.h"

#include "NightSkyDuelHealthState.h"
#include "NightSkyDuelScaffoldHUD.h"
#include "Engine/World.h"

ANightSkyDuelScaffoldGameMode::ANightSkyDuelScaffoldGameMode()
{
    DefaultPawnClass = nullptr;
    HUDClass = ANightSkyDuelScaffoldHUD::StaticClass();
}

void ANightSkyDuelScaffoldGameMode::StartPlay()
{
    Super::StartPlay();

    FActorSpawnParameters Parameters;
    Parameters.Name = TEXT("NightSkyDuelReadOnlyHealthPublisher");
    Parameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    GetWorld()->SpawnActor<ANightSkyDuelHealthState>(ANightSkyDuelHealthState::StaticClass(), FTransform::Identity, Parameters);
}
