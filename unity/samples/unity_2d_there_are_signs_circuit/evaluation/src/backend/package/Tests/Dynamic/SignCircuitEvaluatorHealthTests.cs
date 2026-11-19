using System;
using System.Collections;
using System.Collections.Generic;
using NUnit.Framework;
using OmniGame.Benchmark.SignCircuit.Contract;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    /// <summary>
    /// Evaluator-owned scene/UI helpers used by the Order(0) health testcase in
    /// SignCircuitDynamicTests. Keeping the testcase in the same fixture as
    /// DYN01-DYN12 makes its order deterministic within the Dynamic assembly.
    /// </summary>
    internal static class SignCircuitEvaluatorHealthSupport
    {
        static Scene activeHealthScene;

        internal static IEnumerator ReplaceWithIsolatedScene(
            string suffix,
            Action<GameObject> receiveRoot)
        {
            Debug.Log("[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] create_scene:" + suffix);
            Scene previousHealthScene = activeHealthScene;
            Scene healthScene = SceneManager.CreateScene(
                "SignCircuitEvaluatorHealth_" + suffix + "_" +
                Guid.NewGuid().ToString("N"));
            SceneManager.SetActiveScene(healthScene);
            activeHealthScene = healthScene;

            // Never enumerate or unload runner/candidate scenes from the health
            // testcase. Only retire the previous evaluator-owned health scene.
            if (previousHealthScene.IsValid() && previousHealthScene.isLoaded)
            {
                Debug.Log(
                    "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] unload_previous:" +
                    previousHealthScene.name);
                AsyncOperation unload =
                    SceneManager.UnloadSceneAsync(previousHealthScene);
                Assert.That(unload, Is.Not.Null,
                    "[OMNIGAME_EVALUATOR_INFRASTRUCTURE] Unity refused to unload " +
                    "the previous evaluator-owned health scene.");
                float unloadDeadline = Time.realtimeSinceStartup + 8f;
                while (!unload.isDone &&
                       Time.realtimeSinceStartup < unloadDeadline)
                {
                    yield return null;
                }
                Assert.That(unload.isDone, Is.True,
                    "[OMNIGAME_EVALUATOR_INFRASTRUCTURE] Timed out unloading the " +
                    "previous evaluator-owned health scene.");
            }

            var root = new GameObject("EvaluatorHealthRoot_" + suffix);
            SceneManager.MoveGameObjectToScene(root, healthScene);
            receiveRoot(root);
            yield return null;
            Debug.Log("[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] scene_ready:" + suffix);
        }

        internal static UiClickTarget CreateUguiHealthTarget(
            GameObject healthRoot,
            string suffix,
            Action onClick)
        {
            GameObject eventSystemObject = new GameObject(
                "EvaluatorHealthEventSystem_" + suffix, typeof(EventSystem),
                typeof(InputSystemUIInputModule));
            eventSystemObject.transform.SetParent(healthRoot.transform, false);
            InputSystemUIInputModule inputModule =
                eventSystemObject.GetComponent<InputSystemUIInputModule>();
            inputModule.AssignDefaultActions();

            GameObject canvasObject = new GameObject(
                "EvaluatorHealthCanvas_" + suffix, typeof(RectTransform),
                typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasObject.transform.SetParent(healthRoot.transform, false);
            Canvas canvas = canvasObject.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = short.MaxValue;

            GameObject buttonObject = new GameObject(
                "EvaluatorHealthButton_" + suffix, typeof(RectTransform),
                typeof(Image), typeof(Button));
            buttonObject.transform.SetParent(canvasObject.transform, false);
            RectTransform rect = buttonObject.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = Vector2.zero;
            rect.sizeDelta = new Vector2(320f, 120f);
            Image image = buttonObject.GetComponent<Image>();
            image.color = Color.white;
            image.raycastTarget = true;
            Button button = buttonObject.GetComponent<Button>();
            button.targetGraphic = image;
            button.onClick.AddListener(() => onClick());
            return new UiClickTarget
            {
                Backend = UiClickBackend.Ugui,
                Name = button.name,
                Label = "Evaluator Health " + suffix,
                UguiButton = button
            };
        }

        internal static UiClickTarget RequireTopHit(UiClickTarget clickTarget)
        {
            Canvas.ForceUpdateCanvases();
            EventSystem eventSystem = EventSystem.current;
            Assert.That(eventSystem, Is.Not.Null,
                "The evaluator health fixture has no active EventSystem.");
            GameObject expectedHandler =
                ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                    clickTarget.UguiButton.gameObject);
            Assert.That(expectedHandler, Is.Not.Null,
                "The evaluator health Button has no normal pointer-click handler.");
            Assert.That(NativeInputDriver.TryFindTopHitPoint(
                    clickTarget.UguiButton.transform as RectTransform,
                    expectedHandler, eventSystem, default,
                    out Vector2 healthPoint, out string sampledHits), Is.True,
                "The evaluator health Button has no real EventSystem top-hit point. " +
                sampledHits);
            clickTarget.ScreenPoint = healthPoint;
            clickTarget.RouteDescription =
                "evaluator health discovered uGUI top hit;" + sampledHits;
            return clickTarget;
        }

        internal static void AssertSemanticStatusLocatorRegression(
            GameObject healthRoot)
        {
            const float viewportWidth = 1280f;
            const float viewportHeight = 720f;
            Rect compactWide = new Rect(32f, 576f, 1216f, 72f);
            Assert.That(compactWide.width / viewportWidth, Is.GreaterThan(0.90f));
            Assert.That(compactWide.height / viewportHeight, Is.LessThan(0.20f));
            Assert.That(SignCircuitSemanticUiObserver
                    .IsPlausibleSemanticRectForViewport(
                        SignCircuitSemanticUiObserver.StatusId,
                        compactWide, viewportWidth, viewportHeight,
                        out string compactReason), Is.True,
                "A low-profile real status field spanning most of the viewport " +
                "must remain observable. reason=" + compactReason);

            Rect wideAndTall = new Rect(32f, 504f, 1216f, 180f);
            Assert.That(SignCircuitSemanticUiObserver
                    .IsPlausibleSemanticRectForViewport(
                        SignCircuitSemanticUiObserver.StatusId,
                        wideAndTall, viewportWidth, viewportHeight,
                        out string tallReason), Is.False,
                "A wide status locator that is no longer low-profile must be rejected.");
            Assert.That(tallReason, Is.EqualTo("hud_locator_too_broad"));

            Rect oversized = new Rect(0f, 216f, 1280f, 432f);
            Assert.That(SignCircuitSemanticUiObserver
                    .IsPlausibleSemanticRectForViewport(
                        SignCircuitSemanticUiObserver.StatusId,
                        oversized, viewportWidth, viewportHeight,
                        out string oversizedReason), Is.False,
                "An oversized status locator must still be rejected.");
            Assert.That(oversizedReason, Is.EqualTo("hud_locator_too_broad"));

            GameObject canvasObject = new GameObject(
                "EvaluatorHealthSemanticCanvas", typeof(RectTransform),
                typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasObject.transform.SetParent(healthRoot.transform, false);
            Canvas canvas = canvasObject.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = short.MaxValue;

            GameObject textObject = new GameObject(
                "EvaluatorHealthWideStatus", typeof(RectTransform),
                typeof(CanvasRenderer), typeof(Text));
            textObject.transform.SetParent(canvasObject.transform, false);
            RectTransform statusRect = textObject.GetComponent<RectTransform>();
            statusRect.anchorMin = new Vector2(0.025f, 0.80f);
            statusRect.anchorMax = new Vector2(0.975f, 0.90f);
            statusRect.offsetMin = Vector2.zero;
            statusRect.offsetMax = Vector2.zero;
            Text statusText = textObject.GetComponent<Text>();
            statusText.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            statusText.text = "Evaluator health compact wide status";
            statusText.alignment = TextAnchor.MiddleCenter;
            statusText.color = Color.white;
            statusText.raycastTarget = false;
            Canvas.ForceUpdateCanvases();

            var corners = new Vector3[4];
            statusRect.GetWorldCorners(corners);
            Rect actualRect = Rect.MinMaxRect(
                corners[0].x, corners[0].y, corners[2].x, corners[2].y);
            Assert.That(actualRect.width / Mathf.Max(1f, Screen.width),
                Is.GreaterThan(0.90f));
            Assert.That(actualRect.height / Mathf.Max(1f, Screen.height),
                Is.LessThan(0.20f));

            PublishHealthStatus(actualRect);
            Assert.That(SignCircuitSemanticUiObserver.TryReadStatus(
                    out string visibleStatus, out string resolvedSource), Is.True,
                "A compact viewport-wide locator overlapping its real uGUI Text " +
                "must resolve. source=" + resolvedSource);
            Assert.That(visibleStatus,
                Does.Contain("Evaluator health compact wide status"));

            var duplicates = new List<GameObject>();
            for (int index = 0; index < 4; index++)
            {
                GameObject duplicate = UnityEngine.Object.Instantiate(
                    textObject, canvasObject.transform);
                duplicate.name = "EvaluatorHealthAmbiguousStatus" + index;
                duplicate.GetComponent<Text>().text = "Ambiguous status " + index;
                duplicates.Add(duplicate);
            }
            Canvas.ForceUpdateCanvases();
            PublishHealthStatus(actualRect);
            Assert.That(SignCircuitSemanticUiObserver.TryReadStatus(
                    out _, out string ambiguousSource), Is.False,
                "A compact wide locator must not bypass real-text ambiguity checks.");
            Assert.That(ambiguousSource,
                Does.Contain("ambiguous_real_visible_ui_overlap"));
            foreach (GameObject duplicate in duplicates) duplicate.SetActive(false);
        }

        static void PublishHealthStatus(Rect statusRect)
        {
            SignCircuitProbePublisher.Publish(new SignCircuitSnapshot
            {
                scene = "evaluator-health",
                phase = "running",
                progress = 0,
                remainingSeconds = 30f,
                hudVisible = true,
                statusText = "Evaluator health compact wide status",
                playerPosition = Vector2.zero
            }, null, new[]
            {
                new SignCircuitObservationTarget
                {
                    id = SignCircuitSemanticUiObserver.StatusId,
                    screenRect = statusRect,
                    visible = true
                }
            });
        }
    }
}
