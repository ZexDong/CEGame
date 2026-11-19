#include "BomberStarterHealthState.h"

#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
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

TSharedRef<FJsonObject> MakePoint(const FVector2D& Value)
{
    TSharedRef<FJsonObject> Result = MakeShared<FJsonObject>();
    Result->SetNumberField(TEXT("x"), Value.X);
    Result->SetNumberField(TEXT("y"), Value.Y);
    return Result;
}
}

ABomberStarterHealthState::ABomberStarterHealthState()
{
    PrimaryActorTick.bCanEverTick = true;
}

void ABomberStarterHealthState::BeginPlay()
{
    Super::BeginPlay();

    FParse::Value(FCommandLine::Get(), TEXT("EvalStatePath="), StatePath);
    FParse::Value(FCommandLine::Get(), TEXT("EvalGameStatePath="), GameStatePath);
    FParse::Value(FCommandLine::Get(), TEXT("EvalProcessToken="), ProcessToken);
    bObserverEnabled = (!StatePath.IsEmpty() || !GameStatePath.IsEmpty())
        && !FParse::Param(FCommandLine::Get(), TEXT("EvalObserverDisabled"));
    if (ProcessToken.IsEmpty())
    {
        ProcessToken = FGuid::NewGuid().ToString(EGuidFormats::Digits);
    }
    if (!StatePath.IsEmpty())
    {
        StatePath = FPaths::ConvertRelativePathToFull(StatePath);
    }
    if (!GameStatePath.IsEmpty())
    {
        GameStatePath = FPaths::ConvertRelativePathToFull(GameStatePath);
    }
    NextHeartbeatSeconds = FPlatformTime::Seconds() + SnapshotHeartbeatSeconds;
    PublishSnapshot(true);
}

void ABomberStarterHealthState::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);

    const double Now = FPlatformTime::Seconds();
    if (bDirty || Now >= NextHeartbeatSeconds)
    {
        PublishSnapshot(true);
        NextHeartbeatSeconds = Now + SnapshotHeartbeatSeconds;
    }
}

void ABomberStarterHealthState::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    PublishSnapshot(true);
    Super::EndPlay(EndPlayReason);
}

void ABomberStarterHealthState::MarkFirstFrameDrawn()
{
    if (!bFirstFrameDrawn)
    {
        bFirstFrameDrawn = true;
        ++HudRevision;
        bDirty = true;
    }
}

void ABomberStarterHealthState::PublishSnapshot(bool bForce)
{
    if (!bObserverEnabled || (!bForce && !bDirty))
    {
        return;
    }

    ++SnapshotId;
    ++GameSnapshotId;
    const bool bEngineWritten = StatePath.IsEmpty() || WriteSnapshot(StatePath, BuildSnapshot());
    const bool bGameWritten = GameStatePath.IsEmpty() || WriteSnapshot(GameStatePath, BuildGameSnapshot());
    if (bEngineWritten && bGameWritten)
    {
        bDirty = false;
    }
}

bool ABomberStarterHealthState::WriteSnapshot(
    const FString& DestinationPath,
    const TSharedRef<FJsonObject>& Snapshot) const
{
    FString Json;
    const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Json);
    FJsonSerializer::Serialize(Snapshot, Writer);

    const FString TempPath = DestinationPath + TEXT(".tmp");
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(DestinationPath), true);
    if (!FFileHelper::SaveStringToFile(Json, *TempPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))
    {
        return false;
    }
    return IFileManager::Get().Move(*DestinationPath, *TempPath, true, true, false, true);
}

