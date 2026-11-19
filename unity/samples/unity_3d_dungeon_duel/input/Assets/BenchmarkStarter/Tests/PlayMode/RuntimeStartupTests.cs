using System.Collections;
using System.Collections.Generic;
using NUnit.Framework;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.DungeonDuel.PublicRuntimeSmoke
{
    public sealed class RuntimeStartupTests
    {
        readonly List<string> runtimeErrors = new List<string>();

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            runtimeErrors.Clear();
            Application.logMessageReceived += CaptureRuntimeError;
            Time.timeScale = 1f;
            yield return null;
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            Application.logMessageReceived -= CaptureRuntimeError;
            Time.timeScale = 1f;
            yield return null;
        }

        [UnityTest]
        public IEnumerator RUNTIME01_CanonicalSceneRunsRealFirstFramesWithoutErrors()
        {
            AsyncOperation load = SceneManager.LoadSceneAsync(
                DungeonDuelContractConstants.MainScenePath,
                LoadSceneMode.Single);

            Assert.That(load, Is.Not.Null,
                "The saved canonical Scene must be loadable in Play Mode.");
            while (!load.isDone)
            {
                yield return null;
            }

            // Yield real player-loop frames. A blocking Editor sleep loop is not a
            // PlayMode check and cannot reveal Awake/Start/Update failures.
            for (int frame = 0; frame < 20; frame++)
            {
                yield return null;
            }

            Scene scene = SceneManager.GetActiveScene();
            Assert.That(scene.IsValid() && scene.isLoaded, Is.True,
                "The canonical Scene did not remain loaded during Play Mode.");
            Assert.That(scene.path,
                Is.EqualTo(DungeonDuelContractConstants.MainScenePath));
            Assert.That(runtimeErrors, Is.Empty,
                "The first real PlayMode frames logged blocking errors/exceptions:\n" +
                string.Join("\n---\n", runtimeErrors));
        }

        void CaptureRuntimeError(string condition, string stackTrace, LogType type)
        {
            if (type != LogType.Error &&
                type != LogType.Exception &&
                type != LogType.Assert)
            {
                return;
            }

            // Package-manager certificate diagnostics can be emitted by this offline
            // host independently of candidate gameplay. They belong to CLI/host health,
            // not the candidate's first-frame runtime result.
            if (condition.Contains("Curl error 35") ||
                condition.Contains("Cert verify failed") ||
                condition.Contains("UnityTls error code"))
            {
                return;
            }

            runtimeErrors.Add(condition + "\n" + stackTrace);
        }
    }
}
