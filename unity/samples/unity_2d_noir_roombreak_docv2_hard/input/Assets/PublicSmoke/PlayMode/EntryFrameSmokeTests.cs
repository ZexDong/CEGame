using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.Benchmark.NoirRoombreak.PublicSmoke.PlayMode
{
    public sealed class EntryFrameSmokeTests
    {
        [UnityTest]
        public IEnumerator FirstEnabledBuildSceneProducesARealFrame()
        {
            AsyncOperation load = SceneManager.LoadSceneAsync(0, LoadSceneMode.Single);
            while (!load.isDone) yield return null;
            yield return null;
            yield return null;
            Assert.That(SceneManager.GetActiveScene().isLoaded, Is.True);
            Assert.That(Camera.main, Is.Not.Null);
        }
    }
}
