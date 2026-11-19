using System.Collections;
using System.IO;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.Benchmark.Undercooked.PublicSmoke
{
    public sealed class UndercookedPublicPlayModeSmoke
    {
        private const string StarterScene = "Assets/UndercookedStarter/Scenes/KitchenStarter.unity";
        private const string FinalScene = "Assets/UndercookedChallenge/Scenes/UndercookedKitchen.unity";

        [UnityTest]
        public IEnumerator PUB_PLAY_01_SavedEntryAdvancesRealFramesWithCamera()
        {
            var projectRoot = Directory.GetParent(Application.dataPath)?.FullName;
            Assert.NotNull(projectRoot);
            var finalAbsolute = Path.Combine(projectRoot, FinalScene.Replace('/', Path.DirectorySeparatorChar));
            var path = File.Exists(finalAbsolute) ? FinalScene : StarterScene;
            var load = SceneManager.LoadSceneAsync(path, LoadSceneMode.Single);
            Assert.NotNull(load);
            var deadline = Time.realtimeSinceStartup + 15f;
            while (!load.isDone && Time.realtimeSinceStartup < deadline) yield return null;
            Assert.That(load.isDone, Is.True, "Saved entry did not load within 15 seconds.");
            var frame = Time.frameCount;
            yield return null;
            yield return null;
            Assert.That(Time.frameCount, Is.GreaterThan(frame));
            Assert.That(Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Any(camera => camera.isActiveAndEnabled), Is.True, "Saved entry has no active camera.");
        }
    }
}
