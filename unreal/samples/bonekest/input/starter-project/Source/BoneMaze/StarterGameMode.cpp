#include "StarterGameMode.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "GameFramework/PlayerController.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Policies/CondensedJsonPrintPolicy.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/Guid.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "InputCoreTypes.h"

AStarterGameMode::AStarterGameMode()
{
    PrimaryActorTick.bCanEverTick = true;
    DefaultPawnClass = nullptr;
    HUDClass = AStarterHUD::StaticClass();
}

void AStarterGameMode::BeginPlay()
{
    Super::BeginPlay();
    SessionId = FGuid::NewGuid().ToString(EGuidFormats::Digits);
    if (!FParse::Value(FCommandLine::Get(), TEXT("ObservationPath="), SnapshotPath))
        SnapshotPath = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Benchmark/state.json"));
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(SnapshotPath), true);
    if (APlayerController* PC = GetWorld()->GetFirstPlayerController())
    {
        PC->bShowMouseCursor = true;
        PC->SetInputMode(FInputModeGameOnly());
    }
    Publish();
}

void AStarterGameMode::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (APlayerController* PC = GetWorld()->GetFirstPlayerController())
        if (PC->WasInputKeyJustPressed(EKeys::SpaceBar)) ++HealthPulses;
    if (FPlatformTime::Seconds() - LastPublish >= 0.1) Publish();
}

TSharedRef<FJsonObject> AStarterGameMode::Capture() const
{
    // This reports only the unfinished starter. Bind it to real state in the completed game.
    TSharedRef<FJsonObject> Snapshot = MakeShared<FJsonObject>();
    Snapshot->SetStringField(TEXT("phase"), TEXT("not_ready"));
    TSharedRef<FJsonObject> Slots = MakeShared<FJsonObject>();
    for (const TCHAR* Name : {TEXT("lives"), TEXT("scrolls"), TEXT("coins"), TEXT("keys_owned"), TEXT("red_key"), TEXT("green_key"), TEXT("blue_key"), TEXT("room_x"), TEXT("room_y"), TEXT("maze_size"), TEXT("room_changes"), TEXT("monster_x"), TEXT("monster_y"), TEXT("reveal_active"), TEXT("danger_nearby"), TEXT("round_seed")})
        Slots->SetNumberField(Name, 0);
    Snapshot->SetObjectField(TEXT("slots"), Slots);
    Snapshot->SetArrayField(TEXT("entities"), TArray<TSharedPtr<FJsonValue>>());
    Snapshot->SetArrayField(TEXT("targets"), TArray<TSharedPtr<FJsonValue>>());
    return Snapshot;
}

void AStarterGameMode::Publish()
{
    if (SnapshotPath.IsEmpty()) return;
    TSharedRef<FJsonObject> Snapshot = Capture();
    Snapshot->SetStringField(TEXT("schema_version"), TEXT("bonemaze-observation-1.0.0"));
    Snapshot->SetStringField(TEXT("session_id"), SessionId);
    Snapshot->SetStringField(TEXT("round_id"), SessionId + TEXT("-unfinished"));
    Snapshot->SetNumberField(TEXT("process_id"), FPlatformProcess::GetCurrentProcessId());
    Snapshot->SetNumberField(TEXT("snapshot_id"), static_cast<double>(++Sequence));
    Snapshot->SetNumberField(TEXT("monotonic_seconds"), FPlatformTime::Seconds());
    Snapshot->SetNumberField(TEXT("simulation_seconds"), 0);
    TSharedRef<FJsonObject> Health = MakeShared<FJsonObject>();
    Health->SetNumberField(TEXT("input_pulses"), HealthPulses);
    Snapshot->SetObjectField(TEXT("starter_health"), Health);
    FString Json;
    FJsonSerializer::Serialize(Snapshot, TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Json));
    const FString Temporary = SnapshotPath + TEXT(".tmp");
    const bool Saved = FFileHelper::SaveStringToFile(Json, *Temporary, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
    if (!Saved || !IFileManager::Get().Move(*SnapshotPath, *Temporary, true, false, false, true))
        UE_LOG(LogTemp, Error, TEXT("Observation snapshot could not be published."));
    LastPublish = FPlatformTime::Seconds();
}

void AStarterHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas || !GEngine) return;
    DrawRect(FLinearColor(0.045f, 0.07f, 0.055f), 0, 0, Canvas->SizeX, Canvas->SizeY);
    const float Scale = FMath::Min(Canvas->SizeX / 1280.0f, Canvas->SizeY / 720.0f);
    DrawText(TEXT("BONE MAZE"), FLinearColor(0.95f,0.72f,0.24f), 90*Scale,155*Scale,GEngine->GetLargeFont(),2.2f*Scale);
    DrawRect(FLinearColor(0.32f,0.65f,0.42f),90*Scale,245*Scale,1100*Scale,3*Scale);
    DrawText(TEXT("Unfinished starter - presentation assets are available."),FLinearColor::White,
        90*Scale,290*Scale,GEngine->GetMediumFont(),1.2f*Scale);
    DrawText(TEXT("Gameplay has not been implemented."),FLinearColor(0.75f,0.81f,0.77f),
        90*Scale,345*Scale,GEngine->GetMediumFont(),1.1f*Scale);
    DrawText(TEXT("Press Space to check input. Close the window to exit."),FLinearColor(0.75f,0.81f,0.77f),
        90*Scale,400*Scale,GEngine->GetMediumFont(),1.1f*Scale);
    if (GetOwningPlayerController() && GetOwningPlayerController()->IsInputKeyDown(EKeys::SpaceBar))
        DrawText(TEXT("Input received"),FLinearColor(0.4f,1.0f,0.6f),90*Scale,460*Scale,GEngine->GetLargeFont(),Scale);
}
