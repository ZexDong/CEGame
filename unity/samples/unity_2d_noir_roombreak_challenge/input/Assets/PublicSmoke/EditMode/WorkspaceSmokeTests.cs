using System.IO;
using NUnit.Framework;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace GameCreate.Benchmark.NoirRoombreak.PublicSmoke.EditMode
{
    public sealed class WorkspaceSmokeTests
    {
        [Test]
        public void StarterSceneAndSuppliedAssetsAreReadable()
        {
            const string scenePath = "Assets/NoirStarter/Scenes/NoirStarter.unity";
            Assert.That(File.Exists(scenePath), Is.True, "The saved starter Scene is missing.");
            Assert.DoesNotThrow(() => EditorSceneManager.OpenScene(scenePath, OpenSceneMode.Single));
            Assert.That(Object.FindFirstObjectByType<Camera>(), Is.Not.Null);
            Assert.That(AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/TaskAssets/NoirSource/Sprites/Player/Idle.png"), Is.Not.Null);
            Assert.That(AssetDatabase.LoadAssetAtPath<AudioClip>("Assets/TaskAssets/NoirSource/Audio/Player/Jump.wav"), Is.Not.Null);
            Assert.That(AssetDatabase.LoadAssetAtPath<GameObject>("Assets/TaskAssets/NoirSource/Prefabs/Enemies/Anda.prefab"), Is.Not.Null);
        }
    }
}
