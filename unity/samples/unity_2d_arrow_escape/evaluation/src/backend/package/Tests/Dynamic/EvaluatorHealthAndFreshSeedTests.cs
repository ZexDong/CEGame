using System;
using System.Collections;
using System.IO;
using System.Linq;
using NUnit.Framework;
using OmniGame.Benchmark.ArrowEscape.V2;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    /// <summary>
    /// Evaluator health prerequisites are deliberately independent of candidate
    /// gameplay assertions. A failed HEALTH test means the evaluator run is
    /// invalid; it must never be converted into candidate score loss.
    /// </summary>
    [TestFixture]
    public sealed class EvaluatorHealthAndFreshSeedTests
    {
        [UnitySetUp]
        public IEnumerator EnsureFormalResolution()
        {
            yield return EvaluatorDisplayResolution.Ensure1280x720();
            Assert.That(EvaluatorDisplayResolution.IsCurrentExact, Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Dynamic health/seed runtime must execute " +
                "at real 1280x720; " + EvaluatorDisplayResolution.Diagnostic + ".");
        }

        [UnityTearDown]
        public IEnumerator RestoreFormalResolution()
        {
            EvaluatorDisplayResolution.Restore();
            yield return null;
        }

        [UnityTest]
        public IEnumerator EVALUATOR_HEALTH_DynamicInputProbeAndEvidenceWriter()
        {
            yield return LoadCanonicalScene();

            EventSystem[] candidateEventSystems = UnityEngine.Object
                .FindObjectsByType<EventSystem>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None);
            bool[] candidateEventSystemStates = candidateEventSystems
                .Select(item => item.gameObject.activeSelf).ToArray();
            foreach (EventSystem item in candidateEventSystems)
                item.gameObject.SetActive(false);
            var healthEventSystem = new GameObject(
                "Evaluator Health EventSystem", typeof(EventSystem),
                typeof(InputSystemUIInputModule));
            healthEventSystem.GetComponent<InputSystemUIInputModule>()
                .AssignDefaultActions();

            GameObject overlay = null;
            InputSystemPlayerDriver driver = null;
            overlay = CreateHealthOverlay(out GameObject target,
                out EvaluatorHealthClickTarget clickTarget);
            yield return null;

            bool discovered = ArrowEscapeTrajectoryHarness
                .DiscoverPhysicalArrowTargetsForEvaluatorHealth()
                .Any(item => item.PointerTarget == target);
            Assert.That(discovered, Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Physical visible probe could not discover its " +
                "evaluator-owned Graphic pointer target.");

            driver = new InputSystemPlayerDriver();
            var step = new TrajectoryStepEvidence
            {
                step_id = "health.dynamic.native_input",
                operation = "virtual_mouse_click"
            };
            yield return driver.Click(target, "health.dynamic.input", step);
            bool routePassed = step.checks.Count > 0 &&
                               step.checks.All(check => check.status == "pass");
            yield return driver.Dispose();
            driver = null;

            yield return null;
            yield return null;
            string output = TrajectoryEvidenceWriter.ResolveOutputDirectory();
            Directory.CreateDirectory(output);
            string screenshotPath = Path.Combine(output,
                "evaluator-health-dynamic.png");
            Camera camera = UnityEngine.Object.FindObjectsByType<Camera>(
                    FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
            Assert.That(camera, Is.Not.Null,
                "[OMNIGAME_EVALUATOR_HEALTH] No active camera was available for screenshot health.");
            var renderTexture = new RenderTexture(320, 180, 24,
                RenderTextureFormat.ARGB32);
            var texture = new Texture2D(320, 180, TextureFormat.RGB24, false);
            RenderTexture previousActive = RenderTexture.active;
            RenderTexture previousTarget = camera.targetTexture;
            byte[] png;
            try
            {
                camera.targetTexture = renderTexture;
                renderTexture.Create();
                camera.Render();
                RenderTexture.active = renderTexture;
                texture.ReadPixels(new Rect(0, 0, 320, 180), 0, 0, false);
                texture.Apply(false, false);
                png = texture.EncodeToPNG();
            }
            finally
            {
                camera.targetTexture = previousTarget;
                RenderTexture.active = previousActive;
                UnityEngine.Object.DestroyImmediate(texture);
                renderTexture.Release();
                UnityEngine.Object.DestroyImmediate(renderTexture);
            }
            File.WriteAllBytes(screenshotPath, png);

            string evidencePath = Path.Combine(output,
                "evaluator-health-dynamic.json");
            var evidence = new DynamicEvaluatorHealthEvidence
            {
                process_id = System.Diagnostics.Process.GetCurrentProcess().Id,
                screen_width = Screen.width,
                screen_height = Screen.height,
                required_width = EvaluatorDisplayResolution.RequiredWidth,
                required_height = EvaluatorDisplayResolution.RequiredHeight,
                resolution_exact = EvaluatorDisplayResolution.IsCurrentExact,
                configuration_route = EvaluatorDisplayResolution.ConfigurationRoute,
                visible_probe_discovered = discovered,
                native_click_count = clickTarget.ClickCount,
                route_passed = routePassed,
                screenshot_path = screenshotPath,
                screenshot_bytes = png.Length
            };
            int healthClickCount = clickTarget.ClickCount;
            File.WriteAllText(evidencePath, JsonUtility.ToJson(evidence, true));
            UnityEngine.Object.DestroyImmediate(overlay);
            UnityEngine.Object.DestroyImmediate(healthEventSystem);
            for (int index = 0; index < candidateEventSystems.Length; index++)
            {
                if (candidateEventSystems[index] != null)
                    candidateEventSystems[index].gameObject.SetActive(
                        candidateEventSystemStates[index]);
            }
            yield return null;
            Assert.That(routePassed && healthClickCount == 1, Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Evaluator-owned virtual Mouse/EventSystem " +
                "health click did not complete exactly once. " +
                string.Join(" | ", step.checks.Select(check =>
                    check.check_id + "=" + check.status + ":" + check.message)));
            Assert.That(File.Exists(evidencePath) && File.Exists(screenshotPath) &&
                        png.Length > 32, Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Dynamic evidence/screenshot writer is unhealthy.");
        }

        [UnityTest]
        public IEnumerator SEED01_DynamicLeavesBoundDirtyStateForFreshProcess()
        {
            var seed = new FreshProcessSeedEvidence
            {
                dynamic_process_id = System.Diagnostics.Process.GetCurrentProcess().Id,
                screen_width = Screen.width,
                screen_height = Screen.height,
                resolution_exact = EvaluatorDisplayResolution.IsCurrentExact,
                generated_utc = DateTime.UtcNow.ToString("O")
            };
            ArrowEscapeTrajectoryHarness harness = null;
            try
            {
                harness = new ArrowEscapeTrajectoryHarness("canonical_success");
            }
            catch (Exception exception)
            {
                seed.seed_error = exception.GetType().Name + ": " + exception.Message;
            }
            if (harness != null)
            {
                yield return CaptureExceptions(SeedDirtyState(harness, seed), exception =>
                    seed.seed_error = exception.GetType().Name + ": " + exception.Message);
            }
            if (harness != null) yield return harness.Dispose();
            string output = TrajectoryEvidenceWriter.ResolveOutputDirectory();
            Directory.CreateDirectory(output);
            string path = Path.Combine(output, "fresh-process-seed.json");
            File.WriteAllText(path, JsonUtility.ToJson(seed, true));
            Assert.That(File.Exists(path), Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Fresh-process seed evidence was not written.");
        }

        private static IEnumerator SeedDirtyState(
            ArrowEscapeTrajectoryHarness harness,
            FreshProcessSeedEvidence seed)
        {
            yield return harness.Initialize();
            VisibleGameState initial = harness.ObserveVisibleState();
            seed.initial_level = initial?.LevelId;
            seed.initial_budget = initial?.RemainingBudget ?? -1;
            seed.initial_arrow_count = initial?.Arrows.Count ?? -1;
            VisibleArrowTarget dirtyTarget = initial?.Arrows
                .Where(item => item?.PointerTarget != null && item.Interactable)
                .OrderBy(item => item.SemanticId, StringComparer.Ordinal)
                .FirstOrDefault();
            seed.dirty_target_found = dirtyTarget != null;
            seed.dirty_target_id = dirtyTarget?.SemanticId;
            seed.dirty_action = dirtyTarget == null ? null : "normal_arrow_click";

            VisibleGameState after = initial;
            if (harness.Ready && dirtyTarget != null)
            {
                const string stepId = "fresh.seed.arrow_click";
                yield return harness.ClickVisibleArrow(dirtyTarget, stepId);
                TrajectoryStepEvidence clickStep = harness.Evidence.steps
                    .FirstOrDefault(item => string.Equals(
                        item.step_id, stepId, StringComparison.Ordinal));
                seed.dirty_input_route_passed = clickStep != null &&
                                                clickStep.status == "pass";
                seed.dirty_input_route = clickStep?.input_route;
                seed.dirty_top_hit = clickStep?.top_hit;

                float deadline = Time.realtimeSinceStartup + 4f;
                after = harness.ObserveVisibleState();
                while (!VisiblyDirty(initial, after) &&
                       Time.realtimeSinceStartup < deadline)
                {
                    yield return null;
                    after = harness.ObserveVisibleState();
                }
            }

            after ??= harness.ObserveVisibleState();
            seed.after_level = after?.LevelId;
            seed.after_budget = after?.RemainingBudget ?? -1;
            seed.after_arrow_count = after?.Arrows.Count ?? -1;
            seed.dirty_distinct = seed.dirty_input_route_passed &&
                                  VisiblyDirty(initial, after);
        }

        private static bool VisiblyDirty(
            VisibleGameState initial,
            VisibleGameState after) =>
            after != null && initial != null &&
            (!string.Equals(after.LevelId, initial.LevelId,
                 StringComparison.Ordinal) ||
             after.RemainingBudget != initial.RemainingBudget ||
             after.Arrows.Count != initial.Arrows.Count ||
             after.Completed != initial.Completed || after.Failed != initial.Failed);

        private static IEnumerator CaptureExceptions(
            IEnumerator routine,
            Action<Exception> onException)
        {
            while (true)
            {
                bool moved = false;
                object current = null;
                Exception failure = null;
                try
                {
                    moved = routine.MoveNext();
                    if (moved) current = routine.Current;
                }
                catch (Exception exception)
                {
                    failure = exception;
                }
                if (failure != null)
                {
                    onException?.Invoke(failure);
                    break;
                }
                if (!moved) break;
                yield return current;
            }
        }

        private static IEnumerator LoadCanonicalScene()
        {
            Assert.That(Application.CanStreamedLevelBeLoaded(
                    ArrowEscapeContractConstants.MainScenePath), Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Canonical scene is not loadable after Static passed.");
            AsyncOperation load = SceneManager.LoadSceneAsync(
                ArrowEscapeContractConstants.MainScenePath, LoadSceneMode.Single);
            Assert.That(load, Is.Not.Null,
                "[OMNIGAME_EVALUATOR_HEALTH] SceneManager returned no load operation.");
            while (!load.isDone) yield return null;
            yield return null;
        }

        private static GameObject CreateHealthOverlay(
            out GameObject target,
            out EvaluatorHealthClickTarget clickTarget)
        {
            var overlay = new GameObject("Evaluator Health Overlay",
                typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = overlay.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 30000;

            target = new GameObject("Evaluator Health Pointer Surface",
                typeof(RectTransform), typeof(Image), typeof(EvaluatorHealthClickTarget));
            target.transform.SetParent(overlay.transform, false);
            var rect = target.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = new Vector2(180f, 72f);
            rect.anchoredPosition = Vector2.zero;
            var image = target.GetComponent<Image>();
            image.color = new Color(0.12f, 0.86f, 0.72f, 1f);
            image.raycastTarget = true;
            clickTarget = target.GetComponent<EvaluatorHealthClickTarget>();
            return overlay;
        }
    }

    internal sealed class EvaluatorHealthClickTarget : MonoBehaviour,
        IPointerClickHandler
    {
        public int ClickCount { get; private set; }

        public void OnPointerClick(PointerEventData eventData)
        {
            if (eventData != null &&
                eventData.button == PointerEventData.InputButton.Left)
            {
                ClickCount++;
            }
        }
    }

    [Serializable]
    internal sealed class DynamicEvaluatorHealthEvidence
    {
        public int schema_version = 1;
        public string evaluator_health = "dynamic";
        public int process_id;
        public int screen_width;
        public int screen_height;
        public int required_width;
        public int required_height;
        public bool resolution_exact;
        public string configuration_route;
        public bool visible_probe_discovered;
        public int native_click_count;
        public bool route_passed;
        public string screenshot_path;
        public int screenshot_bytes;
    }

    [Serializable]
    internal sealed class FreshProcessSeedEvidence
    {
        public int schema_version = 1;
        public int dynamic_process_id;
        public int screen_width;
        public int screen_height;
        public bool resolution_exact;
        public string generated_utc;
        public string initial_level;
        public int initial_budget;
        public int initial_arrow_count;
        public bool dirty_target_found;
        public string dirty_target_id;
        public string dirty_action;
        public bool dirty_input_route_passed;
        public string dirty_input_route;
        public string dirty_top_hit;
        public string after_level;
        public int after_budget;
        public int after_arrow_count;
        public bool dirty_distinct;
        public string seed_error;
    }
}
