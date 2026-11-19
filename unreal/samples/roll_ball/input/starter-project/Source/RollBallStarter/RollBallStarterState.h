#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "RollBallStarterState.generated.h"

UCLASS()
class ROLLBALLSTARTER_API ARollBallStarterState : public AActor
{
    GENERATED_BODY()

public:
    ARollBallStarterState();

    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

    bool IsLayoutLoaded() const { return bLayoutLoaded; }
    int32 GetGridWidth() const { return GridWidth; }
    int32 GetGridHeight() const { return GridHeight; }
    const FString& GetLayoutId() const { return LayoutId; }
    const FIntPoint& GetStartCell() const { return StartCell; }
    const FIntPoint& GetExitCell() const { return ExitCell; }
    const TArray<FIntPoint>& GetTrapCells() const { return TrapCells; }
    const TArray<FIntPoint>& GetVerticalWalls() const { return VerticalWalls; }
    const TArray<FIntPoint>& GetHorizontalWalls() const { return HorizontalWalls; }
    const FString& GetLoadError() const { return LoadError; }
    void MarkFirstFrameDrawn();

private:
    bool LoadLayout();
    void PublishBridge(bool bForce = false);
    TSharedRef<class FJsonObject> BuildBridgeSnapshot() const;

    FString LayoutId;
    FString LoadError;
    FString StatePath;
    int32 GridWidth = 0;
    int32 GridHeight = 0;
    int64 SnapshotId = 0;
    FIntPoint StartCell = FIntPoint::ZeroValue;
    FIntPoint ExitCell = FIntPoint::ZeroValue;
    TArray<FIntPoint> TrapCells;
    TArray<FIntPoint> VerticalWalls;
    TArray<FIntPoint> HorizontalWalls;
    bool bLayoutLoaded = false;
    bool bFirstFrameDrawn = false;
    bool bPublisherEnabled = false;
    double NextHeartbeatSeconds = 0.0;
};
