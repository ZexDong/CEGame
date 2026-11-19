#pragma once
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
#include "Engine/World.h"
#include "UObject/UObjectIterator.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/AudioComponent.h"
#include "Particles/ParticleSystemComponent.h"
#include "Animation/AnimSingleNodeInstance.h"
#include "Engine/StaticMesh.h"
#include "Engine/SkeletalMesh.h"
#include "Sound/SoundBase.h"
#include "Particles/ParticleSystem.h"
#include "Materials/MaterialInterface.h"
#include "RenderEvidence.h"
#include "GameFramework/PlayerController.h"

inline TArray<TSharedPtr<FJsonValue>> JsonNumbers(std::initializer_list<double> V){TArray<TSharedPtr<FJsonValue>> A;for(double X:V)A.Add(MakeShared<FJsonValueNumber>(X));return A;}
// Project semantic floor anchors at a common height; rendered sprite centres
// cannot locate the feet of characters with different heights or camera angles.
inline void NavigationPoint(UWorld* W,TSharedRef<FJsonObject> J,const FString& Key,FVector P){
    auto PC=W->GetFirstPlayerController();FVector2D S;int32 X=1,Y=1;if(!PC)return;PC->GetViewportSize(X,Y);
    if(X>0&&Y>0&&PC->ProjectWorldLocationToScreen(P,S))J->SetArrayField(Key,JsonNumbers({S.X/X,S.Y/Y}));
}
inline TSharedRef<FJsonObject> NativeEvidence(UWorld* W){
    auto J=MakeShared<FJsonObject>();TArray<TSharedPtr<FJsonValue>> Rendered,Audio;
    for(TObjectIterator<UPrimitiveComponent> It;It;++It){auto C=*It;if(C->GetWorld()!=W||!C->IsRegistered()||!C->IsVisible()||C->bHiddenInGame||!C->GetOwner()||C->GetOwner()->IsHidden())continue;
        FString Path,Clip;auto SM=Cast<UStaticMeshComponent>(C);auto SK=Cast<USkeletalMeshComponent>(C);auto PS=Cast<UParticleSystemComponent>(C);
        if(SM&&SM->GetStaticMesh())Path=SM->GetStaticMesh()->GetPathName();
        if(SK&&SK->GetSkeletalMeshAsset()){Path=SK->GetSkeletalMeshAsset()->GetPathName();if(auto A=SK->GetSingleNodeInstance())if(A->GetCurrentAsset())Clip=A->GetCurrentAsset()->GetPathName();}
        if(PS&&PS->IsActive()&&PS->Template)Path=PS->Template->GetPathName();if(Path.IsEmpty())continue;
        auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("asset"),Path);R->SetStringField(TEXT("animation"),Clip);R->SetBoolField(TEXT("recently_rendered"),C->WasRecentlyRendered(.3f));auto P=C->GetComponentLocation();R->SetArrayField(TEXT("position"),JsonNumbers({P.X,P.Y,P.Z}));
        TArray<TSharedPtr<FJsonValue>> M;for(int I=0;I<C->GetNumMaterials();++I)if(auto Mat=C->GetMaterial(I))M.Add(MakeShared<FJsonValueString>(Mat->GetPathName()));R->SetArrayField(TEXT("materials"),M);Rendered.Add(MakeShared<FJsonValueObject>(R));
    }
    for(TObjectIterator<UAudioComponent> It;It;++It){auto C=*It;bool Belongs=C->GetWorld()==W||(!C->GetWorld()&&C->GetAudioDevice()==W->GetAudioDeviceRaw());if(!Belongs||!C->IsPlaying()||!C->Sound)continue;auto A=MakeShared<FJsonObject>();A->SetStringField(TEXT("asset"),C->Sound->GetPathName());A->SetBoolField(TEXT("paused"),C->bIsPaused);A->SetNumberField(TEXT("volume"),C->VolumeMultiplier);Audio.Add(MakeShared<FJsonValueObject>(A));}
    J->SetArrayField(TEXT("rendered_components"),Rendered);J->SetArrayField(TEXT("playing_audio"),Audio);J->SetObjectField(TEXT("renderer"),PrivateRender::Read());return J;
}
