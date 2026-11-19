#include "UnrealFixtureCapabilities.h"
#include "Engine/World.h"
#include "Engine/GameViewportClient.h"
#include "UnrealClient.h"
#include "Framework/Application/SlateApplication.h"
#include "Layout/WidgetPath.h"
#include "Widgets/SViewport.h"
#include "Widgets/SWindow.h"
#include "GenericPlatform/GenericWindow.h"
#include "EngineUtils.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/Character.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "Components/CapsuleComponent.h"
#include "Components/PrimitiveComponent.h"
#include "Components/BoxComponent.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"

namespace UnrealFixtureCapabilities
{
    ACharacter* FindPlayer(UWorld* World)
    {
        return World ? Cast<ACharacter>(UGameplayStatics::GetPlayerPawn(World, 0)) : nullptr;
    }
    static FVector Vector(const TSharedPtr<FJsonObject>& Json)
    {
        return FVector(Json->GetNumberField(TEXT("x")), Json->GetNumberField(TEXT("y")), Json->GetNumberField(TEXT("z"))) * 100.0;
    }
    static TSharedRef<FJsonObject> Position(FVector Value)
    {
        auto R = MakeShared<FJsonObject>();
        R->SetNumberField(TEXT("x"), Value.X / 100.0); R->SetNumberField(TEXT("y"), Value.Y / 100.0); R->SetNumberField(TEXT("z"), Value.Z / 100.0);
        return R;
    }
    // Positions originate in the public read-only snapshot. Never resolve an
    // opaque entity ID as an Unreal object name or match a candidate class name.
    static AActor* At(UWorld* World, FVector Where, AActor* Player)
    {
        // A snapshot can precede command delivery by a few frames. Prefer the
        // nearest engine actor within the bounded observation freshness radius.
        AActor* Found = nullptr; float Best = 500.0f;
        for (TActorIterator<AActor> It(World); It; ++It)
        {
            if (*It == Player || *It == World->GetAuthGameMode() || !It->GetRootComponent()) continue;
            const float Distance = FVector::Dist(It->GetActorLocation(), Where);
            if (Distance < Best) { Best = Distance; Found = *It; }
        }
        return Found;
    }
    static bool Place(UWorld* World, ACharacter* Player, FVector Desired, FVector Aim, TSharedRef<FJsonObject> Receipt, double MaxGroundZ = TNumericLimits<double>::Max())
    {
        const float Half = Player->GetCapsuleComponent()->GetScaledCapsuleHalfHeight();
        const float Radius = Player->GetCapsuleComponent()->GetScaledCapsuleRadius();
        FCollisionQueryParams Params(SCENE_QUERY_STAT(UEvaluatorGround), false, Player);
        FHitResult Ground;
        if (!World->LineTraceSingleByChannel(Ground, Desired + FVector(0,0,500), Desired - FVector(0,0,1200), ECC_Visibility, Params) || Ground.ImpactNormal.Z < .65f) return false;
        if (Ground.ImpactPoint.Z > MaxGroundZ) return false;
        Desired.Z = Ground.ImpactPoint.Z + Half + 3;
        if (World->OverlapBlockingTestByChannel(Desired, FQuat::Identity, ECC_Pawn, FCollisionShape::MakeCapsule(Radius, Half), Params)) return false;
        Player->GetCharacterMovement()->StopMovementImmediately();
        if (!Player->SetActorLocation(Desired, false, nullptr, ETeleportType::TeleportPhysics)) return false;
        const FRotator Rotation = Aim.Rotation();
        Player->SetActorRotation(FRotator(0, Rotation.Yaw, 0));
        if (Player->GetController()) Player->GetController()->SetControlRotation(Rotation);
        Receipt->SetObjectField(TEXT("position_m"), Position(Player->GetActorLocation()));
        Receipt->SetBoolField(TEXT("ground_and_capsule_verified"), true);
        return true;
    }
    bool Apply(UWorld* World, const TSharedPtr<FJsonObject>& Request, TSharedRef<FJsonObject> Receipt, const FGeometrySettings& Settings)
    {
        auto* Player = FindPlayer(World);
        if (!Player) return false;
        bool Ok = true;
        if (Request->HasField(TEXT("capture_pointer")) && Request->GetBoolField(TEXT("capture_pointer")))
        {
            // Engine viewport focus is an input precondition, not a gameplay
            // action. Include the first mouse down in the measured input path.
            auto* Controller = Cast<APlayerController>(Player->GetController());
            auto* Client = World->GetGameViewport();
            if (Controller && Client && Client->Viewport)
            {
                FInputModeGameOnly Mode;
                Mode.SetConsumeCaptureMouseDown(false);
                Controller->SetInputMode(Mode);
                Client->SetMouseCaptureMode(EMouseCaptureMode::CapturePermanently_IncludingInitialMouseDown);
                Client->Viewport->CaptureMouse(true);
                Client->Viewport->LockMouseToViewport(true);
                // FViewport capture only queues a reply for an input event.
                // Apply the engine's standard capture reply to the actual
                // viewport widget now, before measured input is dispatched.
                const auto Widget = Client->GetGameViewportWidget();
                if (Widget.IsValid() && FSlateApplication::IsInitialized())
                {
                    auto& Slate = FSlateApplication::Get();
                    FWidgetPath Path;
                    const bool PathValid = Slate.GeneratePathToWidgetUnchecked(Widget.ToSharedRef(), Path);
                    Receipt->SetBoolField(TEXT("viewport_path_valid"), PathValid);
                    Receipt->SetBoolField(TEXT("slate_active_before"), Slate.IsActive());
                    if (PathValid)
                    {
                        const auto NativeWindow = Path.GetWindow()->GetNativeWindow();
                        const bool Foreground = NativeWindow.IsValid() && NativeWindow->IsForegroundWindow();
                        Receipt->SetBoolField(TEXT("os_foreground"), Foreground);
                        // OS foreground is established by the bound executor.
                        // Synchronize a queued engine activation notification
                        // only when the native window independently confirms it.
                        if (Foreground && !Slate.IsActive()) Slate.OnApplicationActivationChanged(true);
                        Slate.SetUserFocus(0, Widget, EFocusCause::Mouse);
                        FReply Reply = FReply::Handled().UseHighPrecisionMouseMovement(Widget.ToSharedRef()).SetUserFocus(Widget.ToSharedRef()).LockMouseToWidget(Widget.ToSharedRef());
                        Slate.ProcessReply(Path, Reply, nullptr, nullptr);
                        Receipt->SetBoolField(TEXT("slate_active_after"), Slate.IsActive());
                    }
                }
                Receipt->SetBoolField(TEXT("viewport_capture"), Client->Viewport->HasMouseCapture());
            }
            else Ok = false;
        }
        const TArray<TSharedPtr<FJsonValue>>* Entities;
        // Freeze unrelated locomotion without freezing projectiles, timers,
        // collision, or the player. Damage cases explicitly leave AI running.
        if (Request->TryGetArrayField(TEXT("freeze_enemies"), Entities))
        {
            for (const auto& E : *Entities)
            {
                auto* Actor = At(World, Vector(E->AsObject()), Player);
                if (!Actor) { Ok = false; break; }
                Actor->SetActorTickEnabled(false);
                if (auto* C = Cast<ACharacter>(Actor)) C->GetCharacterMovement()->StopMovementImmediately();
            }
        }
        if (Request->TryGetArrayField(TEXT("remove_props"), Entities))
        {
            for (const auto& E : *Entities)
            {
                auto* Actor = At(World, Vector(E->AsObject()), Player);
                if (!Actor) { Ok = false; break; }
                Actor->Destroy();
            }
        }
        const TSharedPtr<FJsonObject>* Target;
        if (Request->TryGetObjectField(TEXT("near_position_m"), Target))
        {
            const FVector To = Vector(*Target);
            double Distance = Request->GetNumberField(TEXT("distance_m")) * 100.0;
            bool Placed = false;
            for (int Index = 0; Index < 16 && !Placed; ++Index)
            {
                const FVector Direction = FRotator(0, Index * 22.5, 0).Vector();
                // A ground-target aim must not start on a nearby wall roof.
                // Keep the surface near the observed target's ground level.
                const double MaxGroundZ = Request->HasField(TEXT("aim_position_m")) ? To.Z + 50.0 : TNumericLimits<double>::Max();
                Placed = Place(World, Player, To - Direction * Distance, Direction, Receipt, MaxGroundZ);
            }
            Ok &= Placed;
        }
        if (Request->TryGetObjectField(TEXT("position_m"), Target))
            Ok &= Place(World, Player, Vector(*Target), Player->GetActorForwardVector(), Receipt);
        if (Request->TryGetObjectField(TEXT("aim_position_m"), Target))
        {
            // Aim toward an observed world position using the engine eye
            // location. Projectile travel/collision and all results stay native.
            const FVector Origin = Player->GetPawnViewLocation();
            const FVector Direction = (Vector(*Target) - Origin).GetSafeNormal();
            if (Player->GetController() && !Direction.IsNearlyZero())
            {
                Player->SetActorRotation(FRotator(0, Direction.Rotation().Yaw, 0));
                Player->GetController()->SetControlRotation(Direction.Rotation());
                Receipt->SetObjectField(TEXT("aim_origin_m"), Position(Origin));
                Receipt->SetObjectField(TEXT("aim_position_m"), *Target);
                Receipt->SetObjectField(TEXT("aim_direction"), Position(Player->GetController()->GetControlRotation().Vector() * 100.0));
            }
            else Ok = false;
        }
        FString Aim;
        if (Request->TryGetStringField(TEXT("aim"), Aim))
        {
            if (Aim == TEXT("up"))
            {
                if (Player->GetController()) Player->GetController()->SetControlRotation(FRotator(90, 0, 0));
                Receipt->SetStringField(TEXT("endpoint_class"), TEXT("illegal"));
            }
            else
            {
                // Search engine collision geometry from the actual layout.
                bool Found = false;
                for (int Index = 0; Index < 32 && !Found; ++Index)
                {
                    FVector Direction = FRotator(0, Index * 11.25, 0).Vector();
                    FVector Start = Player->GetActorLocation();
                    FCollisionQueryParams Params(SCENE_QUERY_STAT(UEvaluatorAim), false, Player);
                    FHitResult Hit;
                    const bool Blocked = Aim == TEXT("open")
                        ? World->SweepSingleByChannel(Hit, Start, Start + Direction * Settings.AimTraceDistance, FQuat::Identity, ECC_Pawn,
                            FCollisionShape::MakeCapsule(Player->GetCapsuleComponent()->GetScaledCapsuleRadius(), Player->GetCapsuleComponent()->GetScaledCapsuleHalfHeight()), Params)
                        : World->LineTraceSingleByChannel(Hit, Start + FVector(0,0,50), Start + FVector(0,0,50) + Direction * Settings.AimTraceDistance, ECC_Visibility, Params);
                    if ((Aim == TEXT("obstacle") && Blocked && Hit.Distance > 200) || (Aim == TEXT("open") && !Blocked))
                    {
                        FHitResult Ground;
                        FVector End = Start + Direction * Settings.EndpointDistance;
                        if (Aim == TEXT("open") && !World->LineTraceSingleByChannel(Ground, End + FVector(0,0,450), End - FVector(0,0,900), ECC_Visibility, Params)) continue;
                        Player->SetActorRotation(Direction.Rotation());
                        if (Player->GetController()) Player->GetController()->SetControlRotation(Direction.Rotation());
                        Receipt->SetStringField(TEXT("endpoint_class"), TEXT("legal"));
                        Found = true;
                    }
                }
                Ok &= Found;
            }
        }
        if (Request->HasField(TEXT("block_forward_space")) && Request->GetBoolField(TEXT("block_forward_space")))
        {
            // Establish blocked geometry, never invoke destination selection.
            const FVector Forward = Player->GetActorForwardVector().GetSafeNormal2D();
            const float Radius = Player->GetCapsuleComponent()->GetScaledCapsuleRadius();
            AActor* Barrier = World->SpawnActor<AActor>();
            UBoxComponent* Box = NewObject<UBoxComponent>(Barrier);
            Barrier->SetRootComponent(Box);
            Box->SetBoxExtent(FVector(250, 500, 500));
            Box->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
            Box->SetCollisionObjectType(ECC_WorldStatic);
            Box->SetCollisionResponseToAllChannels(ECR_Block);
            Box->RegisterComponent();
            Barrier->SetActorLocation(Player->GetActorLocation() + Forward * (Radius + 5 + 250));
            Barrier->SetActorRotation(Forward.Rotation());
            FCollisionQueryParams Params(SCENE_QUERY_STAT(UEvaluatorBlocked), false, Player);
            FHitResult Hit;
            const bool Blocked = World->SweepSingleByChannel(Hit, Player->GetActorLocation(),
                Player->GetActorLocation() + Forward * Settings.EndpointDistance, FQuat::Identity, ECC_Pawn,
                FCollisionShape::MakeCapsule(Radius, Player->GetCapsuleComponent()->GetScaledCapsuleHalfHeight()), Params);
            Ok &= Blocked && Hit.GetActor() == Barrier && Hit.Distance < Radius;
            Receipt->SetStringField(TEXT("endpoint_class"), Ok ? TEXT("illegal") : TEXT("unconfirmed"));
            Receipt->SetNumberField(TEXT("forward_clearance_m"), Hit.Distance / 100.0);
            Receipt->SetObjectField(TEXT("barrier_position_m"), Position(Barrier->GetActorLocation()));
        }
        return Ok;
    }
}
