#include "RollBallStarterDisplay.h"

#include "Components/DirectionalLightComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInterface.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Engine/Texture2D.h"
#include "UObject/UObjectGlobals.h"

namespace
{
UStaticMesh* LoadMesh(const TCHAR* Path)
{
    return LoadObject<UStaticMesh>(nullptr, Path);
}

UMaterialInterface* LoadStarterMaterial()
{
    // The supplied project material keeps this starter self-contained while
    // giving the meshes real dynamic lighting in a blank map.
    return LoadObject<UMaterialInterface>(nullptr,
        TEXT("/Game/StarterContent/Materials/M_Basic_Floor.M_Basic_Floor"));
}

UMaterialInterface* LoadBallBaseMaterial()
{
    return LoadObject<UMaterialInterface>(nullptr,
        TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
}

UMaterialInstanceDynamic* MakeCheckerMaterial(UMaterialInterface* BaseMaterial)
{
    if (!BaseMaterial) return nullptr;
    UTexture2D* Checker = UTexture2D::CreateTransient(32, 32, PF_B8G8R8A8);
    if (!Checker || !Checker->GetPlatformData() || Checker->GetPlatformData()->Mips.Num() == 0) return nullptr;
    FTexture2DMipMap& Mip = Checker->GetPlatformData()->Mips[0];
    FColor* Pixels = static_cast<FColor*>(Mip.BulkData.Lock(LOCK_READ_WRITE));
    for (int32 Y = 0; Y < 32; ++Y) for (int32 X = 0; X < 32; ++X)
        Pixels[Y * 32 + X] = (((X / 4) + (Y / 4)) % 2 == 0) ? FColor(245, 194, 62, 255) : FColor(34, 48, 78, 255);
    Mip.BulkData.Unlock();
    Checker->SRGB = true;
    Checker->UpdateResource();
    UMaterialInstanceDynamic* Material = UMaterialInstanceDynamic::Create(BaseMaterial, GetTransientPackage());
    if (Material)
    {
        Material->SetTextureParameterValue(TEXT("Texture"), Checker);
        Material->SetTextureParameterValue(TEXT("BaseColor"), Checker);
        Material->SetTextureParameterValue(TEXT("Albedo"), Checker);
        Material->SetTextureParameterValue(TEXT("DiffuseTexture"), Checker);
    }
    return Material;
}

void SetMaterial(UStaticMeshComponent* Component, UMaterialInterface* Material)
{
    if (Component && Material)
    {
        Component->SetMaterial(0, Material);
    }
}

UStaticMeshComponent* AddMesh(AActor* Owner, UStaticMesh* Mesh, const FVector& Location,
    const FVector& Scale, UMaterialInterface* Material)
{
    UStaticMeshComponent* Component = NewObject<UStaticMeshComponent>(Owner);
    Component->SetStaticMesh(Mesh);
    Component->SetRelativeLocation(Location);
    Component->SetRelativeScale3D(Scale);
    Component->SetMobility(EComponentMobility::Movable);
    Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    SetMaterial(Component, Material);
    Component->AttachToComponent(Owner->GetRootComponent(), FAttachmentTransformRules::KeepRelativeTransform);
    Component->RegisterComponent();
    return Component;
}
}

ARollBallStarterDisplay::ARollBallStarterDisplay()
{
    PrimaryActorTick.bCanEverTick = true;

    USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("DisplayRoot"));
    RootComponent = Root;
}

void ARollBallStarterDisplay::BeginPlay()
{
    Super::BeginPlay();

    UStaticMesh* FloorMesh = LoadMesh(TEXT("/Game/StarterContent/Architecture/Floor_400x400.Floor_400x400"));
    UStaticMesh* WallMesh = LoadMesh(TEXT("/Game/StarterContent/Architecture/Wall_400x200.Wall_400x200"));
    UStaticMesh* SphereMesh = LoadMesh(TEXT("/Game/StarterContent/Shapes/Shape_Sphere.Shape_Sphere"));
    UMaterialInterface* StarterMaterial = LoadStarterMaterial();
    UMaterialInterface* BallMaterial = MakeCheckerMaterial(LoadBallBaseMaterial());

    // A compact sample platform makes the mesh scale, bevels, and shadows
    // readable without presenting the task's fixed layout or route.
    AddMesh(this, FloorMesh, FVector(-200.0f, -200.0f, 0.0f), FVector(1.0f, 1.0f, 0.18f), StarterMaterial);
    AddMesh(this, FloorMesh, FVector(200.0f, -200.0f, 0.0f), FVector(1.0f, 1.0f, 0.18f), StarterMaterial);
    AddMesh(this, FloorMesh, FVector(-200.0f, 200.0f, 0.0f), FVector(1.0f, 1.0f, 0.18f), StarterMaterial);
    AddMesh(this, FloorMesh, FVector(200.0f, 200.0f, 0.0f), FVector(1.0f, 1.0f, 0.18f), StarterMaterial);

    AddMesh(this, WallMesh, FVector(-600.0f, 0.0f, 130.0f), FVector(0.22f, 1.6f, 1.3f), StarterMaterial);
    AddMesh(this, WallMesh, FVector(600.0f, 0.0f, 130.0f), FVector(0.22f, 1.6f, 1.3f), StarterMaterial);
    AddMesh(this, WallMesh, FVector(0.0f, -600.0f, 130.0f), FVector(1.6f, 0.22f, 1.3f), StarterMaterial)->SetRelativeRotation(FRotator(0.0f, 90.0f, 0.0f));
    AddMesh(this, WallMesh, FVector(0.0f, 600.0f, 130.0f), FVector(1.6f, 0.22f, 1.3f), StarterMaterial)->SetRelativeRotation(FRotator(0.0f, 90.0f, 0.0f));

    RollingSphere = AddMesh(this, SphereMesh, FVector(0.0f, 0.0f, 190.0f), FVector(0.82f), BallMaterial ? BallMaterial : StarterMaterial);

    UDirectionalLightComponent* KeyLight = NewObject<UDirectionalLightComponent>(this, TEXT("KeyLight"));
    KeyLight->SetIntensity(4.0f);
    KeyLight->SetLightColor(FLinearColor(1.0f, 0.90f, 0.78f));
    KeyLight->SetRelativeRotation(FRotator(-48.0f, -32.0f, 0.0f));
    KeyLight->SetupAttachment(RootComponent);
    KeyLight->RegisterComponent();

    UPointLightComponent* FillLight = NewObject<UPointLightComponent>(this, TEXT("FillLight"));
    FillLight->SetIntensity(1400.0f);
    FillLight->SetAttenuationRadius(1800.0f);
    FillLight->SetLightColor(FLinearColor(0.45f, 0.62f, 1.0f));
    FillLight->SetRelativeLocation(FVector(-350.0f, 250.0f, 700.0f));
    FillLight->SetupAttachment(RootComponent);
    FillLight->RegisterComponent();
}

void ARollBallStarterDisplay::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    if (RollingSphere)
    {
        // Slow continuous rotation communicates the sphere's 3D surface and
        // keeps the starter visibly alive without implementing movement input.
        SphereSpin = FMath::Fmod(SphereSpin + DeltaSeconds * 30.0f, 360.0f);
        RollingSphere->SetRelativeRotation(FRotator(SphereSpin, SphereSpin * 0.35f, 0.0f));
    }
}

