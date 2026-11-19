namespace OmniGame.Benchmark.ArrowEscape.V2
{
    /// <summary>
    /// Implement this on the ScriptableObject used to author a level.
    /// The returned value must be reconstructed from serialized fields, not a test-only fixture.
    /// </summary>
    public interface IArrowEscapeLevelAsset
    {
        ArrowEscapeLevelSpec ExportBenchmarkLevel();
    }
}
