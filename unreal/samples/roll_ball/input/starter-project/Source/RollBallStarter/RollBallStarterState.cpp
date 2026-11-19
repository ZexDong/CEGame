#include "RollBallStarterState.h"

#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"

namespace
{
constexpr double SnapshotHeartbeatSeconds = 0.25;

bool ReadCell(const TSharedPtr<FJsonObject>& Object, FIntPoint& Cell)
{
    if (!Object.IsValid())
    {
        return false;
    }

    double X = 0.0;
    double Y = 0.0;
    if (!Object->TryGetNumberField(TEXT("x"), X) || !Object->TryGetNumberField(TEXT("y"), Y))
    {
        return false;
    }

    Cell = FIntPoint(static_cast<int32>(X), static_cast<int32>(Y));
    return true;
}

TSharedRef<FJsonObject> MakeCell(const FIntPoint& Cell)
{
    TSharedRef<FJsonObject> Result = MakeShared<FJsonObject>();
    Result->SetNumberField(TEXT("x"), Cell.X);
    Result->SetNumberField(TEXT("y"), Cell.Y);
    return Result;
}

bool ReadCellArray(const TSharedPtr<FJsonObject>& Root, const TCHAR* FieldName, TArray<FIntPoint>& Output)
{
    const TArray<TSharedPtr<FJsonValue>>* Values = nullptr;
    if (!Root.IsValid() || !Root->TryGetArrayField(FieldName, Values) || !Values)
    {
        return false;
    }

    Output.Reset();
    for (const TSharedPtr<FJsonValue>& Value : *Values)
    {
        FIntPoint Cell;
        if (!Value.IsValid() || !ReadCell(Value->AsObject(), Cell))
        {
            return false;
        }
        Output.Add(Cell);
    }
    return true;
}

TArray<TSharedPtr<FJsonValue>> MakeCellArray(const TArray<FIntPoint>& Cells)
{
    TArray<TSharedPtr<FJsonValue>> Values;
    Values.Reserve(Cells.Num());
    for (const FIntPoint& Cell : Cells)
    {
        Values.Add(MakeShared<FJsonValueObject>(MakeCell(Cell)));
    }
    return Values;
}
}

ARollBallStarterState::ARollBallStarterState()
{
    PrimaryActorTick.bCanEverTick = true;
}

void ARollBallStarterState::BeginPlay()
{
    Super::BeginPlay();
    bLayoutLoaded = LoadLayout();

    FParse::Value(FCommandLine::Get(), TEXT("RollBallStatePath="), StatePath);
    bPublisherEnabled = !StatePath.IsEmpty();
    if (bPublisherEnabled)
    {
        StatePath = FPaths::ConvertRelativePathToFull(StatePath);
    }

    NextHeartbeatSeconds = FPlatformTime::Seconds() + SnapshotHeartbeatSeconds;
    PublishBridge(true);
}

void ARollBallStarterState::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    const double Now = FPlatformTime::Seconds();
    if (Now >= NextHeartbeatSeconds)
    {
        PublishBridge(true);
        NextHeartbeatSeconds = Now + SnapshotHeartbeatSeconds;
    }
}

void ARollBallStarterState::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
    PublishBridge(true);
    Super::EndPlay(EndPlayReason);
}

