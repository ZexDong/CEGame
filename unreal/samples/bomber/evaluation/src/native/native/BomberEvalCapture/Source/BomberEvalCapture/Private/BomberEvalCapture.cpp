#include "Modules/ModuleManager.h"
#include "Containers/Ticker.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "UnrealClient.h"
#include "ImageUtils.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "BomberOriginalReferenceObserver.h"

class FBomberEvalCaptureModule final : public IModuleInterface
{
    FString Root, Token, PendingId, PendingName, LastId;
    FTSTicker::FDelegateHandle TickHandle;
    FDelegateHandle CaptureHandle;
    bool OriginalReferenceObserver = false;
    double LastObservation = 0;

    void WriteJson(const FString& Name, const TSharedRef<FJsonObject>& Value)
    {
        FString Text;
        FJsonSerializer::Serialize(Value, TJsonWriterFactory<>::Create(&Text));
        const FString Path = Root / Name;
        FFileHelper::SaveStringToFile(Text, *(Path + TEXT(".tmp")), FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
        IFileManager::Get().Move(*Path, *(Path + TEXT(".tmp")), true, true);
    }

    TSharedRef<FJsonObject> Identity() const
    {
        auto Value = MakeShared<FJsonObject>();
        Value->SetStringField(TEXT("producer"), TEXT("ue-native-viewport"));
        Value->SetStringField(TEXT("process_token"), Token);
        Value->SetStringField(TEXT("project_file"), FPaths::ConvertRelativePathToFull(FPaths::GetProjectFilePath()));
        Value->SetNumberField(TEXT("process_id"), FPlatformProcess::GetCurrentProcessId());
        Value->SetNumberField(TEXT("frame"), double(GFrameCounter));
        Value->SetNumberField(TEXT("monotonic_ms"), FPlatformTime::Seconds() * 1000.0);
        return Value;
    }

    bool Tick(float)
    {
        if (!GEngine || !GEngine->GameViewport || !GEngine->GameViewport->Viewport) { return true; }
        if (OriginalReferenceObserver && FPlatformTime::Seconds() - LastObservation >= 0.1)
        {
            auto Snapshot = Identity();
            Snapshot->SetObjectField(TEXT("original"), BomberOriginalSnapshot(GEngine->GameViewport->GetWorld()));
            WriteJson(TEXT("original-state.json"), Snapshot);
            LastObservation = FPlatformTime::Seconds();
        }
        if (!PendingId.IsEmpty()) { return true; }
        FString Text;
        if (!FFileHelper::LoadFileToString(Text, *(Root / TEXT("request.json")))) { return true; }
        TSharedPtr<FJsonObject> Request;
        if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Request) || !Request.IsValid()) { return true; }
        FString Id, Name, RequestToken;
        if (!Request->TryGetStringField(TEXT("request_id"), Id) || !Request->TryGetStringField(TEXT("name"), Name)
            || !Request->TryGetStringField(TEXT("process_token"), RequestToken) || RequestToken != Token || Id == LastId) { return true; }
        if (Id.IsEmpty() || Name.IsEmpty() || Name.Len() > 128) { return true; }
        for (TCHAR Ch : Name) { if (!(FChar::IsAlnum(Ch) || Ch == '-' || Ch == '_')) { return true; } }
        auto* Viewport = GEngine->GameViewport->Viewport;
        // Set physical render dimensions, never desktop coordinates or DPI-scaled crops.
        if (Viewport->GetSizeXY() != FIntPoint(1280, 720))
        {
            if (FViewportFrame* Frame = Viewport->GetViewportFrame()) { Frame->ResizeFrame(1280, 720, EWindowMode::Windowed); }
            return true;
        }
        PendingId = Id; PendingName = Name; LastId = Id;
        FScreenshotRequest::RequestScreenshot(Root / (Name + TEXT(".png")), true, false, false);
        return true;
    }

    void Captured(int32 Width, int32 Height, const TArray<FColor>& Pixels)
    {
        if (PendingId.IsEmpty()) { return; }
        auto Receipt = Identity();
        Receipt->SetStringField(TEXT("request_id"), PendingId);
        Receipt->SetStringField(TEXT("name"), PendingName);
        Receipt->SetNumberField(TEXT("width"), Width);
        Receipt->SetNumberField(TEXT("height"), Height);
        Receipt->SetBoolField(TEXT("includes_ui"), true);
        if (OriginalReferenceObserver)
        {
            Receipt->SetObjectField(TEXT("original"), BomberOriginalSnapshot(GEngine->GameViewport->GetWorld()));
        }
        TArray64<uint8> Png;
        FImageUtils::PNGCompressImageArray(Width, Height, TArrayView64<const FColor>(Pixels.GetData(), Pixels.Num()), Png);
        const bool Saved = FFileHelper::SaveArrayToFile(Png, *(Root / (PendingName + TEXT(".png"))));
        Receipt->SetStringField(TEXT("status"), Saved && Width == 1280 && Height == 720 ? TEXT("ok") : TEXT("render_capture_error"));
        WriteJson(PendingName + TEXT(".native.json"), Receipt);
        PendingId.Empty(); PendingName.Empty();
    }

public:
    virtual void StartupModule() override
    {
        if (!FParse::Value(FCommandLine::Get(), TEXT("BomberCaptureRoot="), Root)
            || !FParse::Value(FCommandLine::Get(), TEXT("EvalProcessToken="), Token)) { return; }
        Root = FPaths::ConvertRelativePathToFull(Root);
        OriginalReferenceObserver = FParse::Param(FCommandLine::Get(), TEXT("BomberOriginalReferenceObserver"))
            && FPaths::GetBaseFilename(FPaths::GetProjectFilePath()) == TEXT("Bomber");
        IFileManager::Get().MakeDirectory(*Root, true);
        CaptureHandle = UGameViewportClient::OnScreenshotCaptured().AddRaw(this, &FBomberEvalCaptureModule::Captured);
        TickHandle = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateRaw(this, &FBomberEvalCaptureModule::Tick), 0.01f);
        auto Ready = Identity(); Ready->SetStringField(TEXT("status"), TEXT("ready")); WriteJson(TEXT("ready.json"), Ready);
    }
    virtual void ShutdownModule() override
    {
        if (TickHandle.IsValid()) { FTSTicker::GetCoreTicker().RemoveTicker(TickHandle); }
        if (CaptureHandle.IsValid()) { UGameViewportClient::OnScreenshotCaptured().Remove(CaptureHandle); }
    }
};
IMPLEMENT_MODULE(FBomberEvalCaptureModule, BomberEvalCapture)
