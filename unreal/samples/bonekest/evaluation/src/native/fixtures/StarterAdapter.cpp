#include "StateFixture.h"
#include "NativeEvidence.h"
namespace StateFixture {
const TCHAR* AdapterVersion(){return TEXT("bonemaze-untouched-input-1.0");}
TSharedRef<FJsonObject> ReadGame(UWorld* W){auto J=NativeEvidence(W);J->SetBoolField(TEXT("mapped"),true);J->SetStringField(TEXT("phase"),TEXT("not_ready"));return J;}
bool ApplyGame(UWorld*,const TSharedPtr<FJsonObject>&,FString& Error){Error=TEXT("PUBLIC_STARTER_HAS_NO_GAMEPLAY_STATE");return false;}
}
