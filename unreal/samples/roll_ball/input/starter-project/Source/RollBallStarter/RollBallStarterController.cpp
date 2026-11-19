#include "RollBallStarterController.h"

#include "Components/InputComponent.h"
#include "InputCoreTypes.h"
#include "Kismet/KismetSystemLibrary.h"

void ARollBallStarterController::SetupInputComponent()
{
    Super::SetupInputComponent();
    check(InputComponent);
    InputComponent->BindKey(EKeys::Escape, IE_Pressed, this, &ARollBallStarterController::QuitStarter);
}

void ARollBallStarterController::QuitStarter()
{
    UKismetSystemLibrary::QuitGame(this, this, EQuitPreference::Quit, false);
}
