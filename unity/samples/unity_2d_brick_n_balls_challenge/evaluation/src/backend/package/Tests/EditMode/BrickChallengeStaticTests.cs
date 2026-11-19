using System.IO;
using System.Linq;
using System.Security.Cryptography;
using NUnit.Framework;
using OmniGame.Benchmark.BrickChallenge.Contracts;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace OmniGame.Benchmark.BrickChallenge.Evaluator.EditMode
{
    public sealed class BrickChallengeStaticTests
    {
        [Test]
        public void D1_EntrySceneAndBuildSettings_5()
        {
            const string path = "Assets/Scenes/BrickChallenge.unity";
            Assert.That(File.Exists(path), Is.True);
            Assert.That(EditorBuildSettings.scenes.Any(scene => scene.enabled && scene.path == path), Is.True);
            Assert.DoesNotThrow(() => EditorSceneManager.OpenScene(path, OpenSceneMode.Single));
        }

        [Test]
        public void D1_CompilableProbeImplementationAndMedia_5()
        {
            bool implementation = TypeCache.GetTypesDerivedFrom<MonoBehaviour>()
                .Any(type => typeof(IBrickChallengeProbe).IsAssignableFrom(type) && !type.IsAbstract);
            Assert.That(implementation, Is.True, "No concrete public read-only probe implementation was found.");
            Assert.That(AssetDatabase.FindAssets("t:Sprite", new[] { "Assets/TaskAssets" }).Length, Is.GreaterThanOrEqualTo(9));
            Assert.That(AssetDatabase.FindAssets("t:AudioClip", new[] { "Assets/TaskAssets" }).Length, Is.GreaterThanOrEqualTo(6));
            AssertSha256("Assets/TaskAssets/Resources/BrickChallenge/Audio/Ball_Lost.wav", "c3c57af2e0866acd3311635b79f904e644c2768b72e34b22a1bff743036ee3a0");
            AssertSha256("Assets/TaskAssets/Resources/BrickChallenge/Audio/Ball_Shoot.wav", "86fc2b84137556f65b94d0da80de210459852ad61ffd1f107119d2bde761564f");
            AssertSha256("Assets/TaskAssets/Resources/BrickChallenge/Audio/Brick_Destroyed.wav", "4e2dea62e5804b066383dd78b918e8cc3ba200f76253fab4ff03108ab2448a95");
            AssertSha256("Assets/TaskAssets/Resources/BrickChallenge/Audio/Brick_Hit.wav", "d64bd3aceaa02973315be0dd9b79d8f5bb4b75cbc4d685c627774c3cfb5653c3");
            AssertSha256("Assets/TaskAssets/Resources/BrickChallenge/Audio/Button_Clicked.wav", "8e426e7ee324faa86c6043cb82afdcb4a62f15d7c5549466be1bfe4ca1c929b9");
            AssertSha256("Assets/TaskAssets/Resources/BrickChallenge/Audio/Wall_Hit.wav", "75cc4bbd314a13b6bc988b2ce367bd0f5fb1290769199bc5240dbcfb4739a66d");
        }

        private static void AssertSha256(string path, string expected)
        {
            Assert.That(File.Exists(path), Is.True, "Missing protected supplied asset: " + path);
            using (SHA256 sha = SHA256.Create())
            {
                string actual = System.BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(path))).Replace("-", string.Empty).ToLowerInvariant();
                Assert.That(actual, Is.EqualTo(expected), "Protected supplied asset changed: " + path);
            }
        }
    }
}
