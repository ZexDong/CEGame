#include "MinimalInterfaceState.h"

#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Misc/App.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Guid.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

namespace
{
constexpr double SnapshotHeartbeatSeconds = 0.25;
constexpr double MinimumChangePublishSeconds = 0.05;
constexpr double DragThreshold = 0.025;

TSharedRef<FJsonObject> MakeVector(const FVector2D& Value)
{
    TSharedRef<FJsonObject> Result = MakeShared<FJsonObject>();
    Result->SetNumberField(TEXT("x"), Value.X);
    Result->SetNumberField(TEXT("y"), Value.Y);
    return Result;
}

TSharedRef<FJsonObject> MakeBounds(const FMinimalTargetState& Target)
{
    TSharedRef<FJsonObject> Result = MakeVector(Target.Position);
    Result->SetNumberField(TEXT("width"), Target.Size.X);
    Result->SetNumberField(TEXT("height"), Target.Size.Y);
    return Result;
}
}

AMinimalInterfaceState::AMinimalInterfaceState()
{
    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.TickInterval = 0.0f;
}

void AMinimalInterfaceState::BeginPlay()
{
    Super::BeginPlay();

    FMinimalTargetState ClickTarget;
    ClickTarget.TargetId = TEXT("click_target");
    ClickTarget.ObjectId = TEXT("click_target_object");
    ClickTarget.Activation = TEXT("left_click");
    ClickTarget.Position = FVector2D(0.69, 0.20);
    ClickTarget.Size = FVector2D(0.22, 0.20);
    Targets.Add(ClickTarget);

    FMinimalTargetState DragTarget;
    DragTarget.TargetId = TEXT("drag_target");
    DragTarget.ObjectId = TEXT("drag_target_object");
    DragTarget.Activation = TEXT("left_drag");
    DragTarget.Position = FVector2D(0.44, 0.40);
    DragTarget.Size = FVector2D(0.22, 0.20);
    Targets.Add(DragTarget);

    FParse::Value(FCommandLine::Get(), TEXT("EvalStatePath="), StatePath);
    FParse::Value(FCommandLine::Get(), TEXT("EvalProcessToken="), ProcessToken);
    bObserverEnabled = !StatePath.IsEmpty()
        && !FParse::Param(FCommandLine::Get(), TEXT("EvalObserverDisabled"));

    if (ProcessToken.IsEmpty())
    {
        ProcessToken = FGuid::NewGuid().ToString(EGuidFormats::Digits);
    }
    if (!StatePath.IsEmpty())
    {
        StatePath = FPaths::ConvertRelativePathToFull(StatePath);
    }
    RoundId = MakeRoundId();
    const double Now = FPlatformTime::Seconds();
    NextHeartbeatSeconds = Now + SnapshotHeartbeatSeconds;
    NextChangePublishSeconds = Now + MinimumChangePublishSeconds;
    PublishSnapshot(true);
}

void AMinimalInterfaceState::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);

    if (bMoveHeld)
    {
        const double PreviousX = ObjectPosition.X;
        ObjectPosition.X = FMath::Clamp(ObjectPosition.X + DeltaSeconds * 0.22, 0.06, 0.94);
        HoldCount += 1;
        if (!FMath::IsNearlyEqual(PreviousX, ObjectPosition.X))
        {
            MarkChanged(TEXT("W HELD: OBJECT MOVING"));
        }
    }

    const double Now = FPlatformTime::Seconds();
    if (bDirty && Now >= NextChangePublishSeconds)
    {
        PublishSnapshot();
        NextChangePublishSeconds = Now + MinimumChangePublishSeconds;
        NextHeartbeatSeconds = Now + SnapshotHeartbeatSeconds;
    }
    else if (Now >= NextHeartbeatSeconds)
    {
        PublishSnapshot(true);
        NextHeartbeatSeconds = Now + SnapshotHeartbeatSeconds;
    }
}

void AMinimalInterfaceState::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    if (bMoveHeld || bPointerHeld)
    {
        bMoveHeld = false;
        bPointerHeld = false;
        bDragging = false;
        MarkChanged(TEXT("INPUT RELEASED DURING SHUTDOWN"));
    }
    PublishSnapshot(true);
    Super::EndPlay(EndPlayReason);
}

void AMinimalInterfaceState::HandleDiscreteInput()
{
    ++DiscreteCount;
    MarkChanged(FString::Printf(TEXT("SPACE PRESSED: %d"), DiscreteCount));
}

void AMinimalInterfaceState::SetMoveHeld(bool bHeld)
{
    if (bMoveHeld == bHeld)
    {
        return;
    }
    bMoveHeld = bHeld;
    MarkChanged(bMoveHeld ? TEXT("W DOWN") : TEXT("W RELEASED"));
}

