// Private semantic setup adapter. Added ONLY to an isolated assessment copy.
// It never calls scoring, damage, capture, pickup, win, death or restart methods.
#include "StateFixture.h"
#include "ChompGame.h"
#include "Engine/World.h"
#include "Components/StaticMeshComponent.h"
#include "Camera/CameraActor.h"
#include "HAL/PlatformTime.h"
#include "Engine/StaticMesh.h"
#include "Engine/Engine.h"
#include "GameFramework/GameUserSettings.h"
#include "Components/InstancedStaticMeshComponent.h"

namespace StateFixture
{
const TCHAR* AdapterVersion(){return TEXT("chomp-gold-preconditions-1.0.0");}
static AChompGame* Find(UWorld* W){return W?Cast<AChompGame>(W->GetAuthGameMode()):nullptr;}
static TSharedRef<FJsonObject> Point(FVector P){auto J=MakeShared<FJsonObject>();J->SetNumberField(TEXT("x"),P.X);J->SetNumberField(TEXT("y"),P.Y);J->SetNumberField(TEXT("z"),P.Z);return J;}
TSharedRef<FJsonObject> ReadGame(UWorld* W)
{
    auto J=MakeShared<FJsonObject>();auto* G=Find(W);J->SetBoolField(TEXT("provider_available"),G!=nullptr);if(!G)return J;
    J->SetObjectField(TEXT("observation"),G->Observation());
    auto Native=MakeShared<FJsonObject>();Native->SetNumberField(TEXT("score"),G->Score);Native->SetNumberField(TEXT("lives"),G->Lives);Native->SetNumberField(TEXT("active_seconds"),G->Active);Native->SetStringField(TEXT("phase"),G->Phase);Native->SetStringField(TEXT("run_id"),G->RunId);
    Native->SetObjectField(TEXT("player_world_cm"),Point(G->UpperJaw->GetComponentLocation()));
    auto PlayerGrid=MakeShared<FJsonObject>();auto Actual=G->UpperJaw->GetComponentLocation();PlayerGrid->SetNumberField(TEXT("x"),Actual.Y/100);PlayerGrid->SetNumberField(TEXT("y"),-Actual.X/100);Native->SetObjectField(TEXT("rendered_player_grid"),PlayerGrid);
    Native->SetObjectField(TEXT("camera_world_cm"),Point(G->Camera->GetActorLocation()));
    TArray<TSharedPtr<FJsonValue>> Geometry;
    for(auto* C:{G->UpperJaw.Get(),G->LowerJaw.Get(),G->FruitBody.Get(),G->FruitCrown.Get()})
    {
        auto A=MakeShared<FJsonObject>();A->SetStringField(TEXT("mesh"),C->GetStaticMesh()->GetPathName());A->SetBoolField(TEXT("visible"),C->IsVisible());A->SetObjectField(TEXT("position_cm"),Point(C->GetComponentLocation()));Geometry.Add(MakeShared<FJsonValueObject>(A));
    }
    for(int I=0;I<4;++I){auto A=MakeShared<FJsonObject>();A->SetStringField(TEXT("id"),G->GhostIds[I]);A->SetObjectField(TEXT("position_cm"),Point(G->GhostHeads[I]->GetComponentLocation()));A->SetBoolField(TEXT("body_visible"),G->GhostBodies[I]->IsVisible());A->SetStringField(TEXT("mesh"),G->GhostHeads[I]->GetStaticMesh()->GetPathName());Geometry.Add(MakeShared<FJsonValueObject>(A));}
    Native->SetArrayField(TEXT("geometry"),Geometry);
    TArray<TSharedPtr<FJsonValue>> Components;TInlineComponentArray<UStaticMeshComponent*> Meshes(G);
    for(auto* C:Meshes){auto R=MakeShared<FJsonObject>();if(C->GetStaticMesh())R->SetStringField(TEXT("mesh"),C->GetStaticMesh()->GetPathName());R->SetBoolField(TEXT("registered"),C->IsRegistered());R->SetBoolField(TEXT("visible"),C->IsVisible()&&!G->IsHidden());R->SetObjectField(TEXT("world_cm"),Point(C->GetComponentLocation()));auto* I=Cast<UInstancedStaticMeshComponent>(C);R->SetNumberField(TEXT("instances"),I?I->GetInstanceCount():1);TArray<TSharedPtr<FJsonValue>> Materials;for(int K=0;K<C->GetNumMaterials();++K)if(C->GetMaterial(K))Materials.Add(MakeShared<FJsonValueString>(C->GetMaterial(K)->GetPathName()));R->SetArrayField(TEXT("materials"),Materials);Components.Add(MakeShared<FJsonValueObject>(R));}
    Native->SetArrayField(TEXT("render_components"),Components);
    auto* U=GEngine->GetGameUserSettings();auto Settings=MakeShared<FJsonObject>();Settings->SetBoolField(TEXT("vsync"),U->IsVSyncEnabled());Settings->SetNumberField(TEXT("quality"),U->GetOverallScalabilityLevel());Settings->SetStringField(TEXT("window_mode"),U->GetFullscreenMode()==EWindowMode::Fullscreen?TEXT("fullscreen"):TEXT("windowed"));Settings->SetNumberField(TEXT("width"),U->GetScreenResolution().X);Settings->SetNumberField(TEXT("height"),U->GetScreenResolution().Y);Native->SetObjectField(TEXT("engine_settings"),Settings);
    J->SetObjectField(TEXT("native"),Native);return J;
}
bool ApplyGame(UWorld* W,const TSharedPtr<FJsonObject>& S,FString& Error)
{
    auto* G=Find(W);if(!G){Error=TEXT("ADAPTER_LAYOUT_UNAVAILABLE");return false;}
    if(G->Phase!=TEXT("paused")||G->RunId.IsEmpty()){Error=TEXT("SETUP_REQUIRES_NORMAL_STARTED_PAUSED_RUN");return false;}
    TSet<FString> Allowed={TEXT("player"),TEXT("ghosts"),TEXT("ordinary_cells"),TEXT("energizer_cells"),TEXT("score"),TEXT("lives"),TEXT("extra_life_progress"),TEXT("capture_chain"),TEXT("active_seconds"),TEXT("wave_index"),TEXT("wave_remaining_seconds"),TEXT("frightened_remaining_seconds"),TEXT("inactivity_remaining_seconds"),TEXT("fruit_remaining_seconds"),TEXT("fruit_thresholds")};
    for(const auto& Pair:S->Values)if(!Allowed.Contains(Pair.Key)){Error=TEXT("FIELD_NOT_ALLOWED:")+Pair.Key;return false;}
    // Validate and stage all requested changes before committing any field.
    FChompMotion Player=G->Player;FChompGhost Ghosts[4];for(int I=0;I<4;++I)Ghosts[I]=G->Ghosts[I];
    auto Motion=[&](const TSharedPtr<FJsonObject>& J,FChompMotion& M,bool Home)->bool
    {
        TSet<FString> Keys={TEXT("x"),TEXT("y"),TEXT("direction"),TEXT("progress")};for(const auto& P:J->Values)if(!Keys.Contains(P.Key))return false;
        double X=0,Y=0,D=0,P=0;if(!J->TryGetNumberField(TEXT("x"),X)||!J->TryGetNumberField(TEXT("y"),Y)||!J->TryGetNumberField(TEXT("direction"),D))return false;J->TryGetNumberField(TEXT("progress"),P);
        if(X!=FMath::FloorToDouble(X)||Y!=FMath::FloorToDouble(Y)||D!=FMath::FloorToDouble(D)||D<0||D>3||P<0||P>=1||!G->Legal({int(X),int(Y)},Home))return false;
        M.Place({int(X),int(Y)},int(D));if(P>0){M.To=G->Next(M.From,M.Direction,Home);if(M.To==M.From)return false;M.Progress=P;}M.Moving=M.To!=M.From;return true;
    };
    const TSharedPtr<FJsonObject>* P=nullptr;if(S->TryGetObjectField(TEXT("player"),P)&&!Motion(*P,Player,false)){Error=TEXT("PLAYER_PRECONDITION_INVALID");return false;}
    const TArray<TSharedPtr<FJsonValue>>* A=nullptr;
    if(S->TryGetArrayField(TEXT("ghosts"),A))
    {
        TSet<FString> Seen;
        for(auto V:*A)
        {
            auto J=V->AsObject();FString Id,State;if(!J||!J->TryGetStringField(TEXT("id"),Id)||!J->TryGetStringField(TEXT("state"),State)||Seen.Contains(Id)){Error=TEXT("GHOST_PRECONDITION_INVALID");return false;}
            int I=-1;for(int K=0;K<4;++K)if(Id==G->GhostIds[K])I=K;if(I<0||!(State==TEXT("waiting")||State==TEXT("leaving")||State==TEXT("normal")||State==TEXT("returning"))){Error=TEXT("GHOST_STATE_INVALID");return false;}Seen.Add(Id);
            const TSharedPtr<FJsonObject>* M=nullptr;if(!J->TryGetObjectField(TEXT("motion"),M)||!Motion(*M,Ghosts[I].Motion,State!=TEXT("normal"))){Error=TEXT("GHOST_MOTION_INVALID");return false;}
            Ghosts[I].State=State;Ghosts[I].Intent=State==TEXT("waiting")?FIntPoint(-1,-1):State==TEXT("returning")?G->Homes[I]:State==TEXT("leaving")?FIntPoint(14,9):G->Corners[I][0];Ghosts[I].Corner=0;
        }
    }
    TSet<int> Dots=G->Dots,Orbs=G->Energizers;
    auto Cells=[&](const TCHAR* Key,TSet<int>& Target,bool Orb)->bool
    {
        const TArray<TSharedPtr<FJsonValue>>* Array=nullptr;if(!S->TryGetArrayField(Key,Array))return true;Target.Empty();
        for(auto V:*Array){auto C=V->AsObject();double X,Y;if(!C||!C->TryGetNumberField(TEXT("x"),X)||!C->TryGetNumberField(TEXT("y"),Y)||X<0||X>29||Y<0||Y>27||X!=FMath::FloorToDouble(X)||Y!=FMath::FloorToDouble(Y))return false;TCHAR B=G->Board[int(Y)][int(X)];if(Orb?B!='E':!(B=='.'||B=='T'||B=='F'))return false;int K=int(Y)*30+int(X);if(Target.Contains(K))return false;Target.Add(K);}return true;
    };
    if(!Cells(TEXT("ordinary_cells"),Dots,false)||Dots.Num()<1||!Cells(TEXT("energizer_cells"),Orbs,true)){Error=TEXT("PICKUP_PRECONDITION_INVALID");return false;}
    struct FValue{const TCHAR* Key;double Min,Max,Value;};
    TArray<FValue> Values={{TEXT("score"),0,10000000,double(G->Score)},{TEXT("lives"),1,3,double(G->Lives)},{TEXT("extra_life_progress"),0,10000000,double(G->ExtraProgress)},{TEXT("capture_chain"),0,20,double(G->Chain)},{TEXT("active_seconds"),0,10000,G->Active},{TEXT("wave_index"),0,7,double(G->Wave)},{TEXT("wave_remaining_seconds"),0,5,G->WaveLeft},{TEXT("frightened_remaining_seconds"),0,5,G->FrightLeft},{TEXT("inactivity_remaining_seconds"),0,5,G->InactivityLeft},{TEXT("fruit_remaining_seconds"),0,10,G->FruitLeft}};
    for(auto& V:Values){double N;if(S->TryGetNumberField(V.Key,N)){if(!FMath::IsFinite(N)||N<V.Min||N>V.Max){Error=TEXT("VALUE_RANGE:")+FString(V.Key);return false;}V.Value=N;}}
    for(int I:{0,1,2,3,5})if(Values[I].Value!=FMath::FloorToDouble(Values[I].Value)){Error=TEXT("INTEGER_REQUIRED");return false;}
    TArray<int> Spent=G->SpentFruit;if(S->TryGetArrayField(TEXT("fruit_thresholds"),A)){Spent.Empty();for(auto V:*A){double N=V->AsNumber();if((N!=70&&N!=170)||Spent.Contains(int(N))){Error=TEXT("FRUIT_THRESHOLDS_INVALID");return false;}Spent.Add(int(N));}Spent.Sort();}
    G->Player=Player;for(int I=0;I<4;++I)G->Ghosts[I]=Ghosts[I];G->Dots=Dots;G->Energizers=Orbs;G->Consumed=299-Dots.Num();G->Score=int(Values[0].Value);G->Lives=int(Values[1].Value);G->ExtraProgress=int(Values[2].Value);G->Chain=int(Values[3].Value);G->Active=Values[4].Value;G->Wave=int(Values[5].Value);G->WaveLeft=Values[6].Value;G->FrightLeft=Values[7].Value;G->InactivityLeft=Values[8].Value;G->FruitLeft=Values[9].Value;G->FruitPresent=G->FruitLeft>0;G->SpentFruit=Spent;
    G->RequestDirection=-1;G->RequestHeld=false;G->RequestExpires=0;G->Wrapped=true;
    // Presentation synchronization only. No rule/outcome method is invoked.
    G->RebuildPickups();return true;
}
}
