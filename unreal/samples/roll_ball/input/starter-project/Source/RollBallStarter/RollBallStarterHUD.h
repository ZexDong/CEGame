#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "RollBallStarterHUD.generated.h"

UCLASS()
class ROLLBALLSTARTER_API ARollBallStarterHUD : public AHUD
{
    GENERATED_BODY()

public:
    virtual void DrawHUD() override;

private:
    void DrawLabel(const FString& Label, float X, float Y, float Scale = 1.0f, const FLinearColor& Color = FLinearColor::White);
};
