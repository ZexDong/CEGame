using System.IO;
using NUnit.Framework;
using OmniGame.Benchmark.ArrowEscape.V2;
using UnityEditor;
using UnityEngine;

namespace OmniGame.Benchmark.ArrowEscape.PublicSmoke
{
    public sealed class StarterEnvironmentTests
    {
        [Test]
        public void LockedEditorVersionMatches()
        {
            Assert.That(Application.unityVersion, Is.EqualTo("6000.0.80f1"));
        }

        [Test]
        public void ProtectedStarterSceneExists()
        {
            const string scenePath = "Assets/BenchmarkStarter/Scenes/Starter.unity";
            Assert.That(AssetDatabase.LoadAssetAtPath<SceneAsset>(scenePath), Is.Not.Null);
        }

        [Test]
        public void PublicTaskInputsExist()
        {
            string[] requiredFiles =
            {
                "GDD.md",
                "INITIAL_AGENT_PROMPT.md",
                "UNITY_OFFLINE_AGENT_MANUAL.md",
                "BENCHMARK_MANIFEST.json",
                "ASSET_MANIFEST.json",
                "ASSET_CATALOG.json",
                "ASSET_CATALOG.md",
                "ASSET_COVERAGE.json",
                "ASSET_CONTACT_SHEET.png",
                "TOOLCHAIN.md",
                "UNITY_BENCHMARK_TOOL_GUIDE.md",
                "TaskAssets/badges/key_badge.png",
                "TaskAssets/badges/lock_badge.png",
                "TaskAssets/reference/sample_dependency_level.json"
            };

            foreach (string path in requiredFiles)
            {
                Assert.That(File.Exists(path), Is.True, $"Missing protected task input: {path}");
            }
        }

        [Test]
        public void PublicContractAndSubmissionRootAreFrozen()
        {
            Assert.That(ArrowEscapeContractConstants.BenchmarkId, Is.EqualTo("unity.arrow_escape_reconstruction.v2"));
            Assert.That(ArrowEscapeContractConstants.ContractVersion, Is.EqualTo("3.0"));
            StringAssert.StartsWith("Assets/ArrowEscapeBenchmark/", ArrowEscapeContractConstants.MainScenePath);
            StringAssert.StartsWith("Assets/ArrowEscapeBenchmark/", ArrowEscapeContractConstants.ArrowPrefabPath);
        }
    }
}
