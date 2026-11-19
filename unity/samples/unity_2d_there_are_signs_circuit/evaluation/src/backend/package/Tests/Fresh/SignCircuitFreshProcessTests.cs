using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using NUnit.Framework;
using OmniGame.Benchmark.SignCircuit.Contract;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    [TestFixture]
    public sealed class SignCircuitFreshProcessTests
    {
        const string MainScenePath =
            "Assets/Scenes/Benchmark/SignCircuit.unity";
        [UnityTest]
        public IEnumerator FRESH01_BestTimeSurvivesFreshProcess()
        {
            string outputDirectory = ReadArgument("-signCircuitEvidenceOutput");
            Assert.That(string.IsNullOrWhiteSpace(outputDirectory), Is.False,
                "Fresh-process evidence output argument is missing.");
            string seedPath = Path.Combine(outputDirectory, "fresh-seed.json");
            if (!File.Exists(seedPath))
            {
                Assert.Fail("[OMNIGAME_CANDIDATE_BLOCKED] Canonical success did not " +
                            "produce fresh-seed.json; fresh-process persistence scoring " +
                            "is blocked by a missing candidate prerequisite.");
            }
            FreshSeed seed = JsonUtility.FromJson<FreshSeed>(File.ReadAllText(seedPath));
            Assert.That(seed, Is.Not.Null);
            string evaluationSessionId = ReadArgument("-signCircuitEvaluationSession");
            Assert.That(evaluationSessionId, Is.Not.Empty,
                "Fresh-process evaluation session id is missing.");
            Assert.That(seed.evaluation_session_id, Is.EqualTo(evaluationSessionId),
                "The dynamic-process seed belongs to a different evaluation session.");
            Assert.That(TryParseNumber(seed.best_time_number, out double expected), Is.True,
                "The dynamic-process best-time seed has no numeric value.");
            int processId = System.Diagnostics.Process.GetCurrentProcess().Id;
            Assert.That(seed.source_process_id, Is.Not.EqualTo(processId),
                "Fresh verification ran in the same Unity process as canonical success.");
            Assert.That(seed.company_name, Is.EqualTo(Application.companyName));
            Assert.That(seed.product_name, Is.EqualTo(Application.productName));
            Assert.That(seed.persistent_data_path, Is.EqualTo(Application.persistentDataPath));
            Assert.That(seed.persisted_record, Is.Not.Null,
                "Canonical success did not identify a real persisted record.");

            SignCircuitPersistenceSnapshot freshBacking =
                SignCircuitPersistenceProbe.Capture();
            SignCircuitPersistenceRecord survivingRecord =
                SignCircuitPersistenceProbe.FindMatchingRecord(
                    freshBacking, seed.persisted_record);
            Assert.That(survivingRecord, Is.Not.Null,
                "Before loading the candidate scene in the fresh process, the exact " +
                "durable record selected after canonical success was absent or changed. " +
                "The record representation is intentionally not required to equal seconds.");

            Assert.That(Application.CanStreamedLevelBeLoaded(MainScenePath), Is.True,
                $"Canonical scene is not enabled and loadable: {MainScenePath}");
            Time.timeScale = 1f;
            AsyncOperation load = SceneManager.LoadSceneAsync(
                MainScenePath, LoadSceneMode.Single);
            Assert.That(load, Is.Not.Null);
            float loadDeadline = Time.realtimeSinceStartup + 15f;
            while (!load.isDone && Time.realtimeSinceStartup < loadDeadline)
            {
                yield return null;
            }
            Assert.That(load.isDone, Is.True, "Fresh-process scene load timed out.");

            string bestText = null;
            double actual = 0d;
            SignCircuitSnapshot latestProbeSnapshot = default;
            bool hasProbeSnapshot = false;
            int freshProgress = -1;
            float freshTimer = -1f;
            string freshStatus = null;
            string freshTimerSource = null;
            string freshStatusSource = null;
            float displayDeadline = Time.realtimeSinceStartup + 4f;
            while (Time.realtimeSinceStartup < displayDeadline)
            {
                if (SignCircuitProbeReader.TryRead(out SignCircuitSnapshot snapshot) &&
                    string.Equals(snapshot.scene, "circuit", StringComparison.OrdinalIgnoreCase))
                {
                    latestProbeSnapshot = snapshot;
                    hasProbeSnapshot = true;
                }
                if (SignCircuitSemanticUiObserver.TryReadBest(
                        out string candidateText, out double candidateValue,
                        out bool hasNumericBest, out _) && hasNumericBest &&
                    SignCircuitSemanticUiObserver.TryReadProgress(
                        out int visibleProgress, out _) &&
                    SignCircuitSemanticUiObserver.TryReadTimer(
                        out float visibleTimer, out string timerSource) &&
                    SignCircuitSemanticUiObserver.TryReadStatus(
                        out string visibleStatus, out string statusSource))
                {
                    actual = candidateValue;
                    bestText = candidateText;
                    freshProgress = visibleProgress;
                    freshTimer = visibleTimer;
                    freshStatus = visibleStatus;
                    freshTimerSource = timerSource;
                    freshStatusSource = statusSource;
                    break;
                }
                yield return null;
            }

            if (bestText == null)
            {
                Assert.Fail("[OMNIGAME_CANDIDATE_FEATURE_MISSING] The fresh process did " +
                            "not expose a numeric best-time value through ui.best overlapping " +
                            "real visible UI. Probe values cannot substitute for visible UI.");
            }
            Assert.That(actual, Is.EqualTo(expected).Within(0.02d),
                "The visible best time changed or disappeared across Unity processes.");
            Assert.That(freshProgress, Is.GreaterThanOrEqualTo(0),
                "The fresh process exposed no independently readable progress HUD.");
            Assert.That(freshProgress, Is.EqualTo(0),
                "Ordinary visible run progress leaked into the fresh process.");
            Assert.That(freshTimer, Is.InRange(25.5f, 30.1f),
                "The fresh process did not reopen on a clean near-30-second run.");
            Assert.That(string.IsNullOrWhiteSpace(freshStatus), Is.False,
                "The fresh process exposed no independently readable status field.");
            Assert.That(SignCircuitSemanticUiObserver.AnyStatePanelVisible(), Is.False,
                "The fresh Game view still displayed a semantic pause/success/failure panel.");

            bool staleProbeBestHint = !hasProbeSnapshot ||
                !latestProbeSnapshot.hudVisible || !latestProbeSnapshot.hasBestTime ||
                Math.Abs(latestProbeSnapshot.bestTimeSeconds - actual) > 0.02d;
            bool staleProbeProgressHint = !hasProbeSnapshot ||
                !latestProbeSnapshot.hudVisible ||
                latestProbeSnapshot.progress != freshProgress;
            bool staleProbeTimerHint = !hasProbeSnapshot ||
                !latestProbeSnapshot.hudVisible ||
                Math.Abs(latestProbeSnapshot.remainingSeconds - freshTimer) > 0.15d;
            bool staleProbePanelHint = hasProbeSnapshot &&
                (latestProbeSnapshot.successVisible ||
                 latestProbeSnapshot.failureVisible || latestProbeSnapshot.pauseVisible);

            SignCircuitEvidenceWriter.WriteFreshResult(
                nameof(FRESH01_BestTimeSurvivesFreshProcess),
                expected,
                actual,
                bestText,
                survivingRecord,
                true,
                new[]
                {
                    "fresh_process_pid=" + processId,
                    "dynamic_process_pid=" + seed.source_process_id,
                    "visible_best_time=" + bestText,
                    "visible_progress=" + freshProgress + "/3",
                    "visible_timer=" + freshTimer.ToString("F2",
                        CultureInfo.InvariantCulture),
                    "visible_timer_source=" + freshTimerSource,
                    "visible_status=" + freshStatus,
                    "visible_status_source=" + freshStatusSource,
                    "probe_best_time_hint=" +
                        (hasProbeSnapshot && latestProbeSnapshot.hasBestTime
                            ? latestProbeSnapshot.bestTimeSeconds.ToString("F2",
                                CultureInfo.InvariantCulture)
                            : "<unavailable>"),
                    "stale_probe_best_hint=" +
                        staleProbeBestHint.ToString().ToLowerInvariant(),
                    "probe_progress_hint=" +
                        (hasProbeSnapshot
                            ? latestProbeSnapshot.progress + "/3"
                            : "<unavailable>"),
                    "stale_probe_progress_hint=" +
                        staleProbeProgressHint.ToString().ToLowerInvariant(),
                    "probe_timer_hint=" +
                        (hasProbeSnapshot
                            ? latestProbeSnapshot.remainingSeconds.ToString("F2",
                                CultureInfo.InvariantCulture)
                            : "<unavailable>"),
                    "stale_probe_timer_hint=" +
                        staleProbeTimerHint.ToString().ToLowerInvariant(),
                    "stale_probe_panel_hint=" +
                        staleProbePanelHint.ToString().ToLowerInvariant(),
                    "terminal_panels_hidden=true",
                    "durable_record=" + survivingRecord.id,
                    "durable_fingerprint=" + survivingRecord.fingerprint_sha256,
                    "backing_checked_before_scene_load=true"
                });
        }

        static bool TryParseNumber(string value, out double number)
        {
            Match match = Regex.Match(value ?? string.Empty, @"\d+(?:[\.,]\d+)?");
            return double.TryParse(
                match.Success ? match.Value.Replace(',', '.') : string.Empty,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out number);
        }

        static string ReadArgument(string key)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], key,
                        StringComparison.OrdinalIgnoreCase))
                {
                    return args[index + 1].Trim('"');
                }
            }
            return string.Empty;
        }

        [Serializable]
        sealed class FreshSeed
        {
            public string evaluation_session_id;
            public string best_time_number;
            public int source_process_id;
            public string company_name;
            public string product_name;
            public string persistent_data_path;
            public SignCircuitPersistenceRecord persisted_record;
        }

    }
}
