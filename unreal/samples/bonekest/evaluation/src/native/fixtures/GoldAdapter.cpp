#include "StateFixture.h"
#include "BoneGame.h"
#include "Engine/World.h"
#include "Components/SkeletalMeshComponent.h"
#include "NativeEvidence.h"

namespace StateFixture {
const TCHAR* AdapterVersion(){return TEXT("bonemaze-gold-semantic-1.0");}
TSharedRef<FJsonObject> ReadGame(UWorld* W){
    auto J=NativeEvidence(W);auto G=Cast<ABoneGame>(W->GetAuthGameMode());
    J->SetBoolField(TEXT("mapped"),G!=nullptr);if(!G)return J;
    J->SetStringField(TEXT("phase"),G->Phase);J->SetStringField(TEXT("round_id"),G->RoundId);
    J->SetNumberField(TEXT("lives"),G->Lives);J->SetNumberField(TEXT("scrolls"),G->Scrolls);J->SetNumberField(TEXT("coins"),G->Coins);
    J->SetNumberField(TEXT("room_changes"),G->Changes);J->SetNumberField(TEXT("room_index"),G->Current);J->SetNumberField(TEXT("monster_index"),G->Monster);
    J->SetArrayField(TEXT("position"),JsonNumbers({G->MageLocation.X,G->MageLocation.Y,G->MageLocation.Z}));
    if(G->Size){auto N=MakeShared<FJsonObject>();NavigationPoint(W,N,TEXT("player"),G->MageLocation);NavigationPoint(W,N,TEXT("center"),FVector(0,0,G->MageLocation.Z));
        const TCHAR* Slots[]={TEXT("north"),TEXT("east"),TEXT("south"),TEXT("west")};
        for(int I=0;I<4;++I){NavigationPoint(W,N,FString(TEXT("passage:"))+Slots[I],G->ExitPosition(I,650));NavigationPoint(W,N,FString(TEXT("gate:"))+Slots[I],G->ExitPosition(I,630));}
        NavigationPoint(W,N,TEXT("final_portal"),FVector(200,160,G->MageLocation.Z));
        for(int I=0;I<G->Pickups.Num();++I)if(G->Pickups[I].Room==G->Current){auto P=G->Pickups[I].Location;P.Z=G->MageLocation.Z;NavigationPoint(W,N,G->Id(TEXT("pickup"),I),P);}
        J->SetObjectField(TEXT("navigation"),N);
    }
    return J;
}
bool ApplyGame(UWorld* W,const TSharedPtr<FJsonObject>& S,FString& Error){
    auto G=Cast<ABoneGame>(W->GetAuthGameMode());if(!G||G->Phase!=TEXT("exploring")){Error=TEXT("SETUP_REQUIRES_SETTLED_ROUND");return false;}
    const TSet<FString> Allowed={TEXT("room"),TEXT("monster_room"),TEXT("lives"),TEXT("scrolls"),TEXT("coins"),TEXT("keys"),TEXT("anchor"),TEXT("slot"),TEXT("pickup_id"),TEXT("distance"),TEXT("local_position")};
    for(auto& P:S->Values)if(!Allowed.Contains(P.Key)){Error=TEXT("FIELD_NOT_ALLOWLISTED");return false;}
    int32 Room=G->Current,Monster=G->Monster,Lives=G->Lives,Scrolls=G->Scrolls,Coins=G->Coins;FString Anchor;
    auto Cell=[&](const TCHAR* Key,int32& Out){if(!S->HasField(Key))return true;auto A=S->GetArrayField(Key);if(A.Num()!=2)return false;int X=A[0]->AsNumber(),Y=A[1]->AsNumber();if(X<1||Y<1||X>G->Size||Y>G->Size)return false;Out=(Y-1)*G->Size+X-1;return true;};
    if(!Cell(TEXT("room"),Room)||!Cell(TEXT("monster_room"),Monster)){Error=TEXT("INVALID_ROOM");return false;}
    for(auto Pair:{TPair<const TCHAR*,int32*>(TEXT("lives"),&Lives),{TEXT("scrolls"),&Scrolls},{TEXT("coins"),&Coins}}){if(S->HasField(Pair.Key)){double V=S->GetNumberField(Pair.Key);if(V<0||V>10000||V!=FMath::FloorToDouble(V)){Error=TEXT("INVALID_RESOURCE");return false;}*Pair.Value=V;}}
    if(Lives<1||Coins>49){Error=TEXT("SETUP_MUST_BE_NONTERMINAL");return false;}
    bool Keys[3]={G->Keys[0],G->Keys[1],G->Keys[2]};if(S->HasField(TEXT("keys"))){for(auto& K:Keys)K=false;for(auto V:S->GetArrayField(TEXT("keys"))){FString K=V->AsString();if(K==TEXT("red"))Keys[0]=true;else if(K==TEXT("green"))Keys[1]=true;else if(K==TEXT("blue"))Keys[2]=true;else{Error=TEXT("INVALID_KEY_COLOR");return false;}}}
    FVector Position(0,0,18);S->TryGetStringField(TEXT("anchor"),Anchor);
    if(Anchor==TEXT("passage")||Anchor==TEXT("gate")){
        FString Slot;S->TryGetStringField(TEXT("slot"),Slot);int32 I=Slot==TEXT("north")?0:Slot==TEXT("east")?1:Slot==TEXT("south")?2:Slot==TEXT("west")?3:-1;
        if(I<0){Error=TEXT("INVALID_SLOT");return false;}double D=Anchor==TEXT("gate")?530:585;S->TryGetNumberField(TEXT("distance"),D);if(D<450||D>610){Error=TEXT("UNSAFE_ANCHOR_DISTANCE");return false;}Position=G->ExitPosition(I,D);
    }else if(Anchor==TEXT("pickup")){
        FString Id;S->TryGetStringField(TEXT("pickup_id"),Id);int32 Index=INDEX_NONE;for(int I=0;I<G->Pickups.Num();++I)if(G->Id(TEXT("pickup"),I)==Id)Index=I;
        if(Index<0||G->Pickups[Index].Consumed||G->Pickups[Index].Room!=Room){Error=TEXT("PICKUP_SEMANTIC_ID_UNMAPPED");return false;}
        Position=G->Pickups[Index].Location-FVector(115,0,0);Position.Z=18;
    }else if(Anchor==TEXT("final_portal")){if(Room!=G->ExitRoom){Error=TEXT("NOT_EXIT_ROOM");return false;}Position=FVector(40,160,18);}
    else if(!Anchor.IsEmpty()&&Anchor!=TEXT("center")){Error=TEXT("UNKNOWN_ANCHOR");return false;}
    if(S->HasField(TEXT("local_position"))){auto A=S->GetArrayField(TEXT("local_position"));if(A.Num()!=2||A[0]->AsNumber()<.1||A[0]->AsNumber()>.9||A[1]->AsNumber()<.1||A[1]->AsNumber()>.9){Error=TEXT("INVALID_LOCAL_POSITION");return false;}Position=FVector(A[1]->AsNumber()*1440-720,A[0]->AsNumber()*1440-720,18);}
    // Commit only audited precursor fields. No hit/pickup/cast/turn/reset/outcome call.
    bool Rebuild=Room!=G->Current;G->Current=Room;G->Monster=Monster;G->Lives=Lives;G->Scrolls=Scrolls;G->Coins=Coins;for(int I=0;I<3;++I)G->Keys[I]=Keys[I];
    G->MageLocation=Position;G->ArrivalSlot=-1;G->FinalInside=false;G->Nearby=G->Distance(Room,Monster)==1;
    if(Rebuild)G->BuildRoom();else if(G->MageActor)G->MageActor->SetActorLocation(Position);
    G->RefreshTargets();G->Publish();return true;
}
}
