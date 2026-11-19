using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.BrickChallenge.PublicSmoke.PlayMode
{
    public sealed class EntryFrameSmokeTests
    {
        [UnityTest]
        public IEnumerator EntrySceneProducesARealFrame()
        {
            AsyncOperation load = SceneManager.LoadSceneAsync("BrickChallenge", LoadSceneMode.Single);
            while (!load.isDone) yield return null;
            yield return null;
            yield return null;
            Assert.That(SceneManager.GetActiveScene().name, Is.EqualTo("BrickChallenge"));
            Assert.That(Camera.main, Is.Not.Null);
        }
    }
}
