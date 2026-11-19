using UnityEngine;

namespace OmniGame.Benchmark.DungeonDuel.V2
{
    /// <summary>
    /// Mandatory, read-only submission probe. It exposes semantic targets and
    /// truthful state only; all scored player actions still travel through the
    /// candidate's normal Unity Input System path.
    /// </summary>
    public interface IDungeonDuelBenchmarkProbe
    {
        string ContractVersion { get; }

        DungeonDuelGameSnapshot CaptureBenchmarkSnapshot();

        GameObject GetActorPointerTarget(DungeonDuelActorId actorId);

        GameObject GetGatePointerTarget();

        Vector3 GetWorldTargetPosition(DungeonDuelWorldTargetId targetId);
    }

}
