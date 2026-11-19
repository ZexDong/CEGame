#include "MinimalInterfaceHUD.h"

#include "MinimalInterfaceState.h"
#include "CanvasItem.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"

namespace
{
AMinimalInterfaceState* FindFixtureState(UWorld* World)
{
    if (!World)
    {
        return nullptr;
    }
    for (TActorIterator<AMinimalInterfaceState> It(World); It; ++It)
    {
        return *It;
    }
    return nullptr;
}
}

void AMinimalInterfaceHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas || Canvas->SizeX <= 0 || Canvas->SizeY <= 0)
    {
        return;
    }

    DrawFilledBox(FVector2D::ZeroVector, FVector2D(Canvas->SizeX, Canvas->SizeY), FLinearColor(0.018, 0.024, 0.045, 1.0));
    AMinimalInterfaceState* State = FindFixtureState(GetWorld());
    if (!State)
    {
        DrawLabel(TEXT("INITIALIZING FIXTURE"), 36.0f, 36.0f, 1.4f);
        return;
    }

    const float Width = Canvas->SizeX;
    const float Height = Canvas->SizeY;

    DrawLabel(TEXT("UNREAL PUBLIC EVALUATION INTERFACE"), 32.0f, 24.0f, 1.35f);
    DrawLabel(TEXT("SPACE = PRESS    HOLD W = MOVE    R = RESTART"), 32.0f, 58.0f, 1.0f);
    DrawLabel(FString::Printf(TEXT("Round %d | Restarts %d | Feedback: %s"),
        State->GetRoundIndex(), State->GetRestartCount(), *State->GetFeedback()), 32.0f, 88.0f, 1.0f);

    for (const FMinimalTargetState& Target : State->GetTargets())
    {
        const FVector2D Position(Target.Position.X * Width, Target.Position.Y * Height);
        const FVector2D Size(Target.Size.X * Width, Target.Size.Y * Height);
        const bool bClickTarget = Target.TargetId == TEXT("click_target");
        const FLinearColor Color = bClickTarget
            ? (State->GetClickCount() % 2 == 0 ? FLinearColor(0.12, 0.55, 0.90, 1.0) : FLinearColor(0.18, 0.90, 0.42, 1.0))
            : (State->IsDragging() ? FLinearColor(1.0, 0.72, 0.12, 1.0) : FLinearColor(0.86, 0.30, 0.55, 1.0));
        DrawFilledBox(Position, Size, Color);
        const FString Text = bClickTarget
            ? FString::Printf(TEXT("CLICK ME\nCount: %d"), State->GetClickCount())
            : FString::Printf(TEXT("DRAG ME\nCount: %d"), State->GetDragCount());
        DrawLabel(Text, Position.X + 16.0f, Position.Y + 18.0f, 1.1f);
    }

    const FVector2D ObjectPosition(State->GetObjectPosition().X * Width, State->GetObjectPosition().Y * Height);
    DrawFilledBox(ObjectPosition - FVector2D(24.0, 24.0), FVector2D(48.0, 48.0),
        State->IsMoveHeld() ? FLinearColor(1.0, 0.82, 0.18, 1.0) : FLinearColor(0.95, 0.50, 0.12, 1.0));
    DrawLabel(TEXT("MOVABLE OBJECT"), ObjectPosition.X - 62.0f, ObjectPosition.Y + 34.0f, 0.85f);

    const FVector2D DragPosition(State->GetDragPosition().X * Width, State->GetDragPosition().Y * Height);
    DrawFilledBox(DragPosition - FVector2D(11.0, 11.0), FVector2D(22.0, 22.0), FLinearColor::White);
    DrawLabel(FString::Printf(TEXT("SPACE %d | HOLD TICKS %d | CLICK %d | DRAG %d"),
        State->GetDiscreteCount(), State->GetHoldCount(), State->GetClickCount(), State->GetDragCount()),
        32.0f, Height - 48.0f, 1.0f);
    State->MarkFirstFrameDrawn();
}

void AMinimalInterfaceHUD::DrawFilledBox(const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color)
{
    FCanvasTileItem Tile(Position, Size, Color);
    Tile.BlendMode = SE_BLEND_Opaque;
    Canvas->DrawItem(Tile);
}

void AMinimalInterfaceHUD::DrawLabel(const FString& Label, float X, float Y, float Scale)
{
    FCanvasTextItem Text(FVector2D(X, Y), FText::FromString(Label), GEngine->GetLargeFont(), FLinearColor::White);
    Text.Scale = FVector2D(Scale, Scale);
    Text.EnableShadow(FLinearColor::Black);
    Canvas->DrawItem(Text);
}
