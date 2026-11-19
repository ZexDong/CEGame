using System.Collections;
using System.Linq;
using NUnit.Framework;
using OmniGame.Benchmark.ArrowEscape.V2;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    internal sealed class EvaluatorRegressionDirectPollingSurface : MonoBehaviour
    {
    }

    internal sealed class EvaluatorRegressionHierarchyArrowAdapter : MonoBehaviour,
        IArrowEscapeInputTarget
    {
        public string ArrowId { get; set; }
        public GameObject PointerTarget { get; set; }
    }

    [TestFixture]
    public sealed class ArrowEscapeTrajectoryHarnessRegressionTests
    {
        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_UguiMotionIsVisibleInEveryCanvasMode()
        {
            foreach (RenderMode mode in new[]
                     {
                         RenderMode.ScreenSpaceOverlay,
                         RenderMode.ScreenSpaceCamera,
                         RenderMode.WorldSpace
                     })
            {
                GameObject cameraObject = null;
                GameObject canvasObject = null;
                try
                {
                    Camera camera = null;
                    if (mode != RenderMode.ScreenSpaceOverlay)
                    {
                        cameraObject = new GameObject("TrajectoryRegressionCamera", typeof(Camera));
                        camera = cameraObject.GetComponent<Camera>();
                        camera.orthographic = true;
                        camera.orthographicSize = 5f;
                        cameraObject.transform.position = new Vector3(0f, 0f, -10f);
                    }

                    canvasObject = new GameObject("TrajectoryRegressionCanvas",
                        typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
                    Canvas canvas = canvasObject.GetComponent<Canvas>();
                    canvas.renderMode = mode;
                    if (camera != null) canvas.worldCamera = camera;

                    RectTransform canvasRect = canvasObject.GetComponent<RectTransform>();
                    if (mode == RenderMode.WorldSpace)
                    {
                        canvasRect.sizeDelta = new Vector2(800f, 600f);
                        canvasRect.localScale = Vector3.one * 0.01f;
                    }

                    var target = new GameObject("TrajectoryRegressionTarget",
                        typeof(RectTransform), typeof(Image));
                    target.transform.SetParent(canvasObject.transform, false);
                    RectTransform targetRect = target.GetComponent<RectTransform>();
                    targetRect.sizeDelta = new Vector2(80f, 40f);
                    targetRect.anchoredPosition = new Vector2(-50f, 0f);

                    Canvas.ForceUpdateCanvases();
                    yield return null;
                    Rect before = ArrowEscapeTrajectoryHarness.VisibleScreenRect(target);

                    targetRect.anchoredPosition += new Vector2(100f, 0f);
                    Canvas.ForceUpdateCanvases();
                    yield return null;
                    Rect after = ArrowEscapeTrajectoryHarness.VisibleScreenRect(target);

                    Assert.That(before.width, Is.GreaterThan(0f), mode + " width");
                    Assert.That(before.height, Is.GreaterThan(0f), mode + " height");
                    Assert.That(after.center.x, Is.GreaterThan(before.center.x + 0.5f),
                        mode + " horizontal motion");
                }
                finally
                {
                    if (canvasObject != null) Object.DestroyImmediate(canvasObject);
                    if (cameraObject != null) Object.DestroyImmediate(cameraObject);
                }
            }
        }

        [Test]
        public void EVALUATOR_REGRESSION_CompleteExitDoesNotDependOnVisualProjection()
        {
            var exited = new ArrowEscapeArrowSnapshot
            {
                State = ArrowEscapeArrowState.Exited,
                OccupiedCells = System.Array.Empty<ArrowEscapeGridCell>()
            };

            Assert.That(ArrowEscapeTrajectoryHarness.IsCompleteExit(exited), Is.True);
        }

        [Test]
        public void EVALUATOR_REGRESSION_AmbiguousDependencyBadgesSealCandidateNonPass()
        {
            var first = new VisibleArrowTarget { HasKeyBadge = true };
            var second = new VisibleArrowTarget { HasKeyBadge = true };
            Assert.That(DynamicTrajectoryTests.SelectUniqueCandidate(
                System.Array.Empty<VisibleArrowTarget>(), item => item.HasKeyBadge), Is.Null);
            Assert.That(DynamicTrajectoryTests.SelectUniqueCandidate(
                new[] { first, second }, item => item.HasKeyBadge), Is.Null);
            Assert.That(DynamicTrajectoryTests.SelectUniqueCandidate(
                new[] { first }, item => item.HasKeyBadge), Is.SameAs(first));

            var harness = new ArrowEscapeTrajectoryHarness("dependency_chain");
            harness.Expect("dependency.lock_b_available",
                "dependency.lock_b_available.badges",
                "exactly one key-badged middle target",
                "key_badges=2", false,
                "Candidate exposed an ambiguous dependency badge state.");
            harness.SealEvidenceForEvaluatorRegression();

            Assert.That(harness.Evidence.passed, Is.False);
            Assert.That(harness.Evidence.checks_failed, Is.EqualTo(1));
            Assert.That(harness.Evidence.checks_blocked, Is.GreaterThan(0));
            Assert.That(harness.Evidence.failure,
                Does.Contain("ambiguous dependency badge state"));
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_AndRestartWaitsForRecoveringVisibleGroup()
        {
            int observations = 0;
            VisibleGameState finalState = null;
            System.Func<VisibleGameState> observe = () =>
            {
                observations++;
                if (observations < 4)
                {
                    return new VisibleGameState
                    {
                        LevelId = ArrowEscapeContractConstants.ModesLevelId
                    };
                }

                finalState = new VisibleGameState
                {
                    LevelId = ArrowEscapeContractConstants.ModesLevelId,
                    Arrows = new System.Collections.Generic.List<VisibleArrowTarget>
                    {
                        new VisibleArrowTarget { HasKeyBadge = true },
                        new VisibleArrowTarget { HasKeyBadge = true },
                        new VisibleArrowTarget { HasLockBadge = true }
                    }
                };
                return finalState;
            };

            int yieldedFrames = 0;
            IEnumerator wait = DynamicTrajectoryTests.WaitForAndGroupReady(observe, 1f);
            while (wait.MoveNext())
            {
                yieldedFrames++;
                yield return wait.Current;
            }

            Assert.That(yieldedFrames, Is.GreaterThanOrEqualTo(3),
                "The evaluator must not sample the opposite order during transient restart rebuild frames.");
            Assert.That(observations, Is.EqualTo(4));
            Assert.That(DynamicTrajectoryTests.IsAndGroupReady(finalState), Is.True);
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_DestroyedArrowRootSealsVisibleExitObservation()
        {
            EventSystem previousEventSystem = EventSystem.current;
            EventSystem[] existingEventSystems = Object.FindObjectsByType<EventSystem>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            bool[] existingStates = existingEventSystems
                .Select(item => item.gameObject.activeSelf).ToArray();
            foreach (EventSystem item in existingEventSystems)
            {
                item.gameObject.SetActive(false);
            }

            GameObject eventSystemObject = new GameObject(
                "DestroyExitEventSystem", typeof(EventSystem),
                typeof(InputSystemUIInputModule));
            EventSystem.current = eventSystemObject.GetComponent<EventSystem>();
            eventSystemObject.GetComponent<InputSystemUIInputModule>()
                .AssignDefaultActions();
            GameObject canvasObject = new GameObject(
                "DestroyExitCanvas", typeof(RectTransform), typeof(Canvas),
                typeof(GraphicRaycaster));
            canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
            GameObject targetObject = new GameObject(
                "DestroyExitArrow", typeof(RectTransform), typeof(Image),
                typeof(DestroyAfterVisibleMotionRegressionTarget));
            targetObject.transform.SetParent(canvasObject.transform, false);
            RectTransform rect = targetObject.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.anchoredPosition = new Vector2(-200f, 0f);
            rect.sizeDelta = new Vector2(120f, 48f);
            Image image = targetObject.GetComponent<Image>();
            image.color = Color.white;
            image.raycastTarget = true;
            yield return null;
            Canvas.ForceUpdateCanvases();

            var harness = new ArrowEscapeTrajectoryHarness("canonical_success");
            var target = new VisibleArrowTarget
            {
                PointerTarget = targetObject,
                Bounds = ArrowEscapeTrajectoryHarness.VisibleScreenRect(targetObject),
                StableKey = "destroy-exit-regression"
            };
            VisibleExitObservation observation = null;
            yield return harness.ObserveVisibleExit(target,
                "destroy-exit-regression", value => observation = value, "right");

            Assert.That(targetObject == null, Is.True,
                "The candidate fixture must destroy its arrow root after visible travel.");
            Assert.That(observation, Is.Not.Null);
            Assert.That(observation.Removed, Is.True);
            Assert.That(observation.Continuous, Is.True);
            Assert.That(observation.Forward, Is.True,
                "Destroyed is not enough: the fixture must still prove full forward travel.");

            yield return harness.Dispose();
            Object.Destroy(canvasObject);
            Object.Destroy(eventSystemObject);
            for (int index = 0; index < existingEventSystems.Length; index++)
            {
                if (existingEventSystems[index] != null)
                {
                    existingEventSystems[index].gameObject.SetActive(existingStates[index]);
                }
            }
            if (previousEventSystem != null)
            {
                EventSystem.current = previousEventSystem;
            }
            yield return null;
        }

        [Test]
        public void EVALUATOR_REGRESSION_ArrowAdapterWinsOverUiLabelHeuristic()
        {
            Assert.That(ArrowEscapeTrajectoryHarness.ShouldRejectArrowByUiLabel(
                true, "Arrow_hint_clear"), Is.False,
                "a real arrow whose gameplay ID contains 'hint' must not become the Hint UI");
            Assert.That(ArrowEscapeTrajectoryHarness.ShouldRejectArrowByUiLabel(
                false, "Hint"), Is.True,
                "an unadapted Hint-labelled surface remains excluded from generic arrow discovery");
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_DecorativeLineRendererIsNotAnArrowTarget()
        {
            GameObject cameraObject = null;
            GameObject decoration = null;
            Material material = null;
            try
            {
                cameraObject = new GameObject("DecorativeLineCamera", typeof(Camera));
                Camera camera = cameraObject.GetComponent<Camera>();
                camera.orthographic = true;
                camera.orthographicSize = 5f;
                camera.transform.position = new Vector3(0f, 0f, -10f);

                decoration = new GameObject("Grid 0,0", typeof(LineRenderer));
                LineRenderer line = decoration.GetComponent<LineRenderer>();
                material = new Material(Shader.Find("Sprites/Default"));
                line.sharedMaterial = material;
                line.useWorldSpace = false;
                line.positionCount = 2;
                line.SetPosition(0, new Vector3(-0.04f, 0f));
                line.SetPosition(1, new Vector3(0.04f, 0f));
                line.startWidth = line.endWidth = 0.08f;
                yield return null;

                VisibleArrowTarget[] withoutPointerSurface = ArrowEscapeTrajectoryHarness
                    .DiscoverPhysicalArrowTargetsForEvaluatorHealth()
                    .Where(item => item.PointerTarget == decoration)
                    .ToArray();
                Assert.That(withoutPointerSurface, Is.Empty,
                    "a decorative LineRenderer without a player input surface is not an arrow");

                BoxCollider2D collider = decoration.AddComponent<BoxCollider2D>();
                collider.size = Vector2.one * 0.2f;
                yield return null;
                VisibleArrowTarget[] withPointerSurface = ArrowEscapeTrajectoryHarness
                    .DiscoverPhysicalArrowTargetsForEvaluatorHealth()
                    .Where(item => item.PointerTarget == decoration)
                    .ToArray();
                Assert.That(withPointerSurface, Has.Length.EqualTo(1),
                    "the same visible geometry becomes discoverable when backed by a real Collider2D");

                collider.enabled = false;
                VisibleArrowTarget[] movingSurface = ArrowEscapeTrajectoryHarness
                    .DiscoverPhysicalArrowTargetsForEvaluatorHealth()
                    .Where(item => item.PointerTarget == decoration)
                    .ToArray();
                Assert.That(movingSurface, Has.Length.EqualTo(1),
                    "a temporarily disabled moving-arrow collider retains physical identity");
            }
            finally
            {
                if (decoration != null) Object.DestroyImmediate(decoration);
                if (cameraObject != null) Object.DestroyImmediate(cameraObject);
                if (material != null) Object.DestroyImmediate(material);
            }
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_AdapterOwnerAndHeadAreOneArrowTarget()
        {
            GameObject cameraObject = null;
            GameObject root = null;
            Material material = null;
            Texture2D texture = null;
            Sprite sprite = null;
            try
            {
                cameraObject = new GameObject("HierarchyArrowCamera", typeof(Camera));
                cameraObject.tag = "MainCamera";
                Camera camera = cameraObject.GetComponent<Camera>();
                camera.orthographic = true;
                camera.orthographicSize = 5f;
                camera.transform.position = new Vector3(0f, 0f, -10f);

                root = new GameObject("arrow_a", typeof(LineRenderer),
                    typeof(EvaluatorRegressionHierarchyArrowAdapter));
                LineRenderer line = root.GetComponent<LineRenderer>();
                material = new Material(Shader.Find("Sprites/Default"));
                line.sharedMaterial = material;
                line.useWorldSpace = false;
                line.positionCount = 2;
                line.SetPosition(0, new Vector3(-1f, 0f));
                line.SetPosition(1, Vector3.zero);
                line.startWidth = line.endWidth = 0.2f;

                texture = new Texture2D(2, 2);
                texture.SetPixels(new[]
                {
                    Color.white, Color.white, Color.white, Color.white
                });
                texture.Apply();
                sprite = Sprite.Create(texture, new Rect(0f, 0f, 2f, 2f),
                    new Vector2(0.5f, 0.5f), 2f);

                var head = new GameObject("Head", typeof(SpriteRenderer),
                    typeof(BoxCollider2D));
                head.transform.SetParent(root.transform, false);
                head.transform.localPosition = new Vector3(0.5f, 0f, 0f);
                head.GetComponent<SpriteRenderer>().sprite = sprite;

                var badge = new GameObject("KeyBadge", typeof(SpriteRenderer));
                badge.transform.SetParent(root.transform, false);
                badge.transform.localPosition = new Vector3(0f, 0.4f, 0f);
                badge.GetComponent<SpriteRenderer>().sprite = sprite;

                EvaluatorRegressionHierarchyArrowAdapter adapter =
                    root.GetComponent<EvaluatorRegressionHierarchyArrowAdapter>();
                adapter.ArrowId = "arrow_a";
                adapter.PointerTarget = head;
                yield return null;

                VisibleArrowTarget[] matching = ArrowEscapeTrajectoryHarness
                    .DiscoverPhysicalArrowTargetsForEvaluatorHealth()
                    .Where(item => item.PointerTarget == root ||
                                   item.PointerTarget == head)
                    .ToArray();
                Assert.That(matching, Has.Length.EqualTo(1),
                    "a rendered owner plus its collider-backed PointerTarget are one logical arrow");
                Assert.That(matching[0].PointerTarget, Is.SameAs(head),
                    "the adapter's ordinary player pointer surface remains the click target");
                Assert.That(matching[0].HasKeyBadge, Is.True,
                    "visible sibling badge evidence is retained while the wrapper is collapsed");
            }
            finally
            {
                if (root != null) Object.DestroyImmediate(root);
                if (cameraObject != null) Object.DestroyImmediate(cameraObject);
                if (sprite != null) Object.DestroyImmediate(sprite);
                if (texture != null) Object.DestroyImmediate(texture);
                if (material != null) Object.DestroyImmediate(material);
            }
        }

        [Test]
        public void EVALUATOR_REGRESSION_ExactObjectLocatorAcceptsDifferentOverlappingBoundsOnly()
        {
            var physical = new Rect(100f, 100f, 260f, 120f);
            var sameObjectSemantic = new Rect(300f, 140f, 80f, 40f);
            var unrelatedSemantic = new Rect(800f, 500f, 80f, 40f);

            Assert.That(ArrowEscapeTrajectoryHarness
                .PhysicalRectCorroboratesSemantic(physical, sameObjectSemantic), Is.True,
                "a line body plus sprite head may produce wider physical bounds than its public locator");
            Assert.That(ArrowEscapeTrajectoryHarness
                .PhysicalRectCorroboratesSemantic(physical, unrelatedSemantic), Is.False,
                "an object-identity adapter must not legalize a registry Rect elsewhere on screen");
            Assert.That(ArrowEscapeTrajectoryHarness
                .PhysicalRectCorroboratesSemantic(default, sameObjectSemantic), Is.False,
                "registry data without independent physical geometry remains invalid");
        }

        [Test]
        public void EVALUATOR_REGRESSION_ControlSurfaceAllowsOnlyBoundedLayoutOverhang()
        {
            Assert.That(ArrowEscapeTrajectoryHarness.PlayerSurfaceControlWithinFrame(
                new Rect(273.28f, -4.03f, 183.04f, 133.63f)), Is.True,
                "small transparent Button/label layout overhang must not invalidate a readable control");
            Assert.That(ArrowEscapeTrajectoryHarness.PlayerSurfaceControlWithinFrame(
                new Rect(866f, -6f, 116f, 134f)), Is.False,
                "a control extending more than five pixels beyond the player frame remains clipped");
            Assert.That(ArrowEscapeTrajectoryHarness.PlayerSurfaceControlWithinFrame(
                new Rect(100f, 100f, 180f, 64f)), Is.True);
            Assert.That(ArrowEscapeTrajectoryHarness.PlayerSurfaceControlWithinFrame(
                new Rect(-20f, 100f, 180f, 64f)), Is.False);
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_ExactUiLocatorRequiresRealOverlappingGeometry()
        {
            GameObject canvasObject = null;
            GameObject target = null;
            try
            {
                canvasObject = new GameObject("ExactUiLocatorCanvas",
                    typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
                canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
                target = new GameObject("Restart", typeof(RectTransform),
                    typeof(Image), typeof(Button));
                target.transform.SetParent(canvasObject.transform, false);
                RectTransform rect = target.GetComponent<RectTransform>();
                rect.sizeDelta = new Vector2(120f, 56f);
                Canvas.ForceUpdateCanvases();
                yield return null;

                Rect physical = ArrowEscapeTrajectoryHarness.VisibleScreenRect(target);
                var adapter = new StubUiAdapter(ArrowEscapeUiAction.Restart, target);
                var overlapping = new ArrowEscapeVisibleTargetSnapshot
                {
                    Id = "restart",
                    Kind = ArrowEscapeVisibleTargetKind.Restart,
                    ScreenRect = new Rect(physical.center.x - 20f,
                        physical.center.y - 12f, 40f, 24f),
                    Visible = true,
                    Interactable = true
                };

                VisibleUiTarget resolved = ArrowEscapeTrajectoryHarness
                    .ResolveExactAdapterPhysicalTarget(adapter, overlapping);
                Assert.That(resolved, Is.Not.Null,
                    "the same real visible Button may expose a smaller public locator Rect");
                Assert.That(resolved.PointerTarget, Is.SameAs(target));

                overlapping.ScreenRect = new Rect(Screen.width + 200f,
                    Screen.height + 200f, 40f, 24f);
                Assert.That(ArrowEscapeTrajectoryHarness
                    .ResolveExactAdapterPhysicalTarget(adapter, overlapping), Is.Null,
                    "a public locator cannot legalize unrelated or off-screen geometry");

                target.GetComponent<Image>().enabled = false;
                Assert.That(ArrowEscapeTrajectoryHarness
                    .ResolveExactAdapterPhysicalTarget(adapter, new ArrowEscapeVisibleTargetSnapshot
                    {
                        Id = "restart",
                        Kind = ArrowEscapeVisibleTargetKind.Restart,
                        ScreenRect = physical,
                        Visible = true,
                        Interactable = true
                    }), Is.Null,
                    "the adapter cannot self-prove a control with no live visible geometry");
            }
            finally
            {
                if (target != null) Object.DestroyImmediate(target);
                if (canvasObject != null) Object.DestroyImmediate(canvasObject);
            }
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_StandardUguiButtonHasOnePhysicalInputSurface()
        {
            GameObject canvasObject = null;
            GameObject buttonObject = null;
            GameObject labelObject = null;
            try
            {
                canvasObject = new GameObject("PassiveDuplicateRegressionCanvas",
                    typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler),
                    typeof(GraphicRaycaster));
                canvasObject.GetComponent<Canvas>().renderMode =
                    RenderMode.ScreenSpaceOverlay;

                buttonObject = new GameObject("Hint", typeof(RectTransform),
                    typeof(Image), typeof(Button));
                buttonObject.transform.SetParent(canvasObject.transform, false);
                RectTransform buttonRect = buttonObject.GetComponent<RectTransform>();
                buttonRect.anchorMin = buttonRect.anchorMax = new Vector2(0.5f, 0.5f);
                buttonRect.sizeDelta = new Vector2(180f, 64f);

                labelObject = new GameObject("Hint Text", typeof(RectTransform),
                    typeof(Text));
                labelObject.transform.SetParent(buttonObject.transform, false);
                RectTransform labelRect = labelObject.GetComponent<RectTransform>();
                labelRect.anchorMin = Vector2.zero;
                labelRect.anchorMax = Vector2.one;
                labelRect.offsetMin = Vector2.zero;
                labelRect.offsetMax = Vector2.zero;
                Text label = labelObject.GetComponent<Text>();
                label.text = "HINT";
                label.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                label.raycastTarget = false;

                Canvas.ForceUpdateCanvases();
                yield return null;

                VisibleUiTarget[] local = ArrowEscapeTrajectoryHarness
                    .DiscoverPhysicalUiTargetsForEvaluatorRegression(
                        ArrowEscapeUiAction.Hint)
                    .Where(item => item.PointerTarget == canvasObject ||
                                   item.PointerTarget == buttonObject ||
                                   item.PointerTarget == labelObject)
                    .ToArray();

                Assert.That(local, Has.Length.EqualTo(1),
                    "CanvasScaler/GraphicRaycaster and child Text are passive UI " +
                    "components, not extra direct-polling input surfaces.");
                Assert.That(local[0].PointerTarget, Is.SameAs(buttonObject));
                Assert.That(local[0].Technology, Is.EqualTo("uGUI.Button"));
            }
            finally
            {
                if (canvasObject != null) Object.DestroyImmediate(canvasObject);
            }
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_CandidateDirectPollingSurfaceRemainsSupported()
        {
            GameObject canvasObject = null;
            GameObject targetObject = null;
            try
            {
                canvasObject = new GameObject("DirectPollingRegressionCanvas",
                    typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
                canvasObject.GetComponent<Canvas>().renderMode =
                    RenderMode.ScreenSpaceOverlay;

                targetObject = new GameObject("Retry", typeof(RectTransform),
                    typeof(Image), typeof(EvaluatorRegressionDirectPollingSurface));
                targetObject.transform.SetParent(canvasObject.transform, false);
                RectTransform targetRect = targetObject.GetComponent<RectTransform>();
                targetRect.anchorMin = targetRect.anchorMax = new Vector2(0.5f, 0.5f);
                targetRect.sizeDelta = new Vector2(180f, 64f);

                Canvas.ForceUpdateCanvases();
                yield return null;

                VisibleUiTarget[] local = ArrowEscapeTrajectoryHarness
                    .DiscoverPhysicalUiTargetsForEvaluatorRegression(
                        ArrowEscapeUiAction.Restart)
                    .Where(item => item.PointerTarget == targetObject)
                    .ToArray();

                Assert.That(local, Has.Length.EqualTo(1),
                    "candidate-authored visible direct-polling geometry must remain " +
                    "available after passive Unity UI components are excluded");
                Assert.That(local[0].Technology, Does.Contain("direct Input System polling"));
            }
            finally
            {
                if (canvasObject != null) Object.DestroyImmediate(canvasObject);
            }
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_BareUguiGraphicSupportsSceneLevelDirectPolling()
        {
            GameObject canvasObject = null;
            GameObject controllerObject = null;
            GameObject targetObject = null;
            try
            {
                canvasObject = new GameObject("BareGraphicRegressionCanvas",
                    typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
                canvasObject.GetComponent<Canvas>().renderMode =
                    RenderMode.ScreenSpaceOverlay;

                // The candidate-owned polling behaviour deliberately lives on a
                // separate scene controller, matching implementations that compare
                // Mouse.current against several runtime-created RectTransforms.
                controllerObject = new GameObject("SceneDirectPollingController",
                    typeof(EvaluatorRegressionDirectPollingSurface));
                targetObject = new GameObject("Restart", typeof(RectTransform),
                    typeof(Image));
                targetObject.transform.SetParent(canvasObject.transform, false);
                RectTransform targetRect = targetObject.GetComponent<RectTransform>();
                targetRect.anchorMin = targetRect.anchorMax = new Vector2(0.5f, 0.5f);
                targetRect.sizeDelta = new Vector2(180f, 64f);
                Assert.That(targetObject.GetComponent<Button>(), Is.Null);
                Assert.That(ExecuteEvents.GetEventHandler<IPointerClickHandler>(targetObject),
                    Is.Null);

                Canvas.ForceUpdateCanvases();
                yield return null;

                VisibleUiTarget[] local = ArrowEscapeTrajectoryHarness
                    .DiscoverPhysicalUiTargetsForEvaluatorRegression(
                        ArrowEscapeUiAction.Restart)
                    .Where(item => item.PointerTarget == targetObject)
                    .ToArray();

                Assert.That(local, Has.Length.EqualTo(1),
                    "a visible raycastable uGUI Graphic must remain available when " +
                    "Mouse.current polling is owned by a separate scene controller");
                Assert.That(local[0].Technology,
                    Does.Contain("uGUI.Graphic").And.Contain("direct Input System polling"));
            }
            finally
            {
                if (targetObject != null) Object.DestroyImmediate(targetObject);
                if (controllerObject != null) Object.DestroyImmediate(controllerObject);
                if (canvasObject != null) Object.DestroyImmediate(canvasObject);
            }
        }

        [UnityTest]
        public IEnumerator EVALUATOR_REGRESSION_ExactArrowLocatorRequiresVisibleInputSurface()
        {
            GameObject canvasObject = null;
            GameObject target = null;
            try
            {
                canvasObject = new GameObject("ExactArrowLocatorCanvas",
                    typeof(RectTransform), typeof(Canvas), typeof(GraphicRaycaster));
                canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
                target = new GameObject("Arrow_alpha", typeof(RectTransform),
                    typeof(Image), typeof(BoxCollider2D));
                target.transform.SetParent(canvasObject.transform, false);
                RectTransform rect = target.GetComponent<RectTransform>();
                rect.sizeDelta = new Vector2(160f, 64f);
                Canvas.ForceUpdateCanvases();
                yield return null;

                Rect physical = ArrowEscapeTrajectoryHarness.VisibleScreenRect(target);
                var adapter = new StubArrowAdapter("alpha", target);
                var semantic = new ArrowEscapeVisibleTargetSnapshot
                {
                    Id = "alpha",
                    Kind = ArrowEscapeVisibleTargetKind.Arrow,
                    ScreenRect = new Rect(physical.center.x - 24f,
                        physical.center.y - 12f, 48f, 24f),
                    Visible = true,
                    Interactable = true
                };

                VisibleArrowTarget resolved = ArrowEscapeTrajectoryHarness
                    .ResolveExactArrowAdapterPhysicalTarget(adapter, semantic);
                Assert.That(resolved, Is.Not.Null,
                    "the exact adapter is legal only after real geometry and an input surface corroborate it");
                Assert.That(resolved.PointerTarget, Is.SameAs(target));

                target.GetComponent<Image>().enabled = false;
                Assert.That(ArrowEscapeTrajectoryHarness
                    .ResolveExactArrowAdapterPhysicalTarget(adapter, semantic), Is.Null,
                    "a collider plus registry entry cannot self-prove an invisible arrow");
            }
            finally
            {
                if (target != null) Object.DestroyImmediate(target);
                if (canvasObject != null) Object.DestroyImmediate(canvasObject);
            }
        }

        [Test]
        public void EVALUATOR_REGRESSION_RestartTreatsNullAndEmptyOptionalIdsAsTheSameFreshState()
        {
            var expected = new ArrowEscapeGameSnapshot
            {
                LevelId = "level",
                Phase = ArrowEscapeGamePhase.Playing,
                InitialBudget = 3,
                RemainingBudget = 3,
                LastSelectedArrowId = null,
                LastHintArrowId = null,
                StateRevision = 4,
                Arrows = System.Array.Empty<ArrowEscapeArrowSnapshot>()
            };
            var actual = new ArrowEscapeGameSnapshot
            {
                LevelId = "level",
                Phase = ArrowEscapeGamePhase.Playing,
                InitialBudget = 3,
                RemainingBudget = 3,
                LastSelectedArrowId = string.Empty,
                LastHintArrowId = string.Empty,
                StateRevision = 5,
                Arrows = System.Array.Empty<ArrowEscapeArrowSnapshot>()
            };

            Assert.That(ArrowEscapeTrajectoryHarness.RestartEquivalent(expected, actual), Is.True);
        }

        [Test]
        public void EVALUATOR_REGRESSION_ExitedSnapshotMustReleaseLogicalOccupancy()
        {
            var stale = new ArrowEscapeArrowSnapshot
            {
                State = ArrowEscapeArrowState.Exited,
                OccupiedCells = new[] { new ArrowEscapeGridCell(6, 2) }
            };

            Assert.That(ArrowEscapeTrajectoryHarness.IsCompleteExit(stale), Is.False);
        }

        [Test]
        public void EVALUATOR_REGRESSION_CanonicalJourneyUsesEveryAuthoredActiveArrow()
        {
            var snapshot = new ArrowEscapeGameSnapshot
            {
                Arrows = Enumerable.Range(0, 4).Select(index => new ArrowEscapeArrowSnapshot
                {
                    Id = "arrow_" + index,
                    State = ArrowEscapeArrowState.Available,
                    OccupiedCells = new[]
                    {
                        new ArrowEscapeGridCell(1, index),
                        new ArrowEscapeGridCell(0, index)
                    }
                }).ToArray()
            };

            Assert.That(DynamicTrajectoryTests.CanonicalActiveArrowCount(snapshot), Is.EqualTo(4));
        }

        [Test]
        public void EVALUATOR_REGRESSION_ExitObservationUsesTheFullPublicFourSecondWindow()
        {
            Assert.That(ArrowEscapeTrajectoryHarness.ExitObservationWindowOpen(0.009f, false),
                Is.True, "a slow-start animation must not be rejected after a few fast headless frames");
            Assert.That(ArrowEscapeTrajectoryHarness.ExitObservationWindowOpen(3.999f, false),
                Is.True);
            Assert.That(ArrowEscapeTrajectoryHarness.ExitObservationWindowOpen(4f, false),
                Is.False);
            Assert.That(ArrowEscapeTrajectoryHarness.ExitObservationWindowOpen(0.1f, true),
                Is.False);
        }

        [TestCase(6, 4, 2)]
        [TestCase(6, 6, 0)]
        [TestCase(3, 4, -1)]
        public void EVALUATOR_REGRESSION_LastMoveSetupConsumesOnlyMovesBudgetSurplus(
            int initialBudget, int authoredArrowCount, int expectedBlockedAttempts)
        {
            Assert.That(DynamicTrajectoryTests.RequiredBlockedAttemptsForLastMove(
                initialBudget, authoredArrowCount), Is.EqualTo(expectedBlockedAttempts));
        }

        [Test]
        public void EVALUATOR_REGRESSION_BlockedDiscoveryWaitsOnlyForMatchingPublicBlockedOutcome()
        {
            var target = new VisibleArrowTarget { SemanticId = "blocked_arrow" };
            var snapshot = new ArrowEscapeGameSnapshot
            {
                Phase = ArrowEscapeGamePhase.Playing,
                BudgetMode = ArrowEscapeBudgetMode.Moves,
                RemainingBudget = 4,
                LastSelectedArrowId = "blocked_arrow",
                LastSelectionOutcome = ArrowEscapeSelectionOutcome.Blocked,
                LastInputSource = ArrowEscapeInputSource.PlayerPointer
            };

            Assert.That(DynamicTrajectoryTests.RequiresBlockedExitWindow(
                snapshot, target, 5), Is.True,
                "a matching normal blocked attempt still receives the complete physical exit window");

            snapshot.LastSelectionOutcome = ArrowEscapeSelectionOutcome.StartedExit;
            Assert.That(DynamicTrajectoryTests.RequiresBlockedExitWindow(
                snapshot, target, 5), Is.False,
                "a clear attempt must not consume four seconds during blocked-target discovery");

            snapshot.LastSelectionOutcome = ArrowEscapeSelectionOutcome.Ignored;
            Assert.That(DynamicTrajectoryTests.RequiresBlockedExitWindow(
                snapshot, target, 5), Is.False,
                "an ignored or non-committing candidate target must be skipped immediately");

            snapshot.LastSelectionOutcome = ArrowEscapeSelectionOutcome.Blocked;
            snapshot.LastSelectedArrowId = "another_arrow";
            Assert.That(DynamicTrajectoryTests.RequiresBlockedExitWindow(
                snapshot, target, 5), Is.False,
                "a different selected ID cannot authorize waiting on this visible target");

            snapshot.LastSelectedArrowId = "blocked_arrow";
            snapshot.LastInputSource = ArrowEscapeInputSource.None;
            Assert.That(DynamicTrajectoryTests.RequiresBlockedExitWindow(
                snapshot, target, 5), Is.False,
                "read-only state without a normal player-pointer source cannot select the scored path");
        }

        [Test]
        public void EVALUATOR_REGRESSION_LargeIgnoredCandidateSetHasZeroFullExitWaits()
        {
            int waits = Enumerable.Range(0, 64).Count(index =>
                DynamicTrajectoryTests.RequiresBlockedExitWindow(
                    new ArrowEscapeGameSnapshot
                    {
                        Phase = ArrowEscapeGamePhase.Playing,
                        BudgetMode = ArrowEscapeBudgetMode.Moves,
                        RemainingBudget = 64,
                        LastSelectedArrowId = "arrow_" + index,
                        LastSelectionOutcome = ArrowEscapeSelectionOutcome.Ignored,
                        LastInputSource = ArrowEscapeInputSource.PlayerPointer
                    },
                    new VisibleArrowTarget { SemanticId = "arrow_" + index },
                    64));

            Assert.That(waits, Is.Zero,
                "large non-committing boards must seal candidate non-pass evidence instead of reaching Unity's 180-second default timeout");
        }

        [Test]
        public void EVALUATOR_REGRESSION_ContinuousCardinalJourneyAliasesObservedDirectionChecks()
        {
            var harness = new ArrowEscapeTrajectoryHarness("motion_cardinals");
            harness.Expect("motion.sequence.1", "motion.sequence.1.input.top_hit",
                "visible target", "visible target", true);
            harness.Expect("motion.sequence.1", "motion.sequence.1.moving",
                "movement", "movement", true);

            harness.AliasStepChecks("motion.sequence.1", "motion.exit.up");

            TrajectoryCheckEvidence[] checks = harness.Evidence.steps
                .SelectMany(step => step.checks).ToArray();
            Assert.That(checks.Any(check =>
                check.check_id == "motion.exit.up.input.top_hit" && check.status == "pass"),
                Is.True);
            Assert.That(checks.Any(check =>
                check.check_id == "motion.exit.up.moving" && check.status == "pass"),
                Is.True);
        }

        [Test]
        public void EVALUATOR_REGRESSION_VisibleShapeAllowsHintTintAndTransientFeedback()
        {
            var root = new GameObject("VisibleStyleRegressionRoot",
                typeof(RectTransform), typeof(Image));
            var headObject = new GameObject("Arrow Head", typeof(RectTransform), typeof(Text));
            headObject.transform.SetParent(root.transform, false);
            Text head = headObject.GetComponent<Text>();
            var feedbackObject = new GameObject("Feedback", typeof(RectTransform), typeof(Text));
            feedbackObject.transform.SetParent(root.transform, false);
            Text feedback = feedbackObject.GetComponent<Text>();
            try
            {
                head.text = "▲";
                head.fontSize = 32;
                feedback.text = string.Empty;
                Image body = root.GetComponent<Image>();
                body.color = Color.cyan;
                head.color = Color.cyan;
                string baseline = ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root);

                body.color = Color.yellow;
                head.color = Color.yellow;
                string tinted = ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root);
                Assert.That(tinted, Is.EqualTo(baseline),
                    "a legal Hint tint must not be classified as shape destruction");

                feedback.text = "CLEAR PATH";
                feedback.color = Color.yellow;
                string withFeedback = ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root);
                Assert.That(withFeedback, Is.EqualTo(baseline),
                    "transient captions are not part of an arrow that already has core geometry");
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStylePreserved(
                    baseline, withFeedback), Is.True,
                    "temporary visible feedback may add geometry without replacing the arrow core");

                feedback.text = string.Empty;
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root),
                    Is.EqualTo(baseline));
            }
            finally
            {
                Object.DestroyImmediate(root);
            }
        }

        [TestCase("MOVES  6", "Moves", 6)]
        [TestCase("HEARTS ♥ 3", "Hearts", 3)]
        [TestCase("Hearts remaining: 2", "Hearts", 2)]
        [TestCase("Mode: Moves | Remaining 0", "Moves", 0)]
        [TestCase("4 | REMAINING | MOVES", "Moves", 4)]
        [TestCase("2 | HEARTS", "Hearts", 2)]
        public void EVALUATOR_REGRESSION_BudgetParserAcceptsVisibleModeDecorations(
            string visibleText, string expectedMode, int expectedRemaining)
        {
            Assert.That(ArrowEscapeTrajectoryHarness.TryParseVisibleBudget(
                visibleText, out string mode, out int remaining), Is.True);
            Assert.That(mode, Is.EqualTo(expectedMode));
            Assert.That(remaining, Is.EqualTo(expectedRemaining));
        }

        [Test]
        public void EVALUATOR_REGRESSION_BudgetParserDoesNotPairModeWithLevelCounter()
        {
            Assert.That(ArrowEscapeTrajectoryHarness.TryParseVisibleBudget(
                new[]
                {
                    "1 / 3   TUTORIAL",
                    "BUDGET MODE  •  MOVES",
                    "8 MOVES"
                }, out string mode, out int remaining), Is.True);
            Assert.That(mode, Is.EqualTo("Moves"));
            Assert.That(remaining, Is.EqualTo(8),
                "The level counter must not replace the visible remaining budget.");

            Assert.That(ArrowEscapeTrajectoryHarness.TryParseVisibleBudget(
                new[] { "LEVEL 1 • TUTORIAL", "MOVES", "4", "REMAINING" },
                out mode, out remaining), Is.True);
            Assert.That(mode, Is.EqualTo("Moves"));
            Assert.That(remaining, Is.EqualTo(4));
        }

        [TestCase("LEVEL 1  •  TUTORIAL", "tutorial")]
        [TestCase("LEVEL 2  •  MODES & HINT", "modes_and_hint")]
        [TestCase("LEVEL 3  •  KEY CHAIN", "prerequisite_chain")]
        [TestCase("prerequisite_chain", "prerequisite_chain")]
        public void EVALUATOR_REGRESSION_FriendlyLevelLabelsResolveToCanonicalIds(
            string visibleText, string expectedLevelId)
        {
            Assert.That(ArrowEscapeTrajectoryHarness.ResolveVisibleLevelId(visibleText),
                Is.EqualTo(expectedLevelId));
            Assert.That(ArrowEscapeTrajectoryHarness.VisibleLevelMatchesSnapshot(
                new[] { visibleText }, expectedLevelId), Is.True);
        }

        [Test]
        public void EVALUATOR_REGRESSION_ModeAndBudgetMayUseSeparateVisibleTexts()
        {
            Assert.That(ArrowEscapeTrajectoryHarness.VisibleBudgetMatchesSnapshot(
                new[] { "MOVES", "4", "REMAINING" },
                ArrowEscapeBudgetMode.Moves, 4), Is.True);
            Assert.That(ArrowEscapeTrajectoryHarness.VisibleBudgetMatchesSnapshot(
                new[] { "HEARTS", "2" },
                ArrowEscapeBudgetMode.Hearts, 3), Is.False);
            Assert.That(ArrowEscapeTrajectoryHarness.VisibleBudgetMatchesSnapshot(
                new[] { "LEVEL 1 • TUTORIAL", "MOVES", "REMAINING" },
                ArrowEscapeBudgetMode.Moves, 1), Is.False,
                "the level number alone must not impersonate a missing budget value");
        }

        [Test]
        public void EVALUATOR_REGRESSION_NearEdgeContinuousExitDoesNotRequireViewportQuarterTravel()
        {
            Assert.That(ArrowEscapeTrajectoryHarness.QualifiesCardinalForward(
                "up", "up", 162.9f, 85, 85), Is.True,
                "a continuously moving near-edge arrow may fully exit in less than 25% of the viewport");
            Assert.That(ArrowEscapeTrajectoryHarness.QualifiesCardinalForward(
                "up", "right", 162.9f, 85, 85), Is.False);
            Assert.That(ArrowEscapeTrajectoryHarness.QualifiesCardinalForward(
                "up", "up", 162.9f, 1, 1), Is.False,
                "teleport-like or one-frame removal remains rejected");
        }

        [Test]
        public void EVALUATOR_REGRESSION_EmptyFeedbackTextColorDoesNotPreventRecovery()
        {
            var root = new GameObject("FeedbackSignatureRegression",
                typeof(RectTransform), typeof(Image));
            var feedbackObject = new GameObject("Feedback",
                typeof(RectTransform), typeof(Text));
            feedbackObject.transform.SetParent(root.transform, false);
            Text feedback = feedbackObject.GetComponent<Text>();
            try
            {
                feedback.text = string.Empty;
                feedback.color = Color.white;
                string baseline = ArrowEscapeTrajectoryHarness.VisualSignature(root);

                feedback.text = "CLEAR PATH";
                feedback.color = Color.yellow;
                Assert.That(ArrowEscapeTrajectoryHarness.VisualSignature(root),
                    Is.Not.EqualTo(baseline), "visible feedback must be observable");

                feedback.text = string.Empty;
                Assert.That(ArrowEscapeTrajectoryHarness.VisualSignature(root),
                    Is.EqualTo(baseline),
                    "an invisible empty Text must not keep feedback permanently changed");
            }
            finally
            {
                Object.DestroyImmediate(root);
            }
        }

        [Test]
        public void EVALUATOR_REGRESSION_TextOnlyDirectionalGlyphRemainsCoreShape()
        {
            var root = new GameObject("TextOnlyArrow", typeof(RectTransform));
            var headObject = new GameObject("Direction", typeof(RectTransform), typeof(Text));
            headObject.transform.SetParent(root.transform, false);
            Text head = headObject.GetComponent<Text>();
            head.text = "→";
            head.fontSize = 36;
            var feedbackObject = new GameObject("Feedback", typeof(RectTransform), typeof(Text));
            feedbackObject.transform.SetParent(root.transform, false);
            Text feedback = feedbackObject.GetComponent<Text>();
            try
            {
                string baseline = ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root);
                feedback.text = "CLEAR PATH";
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root),
                    Is.EqualTo(baseline), "temporary text must not replace the directional glyph");

                head.text = string.Empty;
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStylePreserved(
                    baseline, ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root)), Is.False,
                    "a text-only arrow loses its recognizable shape when its direction glyph vanishes");
            }
            finally
            {
                Object.DestroyImmediate(root);
            }
        }

        [Test]
        public void EVALUATOR_REGRESSION_VisibleShapeRejectsTransparentMissingOrDeformedCore()
        {
            var root = new GameObject("VisibleShapeMutationRoot",
                typeof(RectTransform), typeof(Image));
            var headObject = new GameObject("Arrow Head", typeof(RectTransform), typeof(Text));
            headObject.transform.SetParent(root.transform, false);
            Text head = headObject.GetComponent<Text>();
            head.text = "▲";
            head.fontSize = 32;
            Image body = root.GetComponent<Image>();
            try
            {
                string baseline = ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root);

                body.color = new Color(1f, 1f, 1f, 0f);
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStylePreserved(
                    baseline, ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root)), Is.False,
                    "a transparent core component is not a preserved recognizable shape");
                body.color = Color.white;

                head.enabled = false;
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStylePreserved(
                    baseline, ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root)), Is.False,
                    "a missing direction marker must be rejected");
                head.enabled = true;

                root.transform.localScale = new Vector3(0.1f, 2.5f, 1f);
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStylePreserved(
                    baseline, ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root)), Is.False,
                    "severe scale deformation must be rejected");
                root.transform.localScale = Vector3.one;

                head.text = "▼";
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStylePreserved(
                    baseline, ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root)), Is.False,
                    "changing the visible direction marker changes the recognizable arrow shape");
            }
            finally
            {
                Object.DestroyImmediate(root);
            }
        }

        [Test]
        public void EVALUATOR_REGRESSION_LineRendererRootTranslationPreservesRecognizableShape()
        {
            var root = new GameObject("MovingPolylineArrow", typeof(LineRenderer));
            LineRenderer line = root.GetComponent<LineRenderer>();
            line.useWorldSpace = false;
            line.startWidth = line.endWidth = 0.17f;
            line.startColor = line.endColor = Color.cyan;
            line.positionCount = 5;
            line.SetPositions(new[]
            {
                Vector3.zero,
                new Vector3(0.95f, 0f),
                new Vector3(0.60f, 0.285f),
                new Vector3(0.95f, 0f),
                new Vector3(0.60f, -0.285f)
            });
            try
            {
                string baseline = ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root);
                root.transform.position = new Vector3(3.25f, -1.5f, 0f);
                string moved = ArrowEscapeTrajectoryHarness.VisibleStyleSignature(root);
                Assert.That(ArrowEscapeTrajectoryHarness.VisibleStylePreserved(
                    baseline, moved), Is.True,
                    ArrowEscapeTrajectoryHarness.VisibleStyleDifference(baseline, moved));
            }
            finally
            {
                Object.DestroyImmediate(root);
            }
        }

        [Test]
        public void EVALUATOR_REGRESSION_HintAcceptanceAllowsEveryLegalCandidate()
        {
            ArrowEscapeLevelSpec level = TrajectoryFixtures.Resolve("hint_composition");
            var snapshot = new ArrowEscapeGameSnapshot
            {
                Phase = ArrowEscapeGamePhase.Playing,
                Arrows = level.Arrows.Select(spec => new ArrowEscapeArrowSnapshot
                {
                    Id = spec.Id,
                    State = spec.Id == "only_clear"
                        ? ArrowEscapeArrowState.Exited
                        : ArrowEscapeArrowState.Available,
                    OccupiedCells = spec.Id == "only_clear"
                        ? System.Array.Empty<ArrowEscapeGridCell>()
                        : spec.Path.ToArray()
                }).ToArray()
            };

            Assert.That(TrajectoryFixtures.LegalHintArrowIds(level, snapshot),
                Is.EquivalentTo(new[] { "blocker", "locked" }));
        }

        [Test]
        public void EVALUATOR_REGRESSION_RestartEquivalenceRequiresCleanPublicStateAndNewRevision()
        {
            ArrowEscapeGameSnapshot baseline = Snapshot(
                lastSelected: null,
                outcome: ArrowEscapeSelectionOutcome.Ignored,
                source: ArrowEscapeInputSource.None,
                lastHint: null,
                revision: 3);
            ArrowEscapeGameSnapshot cleanRestart = Snapshot(
                lastSelected: null,
                outcome: ArrowEscapeSelectionOutcome.Ignored,
                source: ArrowEscapeInputSource.None,
                lastHint: null,
                revision: 8);

            Assert.That(ArrowEscapeTrajectoryHarness.RestartEquivalent(baseline, cleanRestart), Is.True);

            cleanRestart.LastHintArrowId = "stale_hint";
            Assert.That(ArrowEscapeTrajectoryHarness.RestartEquivalent(baseline, cleanRestart), Is.False);
            cleanRestart.LastHintArrowId = null;

            cleanRestart.LastSelectedArrowId = "stale_selection";
            cleanRestart.LastSelectionOutcome = ArrowEscapeSelectionOutcome.Blocked;
            cleanRestart.LastInputSource = ArrowEscapeInputSource.PlayerPointer;
            Assert.That(ArrowEscapeTrajectoryHarness.RestartEquivalent(baseline, cleanRestart), Is.False);

            cleanRestart.LastSelectedArrowId = null;
            cleanRestart.LastSelectionOutcome = ArrowEscapeSelectionOutcome.Ignored;
            cleanRestart.LastInputSource = ArrowEscapeInputSource.None;
            cleanRestart.StateRevision = baseline.StateRevision;
            Assert.That(ArrowEscapeTrajectoryHarness.RestartEquivalent(baseline, cleanRestart), Is.False);
        }

        private static ArrowEscapeGameSnapshot Snapshot(
            string lastSelected,
            ArrowEscapeSelectionOutcome outcome,
            ArrowEscapeInputSource source,
            string lastHint,
            int revision) => new ArrowEscapeGameSnapshot
        {
            LevelId = "regression",
            Phase = ArrowEscapeGamePhase.Playing,
            BudgetMode = ArrowEscapeBudgetMode.Moves,
            InitialBudget = 4,
            RemainingBudget = 4,
            LastSelectedArrowId = lastSelected,
            LastSelectionOutcome = outcome,
            LastInputSource = source,
            LastHintArrowId = lastHint,
            CompletedUiVisible = false,
            FailedUiVisible = false,
            StateRevision = revision,
            Arrows = new[]
            {
                new ArrowEscapeArrowSnapshot
                {
                    Id = "arrow_a",
                    State = ArrowEscapeArrowState.Available,
                    OccupiedCells = new[]
                    {
                        new ArrowEscapeGridCell(1, 1),
                        new ArrowEscapeGridCell(0, 1)
                    }
                }
            }
        };

        private sealed class StubUiAdapter : IArrowEscapeUiInputTarget
        {
            public StubUiAdapter(ArrowEscapeUiAction action, GameObject pointerTarget)
            {
                Action = action;
                PointerTarget = pointerTarget;
            }

            public ArrowEscapeUiAction Action { get; }
            public GameObject PointerTarget { get; }
        }

        private sealed class StubArrowAdapter : IArrowEscapeInputTarget
        {
            public StubArrowAdapter(string arrowId, GameObject pointerTarget)
            {
                ArrowId = arrowId;
                PointerTarget = pointerTarget;
            }

            public string ArrowId { get; }
            public GameObject PointerTarget { get; }
        }
    }

    internal sealed class DestroyAfterVisibleMotionRegressionTarget : MonoBehaviour,
        IPointerClickHandler
    {
        public void OnPointerClick(PointerEventData eventData)
        {
            if (eventData.button == PointerEventData.InputButton.Left)
            {
                StartCoroutine(ExitAndDestroy());
            }
        }

        private IEnumerator ExitAndDestroy()
        {
            RectTransform rect = GetComponent<RectTransform>();
            for (int frame = 0; frame < 6; frame++)
            {
                if (rect == null) yield break;
                rect.anchoredPosition += new Vector2(60f, 0f);
                yield return null;
            }
            Object.DestroyImmediate(gameObject);
        }
    }
}
