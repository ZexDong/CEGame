#include "StateFixture.h"
namespace StateFixture
{
const TCHAR* AdapterVersion(){return TEXT("chomp-untouched-starter-probe-1.0.0");}
TSharedRef<FJsonObject> ReadGame(UWorld*){auto J=MakeShared<FJsonObject>();J->SetBoolField(TEXT("provider_available"),false);J->SetStringField(TEXT("reason"),TEXT("Public starter has no gameplay state"));return J;}
bool ApplyGame(UWorld*,const TSharedPtr<FJsonObject>&,FString& Error){Error=TEXT("STARTER_GAMEPLAY_UNAVAILABLE");return false;}
}
