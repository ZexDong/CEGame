#include "Captain2DScaffoldHUD.h"

#include "Captain2DHealthState.h"
#include "CanvasItem.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"

namespace
{
ACaptain2DHealthState* FindHealthState(UWorld* World)
{
    if (!World)
    {
        return nullptr;
    }
    for (TActorIterator<ACaptain2DHealthState> It(World); It; ++It)
    {
        return *It;
    }
    return nullptr;
}
}

void ACaptain2DScaffoldHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas || Canvas->SizeX <= 0 || Canvas->SizeY <= 0)
    {
        return;
    }

    DrawFilledBox(FVector2D::ZeroVector, FVector2D(Canvas->SizeX, Canvas->SizeY), FLinearColor(0.018, 0.024, 0.045, 1.0));
    DrawFilledBox(FVector2D(64.0, 64.0), FVector2D(Canvas->SizeX - 128.0, Canvas->SizeY - 128.0), FLinearColor(0.055, 0.090, 0.145, 1.0));
    DrawLabel(TEXT("CAPTAIN2D PUBLIC STARTER SCAFFOLD"), 104.0f, 118.0f, 1.45f);
    DrawLabel(TEXT("GAMEPLAY IS NOT IMPLEMENTED"), 104.0f, 184.0f, 1.2f);
    DrawLabel(TEXT("Built-in Paper2D is available. Marketplace plugins are not required."), 104.0f, 246.0f, 0.9f);
    DrawLabel(TEXT("This screen only proves that the clean starter can open and render."), 104.0f, 286.0f, 0.9f);
    DrawLabel(TEXT("READ-ONLY HEALTH PUBLISHER: READY"), 104.0f, 374.0f, 1.0f);

    if (ACaptain2DHealthState* State = FindHealthState(GetWorld()))
    {
        State->MarkFirstFrameDrawn();
    }
}

void ACaptain2DScaffoldHUD::DrawFilledBox(const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color)
{
    FCanvasTileItem Tile(Position, Size, Color);
    Tile.BlendMode = SE_BLEND_Opaque;
    Canvas->DrawItem(Tile);
}

void ACaptain2DScaffoldHUD::DrawLabel(const FString& Label, float X, float Y, float Scale)
{
    FCanvasTextItem Text(FVector2D(X, Y), FText::FromString(Label), GEngine->GetLargeFont(), FLinearColor::White);
    Text.Scale = FVector2D(Scale, Scale);
    Text.EnableShadow(FLinearColor::Black);
    Canvas->DrawItem(Text);
}
