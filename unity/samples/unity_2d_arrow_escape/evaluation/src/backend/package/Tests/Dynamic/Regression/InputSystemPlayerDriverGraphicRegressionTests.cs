using System.Collections;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.UI;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    [TestFixture]
    public sealed class InputSystemPlayerDriverGraphicRegressionTests
    {
        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_DirectMousePollingNeedsNoEventSystemOrCollider()
        {
            EventSystem[] eventSystems = Object.FindObjectsByType<EventSystem>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] eventSystemStates = eventSystems.Select(item => item.gameObject.activeSelf).ToArray();
            foreach (EventSystem item in eventSystems) item.gameObject.SetActive(false);

            Camera[] cameras = Object.FindObjectsByType<Camera>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] cameraStates = cameras.Select(item => item.enabled).ToArray();
            foreach (Camera item in cameras) item.enabled = false;

            Collider2D[] colliders = Object.FindObjectsByType<Collider2D>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] colliderStates = colliders.Select(item => item.enabled).ToArray();
            foreach (Collider2D item in colliders) item.enabled = false;

            GameObject cameraObject = new GameObject("DirectPollingCamera", typeof(Camera));
            cameraObject.tag = "MainCamera";
            Camera camera = cameraObject.GetComponent<Camera>();
            camera.orthographic = true;
            camera.orthographicSize = 3f;
            camera.transform.position = new Vector3(0f, 0f, -10f);

            GameObject target = new GameObject(
                "DirectPollingTarget", typeof(LineRenderer), typeof(DirectPollingRegressionTarget));
            LineRenderer line = target.GetComponent<LineRenderer>();
            line.positionCount = 2;
            line.SetPositions(new[] { new Vector3(-1f, 0f), new Vector3(1f, 0f) });
            line.startWidth = 0.8f;
            line.endWidth = 0.8f;
            Shader shader = Shader.Find("Sprites/Default");
            Material material = shader == null ? null : new Material(shader);
            if (material != null) line.sharedMaterial = material;
            yield return null;

            var driver = new InputSystemPlayerDriver();
            var evidence = new TrajectoryStepEvidence { step_id = "direct-polling-regression" };
            yield return driver.Click(target, "direct-polling-regression.input", evidence);

            int clickCount = target.GetComponent<DirectPollingRegressionTarget>().ClickCount;
            string route = evidence.input_route;
            string readiness = evidence.checks.Single(check =>
                check.check_id == "direct-polling-regression.input.driver_ready").observed;
            string press = evidence.checks.Single(check =>
                check.check_id == "direct-polling-regression.input.press").status;
            string release = evidence.checks.Single(check =>
                check.check_id == "direct-polling-regression.input.release").status;

            yield return driver.Dispose();
            Object.Destroy(target);
            Object.Destroy(cameraObject);
            if (material != null) Object.Destroy(material);
            for (int index = 0; index < colliders.Length; index++)
                if (colliders[index] != null) colliders[index].enabled = colliderStates[index];
            for (int index = 0; index < cameras.Length; index++)
                if (cameras[index] != null) cameras[index].enabled = cameraStates[index];
            for (int index = 0; index < eventSystems.Length; index++)
                if (eventSystems[index] != null) eventSystems[index].gameObject.SetActive(eventSystemStates[index]);
            yield return null;

            Assert.That(clickCount, Is.EqualTo(1));
            Assert.That(route, Is.EqualTo("visual_bounds_native_mouse"));
            Assert.That(readiness, Does.Contain("direct Input System polling route"));
            Assert.That(press, Is.EqualTo("pass"));
            Assert.That(release, Is.EqualTo("pass"));
            Assert.That(evidence.pointer_events, Is.Empty,
                "Direct polling is proven by device state plus candidate outcome, not EventSystem callbacks.");
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_UguiButtonSurfaceSupportsSceneLevelDirectPollingWithoutEventSystem()
        {
            EventSystem previousEventSystem = EventSystem.current;
            EventSystem[] eventSystems = Object.FindObjectsByType<EventSystem>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] eventSystemStates = eventSystems
                .Select(item => item.gameObject.activeSelf).ToArray();
            foreach (EventSystem item in eventSystems) item.gameObject.SetActive(false);
            yield return null;
            Assert.That(EventSystem.current == null ||
                        !EventSystem.current.isActiveAndEnabled, Is.True,
                "The fixture must not expose an active EventSystem delivery route.");

            GameObject canvasObject = new GameObject(
                "DirectPollingButtonCanvas", typeof(RectTransform), typeof(Canvas),
                typeof(GraphicRaycaster));
            canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            GameObject target = new GameObject(
                "Hint", typeof(RectTransform), typeof(Image), typeof(Button));
            target.transform.SetParent(canvasObject.transform, false);
            RectTransform targetRect = target.GetComponent<RectTransform>();
            targetRect.anchorMin = targetRect.anchorMax = new Vector2(0.5f, 0.5f);
            targetRect.sizeDelta = new Vector2(180f, 64f);
            target.GetComponent<Image>().raycastTarget = true;

            GameObject controllerObject = new GameObject(
                "DirectPollingButtonController", typeof(DirectPollingUguiController));
            DirectPollingUguiController controller =
                controllerObject.GetComponent<DirectPollingUguiController>();
            controller.Target = targetRect;
            int buttonCallbackCount = 0;
            target.GetComponent<Button>().onClick.AddListener(() => buttonCallbackCount++);

            yield return null;
            Canvas.ForceUpdateCanvases();
            Assert.That(ExecuteEvents.GetEventHandler<IPointerClickHandler>(target),
                Is.EqualTo(target), "The fixture must expose a passive uGUI Button handler.");

            var driver = new InputSystemPlayerDriver();
            var evidence = new TrajectoryStepEvidence
                { step_id = "direct-polling-button-regression" };
            yield return driver.Click(target,
                "direct-polling-button-regression.input", evidence);

            Assert.That(evidence.status, Is.EqualTo("pass"));
            Assert.That(evidence.input_route, Is.EqualTo("visual_bounds_native_mouse"));
            Assert.That(evidence.checks.Single(check =>
                check.check_id == "direct-polling-button-regression.input.driver_ready")
                .observed, Does.Contain("direct Input System polling route"));
            Assert.That(evidence.checks.Single(check =>
                check.check_id == "direct-polling-button-regression.input.press").status,
                Is.EqualTo("pass"));
            Assert.That(evidence.checks.Single(check =>
                check.check_id == "direct-polling-button-regression.input.release").status,
                Is.EqualTo("pass"));
            Assert.That(controller.ClickCount, Is.EqualTo(1),
                "The scene-level Mouse.current controller must receive the complete click.");
            Assert.That(buttonCallbackCount, Is.Zero,
                "No EventSystem callback should be fabricated for the passive Button surface.");
            Assert.That(evidence.pointer_events, Is.Empty);

            yield return driver.Dispose();
            Object.Destroy(controllerObject);
            Object.Destroy(target);
            Object.Destroy(canvasObject);
            for (int index = 0; index < eventSystems.Length; index++)
            {
                if (eventSystems[index] != null)
                    eventSystems[index].gameObject.SetActive(eventSystemStates[index]);
            }
            if (previousEventSystem != null) EventSystem.current = previousEventSystem;
            yield return null;
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_ClickFindsRaycastableChildGraphicWhenRootCenterIsEmpty()
        {
            GameObject eventSystemObject = new GameObject(
                "RegressionEventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            InputSystemUIInputModule inputModule =
                eventSystemObject.GetComponent<InputSystemUIInputModule>();
            inputModule.AssignDefaultActions();

            GameObject canvasObject = new GameObject(
                "RegressionCanvas", typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
            Canvas canvas = canvasObject.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;

            GameObject pointerRoot = new GameObject(
                "PointerRoot", typeof(RectTransform), typeof(Image),
                typeof(GraphicRegressionClickHandler));
            pointerRoot.transform.SetParent(canvasObject.transform, false);
            RectTransform rootRect = pointerRoot.GetComponent<RectTransform>();
            rootRect.anchorMin = rootRect.anchorMax = new Vector2(0.5f, 0.5f);
            rootRect.sizeDelta = new Vector2(240f, 80f);
            pointerRoot.GetComponent<Image>().raycastTarget = false;

            CreateSegment(pointerRoot.transform, "LeftSegment", new Vector2(-80f, 0f));
            CreateSegment(pointerRoot.transform, "RightSegment", new Vector2(80f, 0f));

            yield return null;
            Canvas.ForceUpdateCanvases();

            var driver = new InputSystemPlayerDriver();
            var evidence = new TrajectoryStepEvidence { step_id = "graphic-regression" };
            yield return driver.Click(pointerRoot, "graphic-regression.input", evidence);

            GraphicRegressionClickHandler handler =
                pointerRoot.GetComponent<GraphicRegressionClickHandler>();
            int clickCount = handler.ClickCount;
            string pointerSequence = string.Join(" -> ", handler.PointerPhases);
            string topHitStatus = evidence.checks.Single(check =>
                check.check_id == "graphic-regression.input.top_hit").status;
            TrajectoryCheckEvidence pressEvidence = evidence.checks.Single(check =>
                check.check_id == "graphic-regression.input.press");
            TrajectoryCheckEvidence releaseEvidence = evidence.checks.Single(check =>
                check.check_id == "graphic-regression.input.release");
            string topHit = evidence.top_hit;

            yield return driver.Dispose();
            Object.Destroy(pointerRoot);
            Object.Destroy(canvasObject);
            Object.Destroy(eventSystemObject);
            yield return null;

            Assert.That(clickCount, Is.EqualTo(1),
                "A normal virtual-Mouse click should reach the parent handler through a visible child Graphic.");
            Assert.That(pointerSequence, Is.EqualTo("down -> up -> click"),
                "The engine route must emit the normal pointer callback sequence.");
            Assert.That(topHitStatus, Is.EqualTo("pass"));
            Assert.That(topHit, Does.Contain("Segment -> PointerRoot"));
            Assert.That(pressEvidence.status, Is.EqualTo("pass"));
            Assert.That(pressEvidence.observed, Does.Contain("PointerDown"),
                "Press evidence must be based on the actual EventSystem callback, not only Mouse button state.");
            Assert.That(releaseEvidence.status, Is.EqualTo("pass"));
            Assert.That(releaseEvidence.observed, Does.Contain("PointerUp -> PointerClick"),
                "Release evidence must prove the normal EventSystem callback sequence.");
            Assert.That(evidence.pointer_events.Select(item => item.phase),
                Is.EqualTo(new[] { "down", "up", "click" }));
            Assert.That(evidence.pointer_events.All(item => item.pointer_id ==
                evidence.pointer_events[0].pointer_id), Is.True);
            Assert.That(evidence.pointer_events.All(item =>
                Vector2.Distance(new Vector2(item.screen_x, item.screen_y),
                    new Vector2(evidence.screen_x, evidence.screen_y)) <= 2f), Is.True);
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_ClickMayDestroyItsOwnUguiTargetOnRelease()
        {
            GameObject eventSystemObject = new GameObject(
                "SelfDestroyEventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            InputSystemUIInputModule inputModule =
                eventSystemObject.GetComponent<InputSystemUIInputModule>();
            inputModule.AssignDefaultActions();

            GameObject canvasObject = new GameObject(
                "SelfDestroyCanvas", typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
            canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            GameObject target = new GameObject(
                "SelfDestroyTarget", typeof(RectTransform), typeof(Image),
                typeof(SelfDestroyOnClickRegressionTarget));
            target.transform.SetParent(canvasObject.transform, false);
            RectTransform rect = target.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = new Vector2(180f, 100f);
            target.GetComponent<Image>().color = Color.white;
            target.GetComponent<Image>().raycastTarget = true;
            yield return null;
            Canvas.ForceUpdateCanvases();

            var driver = new InputSystemPlayerDriver();
            var evidence = new TrajectoryStepEvidence { step_id = "self-destroy-regression" };
            yield return driver.Click(target, "self-destroy-regression.input", evidence);

            Assert.That(target == null, Is.True,
                "The candidate click fixture must really destroy its own target.");
            Assert.That(evidence.status, Is.EqualTo("pass"));
            Assert.That(evidence.checks.Single(check =>
                check.check_id == "self-destroy-regression.input.release").status,
                Is.EqualTo("pass"));
            Assert.That(evidence.pointer_events.Select(item => item.phase),
                Is.EqualTo(new[] { "down", "up", "click" }));

            yield return driver.Dispose();
            Object.Destroy(canvasObject);
            Object.Destroy(eventSystemObject);
            yield return null;
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_TargetDestroyedAfterPressSealsInputFailure()
        {
            GameObject eventSystemObject = new GameObject(
                "PressDestroyEventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            InputSystemUIInputModule inputModule =
                eventSystemObject.GetComponent<InputSystemUIInputModule>();
            inputModule.AssignDefaultActions();

            GameObject canvasObject = new GameObject(
                "PressDestroyCanvas", typeof(RectTransform), typeof(Canvas),
                typeof(GraphicRaycaster));
            canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            GameObject target = new GameObject(
                "PressDestroyTarget", typeof(RectTransform), typeof(Image),
                typeof(SelfDestroyOnPointerDownRegressionTarget));
            target.transform.SetParent(canvasObject.transform, false);
            RectTransform rect = target.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = new Vector2(180f, 100f);
            target.GetComponent<Image>().color = Color.white;
            target.GetComponent<Image>().raycastTarget = true;
            yield return null;
            Canvas.ForceUpdateCanvases();

            var driver = new InputSystemPlayerDriver();
            var evidence = new TrajectoryStepEvidence { step_id = "press-destroy-regression" };
            yield return driver.Click(target, "press-destroy-regression.input", evidence);

            Assert.That(target == null, Is.True,
                "The fixture must destroy the candidate target after PointerDown.");
            Assert.That(evidence.status, Is.EqualTo("fail"));
            Assert.That(evidence.checks.Single(check =>
                check.check_id == "press-destroy-regression.input.press").status,
                Is.EqualTo("pass"));
            Assert.That(evidence.checks.Single(check =>
                check.check_id == "press-destroy-regression.input.release").status,
                Is.EqualTo("fail"));
            Assert.That(evidence.pointer_events.Select(item => item.phase),
                Is.EqualTo(new[] { "down" }));

            yield return driver.Dispose();
            Object.Destroy(canvasObject);
            Object.Destroy(eventSystemObject);
            yield return null;
        }

        [Test]
        public void EVALUATOR_REGRESSION_DestroyedRectTransformIsIgnoredBySampler()
        {
            GameObject target = new GameObject("DestroyedRect", typeof(RectTransform));
            RectTransform rect = target.GetComponent<RectTransform>();
            Object.DestroyImmediate(target);

            var candidates = new System.Collections.Generic.List<Vector2>();
            Assert.DoesNotThrow(() => InputSystemPlayerDriver
                .AddRectTransformSamplePointsForEvaluatorRegression(rect, candidates));
            Assert.That(candidates, Is.Empty);
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_OccludedTargetCannotBeClickedThroughTopHit()
        {
            GameObject eventSystemObject = new GameObject(
                "OcclusionEventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            eventSystemObject.GetComponent<InputSystemUIInputModule>().AssignDefaultActions();
            GameObject canvasObject = new GameObject(
                "OcclusionCanvas", typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
            canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;

            GameObject target = CreateClickableImage(canvasObject.transform, "OccludedTarget", 0);
            GameObject blocker = CreateClickableImage(canvasObject.transform, "TopBlocker", 1);
            yield return null;
            Canvas.ForceUpdateCanvases();

            var driver = new InputSystemPlayerDriver();
            var evidence = new TrajectoryStepEvidence { step_id = "occlusion-regression" };
            yield return driver.Click(target, "occlusion-regression.input", evidence);

            Assert.That(target.GetComponent<GraphicRegressionClickHandler>().ClickCount, Is.Zero,
                "A fully occluded player target must not receive a synthetic gameplay click.");
            Assert.That(blocker.GetComponent<GraphicRegressionClickHandler>().ClickCount, Is.Zero,
                "The evaluator is resolving a target, not clicking whichever object is on top.");
            Assert.That(evidence.checks.Single(check =>
                check.check_id == "occlusion-regression.input.top_hit").status, Is.EqualTo("fail"));
            Assert.That(evidence.pointer_events, Is.Empty);

            yield return driver.Dispose();
            Object.Destroy(target);
            Object.Destroy(blocker);
            Object.Destroy(canvasObject);
            Object.Destroy(eventSystemObject);
            yield return null;
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_RevalidatesInputModuleBeforeEveryClick()
        {
            EventSystem previousEventSystem = EventSystem.current;
            GameObject eventSystemObject = new GameObject(
                "RevalidationEventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            EventSystem.current = eventSystemObject.GetComponent<EventSystem>();
            InputSystemUIInputModule inputModule =
                eventSystemObject.GetComponent<InputSystemUIInputModule>();
            inputModule.AssignDefaultActions();
            GameObject canvasObject = new GameObject(
                "RevalidationCanvas", typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
            canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            GameObject target = CreateClickableImage(canvasObject.transform, "RevalidationTarget", 0);
            yield return null;
            Canvas.ForceUpdateCanvases();

            var driver = new InputSystemPlayerDriver();
            var first = new TrajectoryStepEvidence { step_id = "revalidation-first" };
            yield return driver.Click(target, "revalidation-first.input", first);
            Assert.That(first.status, Is.EqualTo("pass"));

            GameObject replacementEventSystemObject = new GameObject(
                "RevalidationEventSystemWithoutModule", typeof(EventSystem));
            EventSystem.current = replacementEventSystemObject.GetComponent<EventSystem>();
            yield return null;
            var second = new TrajectoryStepEvidence { step_id = "revalidation-second" };
            yield return driver.Click(target, "revalidation-second.input", second);

            TrajectoryCheckEvidence readiness = second.checks.Single(check =>
                check.check_id == "revalidation-second.input.driver_ready");
            TrajectoryCheckEvidence press = second.checks.Single(check =>
                check.check_id == "revalidation-second.input.press");
            TrajectoryCheckEvidence release = second.checks.Single(check =>
                check.check_id == "revalidation-second.input.release");
            Assert.That(readiness.status, Is.EqualTo("pass"),
                "A missing UI module must not invalidate direct Mouse.current polling candidates.");
            Assert.That(readiness.observed, Does.Contain("direct Input System polling route"));
            Assert.That(second.status, Is.EqualTo("pass"),
                "The driver proves native Mouse delivery; gameplay outcome remains a trajectory-state check.");
            Assert.That(press.status, Is.EqualTo("pass"));
            Assert.That(release.status, Is.EqualTo("pass"));
            Assert.That(second.pointer_events, Is.Empty);
            Assert.That(target.GetComponent<GraphicRegressionClickHandler>().ClickCount, Is.EqualTo(1),
                "Without an input module, the second click must not fabricate EventSystem callbacks.");

            yield return driver.Dispose();
            Object.Destroy(target);
            Object.Destroy(canvasObject);
            Object.Destroy(replacementEventSystemObject);
            Object.Destroy(eventSystemObject);
            if (previousEventSystem != null)
            {
                EventSystem.current = previousEventSystem;
            }
            yield return null;
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_WorldColliderUsesVisibleEdgeWhenCenterIsOccluded()
        {
            EventSystem previousEventSystem = EventSystem.current;
            EventSystem[] existingEventSystems = Object.FindObjectsByType<EventSystem>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] eventSystemStates = existingEventSystems
                .Select(item => item.gameObject.activeSelf).ToArray();
            BaseRaycaster[] existingRaycasters = Object.FindObjectsByType<BaseRaycaster>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] raycasterStates = existingRaycasters.Select(item => item.enabled).ToArray();
            Camera[] existingCameras = Object.FindObjectsByType<Camera>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] cameraStates = existingCameras.Select(item => item.enabled).ToArray();
            Collider2D[] existingColliders = Object.FindObjectsByType<Collider2D>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] colliderStates = existingColliders.Select(item => item.enabled).ToArray();
            foreach (EventSystem item in existingEventSystems) item.gameObject.SetActive(false);
            foreach (BaseRaycaster item in existingRaycasters) item.enabled = false;
            foreach (Camera item in existingCameras) item.enabled = false;
            foreach (Collider2D item in existingColliders) item.enabled = false;

            GameObject eventSystemObject = new GameObject(
                "WorldSamplingEventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            EventSystem.current = eventSystemObject.GetComponent<EventSystem>();
            eventSystemObject.GetComponent<InputSystemUIInputModule>().AssignDefaultActions();

            GameObject cameraObject = new GameObject(
                "WorldSamplingCamera", typeof(Camera), typeof(Physics2DRaycaster));
            cameraObject.tag = "MainCamera";
            Camera camera = cameraObject.GetComponent<Camera>();
            camera.orthographic = true;
            camera.orthographicSize = 4f;
            cameraObject.transform.position = new Vector3(0f, 0f, -10f);

            GameObject target = new GameObject(
                "WorldColliderTarget", typeof(BoxCollider2D), typeof(GraphicRegressionClickHandler));
            target.GetComponent<BoxCollider2D>().size = new Vector2(4f, 2f);

            GameObject centerBlocker = new GameObject(
                "WorldCenterBlocker", typeof(BoxCollider2D), typeof(GraphicRegressionClickHandler));
            centerBlocker.transform.position = new Vector3(0f, 0f, -1f);
            centerBlocker.GetComponent<BoxCollider2D>().size = new Vector2(1f, 2.4f);

            Physics2D.SyncTransforms();
            yield return null;
            EventSystem.current = eventSystemObject.GetComponent<EventSystem>();

            var driver = new InputSystemPlayerDriver();
            var evidence = new TrajectoryStepEvidence { step_id = "world-sampling-regression" };
            yield return driver.Click(target, "world-sampling-regression.input", evidence);

            int clickCount = target.GetComponent<GraphicRegressionClickHandler>().ClickCount;
            int blockerClickCount = centerBlocker
                .GetComponent<GraphicRegressionClickHandler>().ClickCount;
            string status = evidence.status;
            string topHit = evidence.top_hit;
            float screenX = evidence.screen_x;
            string[] pointerPhases = evidence.pointer_events
                .Select(item => item.phase).ToArray();

            yield return driver.Dispose();
            Object.Destroy(target);
            Object.Destroy(centerBlocker);
            Object.Destroy(cameraObject);
            Object.Destroy(eventSystemObject);
            for (int index = 0; index < existingColliders.Length; index++)
                if (existingColliders[index] != null) existingColliders[index].enabled = colliderStates[index];
            for (int index = 0; index < existingCameras.Length; index++)
                if (existingCameras[index] != null) existingCameras[index].enabled = cameraStates[index];
            for (int index = 0; index < existingRaycasters.Length; index++)
                if (existingRaycasters[index] != null) existingRaycasters[index].enabled = raycasterStates[index];
            for (int index = 0; index < existingEventSystems.Length; index++)
                if (existingEventSystems[index] != null)
                    existingEventSystems[index].gameObject.SetActive(eventSystemStates[index]);
            if (previousEventSystem != null)
            {
                EventSystem.current = previousEventSystem;
            }
            yield return null;

            Assert.That(clickCount, Is.EqualTo(1),
                "A human-clickable world target must remain clickable when only its center is occluded.");
            Assert.That(blockerClickCount, Is.Zero,
                "The evaluator must search the intended target instead of clicking the center occluder.");
            Assert.That(status, Is.EqualTo("pass"));
            Assert.That(topHit, Does.Contain("WorldColliderTarget"));
            Assert.That(Mathf.Abs(screenX - Screen.width * 0.5f), Is.GreaterThan(5f),
                "The selected point should move away from the occluded world-space center.");
            Assert.That(pointerPhases, Is.EqualTo(new[] { "down", "up", "click" }));
        }

        private static void CreateSegment(Transform parent, string name, Vector2 anchoredPosition)
        {
            GameObject segment = new GameObject(name, typeof(RectTransform), typeof(Image));
            segment.transform.SetParent(parent, false);
            RectTransform rect = segment.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = anchoredPosition;
            rect.sizeDelta = new Vector2(48f, 48f);
            Image image = segment.GetComponent<Image>();
            image.color = Color.white;
            image.raycastTarget = true;
        }

        private static GameObject CreateClickableImage(Transform parent, string name, int siblingIndex)
        {
            GameObject gameObject = new GameObject(
                name, typeof(RectTransform), typeof(Image), typeof(GraphicRegressionClickHandler));
            gameObject.transform.SetParent(parent, false);
            gameObject.transform.SetSiblingIndex(siblingIndex);
            RectTransform rect = gameObject.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = new Vector2(180f, 100f);
            Image image = gameObject.GetComponent<Image>();
            image.color = Color.white;
            image.raycastTarget = true;
            return gameObject;
        }

    }

    internal sealed class GraphicRegressionClickHandler : MonoBehaviour,
        IPointerDownHandler, IPointerUpHandler, IPointerClickHandler
    {
        public int ClickCount { get; private set; }
        public System.Collections.Generic.List<string> PointerPhases { get; } =
            new System.Collections.Generic.List<string>();

        public void OnPointerDown(PointerEventData eventData)
        {
            PointerPhases.Add("down");
        }

        public void OnPointerUp(PointerEventData eventData)
        {
            PointerPhases.Add("up");
        }

        public void OnPointerClick(PointerEventData eventData)
        {
            if (eventData.button == PointerEventData.InputButton.Left)
            {
                PointerPhases.Add("click");
                ClickCount++;
            }
        }
    }

    internal sealed class SelfDestroyOnClickRegressionTarget : MonoBehaviour,
        IPointerDownHandler, IPointerUpHandler, IPointerClickHandler
    {
        public void OnPointerDown(PointerEventData eventData) { }

        public void OnPointerUp(PointerEventData eventData) { }

        public void OnPointerClick(PointerEventData eventData)
        {
            if (eventData.button == PointerEventData.InputButton.Left)
            {
                Object.Destroy(gameObject);
            }
        }
    }

    internal sealed class SelfDestroyOnPointerDownRegressionTarget : MonoBehaviour,
        IPointerDownHandler, IPointerUpHandler, IPointerClickHandler
    {
        public void OnPointerDown(PointerEventData eventData)
        {
            Object.Destroy(gameObject);
        }

        public void OnPointerUp(PointerEventData eventData) { }

        public void OnPointerClick(PointerEventData eventData) { }
    }

    internal sealed class DirectPollingRegressionTarget : MonoBehaviour
    {
        public int ClickCount { get; private set; }

        private void Update()
        {
            Mouse mouse = Mouse.current;
            Camera camera = Camera.main;
            Renderer renderer = GetComponent<Renderer>();
            if (mouse == null || camera == null || renderer == null ||
                !mouse.leftButton.wasReleasedThisFrame)
            {
                return;
            }

            Vector3 min = camera.WorldToScreenPoint(renderer.bounds.min);
            Vector3 max = camera.WorldToScreenPoint(renderer.bounds.max);
            Rect rect = Rect.MinMaxRect(
                Mathf.Min(min.x, max.x), Mathf.Min(min.y, max.y),
                Mathf.Max(min.x, max.x), Mathf.Max(min.y, max.y));
            if (rect.Contains(mouse.position.ReadValue())) ClickCount++;
        }
    }

    internal sealed class DirectPollingUguiController : MonoBehaviour
    {
        public RectTransform Target { get; set; }
        public int ClickCount { get; private set; }
        private bool pressedInside;

        private void Update()
        {
            Mouse mouse = Mouse.current;
            if (mouse == null || Target == null) return;
            Vector2 point = mouse.position.ReadValue();
            bool inside = RectTransformUtility.RectangleContainsScreenPoint(
                Target, point, null);
            if (mouse.leftButton.wasPressedThisFrame)
            {
                pressedInside = inside;
            }
            if (mouse.leftButton.wasReleasedThisFrame)
            {
                if (pressedInside && inside) ClickCount++;
                pressedInside = false;
            }
        }
    }
}
