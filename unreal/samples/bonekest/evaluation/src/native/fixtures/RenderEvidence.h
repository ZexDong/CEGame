#pragma once
#include "CoreMinimal.h"
#include "Dom/JsonObject.h"
#include "Engine/Canvas.h"
#include "Engine/Font.h"
#include "Engine/Texture.h"
#include "GameFramework/HUD.h"
#include "CanvasItem.h"
#include "Framework/Application/SlateApplication.h"
#include "Fonts/FontMeasure.h"

// Read-only taps immediately beside the real draw calls. Every wrapper forwards
// the original arguments unchanged; this surface has no game state or setters.
namespace PrivateRender {
inline TArray<TSharedPtr<FJsonValue>> Commands;
inline uint64 Frame=0;
inline double Timestamp=0;
inline void Begin(UCanvas* C){Commands.Empty();Frame=GFrameCounter;Timestamp=FPlatformTime::Seconds();}
inline void Record(UCanvas* C,FString Kind,FString Text,FString Asset,float X,float Y,float W,float H,float Alpha){
    if(!C||C->SizeX<1||C->SizeY<1)return;auto J=MakeShared<FJsonObject>();J->SetStringField(TEXT("kind"),Kind);J->SetStringField(TEXT("text"),Text);J->SetStringField(TEXT("asset"),Asset);J->SetNumberField(TEXT("alpha"),Alpha);
    TArray<TSharedPtr<FJsonValue>> R;for(double V:{double(X/C->SizeX),double(Y/C->SizeY),double(W/C->SizeX),double(H/C->SizeY)})R.Add(MakeShared<FJsonValueNumber>(V));J->SetArrayField(TEXT("rect"),R);Commands.Add(MakeShared<FJsonValueObject>(J));
}
inline void Text(AHUD* HUD,UCanvas* C,const FString& T,FLinearColor Color,float X,float Y,UFont* Font=nullptr,float Scale=1,bool ScalePosition=false){
    float W=0,H=0;if(Font)C->TextSize(Font,T,W,H,Scale,Scale);Record(C,TEXT("text"),T,Font?Font->GetPathName():TEXT("engine_default"),X*(ScalePosition?Scale:1),Y*(ScalePosition?Scale:1),W,H,Color.A);HUD->DrawText(T,Color,X,Y,Font,Scale,ScalePosition);
}
inline void Texture(AHUD* HUD,UCanvas* C,UTexture* T,float X,float Y,float W,float H,float U,float V,float UW,float VH,FLinearColor Tint=FLinearColor::White,EBlendMode Blend=BLEND_Translucent,float Scale=1,bool ScalePosition=false,float Rotation=0,FVector2D Pivot=FVector2D::ZeroVector){
    Record(C,TEXT("texture"),TEXT(""),T?T->GetPathName():TEXT("null"),X*(ScalePosition?Scale:1),Y*(ScalePosition?Scale:1),W*Scale,H*Scale,Tint.A);HUD->DrawTexture(T,X,Y,W,H,U,V,UW,VH,Tint,Blend,Scale,ScalePosition,Rotation,Pivot);
}
inline void Item(UCanvas* C,FCanvasTextItem& I){
    FVector2D Size;if(I.SlateFontInfo.IsSet())Size=FSlateApplication::Get().GetRenderer()->GetFontMeasureService()->Measure(I.Text,I.SlateFontInfo.GetValue());else{float W=0,H=0;C->TextSize(I.Font,I.Text.ToString(),W,H,I.Scale.X,I.Scale.Y);Size=FVector2D(W,H);}
    Record(C,TEXT("text"),I.Text.ToString(),I.Font?I.Font->GetPathName():TEXT("engine_default"),I.Position.X,I.Position.Y,Size.X,Size.Y,1);C->DrawItem(I);
}
inline TSharedRef<FJsonObject> Read(){auto J=MakeShared<FJsonObject>();J->SetNumberField(TEXT("frame"),double(Frame));J->SetNumberField(TEXT("monotonic_seconds"),Timestamp);J->SetArrayField(TEXT("commands"),Commands);return J;}
}
