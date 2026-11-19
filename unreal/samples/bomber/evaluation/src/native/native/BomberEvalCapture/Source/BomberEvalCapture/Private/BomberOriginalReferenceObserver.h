#pragma once

#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/GameStateBase.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerState.h"
#include "GameplayTagAssetInterface.h"
#include "Components/TextBlock.h"
#include "Components/PanelWidget.h"
#include "UObject/UnrealType.h"
#include "UObject/UObjectIterator.h"

// Private original-reference acquisition only. Never used to observe candidates.
// All reads are native getters or property exports; no ProcessEvent or state setters.
inline bool BomberOriginalType(const UObject* Object, const TCHAR* Name)
{
    for (const UClass* Class = Object ? Object->GetClass() : nullptr; Class; Class = Class->GetSuperClass())
    {
        if (Class->GetName() == Name && Class->GetOutermost()->GetName() == TEXT("/Script/Bomber")) { return true; }
    }
    return false;
}

inline FString BomberOriginalProperty(const UObject* Object, const TCHAR* Name)
{
    FString Value;
    if (Object)
    {
        if (const FProperty* Property = Object->GetClass()->FindPropertyByName(Name))
        {
            Property->ExportText_InContainer(0, Value, Object, Object, const_cast<UObject*>(Object), PPF_None);
        }
    }
    return Value;
}

inline TSharedRef<FJsonObject> BomberOriginalSnapshot(UWorld* World)
{
    auto Result = MakeShared<FJsonObject>();
    Result->SetStringField(TEXT("producer"), TEXT("original-reference-observer-1"));
    if (!World || !BomberOriginalType(World->GetGameState(), TEXT("BmrGameState")))
    {
        Result->SetStringField(TEXT("status"), TEXT("original_world_not_ready"));
        return Result;
    }
    Result->SetStringField(TEXT("status"), TEXT("ok"));
    Result->SetBoolField(TEXT("paused"), World->IsPaused());
    Result->SetNumberField(TEXT("world_seconds"), World->GetTimeSeconds());
    auto TagsOf = [](const UObject* Object)
    {
        FGameplayTagContainer Tags;
        if (const auto* Interface = Cast<IGameplayTagAssetInterface>(Object)) { Interface->GetOwnedGameplayTags(Tags); }
        return Tags.ToStringSimple();
    };
    Result->SetStringField(TEXT("game_tags"), TagsOf(World->GetGameState()));
    TArray<TSharedPtr<FJsonValue>> Actors;
    for (TActorIterator<AActor> It(World); It; ++It)
    {
        const AActor* Actor = *It;
        const bool Pawn = BomberOriginalType(Actor, TEXT("BmrPawn"));
        const bool Bomb = BomberOriginalType(Actor, TEXT("BmrBombAbilityActor"));
        const bool Box = BomberOriginalType(Actor, TEXT("BmrBoxActor"));
        const bool Wall = BomberOriginalType(Actor, TEXT("BmrWallActor"));
        if (!Pawn && !Bomb && !Box && !Wall) { continue; }
        auto Entry = MakeShared<FJsonObject>();
        Entry->SetStringField(TEXT("id"), Actor->GetName());
        Entry->SetStringField(TEXT("kind"), Pawn ? TEXT("player") : Bomb ? TEXT("bomb") : Box ? TEXT("crate") : TEXT("wall"));
        Entry->SetStringField(TEXT("tags"), TagsOf(Actor));
        Entry->SetBoolField(TEXT("hidden"), Actor->IsHidden());
        const FVector Location = Actor->GetActorLocation();
        Entry->SetNumberField(TEXT("x"), Location.X);
        Entry->SetNumberField(TEXT("y"), Location.Y);
        Entry->SetNumberField(TEXT("z"), Location.Z);
        for (const UActorComponent* Component : Actor->GetComponents())
        {
            if (BomberOriginalType(Component, TEXT("BmrMapComponent")))
            {
                Entry->SetStringField(TEXT("cell"), BomberOriginalProperty(Component, TEXT("LocalCell")));
            }
        }
        if (const APawn* Player = Cast<APawn>(Actor))
        {
            Entry->SetBoolField(TEXT("human"), Player->IsPlayerControlled());
            if (const APlayerState* State = Player->GetPlayerState())
            {
                Entry->SetNumberField(TEXT("player_id"), State->GetPlayerId());
                Entry->SetStringField(TEXT("player_name"), State->GetPlayerName());
                Entry->SetStringField(TEXT("end_state"), BomberOriginalProperty(State, TEXT("EndGameState")));
            }
        }
        if (Bomb) { Entry->SetStringField(TEXT("explosion_cells"), BomberOriginalProperty(Actor, TEXT("ExplosionCells"))); }
        Actors.Add(MakeShared<FJsonValueObject>(Entry));
    }
    Result->SetArrayField(TEXT("actors"), Actors);
    TArray<TSharedPtr<FJsonValue>> Widgets;
    for (TObjectIterator<UWidget> It; It; ++It)
    {
        UWidget* Widget = *It;
        if (Widget->GetWorld() != World || !Widget->IsVisible()) { continue; }
        bool ParentHidden = false;
        for (UPanelWidget* Parent = Widget->GetParent(); Parent; Parent = Parent->GetParent())
        {
            if (!Parent->IsVisible()) { ParentHidden = true; break; }
        }
        if (ParentHidden) { continue; }
        const FVector2D Size = Widget->GetCachedGeometry().GetAbsoluteSize();
        if (Size.X < 1 || Size.Y < 1) { continue; }
        FString Text;
        if (const UTextBlock* Block = Cast<UTextBlock>(Widget)) { Text = Block->GetText().ToString(); }
        if (Text.IsEmpty() && !Widget->GetClass()->GetName().Contains(TEXT("Button"))) { continue; }
        auto Entry = MakeShared<FJsonObject>();
        const FVector2D Position = Widget->GetCachedGeometry().GetAbsolutePosition();
        Entry->SetStringField(TEXT("name"), Widget->GetName());
        Entry->SetStringField(TEXT("text"), Text);
        Entry->SetStringField(TEXT("tooltip"), Widget->GetToolTipText().ToString());
        Entry->SetNumberField(TEXT("x"), Position.X);
        Entry->SetNumberField(TEXT("y"), Position.Y);
        Entry->SetNumberField(TEXT("width"), Size.X);
        Entry->SetNumberField(TEXT("height"), Size.Y);
        Widgets.Add(MakeShared<FJsonValueObject>(Entry));
    }
    Result->SetArrayField(TEXT("widgets"), Widgets);
    return Result;
}
