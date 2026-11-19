#include "StateFixture.h"
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "BoneMazeGameMode.h"
#include "BoneMazePawn.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "NativeEvidence.h"
// Taking protected member pointers inside a derived type preserves MSVC's
// original access-qualified symbols; the candidate header is never rewritten.
struct FFixtureAccess : ABoneMazeGameMode {
    static FBoneRun& MutableRun(ABoneMazeGameMode* G){return G->*(&FFixtureAccess::Run);}
    static void ResetPortalLatch(ABoneMazeGameMode* G){G->*(&FFixtureAccess::bPortalRejectedThisEntry)=false;}
    static void Rebuild(ABoneMazeGameMode* G){(G->*(&FFixtureAccess::BuildCurrentRoom))();}
    static void RefreshPrompt(ABoneMazeGameMode* G){(G->*(&FFixtureAccess::UpdateNearbyGatePrompt))();}
    static void PublishState(ABoneMazeGameMode* G){(G->*(&FFixtureAccess::Publish))();}
};
namespace StateFixture {
const TCHAR* AdapterVersion(){return TEXT("bonemaze-ds-harness-semantic-1.1");}
TSharedRef<FJsonObject> ReadGame(UWorld* W){auto J=NativeEvidence(W);auto G=Cast<ABoneMazeGameMode>(W->GetAuthGameMode());J->SetBoolField(TEXT("mapped"),G!=nullptr);if(!G)return J;
    auto& R=FFixtureAccess::MutableRun(G);J->SetStringField(TEXT("phase"),PhaseName(G->GetPhase()));J->SetStringField(TEXT("round_id"),R.RoundId);J->SetNumberField(TEXT("lives"),R.Lives);J->SetNumberField(TEXT("scrolls"),R.Scrolls);J->SetNumberField(TEXT("coins"),R.Coins);J->SetNumberField(TEXT("room_changes"),R.RoomChanges);
    J->SetNumberField(TEXT("room_index"),RoomIndex(R.PlayerX,R.PlayerY,R.MazeSize));J->SetNumberField(TEXT("monster_index"),RoomIndex(R.MonsterX,R.MonsterY,R.MazeSize));if(G->GetMage()){auto P=G->GetMage()->GetActorLocation();J->SetArrayField(TEXT("position"),JsonNumbers({P.X,P.Y,P.Z}));
        auto N=MakeShared<FJsonObject>();auto Center=G->RoomWorldLocation(R.PlayerX,R.PlayerY);Center.Z=P.Z;NavigationPoint(W,N,TEXT("player"),P);NavigationPoint(W,N,TEXT("center"),Center);
        const TCHAR* Slots[]={TEXT("north"),TEXT("east"),TEXT("south"),TEXT("west")};const FVector Dir[]={FVector(0,1,0),FVector(1,0,0),FVector(0,-1,0),FVector(-1,0,0)};
        for(int I=0;I<4;++I){NavigationPoint(W,N,FString(TEXT("passage:"))+Slots[I],Center+Dir[I]*700);NavigationPoint(W,N,FString(TEXT("gate:"))+Slots[I],Center+Dir[I]*700);}
        NavigationPoint(W,N,TEXT("final_portal"),Center);for(auto& Pickup:R.Pickups)if(Pickup.RoomX==R.PlayerX&&Pickup.RoomY==R.PlayerY)NavigationPoint(W,N,Pickup.EntityId,Center+FVector(Pickup.LocalX,Pickup.LocalY,0));J->SetObjectField(TEXT("navigation"),N);
    }return J;
}
bool ApplyGame(UWorld* W,const TSharedPtr<FJsonObject>& S,FString& Error){
    auto G=Cast<ABoneMazeGameMode>(W->GetAuthGameMode());if(!G||G->GetPhase()!=EBoneMazePhase::Exploring||!G->GetMage()){Error=TEXT("SETUP_REQUIRES_SETTLED_ROUND");return false;}
    const TSet<FString> Allowed={TEXT("room"),TEXT("monster_room"),TEXT("lives"),TEXT("scrolls"),TEXT("coins"),TEXT("keys"),TEXT("anchor"),TEXT("slot"),TEXT("pickup_id"),TEXT("distance"),TEXT("local_position")};for(auto& P:S->Values)if(!Allowed.Contains(P.Key)){Error=TEXT("FIELD_NOT_ALLOWLISTED");return false;}
    auto& R=FFixtureAccess::MutableRun(G);int32 X=R.PlayerX,Y=R.PlayerY,MX=R.MonsterX,MY=R.MonsterY,Lives=R.Lives,Scrolls=R.Scrolls,Coins=R.Coins;
    auto Cell=[&](const TCHAR* K,int32& A,int32& B){if(!S->HasField(K))return true;auto V=S->GetArrayField(K);if(V.Num()!=2)return false;A=V[0]->AsNumber();B=V[1]->AsNumber();return A>=1&&B>=1&&A<=R.MazeSize&&B<=R.MazeSize;};
    if(!Cell(TEXT("room"),X,Y)||!Cell(TEXT("monster_room"),MX,MY)){Error=TEXT("INVALID_ROOM");return false;}
    for(auto Pair:{TPair<const TCHAR*,int32*>(TEXT("lives"),&Lives),{TEXT("scrolls"),&Scrolls},{TEXT("coins"),&Coins}}){if(S->HasField(Pair.Key)){double V=S->GetNumberField(Pair.Key);if(V<0||V>10000||V!=FMath::FloorToDouble(V)){Error=TEXT("INVALID_RESOURCE");return false;}*Pair.Value=V;}}
    if(Lives<1||Coins>49){Error=TEXT("SETUP_MUST_BE_NONTERMINAL");return false;}
    bool Keys[3]={R.HasRed,R.HasGreen,R.HasBlue};if(S->HasField(TEXT("keys"))){for(auto& K:Keys)K=false;for(auto V:S->GetArrayField(TEXT("keys"))){FString K=V->AsString();if(K==TEXT("red"))Keys[0]=true;else if(K==TEXT("green"))Keys[1]=true;else if(K==TEXT("blue"))Keys[2]=true;else{Error=TEXT("INVALID_KEY_COLOR");return false;}}}
    FVector Position=G->RoomWorldLocation(X,Y)+FVector(0,0,140);FString Anchor;S->TryGetStringField(TEXT("anchor"),Anchor);
    if(Anchor==TEXT("passage")||Anchor==TEXT("gate")){
        FString Slot;S->TryGetStringField(TEXT("slot"),Slot);int I=Slot==TEXT("north")?0:Slot==TEXT("east")?1:Slot==TEXT("south")?2:Slot==TEXT("west")?3:-1;if(I<0){Error=TEXT("INVALID_SLOT");return false;}
        double D=Anchor==TEXT("gate")?590:590;double Requested;if(S->TryGetNumberField(TEXT("distance"),Requested))D=Requested+60;
        if(D<450||D>670){Error=TEXT("UNSAFE_ANCHOR_DISTANCE");return false;}
        const FVector Dir[]={FVector(0,1,0),FVector(1,0,0),FVector(0,-1,0),FVector(-1,0,0)};Position+=Dir[I]*D;
    }else if(Anchor==TEXT("pickup")){
        FString Id;S->TryGetStringField(TEXT("pickup_id"),Id);int Index=INDEX_NONE;for(int I=0;I<R.Pickups.Num();++I)if(R.Pickups[I].EntityId==Id)Index=I;
        if(Index<0||R.Pickups[Index].Consumed||R.Pickups[Index].RoomX!=X||R.Pickups[Index].RoomY!=Y){Error=TEXT("PICKUP_SEMANTIC_ID_UNMAPPED");return false;}auto& P=R.Pickups[Index];Position+=FVector(P.LocalX-130,P.LocalY,0);
    }else if(Anchor==TEXT("final_portal")){if(X!=R.ExitX||Y!=R.ExitY){Error=TEXT("NOT_EXIT_ROOM");return false;}Position.X-=190;}
    else if(!Anchor.IsEmpty()&&Anchor!=TEXT("center")){Error=TEXT("UNKNOWN_ANCHOR");return false;}
    if(S->HasField(TEXT("local_position"))){auto A=S->GetArrayField(TEXT("local_position"));if(A.Num()!=2||A[0]->AsNumber()<.1||A[0]->AsNumber()>.9||A[1]->AsNumber()<.1||A[1]->AsNumber()>.9){Error=TEXT("INVALID_LOCAL_POSITION");return false;}Position=G->RoomWorldLocation(X,Y)+FVector(A[0]->AsNumber()*1400-700,A[1]->AsNumber()*1400-700,140);}
    bool Rebuild=X!=R.PlayerX||Y!=R.PlayerY;R.PlayerX=X;R.PlayerY=Y;R.MonsterX=MX;R.MonsterY=MY;R.Lives=Lives;R.Scrolls=Scrolls;R.Coins=Coins;R.HasRed=Keys[0];R.HasGreen=Keys[1];R.HasBlue=Keys[2];
    for(auto& Gate:R.Gates)if(Gate.State==EGateState::Locked||Gate.State==EGateState::Closed)Gate.State=Keys[int(Gate.Color)]?EGateState::Closed:EGateState::Locked;
    R.ExitState=Keys[0]&&Keys[1]&&Keys[2]?EExitState::Ready:EExitState::Locked;R.DangerNearby=G->MazeDistance(X,Y,MX,MY)==1;FFixtureAccess::ResetPortalLatch(G);
    if(Rebuild)FFixtureAccess::Rebuild(G);G->GetMage()->GetCharacterMovement()->StopMovementImmediately();G->GetMage()->SetActorLocation(Position,false,nullptr,ETeleportType::TeleportPhysics);FFixtureAccess::RefreshPrompt(G);FFixtureAccess::PublishState(G);return true;
}
}
