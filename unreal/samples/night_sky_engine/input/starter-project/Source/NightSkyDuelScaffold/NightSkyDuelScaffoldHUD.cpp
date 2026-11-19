#include "NightSkyDuelScaffoldHUD.h"

#include "NightSkyDuelHealthState.h"
#include "CanvasItem.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"

namespace
{
ANightSkyDuelHealthState* FindHealthState(UWorld* World)
{
    if (!World)
    {
        return nullptr;
    }
    for (TActorIterator<ANightSkyDuelHealthState> It(World); It; ++It)
    {
        return *It;
    }
    return nullptr;
}
}

void ANightSkyDuelScaffoldHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas || Canvas->SizeX <= 0 || Canvas->SizeY <= 0)
    {
        return;
    }

    DrawFilledBox(FVector2D::ZeroVector, FVector2D(Canvas->SizeX, Canvas->SizeY), FLinearColor(0.012, 0.018, 0.040, 1.0));
    DrawFilledBox(FVector2D(64.0, 64.0), FVector2D(Canvas->SizeX - 128.0, Canvas->SizeY - 128.0), FLinearColor(0.050, 0.075, 0.135, 1.0));
    DrawFilledBox(FVector2D(86.0, 86.0), FVector2D(12.0, Canvas->SizeY - 172.0), FLinearColor(0.15, 0.75, 1.0, 1.0));
    DrawLabel(TEXT("NIGHT SKY DUEL LAB"), 122.0f, 118.0f, 1.55f);
    DrawLabel(TEXT("PUBLIC STARTER - GAMEPLAY NOT IMPLEMENTED"), 122.0f, 184.0f, 1.1f);
    DrawLabel(TEXT("Build the direct-entry fighting slice described in GDD.md Section 6."), 122.0f, 246.0f, 0.9f);
    DrawLabel(TEXT("Built-in Paper2D and engine primitives are available; no external asset is required."), 122.0f, 286.0f, 0.82f);
    DrawLabel(TEXT("READ-ONLY HEALTH BRIDGE: READY"), 122.0f, 374.0f, 1.0f);

    if (ANightSkyDuelHealthState* State = FindHealthState(GetWorld()))
    {
        State->MarkFirstFrameDrawn();
    }
}

void ANightSkyDuelScaffoldHUD::DrawFilledBox(const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color)
{
    FCanvasTileItem Tile(Position, Size, Color);
    Tile.BlendMode = SE_BLEND_Opaque;
    Canvas->DrawItem(Tile);
}

void ANightSkyDuelScaffoldHUD::DrawLabel(const FString& Label, float X, float Y, float Scale)
{
    FCanvasTextItem Text(FVector2D(X, Y), FText::FromString(Label), GEngine->GetLargeFont(), FLinearColor::White);
    Text.Scale = FVector2D(Scale, Scale);
    Text.EnableShadow(FLinearColor::Black);
    Canvas->DrawItem(Text);
}
