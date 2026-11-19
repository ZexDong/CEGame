#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "MinimalInterfaceHUD.generated.h"

UCLASS()
class MINIMALINTERFACE_API AMinimalInterfaceHUD : public AHUD
{
    GENERATED_BODY()

public:
    virtual void DrawHUD() override;

private:
    void DrawFilledBox(const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color);
    void DrawLabel(const FString& Label, float X, float Y, float Scale = 1.0f);
};
