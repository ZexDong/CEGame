#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "BomberStarterHealthState.generated.h"

UCLASS()
class BOMBERSTARTER_API ABomberStarterHealthState : public AActor
{
    GENERATED_BODY()

public:
    ABomberStarterHealthState();

    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

    void MarkFirstFrameDrawn();

private:
    void PublishSnapshot(bool bForce = false);
    bool WriteSnapshot(const FString& DestinationPath, const TSharedRef<class FJsonObject>& Snapshot) const;
    TSharedRef<class FJsonObject> BuildSnapshot() const;
    TSharedRef<class FJsonObject> BuildGameSnapshot() const;
    FString MakeRoundId() const;

    int64 SnapshotId = 0;
    int64 GameSnapshotId = 0;
    int32 HudRevision = 0;
    bool bFirstFrameDrawn = false;
    bool bDirty = true;
    bool bObserverEnabled = false;
    double NextHeartbeatSeconds = 0.0;
    FString ProcessToken;
    FString StatePath;
    FString GameStatePath;
};
