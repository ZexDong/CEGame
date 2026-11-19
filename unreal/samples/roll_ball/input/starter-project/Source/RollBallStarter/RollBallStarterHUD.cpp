#include "RollBallStarterHUD.h"

#include "RollBallStarterState.h"
#include "CanvasItem.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"

namespace
{
ARollBallStarterState* FindStarterState(UWorld* World)
{
    if (!World)
    {
        return nullptr;
    }
    for (TActorIterator<ARollBallStarterState> It(World); It; ++It)
    {
        return *It;
    }
    return nullptr;
}

}

void ARollBallStarterHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas || Canvas->SizeX <= 0 || Canvas->SizeY <= 0)
    {
        return;
    }

    DrawLabel(TEXT("ROLLBALL 3D STARTER"), 34.0f, 28.0f, 1.35f, FLinearColor(0.88f, 0.94f, 1.0f, 1.0f));
    DrawLabel(TEXT("MATERIAL AND LIGHTING DISPLAY"), 36.0f, 72.0f, 0.92f, FLinearColor(1.0f, 0.66f, 0.28f, 1.0f));
    DrawLabel(TEXT("Supplied meshes are shown with dynamic lighting and a rotating sphere."), 36.0f, 112.0f, 0.78f);
    DrawLabel(TEXT("This starter contains no playable rules or controls."), 36.0f, 142.0f, 0.78f);
    DrawLabel(TEXT("Create the playable experience described in GDD.md."), 36.0f, Canvas->SizeY - 52.0f, 0.72f, FLinearColor(0.72f, 0.78f, 0.88f, 1.0f));

    if (ARollBallStarterState* State = FindStarterState(GetWorld()))
    {
        State->MarkFirstFrameDrawn();
    }
}

void ARollBallStarterHUD::DrawLabel(const FString& Label, float X, float Y, float Scale, const FLinearColor& Color)
{
    FCanvasTextItem Text(FVector2D(X, Y), FText::FromString(Label), GEngine->GetLargeFont(), Color);
    Text.Scale = FVector2D(Scale, Scale);
    Text.EnableShadow(FLinearColor::Black);
    Canvas->DrawItem(Text);
}
