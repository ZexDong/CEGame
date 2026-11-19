#include "RollBallStarterGameMode.h"

#include "RollBallStarterController.h"
#include "RollBallStarterDisplay.h"
#include "RollBallStarterHUD.h"
#include "RollBallStarterState.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Engine/World.h"

ARollBallStarterGameMode::ARollBallStarterGameMode()
{
    DefaultPawnClass = nullptr;
    PlayerControllerClass = ARollBallStarterController::StaticClass();
    HUDClass = ARollBallStarterHUD::StaticClass();
}

void ARollBallStarterGameMode::StartPlay()
{
    Super::StartPlay();

    FActorSpawnParameters Parameters;
    Parameters.Name = TEXT("RollBallStarterState");
    Parameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    GetWorld()->SpawnActor<ARollBallStarterState>(ARollBallStarterState::StaticClass(), FTransform::Identity, Parameters);

    FActorSpawnParameters DisplayParameters;
    DisplayParameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    GetWorld()->SpawnActor<ARollBallStarterDisplay>(ARollBallStarterDisplay::StaticClass(), FTransform::Identity, DisplayParameters);

    // Use a perspective, gently elevated view so the starter demonstrates
    // actual depth, shadows, and sphere highlights instead of a flat board map.
    const FVector CameraLocation(1900.0f, -2200.0f, 1900.0f);
    const FVector CameraTarget(0.0f, 0.0f, 100.0f);
    const FRotator CameraRotation = FRotationMatrix::MakeFromX(CameraTarget - CameraLocation).Rotator();
    FActorSpawnParameters CameraParameters;
    CameraParameters.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
    ACameraActor* Camera = GetWorld()->SpawnActor<ACameraActor>(ACameraActor::StaticClass(), CameraLocation, CameraRotation, CameraParameters);
    if (Camera)
    {
        Camera->GetCameraComponent()->FieldOfView = 48.0f;
        if (APlayerController* PlayerController = GetWorld()->GetFirstPlayerController())
        {
            PlayerController->SetViewTarget(Camera);
        }
    }
}
