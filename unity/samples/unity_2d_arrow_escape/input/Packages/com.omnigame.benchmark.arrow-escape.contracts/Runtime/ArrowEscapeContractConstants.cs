namespace OmniGame.Benchmark.ArrowEscape.V2
{
    /// <summary>
    /// Stable paths and identifiers which are part of the public task input.
    /// Implementations may use any internal class names or architecture.
    /// </summary>
    public static class ArrowEscapeContractConstants
    {
        public const string ContractVersion = "3.0";
        public const string BenchmarkId = "unity.arrow_escape_reconstruction.v2";

        public const string MainScenePath = "Assets/ArrowEscapeBenchmark/Scenes/ArrowEscape.unity";
        public const string RuntimeFolder = "Assets/ArrowEscapeBenchmark/Runtime";
        public const string EditorFolder = "Assets/ArrowEscapeBenchmark/Editor";
        public const string PrefabFolder = "Assets/ArrowEscapeBenchmark/Prefabs";
        public const string LevelFolder = "Assets/ArrowEscapeBenchmark/Levels";
        public const string ArrowPrefabPath = "Assets/ArrowEscapeBenchmark/Prefabs/Arrow.prefab";
        public const string KeyBadgePrefabPath = "Assets/ArrowEscapeBenchmark/Prefabs/KeyBadge.prefab";
        public const string LockBadgePrefabPath = "Assets/ArrowEscapeBenchmark/Prefabs/LockBadge.prefab";

        public const string TutorialLevelPath = "Assets/ArrowEscapeBenchmark/Levels/Tutorial.asset";
        public const string ModesLevelPath = "Assets/ArrowEscapeBenchmark/Levels/ModesAndHint.asset";
        public const string PrerequisiteLevelPath = "Assets/ArrowEscapeBenchmark/Levels/PrerequisiteLocks.asset";

        public const string KeyBadgeSpritePath = "Assets/ArrowEscapeBenchmark/Art/Imported/key_badge.png";
        public const string LockBadgeSpritePath = "Assets/ArrowEscapeBenchmark/Art/Imported/lock_badge.png";

        public const string TutorialLevelId = "tutorial";
        public const string ModesLevelId = "modes_and_hint";
        public const string PrerequisiteLevelId = "prerequisite_chain";

        public const string KeyArrowId = "key_a";
        public const string MiddleLockArrowId = "lock_b";
        public const string FinalLockArrowId = "lock_c";
    }
}
