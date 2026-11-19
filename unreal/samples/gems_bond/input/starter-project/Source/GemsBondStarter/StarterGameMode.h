#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/HUD.h"
#include "StarterGameMode.generated.h"

UCLASS()
class GEMSBONDSTARTER_API AStarterHUD : public AHUD
{
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
};

UCLASS()
class GEMSBONDSTARTER_API AStarterGameMode : public AGameModeBase
{
    GENERATED_BODY()
public:
    AStarterGameMode();
    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;
private:
    FString SnapshotPath;
    FString SessionId;
    double LastPublish = -1.0;
    uint64 Sequence = 0;
    int32 HealthPulses = 0;
    // Replace this state mapping with truthful reporting when implementing the game.
    TSharedRef<class FJsonObject> Capture() const;
    void Publish();
};
