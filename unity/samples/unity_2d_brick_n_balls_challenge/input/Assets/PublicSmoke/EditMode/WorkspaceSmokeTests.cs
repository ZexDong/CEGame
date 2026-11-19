using System.IO;
using NUnit.Framework;
using UnityEditor;
using UnityEditor.SceneManagement;

namespace OmniGame.Benchmark.BrickChallenge.PublicSmoke.EditMode
{
    public sealed class WorkspaceSmokeTests
    {
        [Test]
        public void EntrySceneAndSuppliedAssetsAreReadable()
        {
            const string scenePath = "Assets/Scenes/BrickChallenge.unity";
            Assert.That(File.Exists(scenePath), Is.True, "The saved entry Scene is missing.");
            Assert.That(EditorBuildSettings.scenes.Length, Is.GreaterThanOrEqualTo(1));
            Assert.That(EditorBuildSettings.scenes[0].path, Is.EqualTo(scenePath));
            Assert.DoesNotThrow(() => EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single));
            Assert.That(AssetDatabase.FindAssets("t:Sprite", new[] { "Assets/TaskAssets" }).Length, Is.GreaterThanOrEqualTo(9));
            Assert.That(AssetDatabase.FindAssets("t:AudioClip", new[] { "Assets/TaskAssets" }).Length, Is.GreaterThanOrEqualTo(6));
        }
    }
}
