#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "Captain2DScaffoldHUD.generated.h"

UCLASS()
class CAPTAIN2DSCAFFOLD_API ACaptain2DScaffoldHUD : public AHUD
{
    GENERATED_BODY()

public:
    virtual void DrawHUD() override;

private:
    void DrawFilledBox(const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color);
    void DrawLabel(const FString& Label, float X, float Y, float Scale);
};
