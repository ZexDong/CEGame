namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    /// <summary>
    /// Evaluator-private labels for the clean-state player journey a test is
    /// about to execute. These labels are not part of the public submission
    /// contract and never mutate candidate state.
    /// </summary>
    public enum DungeonDuelTrajectoryIntent
    {
        CanonicalSuccess,
        Navigation,
        PlayerCombat,
        EnemyThreat,
        Dash,
        GateUnlock,
        VictoryReady,
        DefeatReady
    }
}