bool ARollBallStarterState::LoadLayout()
{
    const FString LayoutPath = FPaths::Combine(FPaths::ProjectConfigDir(), TEXT("FixedRollBallLayout.json"));
    FString Json;
    if (!FFileHelper::LoadFileToString(Json, *LayoutPath))
    {
        LoadError = TEXT("Fixed layout data could not be read.");
        return false;
    }

    TSharedPtr<FJsonObject> Root;
    const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Json);
    if (!FJsonSerializer::Deserialize(Reader, Root) || !Root.IsValid())
    {
        LoadError = TEXT("Fixed layout data is not valid JSON.");
        return false;
    }

    const TSharedPtr<FJsonObject>* Grid = nullptr;
    const TSharedPtr<FJsonObject>* Start = nullptr;
    const TSharedPtr<FJsonObject>* Exit = nullptr;
    double Width = 0.0;
    double Height = 0.0;
    if (!Root->TryGetStringField(TEXT("layout_id"), LayoutId)
        || !Root->TryGetObjectField(TEXT("grid"), Grid) || !Grid || !Grid->IsValid()
        || !(*Grid)->TryGetNumberField(TEXT("width"), Width)
        || !(*Grid)->TryGetNumberField(TEXT("height"), Height)
        || !Root->TryGetObjectField(TEXT("start_cell"), Start) || !Start
        || !Root->TryGetObjectField(TEXT("exit_cell"), Exit) || !Exit
        || !ReadCell(*Start, StartCell)
        || !ReadCell(*Exit, ExitCell)
        || !ReadCellArray(Root, TEXT("trap_cells"), TrapCells)
        || !ReadCellArray(Root, TEXT("vertical_walls"), VerticalWalls)
        || !ReadCellArray(Root, TEXT("horizontal_walls"), HorizontalWalls))
    {
        LoadError = TEXT("Fixed layout data is missing a required field.");
        return false;
    }

    GridWidth = static_cast<int32>(Width);
    GridHeight = static_cast<int32>(Height);
    if (GridWidth <= 0 || GridHeight <= 0)
    {
        LoadError = TEXT("Fixed layout grid dimensions are invalid.");
        return false;
    }
    return true;
}

void ARollBallStarterState::MarkFirstFrameDrawn()
{
    if (!bFirstFrameDrawn)
    {
        bFirstFrameDrawn = true;
        PublishBridge(true);
    }
}

void ARollBallStarterState::PublishBridge(bool bForce)
{
    if (!bPublisherEnabled || StatePath.IsEmpty() || (!bForce && FPlatformTime::Seconds() < NextHeartbeatSeconds))
    {
        return;
    }

    ++SnapshotId;
    FString Json;
    const TSharedRef<TJsonWriter<>> Writer = TJsonWriterFactory<>::Create(&Json);
    FJsonSerializer::Serialize(BuildBridgeSnapshot(), Writer);

    const FString TempPath = StatePath + TEXT(".tmp");
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(StatePath), true);
    if (FFileHelper::SaveStringToFile(Json, *TempPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))
    {
        IFileManager::Get().Move(*StatePath, *TempPath, true, true, false, true);
    }
}

TSharedRef<FJsonObject> ARollBallStarterState::BuildBridgeSnapshot() const
{
    TSharedRef<FJsonObject> Root = MakeShared<FJsonObject>();
    Root->SetStringField(TEXT("schema_version"), TEXT("1.0.0"));
    Root->SetNumberField(TEXT("process_id"), static_cast<double>(FPlatformProcess::GetCurrentProcessId()));
    Root->SetNumberField(TEXT("snapshot_id"), static_cast<double>(SnapshotId));
    Root->SetNumberField(TEXT("monotonic_ms"), FPlatformTime::Seconds() * 1000.0);
    Root->SetBoolField(TEXT("bridge_ready"), bLayoutLoaded);
    Root->SetBoolField(TEXT("provider_ready"), false);
    Root->SetBoolField(TEXT("first_frame"), bFirstFrameDrawn);
    Root->SetStringField(TEXT("layout_id"), LayoutId);
    Root->SetObjectField(TEXT("start_cell"), MakeCell(StartCell));
    Root->SetObjectField(TEXT("exit_cell"), MakeCell(ExitCell));
    Root->SetArrayField(TEXT("trap_cells"), MakeCellArray(TrapCells));
    Root->SetField(TEXT("game_state"), MakeShared<FJsonValueNull>());
    if (!LoadError.IsEmpty())
    {
        Root->SetStringField(TEXT("bridge_error"), LoadError);
    }
    return Root;
}
