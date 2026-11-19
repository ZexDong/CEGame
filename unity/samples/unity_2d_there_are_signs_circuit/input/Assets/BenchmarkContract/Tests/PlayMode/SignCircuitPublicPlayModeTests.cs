using System.Collections;
using System.Collections.Generic;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.SignCircuit.PublicTests
{
    public sealed class SignCircuitPublicPlayModeTests
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
        public IEnumerator PUBLIC_PLAY_01_SceneFramesCameraAndRuntimeLogAreHealthy()
        {
            Assert.That(Application.CanStreamedLevelBeLoaded(
                "Assets/Scenes/Benchmark/SignCircuit.unity"), Is.True);
            AsyncOperation load = SceneManager.LoadSceneAsync(
                "Assets/Scenes/Benchmark/SignCircuit.unity", LoadSceneMode.Single);
            while (!load.isDone) yield return null;

            // Let Awake, Start, Update, and delayed first-frame work execute. A blocking
            // sleep or immediate enter/exit is not a runtime startup smoke.
            for (int frame = 0; frame < 20; frame++) yield return null;

            Scene activeScene = SceneManager.GetActiveScene();
            Assert.That(activeScene.IsValid() && activeScene.isLoaded, Is.True);
            Assert.That(activeScene.path, Is.EqualTo(
                "Assets/Scenes/Benchmark/SignCircuit.unity"));
            Assert.That(Camera.allCamerasCount, Is.GreaterThan(0));
            Assert.That(runtimeErrors, Is.Empty,
                "The saved Sign Circuit starter logged blocking errors/exceptions " +
                "during real PlayMode frames:\n" + string.Join("\n---\n", runtimeErrors));
        }

        void CaptureRuntimeError(string condition, string stackTrace, LogType type)
        {
            if (type != LogType.Error &&
                type != LogType.Exception &&
                type != LogType.Assert)
            {
                return;
            }

            // Offline host certificate diagnostics are independent of the saved
            // candidate Scene and are classified by CLI/host health instead.
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