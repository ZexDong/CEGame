using System.IO;
using System.Linq;
using NUnit.Framework;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace OmniGame.Benchmark.DungeonDuel.PublicSmoke
{
    public sealed class StarterEnvironmentTests
    {
        const string StarterScene =
            "Assets/DungeonDuelDemo/Starter/DungeonDuelStarter.unity";

        [Test]
        public void PUBLIC01_PinnedUnityVersionIsPresent()
        {
            Assert.That(Application.unityVersion, Is.EqualTo("6000.0.80f1"));
        }

        [Test]
        public void PUBLIC02_CanonicalArtOnlySceneIsTheFirstBuildScene()
        {
            EditorBuildSettingsScene[] enabled = EditorBuildSettings.scenes
                .Where(scene => scene.enabled).ToArray();
            Assert.That(enabled, Is.Not.Empty);
            Assert.That(enabled[0].path,
                Is.EqualTo(DungeonDuelContractConstants.MainScenePath));
            Assert.That(AssetDatabase.LoadAssetAtPath<SceneAsset>(StarterScene), Is.Not.Null);
            Assert.That(AssetDatabase.LoadAssetAtPath<SceneAsset>(
                DungeonDuelContractConstants.MainScenePath), Is.Not.Null,
                "The v2 Input must ship a saved, runnable canonical art-only Scene.");
        }

        [Test]
        public void PUBLIC03_AgentInputDocumentsAndManifestsExist()
        {
            string root = Directory.GetParent(Application.dataPath)?.FullName;
            Assert.That(root, Is.Not.Null);
            foreach (string name in new[]
                     {
                         "README.md",
                         "INITIAL_AGENT_PROMPT.md",
                         "GDD.md",
                         "UNITY_BENCHMARK_TOOL_GUIDE.md",
                         "UNITY_OFFLINE_AGENT_MANUAL.md",
                         "BENCHMARK_MANIFEST.json",
                         "ASSET_MANIFEST.json",
                         "ASSET_CATALOG.json",
                         "ASSET_CATALOG.md",
                         "ASSET_COVERAGE.json",
                         "ASSET_CONTACT_SHEET.png"
                     })
            {
                Assert.That(File.Exists(Path.Combine(root, name)), Is.True,
                    $"Missing canonical Agent input file: {name}");
            }
        }

        [Test]
        public void PUBLIC04_PublicContractVersionAndMainArtifactAreFrozen()
        {
            Assert.That(DungeonDuelContractConstants.ContractVersion, Is.EqualTo("2.0"));
            Assert.That(DungeonDuelContractConstants.MainScenePath,
                Is.EqualTo("Assets/DungeonDuelBenchmark/Scenes/DungeonDuel.unity"));
        }

        [Test]
        public void PUBLIC05_CanonicalSceneCanBeDeserializedAndOpened()
        {
            var scene = EditorSceneManager.OpenScene(
                DungeonDuelContractConstants.MainScenePath,
                OpenSceneMode.Single);

            Assert.That(scene.IsValid(), Is.True,
                "The canonical Scene must deserialize into a valid Unity Scene.");
            Assert.That(scene.isLoaded, Is.True,
                "The canonical Scene must be loaded after it is opened.");
            Assert.That(scene.path,
                Is.EqualTo(DungeonDuelContractConstants.MainScenePath),
                  "Unity opened a Scene other than the canonical benchmark Scene.");
        }

        [Test]
        public void PUBLIC06_CanonicalSceneRetainsSuppliedArenaPresentation()
        {
            var scene = EditorSceneManager.OpenScene(
                DungeonDuelContractConstants.MainScenePath,
                OpenSceneMode.Single);

            var renderers = Resources.FindObjectsOfTypeAll<MeshRenderer>()
                .Where(renderer => renderer.gameObject.scene == scene &&
                    renderer.enabled &&
                    renderer.GetComponent<MeshFilter>() != null &&
                    renderer.sharedMaterials.Any(material => material != null))
                .ToArray();
            var environmentRenderers = renderers.Where(renderer =>
                IsSuppliedEnvironmentName(renderer.gameObject.name)).ToArray();
            var cameras = Resources.FindObjectsOfTypeAll<Camera>()
                .Count(camera => camera.gameObject.scene == scene && camera.enabled);
            var lights = Resources.FindObjectsOfTypeAll<Light>()
                .Count(light => light.gameObject.scene == scene && light.enabled);

            Assert.That(cameras, Is.GreaterThanOrEqualTo(1),
                "The supplied arena must retain a playable camera.");
            Assert.That(lights, Is.GreaterThanOrEqualTo(1),
                "The supplied arena must retain scene lighting.");
            Assert.That(renderers.Length, Is.GreaterThanOrEqualTo(12),
                "The canonical Scene must retain meaningful supplied arena geometry; " +
                "a small primitive-only graybox is not sufficient feedback.");
            Assert.That(environmentRenderers.Length, Is.GreaterThanOrEqualTo(8),
                "The canonical Scene must retain recognizable supplied environment " +
                "geometry such as walls, floors, gates, banners or props.");
        }

        static bool IsSuppliedEnvironmentName(string name)
        {
            return name.StartsWith("env_", System.StringComparison.OrdinalIgnoreCase) ||
                name.StartsWith("wall", System.StringComparison.OrdinalIgnoreCase) ||
                name.StartsWith("floor", System.StringComparison.OrdinalIgnoreCase) ||
                name.StartsWith("banner", System.StringComparison.OrdinalIgnoreCase) ||
                name.StartsWith("lava", System.StringComparison.OrdinalIgnoreCase) ||
                name.StartsWith("pebbles", System.StringComparison.OrdinalIgnoreCase) ||
                name.StartsWith("spawn_door", System.StringComparison.OrdinalIgnoreCase) ||
                name.Equals("BossGate", System.StringComparison.OrdinalIgnoreCase);
        }
    }
}
