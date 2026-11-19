#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "MinimalInterfaceState.generated.h"

USTRUCT()
struct FMinimalTargetState
{
    GENERATED_BODY()

    FString TargetId;
    FString ObjectId;
    FString Activation;
    FVector2D Position = FVector2D::ZeroVector;
    FVector2D Size = FVector2D::ZeroVector;
};

UCLASS()
class MINIMALINTERFACE_API AMinimalInterfaceState : public AActor
{
    GENERATED_BODY()

public:
    AMinimalInterfaceState();

    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;
    virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

    void HandleDiscreteInput();
    void SetMoveHeld(bool bHeld);
    void SetPointerPosition(const FVector2D& NormalizedPosition);
    void HandlePointerDown(const FVector2D& NormalizedPosition);
    void HandlePointerUp(const FVector2D& NormalizedPosition);
    void RestartRound();

    const FMinimalTargetState* FindTarget(const FString& TargetId) const;
    bool IsInsideTarget(const FString& TargetId, const FVector2D& Point) const;
    const TArray<FMinimalTargetState>& GetTargets() const { return Targets; }
    const FVector2D& GetObjectPosition() const { return ObjectPosition; }
    const FVector2D& GetPointerPosition() const { return PointerPosition; }
    const FVector2D& GetDragPosition() const { return DragPosition; }
    int32 GetDiscreteCount() const { return DiscreteCount; }
    int32 GetHoldCount() const { return HoldCount; }
    int32 GetClickCount() const { return ClickCount; }
    int32 GetDragCount() const { return DragCount; }
    int32 GetRestartCount() const { return RestartCount; }
    int32 GetRoundIndex() const { return RoundIndex; }
    int32 GetHudRevision() const { return HudRevision; }
    bool IsMoveHeld() const { return bMoveHeld; }
    bool IsPointerHeld() const { return bPointerHeld; }
    bool IsDragging() const { return bDragging; }
    bool WasFirstFrameDrawn() const { return bFirstFrameDrawn; }
    bool IsObserverEnabled() const { return bObserverEnabled; }
    const FString& GetFeedback() const { return Feedback; }
    const FString& GetRoundId() const { return RoundId; }
    const FString& GetProcessToken() const { return ProcessToken; }

    void MarkFirstFrameDrawn();

private:
    FMinimalTargetState* FindMutableTarget(const FString& TargetId);
    void ResetRoundState();
    void MarkChanged(const FString& NewFeedback);
    void PublishSnapshot(bool bForce = false);
    TSharedRef<class FJsonObject> BuildSnapshot() const;
    FString MakeRoundId() const;

    FVector2D ObjectPosition = FVector2D(0.18, 0.72);
    FVector2D PointerPosition = FVector2D(0.5, 0.5);
    FVector2D PointerPressOrigin = FVector2D::ZeroVector;
    FVector2D DragPosition = FVector2D(0.55, 0.50);
    FVector2D DragGrabOffset = FVector2D(0.11, 0.10);

    TArray<FMinimalTargetState> Targets;
    int32 DiscreteCount = 0;
    int32 HoldCount = 0;
    int32 ClickCount = 0;
    int32 DragCount = 0;
    int32 RestartCount = 0;
    int32 RoundIndex = 1;
    int32 HudRevision = 0;
    int64 SnapshotId = 0;
    bool bMoveHeld = false;
    bool bPointerHeld = false;
    bool bDragging = false;
    bool bFirstFrameDrawn = false;
    bool bDirty = true;
    bool bObserverEnabled = false;
    double NextHeartbeatSeconds = 0.0;
    double NextChangePublishSeconds = 0.0;
    FString Feedback = TEXT("READY");
    FString RoundId;
    FString ProcessToken;
    FString StatePath;
};
