// Private assessment-only mapping. Never compile this file into the delivered Gold.
// Engine-owned GameMode role locates the state owner. This mapping is selected only
// after its source fingerprint matches; unknown architectures require review.
#include "StateFixture.h"
#include "StarterGameMode.h"
#include "Engine/World.h"
#include "Dom/JsonObject.h"
namespace StateFixture
{
const TCHAR* AdapterVersion(){return TEXT("gemsbond-gold-semantic-1.0");}
TSharedRef<FJsonObject> ReadGame(UWorld* W)
{
    auto J=MakeShared<FJsonObject>();auto* G=Cast<AStarterGameMode>(W->GetAuthGameMode());if(!G){J->SetStringField(TEXT("error"),TEXT("MAPPING_MISMATCH"));return J;}
    J->SetStringField(TEXT("session_id"),G->SessionId);J->SetNumberField(TEXT("round"),G->Round);J->SetNumberField(TEXT("coins"),G->Coins);J->SetNumberField(TEXT("simulation_seconds"),G->Sim);J->SetStringField(TEXT("phase"),G->Phase);J->SetNumberField(TEXT("wave"),G->Wave);J->SetNumberField(TEXT("completed"),G->Completed);
    TArray<TSharedPtr<FJsonValue>> Rows;for(const auto& U:G->Units)if(!U.Removed){auto R=MakeShared<FJsonObject>();R->SetStringField(TEXT("kind"),U.Kind);R->SetNumberField(TEXT("id"),U.Id);R->SetNumberField(TEXT("health"),U.Health);R->SetNumberField(TEXT("maximum"),U.Maximum);R->SetNumberField(TEXT("tier"),U.Tier);Rows.Add(MakeShared<FJsonValueObject>(R));}J->SetArrayField(TEXT("entities"),Rows);return J;
}
bool ApplyGame(UWorld* W,const TSharedPtr<FJsonObject>& S,FString& Error)
{
    auto* G=Cast<AStarterGameMode>(W->GetAuthGameMode());if(!G){Error=TEXT("MAPPING_MISMATCH");return false;}
    if(G->Phase!=TEXT("preparing")||G->Units.Num()!=5||G->Coins!=170){Error=TEXT("FRESH_PROCESS_REQUIRED");return false;}
    const TSet<FString> Allowed={TEXT("coins"),TEXT("crystal_health"),TEXT("resume_phase"),TEXT("wave"),TEXT("completed"),TEXT("countdown"),TEXT("units"),TEXT("selected_entity"),TEXT("wave_total"),TEXT("wave_spawned")};
    for(const auto& P:S->Values)if(!Allowed.Contains(P.Key)){Error=TEXT("FIELD_NOT_ALLOWED");return false;}
    double Coins=170,Health=500,Wave=1,Completed=0,Countdown=1,Total=0,Spawned=0;FString Phase=TEXT("countdown");
    S->TryGetNumberField(TEXT("coins"),Coins);S->TryGetNumberField(TEXT("crystal_health"),Health);S->TryGetNumberField(TEXT("wave"),Wave);S->TryGetNumberField(TEXT("completed"),Completed);S->TryGetNumberField(TEXT("countdown"),Countdown);S->TryGetNumberField(TEXT("wave_total"),Total);S->TryGetNumberField(TEXT("wave_spawned"),Spawned);S->TryGetStringField(TEXT("resume_phase"),Phase);
    if(Coins<0||Coins>1000000||Coins!=FMath::FloorToDouble(Coins)||Health<=0||Health>500||Wave<0||Wave>100||Completed<0||Total<0||Total>1000||Spawned<0||Spawned>Total||Countdown<0||Countdown>8||(Phase!=TEXT("preparing")&&Phase!=TEXT("countdown")&&Phase!=TEXT("rest")&&Phase!=TEXT("combat"))){Error=TEXT("PRECONDITION_RANGE");return false;}
    const TArray<TSharedPtr<FJsonValue>>* Rows=nullptr;S->TryGetArrayField(TEXT("units"),Rows);
    TArray<FGBUnit> New;
    if(Rows)for(auto Value:*Rows)
    {
        auto R=Value->AsObject();if(!R){Error=TEXT("UNIT_OBJECT_REQUIRED");return false;}
        const TSet<FString> Fields={TEXT("kind"),TEXT("position"),TEXT("tier"),TEXT("health"),TEXT("paid"),TEXT("cooldown_remaining"),TEXT("income_remaining"),TEXT("construction_remaining"),TEXT("attack_remaining")};for(const auto& P:R->Values)if(!Fields.Contains(P.Key)){Error=TEXT("UNIT_FIELD_NOT_ALLOWED");return false;}
        FGBUnit U;const TArray<TSharedPtr<FJsonValue>>* P=nullptr;
        if(!R->TryGetStringField(TEXT("kind"),U.Kind)||!R->TryGetArrayField(TEXT("position"),P)||P->Num()!=3||(!U.Building()&&!U.Enemy())){Error=TEXT("ENTITY_PRECONDITION_REQUIRED");return false;}
        double Tier=1,Paid=0,Cooldown=0,Income=10,Construction=0,Attack=0;R->TryGetNumberField(TEXT("tier"),Tier);R->TryGetNumberField(TEXT("paid"),Paid);R->TryGetNumberField(TEXT("cooldown_remaining"),Cooldown);R->TryGetNumberField(TEXT("income_remaining"),Income);R->TryGetNumberField(TEXT("construction_remaining"),Construction);R->TryGetNumberField(TEXT("attack_remaining"),Attack);
        if(Tier<1||Tier>3||Tier!=FMath::FloorToDouble(Tier)||Paid<0||Cooldown<0||Cooldown>2||Income<0||Income>10||Construction<0||Construction>.6||Attack<0||Attack>1){Error=TEXT("UNIT_RANGE");return false;}
        U.Tier=int(Tier);G->ApplyStats(U);U.Health=U.Maximum;R->TryGetNumberField(TEXT("health"),U.Health);if(U.Health<=0||U.Health>U.Maximum){Error=TEXT("HEALTH_PRECONDITION_RANGE");return false;}
        U.Position=FVector((*P)[0]->AsNumber(),(*P)[1]->AsNumber(),(*P)[2]->AsNumber());U.Paid=int(Paid);U.Born=100-(.3-Construction);U.BuildUntil=100+Construction;U.Ready=100+Cooldown;U.Income=100+Income;U.AttackAt=100+Attack;
        if(U.Position.X< -1||U.Position.X>20||U.Position.Y< -1||U.Position.Y>20||U.Position.Z<0||U.Position.Z>5){Error=TEXT("POSITION_RANGE");return false;}New.Add(U);
    }
    // Commit validated preconditions only. No damage, purchase, reward, wave-start,
    // upgrade, sale, defeat, reset or scoring function is called by this adapter.
    G->Coins=int64(Coins);G->Sim=100;G->Wave=int(Wave);G->Completed=int(Completed);G->Countdown=Countdown;G->Phase=TEXT("paused");G->ResumePhase=Phase;G->Fast=false;G->FastArmed=false;G->Accumulator=0;
    for(auto& U:G->Units)if(U.Kind==TEXT("crystal"))U.Health=Health;
    G->Schedule.SetNum(int(Total));G->Spawned=int(Spawned);G->SpawnDuration=10;G->WaveStarted=90;
    for(auto U:New){U.Id=G->NextId++;G->Units.Add(U);G->MakeVisual(G->Units.Last());}
    double Select=-1;if(S->TryGetNumberField(TEXT("selected_entity"),Select)&&Select>=0&&Select<New.Num())G->InspectId=G->Units[5+int(Select)].Id;
    return true;
}
}
