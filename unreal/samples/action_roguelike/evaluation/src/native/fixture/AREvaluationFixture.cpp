#include "AREvaluationFixture.h"
#include "ARCandidateAdapter.h"
#include "UnrealFixtureCapabilities.h"
#include "Engine/World.h"
#include "GameFramework/Character.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"

namespace AREvaluationFixture
{
    static bool Invulnerable = true;
    static FString LastRequest;
    static FString Channel;
    static bool Enabled()
    {
        if (Channel.IsEmpty()) FParse::Value(FCommandLine::Get(), TEXT("AREvaluationFixture="), Channel);
        return !Channel.IsEmpty();
    }
    bool Protected(const UObject* Object)
    {
        return Enabled() && Invulnerable && Object && Object->GetWorld();
    }
    static bool ValidRequest(const TSharedPtr<FJsonObject>& Request)
    {
        const TSet<FString> Numbers{TEXT("health"), TEXT("credits"), TEXT("remaining_seconds"), TEXT("distance_m")};
        const TSet<FString> Flags{TEXT("teleport_acquired"), TEXT("invulnerable"), TEXT("capture_pointer"), TEXT("block_forward_space")};
        const TSet<FString> Vectors{TEXT("position_m"), TEXT("near_position_m"), TEXT("aim_position_m")};
        auto VectorValid = [](const TSharedPtr<FJsonObject>& Object)
        {
            if (!Object.IsValid()) return false;
            for (const TCHAR* Axis : {TEXT("x"), TEXT("y"), TEXT("z")})
            {
                double Value;
                if (!Object->TryGetNumberField(Axis, Value) || !FMath::IsFinite(Value)) return false;
            }
            return true;
        };
        for (const auto& Pair : Request->Values)
        {
            if (Numbers.Contains(Pair.Key))
            {
                double Value;
                if (!Pair.Value->TryGetNumber(Value) || !FMath::IsFinite(Value) || Value < 0) return false;
                if ((Pair.Key == TEXT("health") || Pair.Key == TEXT("distance_m")) && Value <= 0) return false;
            }
            else if (Flags.Contains(Pair.Key)) { if (Pair.Value->Type != EJson::Boolean) return false; }
            else if (Vectors.Contains(Pair.Key))
            {
                if (Pair.Value->Type != EJson::Object || !VectorValid(Pair.Value->AsObject())) return false;
            }
            else if (Pair.Key == TEXT("freeze_enemies") || Pair.Key == TEXT("remove_props"))
            {
                if (Pair.Value->Type != EJson::Array) return false;
                for (const auto& Value : Pair.Value->AsArray())
                    if (Value->Type != EJson::Object || !VectorValid(Value->AsObject())) return false;
            }
            else if (Pair.Key == TEXT("aim"))
            {
                if (Pair.Value->Type != EJson::String) return false;
                const FString Aim = Pair.Value->AsString();
                if (Aim != TEXT("up") && Aim != TEXT("open") && Aim != TEXT("obstacle")) return false;
            }
            else if (Pair.Key != TEXT("request_id")) return false;
        }
        return !Request->HasField(TEXT("near_position_m")) || Request->HasField(TEXT("distance_m"));
    }
    void Tick(UWorld* World)
    {
        if (!Enabled() || !World) return;
        auto* Player = UnrealFixtureCapabilities::FindPlayer(World);
        if (!Player) return;
        Player->SetCanBeDamaged(!Invulnerable);
        FString Text;
        if (!FFileHelper::LoadFileToString(Text, *(Channel / TEXT("request.json")))) return;
        TSharedPtr<FJsonObject> Request;
        if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Request) || !Request.IsValid()) return;
        FString Id;
        if (!Request->TryGetStringField(TEXT("request_id"), Id) || Id == LastRequest) return;
        LastRequest = Id;
        auto Receipt = MakeShared<FJsonObject>();
        Receipt->SetStringField(TEXT("request_id"), Id);
        Receipt->SetStringField(TEXT("adapter_version"), TEXT("ar-private-fixture-2.0.0"));
        Receipt->SetNumberField(TEXT("process_id"), FPlatformProcess::GetCurrentProcessId());
        Receipt->SetNumberField(TEXT("monotonic_ms"), FPlatformTime::Seconds() * 1000.0);
        Receipt->SetObjectField(TEXT("requested"), Request.ToSharedRef());
        bool Ok = ValidRequest(Request);
        const bool Valid = Ok;
        if (Valid)
        {
        if (Request->HasField(TEXT("invulnerable"))) Invulnerable = Request->GetBoolField(TEXT("invulnerable"));
        Player->SetCanBeDamaged(!Invulnerable);
        Receipt->SetBoolField(TEXT("invulnerable"), Invulnerable);
        Receipt->SetStringField(TEXT("engine_capabilities_version"), UnrealFixtureCapabilities::Version);
        Receipt->SetStringField(TEXT("candidate_adapter_id"), ARCandidateAdapter::Identity());
        const UnrealFixtureCapabilities::FGeometrySettings Geometry{1400.0, 1200.0};
        Ok &= UnrealFixtureCapabilities::Apply(World, Request, Receipt, Geometry);
        Ok &= ARCandidateAdapter::Apply(World, Request, Receipt);
        }
        Receipt->SetBoolField(TEXT("applied"), Ok);
        Receipt->SetStringField(TEXT("failure_code"), Ok ? TEXT("") : (Valid ? TEXT("FIXTURE_NATIVE_MAPPING_OR_GEOMETRY_FAILED") : TEXT("FIXTURE_WRITE_FORBIDDEN")));
        FString Output;
        FJsonSerializer::Serialize(Receipt, TJsonWriterFactory<>::Create(&Output));
        const FString Temp = Channel / TEXT("response.tmp");
        const FString Path = Channel / TEXT("response.json");
        FFileHelper::SaveStringToFile(Output, *Temp, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
        IFileManager::Get().Move(*Path, *Temp, true, true);
    }
}

namespace
{
    // Engine lifecycle binding works without editing a candidate Tick method.
    struct FFixtureTickRegistration
    {
        FDelegateHandle Handle;
        FFixtureTickRegistration()
        {
            Handle = FWorldDelegates::OnWorldPreActorTick.AddLambda(
                [](UWorld* World, ELevelTick TickType, float DeltaSeconds)
                {
                    if (World && World->IsGameWorld()) AREvaluationFixture::Tick(World);
                });
        }
        ~FFixtureTickRegistration() { FWorldDelegates::OnWorldPreActorTick.Remove(Handle); }
    } FixtureTickRegistration;
}
