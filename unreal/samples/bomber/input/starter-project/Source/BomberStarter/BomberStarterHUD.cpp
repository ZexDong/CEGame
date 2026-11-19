#include "BomberStarterHUD.h"

#include "BomberStarterHealthState.h"
#include "CanvasItem.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"

namespace
{
ABomberStarterHealthState* FindHealthState(UWorld* World)
{
    if (!World)
    {
        return nullptr;
    }
    for (TActorIterator<ABomberStarterHealthState> It(World); It; ++It)
    {
        return *It;
    }
    return nullptr;
}
}

void ABomberStarterHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas || Canvas->SizeX <= 0 || Canvas->SizeY <= 0)
    {
        return;
    }

    DrawFilledBox(FVector2D::ZeroVector, FVector2D(Canvas->SizeX, Canvas->SizeY), FLinearColor(0.012, 0.020, 0.038, 1.0));
    DrawFilledBox(FVector2D(64.0, 64.0), FVector2D(Canvas->SizeX - 128.0, Canvas->SizeY - 128.0), FLinearColor(0.040, 0.085, 0.130, 1.0));
    DrawLabel(TEXT("BOMBER LOCAL DUEL PUBLIC STARTER"), 104.0f, 112.0f, 1.35f, FLinearColor(0.95, 0.82, 0.18, 1.0));
    DrawLabel(TEXT("GAMEPLAY IS NOT IMPLEMENTED"), 104.0f, 180.0f, 1.15f);
    DrawLabel(TEXT("Clean original character, arena, power-up, bomb, and marker assets are supplied."), 104.0f, 244.0f, 0.82f);
    DrawLabel(TEXT("No duel gameplay or preassembled solution is included."), 104.0f, 284.0f, 0.78f);
    DrawLabel(TEXT("READ-ONLY HEALTH PUBLISHER: READY"), 104.0f, 374.0f, 1.0f, FLinearColor(0.30, 0.95, 0.55, 1.0));

    if (ABomberStarterHealthState* State = FindHealthState(GetWorld()))
    {
        State->MarkFirstFrameDrawn();
    }
}

void ABomberStarterHUD::DrawFilledBox(const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color)
{
    FCanvasTileItem Tile(Position, Size, Color);
    Tile.BlendMode = SE_BLEND_Opaque;
    Canvas->DrawItem(Tile);
}

void ABomberStarterHUD::DrawLabel(const FString& Label, float X, float Y, float Scale, const FLinearColor& Color)
{
    FCanvasTextItem Text(FVector2D(X, Y), FText::FromString(Label), GEngine->GetLargeFont(), Color);
    Text.Scale = FVector2D(Scale, Scale);
    Text.EnableShadow(FLinearColor::Black);
    Canvas->DrawItem(Text);
}

