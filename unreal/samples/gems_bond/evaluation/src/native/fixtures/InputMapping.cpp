// Private host-health probe for the untouched, explicitly unfinished input.
#include "StateFixture.h"
#include "Engine/World.h"
namespace StateFixture
{
const TCHAR* AdapterVersion(){return TEXT("gemsbond-untouched-input-probe-1.0");}
TSharedRef<FJsonObject> ReadGame(UWorld* W){auto J=MakeShared<FJsonObject>();J->SetBoolField(TEXT("world_begun_play"),W&&W->HasBegunPlay());J->SetStringField(TEXT("phase"),TEXT("not_ready"));return J;}
bool ApplyGame(UWorld*,const TSharedPtr<FJsonObject>&,FString& Error){Error=TEXT("UNIMPLEMENTED_PUBLIC_GAMEPLAY");return false;}
}
