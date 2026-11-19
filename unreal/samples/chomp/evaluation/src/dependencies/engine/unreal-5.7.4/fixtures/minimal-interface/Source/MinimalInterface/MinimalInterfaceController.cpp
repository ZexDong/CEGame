#include "MinimalInterfaceController.h"

#include "MinimalInterfaceState.h"
#include "Components/InputComponent.h"
#include "EngineUtils.h"
#include "InputCoreTypes.h"

AMinimalInterfaceController::AMinimalInterfaceController()
{
    bShowMouseCursor = true;
    bEnableClickEvents = false;
    bEnableMouseOverEvents = false;
}

void AMinimalInterfaceController::BeginPlay()
{
    Super::BeginPlay();

    bShowMouseCursor = true;
    FInputModeGameAndUI InputMode;
    InputMode.SetHideCursorDuringCapture(false);
    InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
    SetInputMode(InputMode);
}

void AMinimalInterfaceController::SetupInputComponent()
{
    Super::SetupInputComponent();
    check(InputComponent);

    InputComponent->BindKey(EKeys::SpaceBar, IE_Pressed, this, &AMinimalInterfaceController::OnDiscretePressed);
    InputComponent->BindKey(EKeys::W, IE_Pressed, this, &AMinimalInterfaceController::OnMovePressed);
    InputComponent->BindKey(EKeys::W, IE_Released, this, &AMinimalInterfaceController::OnMoveReleased);
    InputComponent->BindKey(EKeys::LeftMouseButton, IE_Pressed, this, &AMinimalInterfaceController::OnPointerPressed);
    InputComponent->BindKey(EKeys::LeftMouseButton, IE_Released, this, &AMinimalInterfaceController::OnPointerReleased);
    InputComponent->BindKey(EKeys::R, IE_Pressed, this, &AMinimalInterfaceController::OnRestartPressed);
}

void AMinimalInterfaceController::PlayerTick(float DeltaTime)
{
    Super::PlayerTick(DeltaTime);

    if (AMinimalInterfaceState* State = GetFixtureState())
    {
        State->SetPointerPosition(ReadNormalizedPointer());
    }
}

AMinimalInterfaceState* AMinimalInterfaceController::GetFixtureState() const
{
    if (!GetWorld())
    {
        return nullptr;
    }

    for (TActorIterator<AMinimalInterfaceState> It(GetWorld()); It; ++It)
    {
        return *It;
    }
    return nullptr;
}

FVector2D AMinimalInterfaceController::ReadNormalizedPointer() const
{
    int32 Width = 0;
    int32 Height = 0;
    double X = 0.0;
    double Y = 0.0;
    GetViewportSize(Width, Height);

    if (Width <= 0 || Height <= 0 || !GetMousePosition(X, Y))
    {
        return FVector2D(-1.0, -1.0);
    }

    return FVector2D(
        FMath::Clamp(X / static_cast<double>(Width), 0.0, 1.0),
        FMath::Clamp(Y / static_cast<double>(Height), 0.0, 1.0));
}

void AMinimalInterfaceController::OnDiscretePressed()
{
    if (AMinimalInterfaceState* State = GetFixtureState())
    {
        State->HandleDiscreteInput();
    }
}

void AMinimalInterfaceController::OnMovePressed()
{
    if (AMinimalInterfaceState* State = GetFixtureState())
    {
        State->SetMoveHeld(true);
    }
}

void AMinimalInterfaceController::OnMoveReleased()
{
    if (AMinimalInterfaceState* State = GetFixtureState())
    {
        State->SetMoveHeld(false);
    }
}

void AMinimalInterfaceController::OnPointerPressed()
{
    if (AMinimalInterfaceState* State = GetFixtureState())
    {
        State->HandlePointerDown(ReadNormalizedPointer());
    }
}

void AMinimalInterfaceController::OnPointerReleased()
{
    if (AMinimalInterfaceState* State = GetFixtureState())
    {
        State->HandlePointerUp(ReadNormalizedPointer());
    }
}

void AMinimalInterfaceController::OnRestartPressed()
{
    if (AMinimalInterfaceState* State = GetFixtureState())
    {
        State->RestartRound();
    }
}
