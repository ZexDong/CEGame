#pragma once
#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "ObservationTransport.generated.h"

// Outbound observation only. No file reader, commands, state setters, or gameplay hooks.
UCLASS()
class CHOMPSTARTER_API UObservationTransport : public UTickableWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual bool DoesSupportWorldType(EWorldType::Type WorldType) const override;
    virtual void Initialize(FSubsystemCollectionBase& Collection) override;
    virtual void Tick(float DeltaTime) override;
    virtual TStatId GetStatId() const override;
    UFUNCTION(BlueprintCallable, Category="Observation")
    void PublishObservation(const FString& StateJson);
    UFUNCTION(BlueprintCallable, Category="Observation")
    void NotifyFrameDrawn();
private:
    FString OutputPath;
    FString ProcessToken;
    FString LatestState;
    uint64 SnapshotId = 0;
    double LastWrite = 0;
    bool FrameDrawn = false;
};
