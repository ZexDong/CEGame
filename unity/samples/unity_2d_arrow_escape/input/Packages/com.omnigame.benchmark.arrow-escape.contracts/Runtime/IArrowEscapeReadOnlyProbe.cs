namespace OmniGame.Benchmark.ArrowEscape.V2
{
    /// <summary>
    /// Mandatory read-only semantic probe for the public Unity project contract.
    /// It exposes the same player-visible level, budget, arrow, badge, Hint and terminal
    /// information that is rendered by the game. It has no action, reset, fixture-loading,
    /// result-forcing or mutation API. Read-only consumers can cross-check probe values against
    /// visible scene objects; normal player actions still travel through a real Input System Mouse.
    /// </summary>
    public interface IArrowEscapeReadOnlyProbe
    {
        string ContractVersion { get; }

        ArrowEscapeGameSnapshot CaptureBenchmarkSnapshot();
    }
}