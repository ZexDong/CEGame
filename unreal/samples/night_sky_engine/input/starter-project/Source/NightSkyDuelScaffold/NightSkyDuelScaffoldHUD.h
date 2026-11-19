#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "NightSkyDuelScaffoldHUD.generated.h"

UCLASS()
class NIGHTSKYDUELSCAFFOLD_API ANightSkyDuelScaffoldHUD : public AHUD
{
    GENERATED_BODY()

public:
    virtual void DrawHUD() override;

private:
    void DrawFilledBox(const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color);
    void DrawLabel(const FString& Label, float X, float Y, float Scale);
};
