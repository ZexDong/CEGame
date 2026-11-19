using System.Linq;
using NUnit.Framework;
using OmniGame.Benchmark.SignCircuit.Contract;
using UnityEditor;
using UnityEngine;

namespace OmniGame.Benchmark.SignCircuit.PublicTests
{
    public sealed class SignCircuitPublicEditModeTests
    {
        [Test]
        public void PUBLIC_EDIT_01_ContractAndScenesAreAvailable()
        {
            Assert.That(Application.unityVersion, Is.EqualTo("6000.0.80f1"));
            Assert.That(SignCircuitSnapshot.CurrentSchemaVersion, Is.EqualTo(2));
            Assert.That(typeof(SignCircuitProbeReader).GetMethod(
                nameof(SignCircuitProbeReader.TryGetObservationTarget)), Is.Not.Null);
            Assert.That(AssetDatabase.LoadAssetAtPath<SceneAsset>(
                "Assets/Scenes/Benchmark/SignCircuit.unity"), Is.Not.Null);
            Assert.That(AssetDatabase.LoadAssetAtPath<SceneAsset>(
                "Assets/Scenes/Menu.unity"), Is.Not.Null);
            Assert.That(AssetDatabase.LoadAssetAtPath<SceneAsset>(
                "Assets/Scenes/Levels/Level1+2.unity"), Is.Not.Null);

            string[] enabledScenes = EditorBuildSettings.scenes
                .Where(scene => scene.enabled)
                .Select(scene => scene.path)
                .ToArray();
            Assert.That(enabledScenes, Does.Contain(
                "Assets/Scenes/Benchmark/SignCircuit.unity"));
            Assert.That(enabledScenes, Does.Contain("Assets/Scenes/Menu.unity"));
            Assert.That(enabledScenes, Does.Contain(
                "Assets/Scenes/Levels/Level1+2.unity"));
        }

        [Test]
        public void PUBLIC_EDIT_02_DuplicateSemanticIdsAreRejected()
        {
            var snapshot = new SignCircuitSnapshot
            {
                scene = "contract-test",
                phase = "running",
                progress = 0,
                remainingSeconds = 30f,
                playerPosition = Vector2.zero
            };
            Rect rect = new Rect(10f, 10f, 100f, 40f);
            SignCircuitProbePublisher.Publish(snapshot, new[]
            {
                new SignCircuitActionTarget { id = "ui.restart", screenRect = rect },
                new SignCircuitActionTarget { id = "UI.RESTART", screenRect = rect }
            }, new[]
            {
                new SignCircuitObservationTarget { id = "ui.progress", screenRect = rect },
                new SignCircuitObservationTarget { id = "UI.PROGRESS", screenRect = rect }
            });

            Assert.That(SignCircuitProbeReader.TryGetActionTarget(
                "ui.restart", out _), Is.False);
            Assert.That(SignCircuitProbeReader.TryGetObservationTarget(
                "ui.progress", out _), Is.False);
        }
    }
}
