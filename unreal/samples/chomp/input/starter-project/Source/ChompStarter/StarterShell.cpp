#include "StarterShell.h"
#include "ObservationTransport.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Camera/CameraActor.h"

AStarterShellController::AStarterShellController()
{
    bShowMouseCursor = true;
}

void AStarterShellHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas) return;
    DrawRect(FLinearColor(0.022f, 0.031f, 0.052f), 0, 0, Canvas->SizeX, Canvas->SizeY);
    const float Left = Canvas->SizeX * 0.08f;
    DrawRect(FLinearColor(0.02f, 0.55f, 1.0f), Left, Canvas->SizeY * 0.30f, Canvas->SizeX * 0.40f, 4);
    DrawText(TEXT("CHOMP"), FLinearColor::White, Left, Canvas->SizeY * 0.37f, GEngine->GetLargeFont(), 3.0f);
    DrawText(TEXT("Blank implementation workspace"), FLinearColor(0.65f, 0.76f, 0.88f), Left, Canvas->SizeY * 0.51f, GEngine->GetMediumFont(), 1.25f);
    DrawText(TEXT("Gameplay has not been implemented."), FLinearColor::White, Left, Canvas->SizeY * 0.59f, GEngine->GetMediumFont());
    DrawText(TEXT("Read GDD.md to build the game."), FLinearColor(0.65f, 0.76f, 0.88f), Left, Canvas->SizeY * 0.65f, GEngine->GetMediumFont());
    if (auto* Transport = GetWorld()->GetSubsystem<UObservationTransport>()) Transport->NotifyFrameDrawn();
}

AStarterShellMode::AStarterShellMode()
{
    DefaultPawnClass = nullptr;
    PlayerControllerClass = AStarterShellController::StaticClass();
    HUDClass = AStarterShellHUD::StaticClass();
}

void AStarterShellMode::StartPlay()
{
    Super::StartPlay();
    auto* Camera = GetWorld()->SpawnActor<ACameraActor>();
    if (auto* Controller = GetWorld()->GetFirstPlayerController()) Controller->SetViewTarget(Camera);
}