void AMinimalInterfaceState::SetPointerPosition(const FVector2D& NormalizedPosition)
{
    if (NormalizedPosition.X < 0.0 || NormalizedPosition.Y < 0.0)
    {
        return;
    }
    if (FVector2D::DistSquared(PointerPosition, NormalizedPosition) < FMath::Square(0.0001))
    {
        return;
    }

    PointerPosition = NormalizedPosition;
    if (bDragging)
    {
        DragPosition = PointerPosition;
        if (FMinimalTargetState* DragTarget = FindMutableTarget(TEXT("drag_target")))
        {
            DragTarget->Position.X = FMath::Clamp(PointerPosition.X - DragGrabOffset.X, 0.0, 1.0 - DragTarget->Size.X);
            DragTarget->Position.Y = FMath::Clamp(PointerPosition.Y - DragGrabOffset.Y, 0.0, 1.0 - DragTarget->Size.Y);
        }
        MarkChanged(TEXT("DRAGGING"));
    }
    else
    {
        MarkChanged(TEXT("POINTER MOVED"));
    }
}

void AMinimalInterfaceState::HandlePointerDown(const FVector2D& NormalizedPosition)
{
    SetPointerPosition(NormalizedPosition);
    bPointerHeld = true;
    PointerPressOrigin = PointerPosition;
    bDragging = IsInsideTarget(TEXT("drag_target"), PointerPosition);
    if (bDragging)
    {
        if (const FMinimalTargetState* DragTarget = FindTarget(TEXT("drag_target")))
        {
            DragGrabOffset = PointerPosition - DragTarget->Position;
        }
        DragPosition = PointerPosition;
    }
    MarkChanged(bDragging ? TEXT("DRAG STARTED") : TEXT("MOUSE DOWN"));
}

void AMinimalInterfaceState::HandlePointerUp(const FVector2D& NormalizedPosition)
{
    SetPointerPosition(NormalizedPosition);
    if (!bPointerHeld)
    {
        return;
    }

    const bool bClick = IsInsideTarget(TEXT("click_target"), PointerPressOrigin)
        && IsInsideTarget(TEXT("click_target"), PointerPosition);
    const bool bCompletedDrag = bDragging
        && FVector2D::Distance(PointerPressOrigin, PointerPosition) >= DragThreshold;

    bPointerHeld = false;
    bDragging = false;

    if (bClick)
    {
        ++ClickCount;
        MarkChanged(FString::Printf(TEXT("CLICK ACCEPTED: %d"), ClickCount));
    }
    else if (bCompletedDrag)
    {
        ++DragCount;
        DragPosition = PointerPosition;
        MarkChanged(FString::Printf(TEXT("DRAG ACCEPTED: %d"), DragCount));
    }
    else
    {
        MarkChanged(TEXT("MOUSE RELEASED"));
    }
}

void AMinimalInterfaceState::RestartRound()
{
    ++RestartCount;
    ++RoundIndex;
    ResetRoundState();
    RoundId = MakeRoundId();
    MarkChanged(TEXT("ROUND RESTARTED"));
}

void AMinimalInterfaceState::ResetRoundState()
{
    ObjectPosition = FVector2D(0.18, 0.72);
    PointerPosition = FVector2D(0.5, 0.5);
    PointerPressOrigin = FVector2D::ZeroVector;
    DragPosition = FVector2D(0.55, 0.50);
    DragGrabOffset = FVector2D(0.11, 0.10);
    DiscreteCount = 0;
    HoldCount = 0;
    ClickCount = 0;
    DragCount = 0;
    bMoveHeld = false;
    bPointerHeld = false;
    bDragging = false;
    if (FMinimalTargetState* DragTarget = FindMutableTarget(TEXT("drag_target")))
    {
        DragTarget->Position = FVector2D(0.44, 0.40);
    }
}

FMinimalTargetState* AMinimalInterfaceState::FindMutableTarget(const FString& TargetId)
{
    return Targets.FindByPredicate([&TargetId](const FMinimalTargetState& Target)
    {
        return Target.TargetId == TargetId;
    });
}

const FMinimalTargetState* AMinimalInterfaceState::FindTarget(const FString& TargetId) const
{
    return Targets.FindByPredicate([&TargetId](const FMinimalTargetState& Target)
    {
        return Target.TargetId == TargetId;
    });
}

bool AMinimalInterfaceState::IsInsideTarget(const FString& TargetId, const FVector2D& Point) const
{
    const FMinimalTargetState* Target = FindTarget(TargetId);
    return Target
        && Point.X >= Target->Position.X
        && Point.X <= Target->Position.X + Target->Size.X
        && Point.Y >= Target->Position.Y
        && Point.Y <= Target->Position.Y + Target->Size.Y;
}

void AMinimalInterfaceState::MarkFirstFrameDrawn()
{
    if (!bFirstFrameDrawn)
    {
        bFirstFrameDrawn = true;
        MarkChanged(TEXT("FIRST FRAME READY"));
    }
}