TSharedRef<FJsonObject> ABomberStarterHealthState::BuildSnapshot() const
{
    TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
    Root->SetStringField(TEXT("schema_version"), TEXT("1.0.0"));
    Root->SetStringField(TEXT("process_token"), ProcessToken);
    Root->SetNumberField(TEXT("process_id"), static_cast<double>(FPlatformProcess::GetCurrentProcessId()));
    Root->SetNumberField(TEXT("snapshot_id"), static_cast<double>(SnapshotId));
    Root->SetStringField(TEXT("round_id"), MakeRoundId());
    Root->SetNumberField(TEXT("round_index"), 0);
    Root->SetNumberField(TEXT("restart_count"), 0);
    Root->SetStringField(TEXT("scene"), TEXT("bomber_local_duel_public_starter"));
    Root->SetNumberField(TEXT("monotonic_ms"), FPlatformTime::Seconds() * 1000.0);
    Root->SetBoolField(TEXT("ready"), true);
    Root->SetBoolField(TEXT("first_frame"), bFirstFrameDrawn);

    TSharedRef<FJsonObject> Object = MakeShared<FJsonObject>();
    Object->SetStringField(TEXT("object_id"), TEXT("bomber_starter_marker"));
    Object->SetObjectField(TEXT("normalized_position"), MakePoint(FVector2D(0.5, 0.5)));
    Root->SetObjectField(TEXT("object"), Object);

    TArray<TSharedPtr<FJsonValue>> EmptyValues;
    TSharedRef<FJsonObject> Keyboard = MakeShared<FJsonObject>();
    Keyboard->SetArrayField(TEXT("keys_down"), EmptyValues);
    Keyboard->SetBoolField(TEXT("w_down"), false);
    Keyboard->SetNumberField(TEXT("discrete_count"), 0);
    Keyboard->SetNumberField(TEXT("hold_count"), 0);
    Root->SetObjectField(TEXT("keyboard"), Keyboard);

    TSharedRef<FJsonObject> Pointer = MakeShared<FJsonObject>();
    Pointer->SetBoolField(TEXT("left_down"), false);
    Pointer->SetObjectField(TEXT("normalized_position"), MakePoint(FVector2D(0.5, 0.5)));
    Pointer->SetObjectField(TEXT("press_origin"), MakePoint(FVector2D(0.5, 0.5)));
    Pointer->SetNumberField(TEXT("click_count"), 0);
    Pointer->SetNumberField(TEXT("drag_count"), 0);
    Pointer->SetObjectField(TEXT("drag_position"), MakePoint(FVector2D(0.5, 0.5)));
    Root->SetObjectField(TEXT("pointer"), Pointer);

    TSharedRef<FJsonObject> Hud = MakeShared<FJsonObject>();
    Hud->SetNumberField(TEXT("revision"), HudRevision);
    Hud->SetStringField(TEXT("feedback"), TEXT("STARTER READY - GAMEPLAY NOT IMPLEMENTED"));
    Root->SetObjectField(TEXT("hud"), Hud);
    Root->SetArrayField(TEXT("targets"), EmptyValues);
    return Root;
}

TSharedRef<FJsonObject> ABomberStarterHealthState::BuildGameSnapshot() const
{
    TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
    Root->SetStringField(TEXT("schema_version"), TEXT("2.0.0"));
    Root->SetStringField(TEXT("process_token"), ProcessToken);
    Root->SetNumberField(TEXT("process_id"), static_cast<double>(FPlatformProcess::GetCurrentProcessId()));
    Root->SetNumberField(TEXT("snapshot_id"), static_cast<double>(GameSnapshotId));
    Root->SetStringField(TEXT("round_id"), MakeRoundId());
    Root->SetNumberField(TEXT("round_index"), 0);
    Root->SetNumberField(TEXT("restart_count"), 0);
    Root->SetNumberField(TEXT("monotonic_ms"), FPlatformTime::Seconds() * 1000.0);
    Root->SetBoolField(TEXT("bridge_ready"), true);
    Root->SetBoolField(TEXT("provider_ready"), false);
    Root->SetField(TEXT("game_state"), MakeShared<FJsonValueNull>());
    return Root;
}

FString ABomberStarterHealthState::MakeRoundId() const
{
    return FString::Printf(TEXT("%s-round-0"), *ProcessToken);
}
