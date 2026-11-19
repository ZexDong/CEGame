#include "StateFixture.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Containers/Ticker.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/EngineVersion.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Serialization/JsonSerializer.h"

namespace StateFixture
{
    static TSharedPtr<FJsonObject> Load(const FString& Path)
    {
        FString Text; TSharedPtr<FJsonObject> Json;
        if (!FFileHelper::LoadFileToString(Text, *Path)) return nullptr;
        return FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Json) ? Json : nullptr;
    }
    static void Save(const FString& Path, const TSharedRef<FJsonObject>& Json)
    {
        FString Text; FJsonSerializer::Serialize(Json, TJsonWriterFactory<>::Create(&Text));
        const FString Temp = Path + TEXT(".tmp");
        if (FFileHelper::SaveStringToFile(Text, *Temp, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM))
            IFileManager::Get().Move(*Path, *Temp, true, true);
    }
    class FService
    {
        FString Directory, Nonce, Identity; int64 Sequence = 0, Sample = 0;
        double NextSample = 0; bool Initialized = false, Authorized = false;
        TSharedRef<FJsonObject> Envelope(UWorld* World)
        {
            auto J = MakeShared<FJsonObject>();
            J->SetStringField(TEXT("transport"), Version);
            J->SetStringField(TEXT("adapter"), AdapterVersion());
            J->SetStringField(TEXT("engine"), FEngineVersion::Current().ToString());
            J->SetStringField(TEXT("candidate_identity"), Identity);
            J->SetNumberField(TEXT("pid"), FPlatformProcess::GetCurrentProcessId());
            J->SetNumberField(TEXT("sample"), ++Sample);
            J->SetNumberField(TEXT("monotonic_seconds"), FPlatformTime::Seconds());
            J->SetObjectField(TEXT("state"), ReadGame(World));
            return J;
        }
    public:
        bool Tick(float)
        {
            if (!Initialized)
            {
                Initialized = true; FString UserDir;
                if (!FParse::Value(FCommandLine::Get(), TEXT("UserDir="), UserDir)) return false;
                Directory = FPaths::Combine(UserDir, TEXT("private-fixture"));
                const auto Auth = Load(Directory / TEXT("authorization.json"));
                if (!Auth || !Auth->TryGetStringField(TEXT("nonce"), Nonce) || Nonce.Len() < 32 ||
                    !Auth->TryGetStringField(TEXT("candidate_identity"), Identity)) return false;
                Authorized = true;
            }
            if (!Authorized || !GEngine) return true;
            UWorld* World = nullptr;
            for (const auto& Context : GEngine->GetWorldContexts())
                if (Context.World() && Context.World()->IsGameWorld() && Context.World()->HasBegunPlay())
                { if (World) return true; World = Context.World(); }
            if (!World) return true;
            const auto Request = Load(Directory / TEXT("request.json"));
            if (Request)
            {
                double Requested = 0; FString Token, Operation;
                if (Request->TryGetNumberField(TEXT("sequence"), Requested) && Requested > Sequence &&
                    Requested == FMath::FloorToDouble(Requested))
                {
                    Sequence = int64(Requested);
                    auto Receipt = Envelope(World);
                    Receipt->SetNumberField(TEXT("sequence"), Sequence);
                    Receipt->SetObjectField(TEXT("before"), ReadGame(World));
                    FString Error; bool Applied = false;
                    const TSharedPtr<FJsonObject>* State = nullptr;
                    if (!Request->TryGetStringField(TEXT("nonce"), Token) || Token != Nonce)
                        Error = TEXT("AUTHORIZATION_MISMATCH");
                    else if (!Request->TryGetStringField(TEXT("operation"), Operation))
                        Error = TEXT("OPERATION_REQUIRED");
                    else if (Operation == TEXT("probe")) Applied = true;
                    else if (Operation != TEXT("apply")) Error = TEXT("OPERATION_NOT_ALLOWED");
                    else if (!Request->TryGetObjectField(TEXT("semantic_state"), State)) Error = TEXT("STATE_REQUIRED");
                    else Applied = ApplyGame(World, *State, Error);
                    Receipt->SetBoolField(TEXT("applied"), Applied);
                    Receipt->SetStringField(TEXT("reason"), Error);
                    Receipt->SetObjectField(TEXT("after"), ReadGame(World));
                    Save(Directory / FString::Printf(TEXT("receipt-%lld.json"), Sequence), Receipt);
                }
            }
            const double Now = FPlatformTime::Seconds();
            if (Now >= NextSample)
            {
                NextSample = Now + .04;
                Save(Directory / TEXT("latest.json"), Envelope(World));
            }
            return true;
        }
    };
    static FService Service;
    static const FTSTicker::FDelegateHandle Handle = FTSTicker::GetCoreTicker().AddTicker(
        FTickerDelegate::CreateLambda([](float Delta) { return Service.Tick(Delta); }));
}
