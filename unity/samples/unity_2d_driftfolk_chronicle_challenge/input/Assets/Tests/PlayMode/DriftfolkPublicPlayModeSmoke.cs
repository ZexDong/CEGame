// Published NUnit filter: GameCreate.Stormbound.PublicSmoke.StormboundPublicPlayModeSmoke
using System;
using System.Collections;
using System.IO;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.Stormbound.PublicSmoke
{
    public sealed class StormboundPublicPlayModeSmoke
    {
        [Serializable] sealed class Manifest
        {
            public string starter_scene;
            public string required_final_scene;
        }

        [UnityTest]
        public IEnumerator PUB_PLAY_01_SavedEntryAdvancesRealFramesWithCamera()
        {
            Time.timeScale = 1;
            var root = Path.GetDirectoryName(Application.dataPath);
            Assert.IsNotNull(root);
            var manifest = JsonUtility.FromJson<Manifest>(File.ReadAllText(Path.Combine(root, "BENCHMARK_MANIFEST.json")));
            var path = File.Exists(Path.Combine(root, manifest.required_final_scene))
                ? manifest.required_final_scene : manifest.starter_scene;
            Assert.IsTrue(Application.CanStreamedLevelBeLoaded(path), "Enable the saved entry in Build Settings.");
            var load = SceneManager.LoadSceneAsync(path, LoadSceneMode.Single);
            Assert.IsNotNull(load);
            var deadline = Time.realtimeSinceStartupAsDouble + 15;
            while (!load.isDone && Time.realtimeSinceStartupAsDouble < deadline) yield return null;
            Assert.IsTrue(load.isDone, "Saved entry did not load within 15 seconds.");
            var frame = Time.frameCount;
            yield return null;
            yield return null;
            Assert.That(Time.frameCount, Is.GreaterThan(frame));
            Assert.IsTrue(UnityEngine.Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Any(camera => camera.isActiveAndEnabled), "Saved entry needs an active camera.");
        }
    }
}
