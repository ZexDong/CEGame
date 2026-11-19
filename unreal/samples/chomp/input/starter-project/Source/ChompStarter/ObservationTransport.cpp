#include "ObservationTransport.h"
#include "Dom/JsonObject.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Guid.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

bool UObservationTransport::DoesSupportWorldType(EWorldType::Type WorldType) const
{
    return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

void UObservationTransport::Initialize(FSubsystemCollectionBase& Collection)
{
    Super::Initialize(Collection);
    FParse::Value(FCommandLine::Get(), TEXT("ChompStatePath="), OutputPath);
    ProcessToken = FGuid::NewGuid().ToString(EGuidFormats::Digits);
    if (!OutputPath.IsEmpty()) IFileManager::Get().MakeDirectory(*FPaths::GetPath(OutputPath), true);
}

TStatId UObservationTransport::GetStatId() const { RETURN_QUICK_DECLARE_CYCLE_STAT(ChompObservationTransport, STATGROUP_Tickables); }
void UObservationTransport::NotifyFrameDrawn() { FrameDrawn = true; }

void UObservationTransport::PublishObservation(const FString& StateJson)
{
    TSharedPtr<FJsonObject> Parsed;
    if (FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(StateJson), Parsed) && Parsed.IsValid()) LatestState = StateJson;
    else { LatestState.Empty(); UE_LOG(LogTemp, Warning, TEXT("Observation must be a JSON object.")); }
}

void UObservationTransport::Tick(float DeltaTime)
{
    const double Now = FPlatformTime::Seconds();
    if (OutputPath.IsEmpty() || Now - LastWrite < 0.05) return;
    LastWrite = Now;
    auto Root = MakeShared<FJsonObject>();
    Root->SetStringField(TEXT("schema_version"), TEXT("1.0.0"));
    Root->SetNumberField(TEXT("process_id"), FPlatformProcess::GetCurrentProcessId());
    Root->SetStringField(TEXT("process_token"), ProcessToken);
    Root->SetNumberField(TEXT("snapshot_id"), ++SnapshotId);
    Root->SetNumberField(TEXT("monotonic_ms"), Now * 1000.0);
    Root->SetBoolField(TEXT("bridge_ready"), true);
    Root->SetBoolField(TEXT("first_frame"), FrameDrawn);
    TSharedPtr<FJsonObject> State;
    const bool Ready = !LatestState.IsEmpty() && FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(LatestState), State) && State.IsValid();
    Root->SetBoolField(TEXT("provider_ready"), Ready);
    if (Ready) Root->SetObjectField(TEXT("game_state"), State);
    else Root->SetField(TEXT("game_state"), MakeShared<FJsonValueNull>());
    FString Json;
    FJsonSerializer::Serialize(Root, TJsonWriterFactory<>::Create(&Json));
    const FString Temporary = OutputPath + TEXT(".tmp");
    if (FFileHelper::SaveStringToFile(Json, *Temporary, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))
        IFileManager::Get().Move(*OutputPath, *Temporary, true, true, false, true);
}