void AMinimalInterfaceState::MarkChanged(const FString& NewFeedback)
{
    Feedback = NewFeedback;
    ++HudRevision;
    bDirty = true;
}

void AMinimalInterfaceState::PublishSnapshot(bool bForce)
{
    if (!bObserverEnabled || StatePath.IsEmpty() || (!bDirty && !bForce && FPlatformTime::Seconds() < NextHeartbeatSeconds))
    {
        return;
    }

    ++SnapshotId;
    FString Json;
    const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Json);
    FJsonSerializer::Serialize(BuildSnapshot(), Writer);

    const FString TempPath = StatePath + TEXT(".tmp");
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(StatePath), true);
    if (FFileHelper::SaveStringToFile(Json, *TempPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))
    {
        if (IFileManager::Get().Move(*StatePath, *TempPath, true, true, false, true))
        {
            bDirty = false;
        }
    }
}

TSharedRef<FJsonObject> AMinimalInterfaceState::BuildSnapshot() const
{
    TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
    Root->SetStringField(TEXT("schema_version"), TEXT("1.0.0"));
    Root->SetStringField(TEXT("process_token"), ProcessToken);
    Root->SetNumberField(TEXT("process_id"), static_cast<double>(FPlatformProcess::GetCurrentProcessId()));
    Root->SetNumberField(TEXT("snapshot_id"), static_cast<double>(SnapshotId));
    Root->SetStringField(TEXT("round_id"), RoundId);
    Root->SetNumberField(TEXT("round_index"), RoundIndex);
    Root->SetNumberField(TEXT("restart_count"), RestartCount);
    Root->SetStringField(TEXT("scene"), TEXT("minimal_interface"));
    Root->SetNumberField(TEXT("monotonic_ms"), FPlatformTime::Seconds() * 1000.0);
    Root->SetBoolField(TEXT("ready"), true);
    Root->SetBoolField(TEXT("first_frame"), bFirstFrameDrawn);

    TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
    Object->SetStringField(TEXT("object_id"), TEXT("movable_object"));
    Object->SetObjectField(TEXT("normalized_position"), MakeVector(ObjectPosition));
    Root->SetObjectField(TEXT("object"), Object);

    TSharedRef<FJsonObject> Keyboard = MakeShared<FJsonObject>();
    TArray<TSharedPtr<FJsonValue>> KeysDown;
    if (bMoveHeld)
    {
        KeysDown.Add(MakeShared<FJsonValueString>(TEXT("W")));
    }
    Keyboard->SetArrayField(TEXT("keys_down"), KeysDown);
    Keyboard->SetBoolField(TEXT("w_down"), bMoveHeld);
    Keyboard->SetNumberField(TEXT("discrete_count"), DiscreteCount);
    Keyboard->SetNumberField(TEXT("hold_count"), HoldCount);
    Root->SetObjectField(TEXT("keyboard"), Keyboard);

    TSharedRef<FJsonObject> Pointer = MakeShared<FJsonObject>();
    Pointer->SetBoolField(TEXT("left_down"), bPointerHeld);
    Pointer->SetObjectField(TEXT("normalized_position"), MakeVector(PointerPosition));
    Pointer->SetObjectField(TEXT("press_origin"), MakeVector(PointerPressOrigin));
    Pointer->SetNumberField(TEXT("click_count"), ClickCount);
    Pointer->SetNumberField(TEXT("drag_count"), DragCount);
    Pointer->SetObjectField(TEXT("drag_position"), MakeVector(DragPosition));
    Root->SetObjectField(TEXT("pointer"), Pointer);

    TSharedRef<FJsonObject> Hud = MakeShared<FJsonObject>();
    Hud->SetNumberField(TEXT("revision"), HudRevision);
    Hud->SetStringField(TEXT("feedback"), Feedback);
    Root->SetObjectField(TEXT("hud"), Hud);

    TArray<TSharedPtr<FJsonValue>> TargetValues;
    for (const FMinimalTargetState& Target : Targets)
    {
        TSharedRef<FJsonObject> TargetObject = MakeShared<FJsonObject>();
        TargetObject->SetStringField(TEXT("target_id"), Target.TargetId);
        TargetObject->SetStringField(TEXT("object_id"), Target.ObjectId);
        TargetObject->SetBoolField(TEXT("visible"), true);
        TargetObject->SetBoolField(TEXT("enabled"), true);
        TargetObject->SetBoolField(TEXT("topmost"), true);
        TargetObject->SetStringField(TEXT("activation"), Target.Activation);
        TargetObject->SetObjectField(TEXT("normalized_bounds"), MakeBounds(Target));
        TargetValues.Add(MakeShared<FJsonValueObject>(TargetObject));
    }
    Root->SetArrayField(TEXT("targets"), TargetValues);
    return Root;
}

FString AMinimalInterfaceState::MakeRoundId() const
{
    return FString::Printf(TEXT("%s-round-%d"), *ProcessToken, RoundIndex);
}
