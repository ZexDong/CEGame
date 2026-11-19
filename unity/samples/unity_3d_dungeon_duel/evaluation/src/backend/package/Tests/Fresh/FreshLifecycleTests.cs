using System;
using System.Collections;
using System.Diagnostics;
using System.IO;
using NUnit.Framework;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    /// <summary>
    /// Evaluator-health prerequisites for the independent Fresh Unity process.
    /// Any failure in these protected probes invalidates the run rather than
    /// being attributed to candidate gameplay.
    /// </summary>
    [TestFixture]
    public sealed class FreshEvaluatorHealthPrerequisiteTests
    {
        [Test, Order(-120)]
        public void EVALUATOR_HEALTH_Fresh_ProcessIsolationAndEvidenceSink()
        {
            string phase = EvaluatorHealthArtifactWriter.FindCommandLineValue(
                "-omnigameEvaluatorPhase");
            string priorText = EvaluatorHealthArtifactWriter.FindCommandLineValue(
                "-omnigamePriorProcessId");
            Assert.That(phase, Is.EqualTo("Fresh").IgnoreCase,
                "Fresh evaluator health did not receive its protected phase identity.");
            Assert.That(int.TryParse(priorText, out int priorProcessId) &&
                        priorProcessId > 0, Is.True,
                "Fresh evaluator health did not receive the Dynamic process ID.");
            int current = Process.GetCurrentProcess().Id;
            Assert.That(current, Is.Not.EqualTo(priorProcessId),
                "Fresh must execute in a completely independent Unity process.");
            string path = EvaluatorHealthArtifactWriter.Write(
                "fresh", priorProcessId);
            Assert.That(File.Exists(path), Is.True,
                "Fresh evaluator health could not write protected evidence.");
        }

        [UnityTest, Order(-110)]
        public IEnumerator EVALUATOR_HEALTH_Fresh_UiProbeLoadsInIndependentAssembly()
        {
            // Keep the evaluator fixture in an isolated temporary Scene.  The
            // candidate HUD is deliberately present in the Fresh process, so
            // scanning the active candidate Scene here can select its
            // legitimate Player 120/120 label instead of this test's 10/10
            // fixture and falsely report evaluator-health failure.
            Scene fixtureScene = SceneManager.CreateScene(
                "FreshEvaluatorHealthFixture");
            Canvas canvas = new GameObject(
                "Fresh Evaluator Health HUD", typeof(Canvas)).GetComponent<Canvas>();
            UnityEngine.SceneManagement.SceneManager.MoveGameObjectToScene(
                canvas.gameObject, fixtureScene);
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            GameObject item = new GameObject(
                "Fresh Evaluator Health Text", typeof(RectTransform),
                typeof(CanvasRenderer), typeof(Text));
            item.transform.SetParent(canvas.transform, false);
            RectTransform rect = item.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0f, 1f);
            rect.pivot = new Vector2(0f, 1f);
            rect.anchoredPosition = new Vector2(20f, -20f);
            rect.sizeDelta = new Vector2(500f, 40f);
            Text text = item.GetComponent<Text>();
            text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            text.fontSize = 20;
            text.color = Color.white;
            text.text = "Player Health 10 / 10";
            yield return null;

            UiSemanticSnapshot ui = UiSemanticProbe.Capture(
                fixtureScene);
            bool parsed = UiSemanticProbe.TryReadPlayerHealth(
                ui, out float health, out float maximum, out string observation);
            Object.Destroy(canvas.gameObject);
            yield return null;
            yield return UnityEngine.SceneManagement.SceneManager.UnloadSceneAsync(
                fixtureScene);

            Assert.That(parsed, Is.True, observation);
            Assert.That(health, Is.EqualTo(10f).Within(0.1f));
            Assert.That(maximum, Is.EqualTo(10f).Within(0.1f));
        }
    }

    [TestFixture]
    public sealed class FreshLifecycleTests
    {
        [UnityTest, Order(10)]
        public IEnumerator FRESH01_ReopensIntoFreshEncounter()
        {
            var recorder = new TrajectoryRecorder("fresh_reopen");
            var harness = new DungeonDuelTrajectoryHarness();

            // This is intentionally a natural load in a brand-new Unity
            // process. No evaluator state mutation is available, so persisted
            // candidate progress cannot be concealed.
            yield return harness.LoadFresh(
                DungeonDuelTrajectoryIntent.CanonicalSuccess,
                recorder, "setup", "setup");

            DungeonDuelGameSnapshot initial = harness.Snapshot();
            Check(recorder, "fresh", "fresh.phase.playing",
                initial != null && initial.Phase == DungeonDuelGamePhase.Playing,
                "active Playing phase", recorder.Snapshot(initial),
                "Fresh reopened into a terminal or unusable phase.");
            Check(recorder, "fresh", "fresh.player.full_health",
                initial != null && initial.Player != null &&
                !initial.Player.IsDead &&
                Mathf.Abs(initial.Player.Health - initial.Player.MaxHealth) <= 0.01f,
                "one healthy Player at maximum health",
                recorder.Snapshot(initial?.Player),
                "Fresh retained damaged/dead Player progress.");
            Check(recorder, "fresh", "fresh.imps.two_alive",
                initial != null && initial.ImpsAlive == 2 &&
                !initial.ImpA.IsDead && !initial.ImpB.IsDead,
                "exactly two living Imps", recorder.Snapshot(initial),
                "Fresh retained enemy-death progress.");
            Check(recorder, "fresh", "fresh.boss.dormant",
                initial != null && initial.Boss != null &&
                !initial.Boss.IsDead && initial.Boss.IsDormant,
                "living dormant Boss", recorder.Snapshot(initial?.Boss),
                "Fresh retained an active/dead Boss state.");
            Check(recorder, "fresh", "fresh.gate.closed",
                initial != null && !initial.GateOpen,
                "closed Boss gate", recorder.Snapshot(initial),
                "Fresh retained an opened Boss gate.");
            Check(recorder, "fresh", "fresh.gate.blocking",
                initial != null && initial.GateBlocking,
                "physical non-trigger gate collider blocks",
                recorder.Snapshot(initial),
                "Fresh gate is not physically blocking.");
            Check(recorder, "fresh", "fresh.dash.ready",
                initial != null && initial.DashCooldownRemaining <= 0.05f,
                "Dash ready with no retained cooldown",
                initial == null ? "null" :
                    initial.DashCooldownRemaining.ToString("F2"),
                "Fresh retained a spent Dash cooldown.");

            DungeonDuelTrajectoryHarness.AudioSemanticState audio =
                harness.CaptureAudioState();
            Check(recorder, "fresh", "fresh.audio.battle_loop",
                audio.HasLoopingBattle,
                "native looping battle audio restored",
                audio.ToString(),
                "Fresh did not restore the active battle-audio state.");

            if (!recorder.HasFailure)
            {
                yield return harness.ValidateHudSemantics(
                    initial, HudSemanticState.Initial, recorder,
                    "fresh", "fresh.hud.neutral");
            }

            yield return WaitRealtime(0.5f);
            DungeonDuelGameSnapshot stable = harness.Snapshot();
            Check(recorder, "stable", "fresh.stable.flow01",
                IsFlow01(stable),
                "stable FLOW-01 after an independent process delay",
                recorder.Snapshot(stable),
                "Fresh state changed back to stale progress after loading.");

            yield return harness.Dispose();
            Assert.That(recorder.Complete(), Is.True,
                "Independent Fresh lifecycle failed; inspect fresh_reopen.json.");
        }

        static bool IsFlow01(DungeonDuelGameSnapshot snapshot) =>
            snapshot != null && snapshot.Phase == DungeonDuelGamePhase.Playing &&
            snapshot.Player != null && !snapshot.Player.IsDead &&
            Mathf.Abs(snapshot.Player.Health - snapshot.Player.MaxHealth) <= 0.01f &&
            snapshot.ImpsAlive == 2 && !snapshot.ImpA.IsDead && !snapshot.ImpB.IsDead &&
            snapshot.Boss != null && !snapshot.Boss.IsDead && snapshot.Boss.IsDormant &&
            !snapshot.GateOpen && snapshot.GateBlocking &&
            snapshot.DashCooldownRemaining <= 0.05f &&
            snapshot.BattleMusicPlaying;

        static void Check(
            TrajectoryRecorder recorder,
            string stepId,
            string checkId,
            bool condition,
            string expected,
            string observed,
            string failure)
        {
            if (condition)
                recorder.Pass(stepId, checkId, expected, observed);
            else
                recorder.Fail(stepId, checkId, expected, observed, failure);
        }

        static IEnumerator WaitRealtime(float seconds)
        {
            float until = Time.realtimeSinceStartup + seconds;
            while (Time.realtimeSinceStartup < until) yield return null;
        }
    }
}

