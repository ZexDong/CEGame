using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
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
    [TestFixture]
    public sealed class StaticGateTests
    {
        // run-evaluation.ps1 treats only failures carrying this evaluator-owned
        // marker as candidate gate failures. Unexpected exceptions, skipped
        // tests and framework failures invalidate the run instead of inventing
        // a candidate score of zero.
        private const string CandidateFailureMarker = "[OMNIGAME_CANDIDATE_STATIC]";
        private const int CaptureWidth = 192;
        private const int CaptureHeight = 108;
        private const int MinimumForegroundPixels = 16;

        private Camera activeCamera;
        private IArrowEscapeReadOnlyProbe readOnlyProbe;
        private int activeReadOnlyProbeCount;

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            yield return EvaluatorDisplayResolution.Ensure1280x720();
            Assert.That(EvaluatorDisplayResolution.IsCurrentExact, Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Static runtime must execute at the " +
                $"real {EvaluatorDisplayResolution.RequiredWidth}x" +
                $"{EvaluatorDisplayResolution.RequiredHeight} display; " +
                EvaluatorDisplayResolution.Diagnostic + ".");

            // Evaluator-owned regression tests must remain runnable even when
            // the candidate has no canonical gameplay scene.  Otherwise a
            // clean starter/input project turns this health check into a
            // SetUp failure and the runner incorrectly reports an evaluator
            // infrastructure error instead of an attributable low candidate
            // score.
            if (TestContext.CurrentContext.Test.Name.StartsWith(
                    "EVALUATOR_", StringComparison.Ordinal))
            {
                yield break;
            }

            AsyncOperation load = SceneManager.LoadSceneAsync(
                ArrowEscapeContractConstants.MainScenePath,
                LoadSceneMode.Single);
            RequireCandidate(load != null,
                "The canonical scene must be enabled in Build Settings and loadable by path.");

            float deadline = Time.realtimeSinceStartup + 10f;
            while (!load.isDone && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }
            RequireCandidate(load.isDone,
                "The canonical scene did not finish loading within ten seconds.");

            // Let Awake/Start, Canvas layout and one normal rendered frame settle.
            yield return null;
            yield return null;

            activeCamera = UnityEngine.Object
                .FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(camera => camera.isActiveAndEnabled);
            RequireCandidate(activeCamera != null,
                "The playable scene must have an active enabled camera.");

            IArrowEscapeReadOnlyProbe[] probes = UnityEngine.Object
                .FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Where(item => item != null && item.isActiveAndEnabled &&
                               item.gameObject.activeInHierarchy)
                .OfType<IArrowEscapeReadOnlyProbe>()
                .ToArray();
            activeReadOnlyProbeCount = probes.Length;
            readOnlyProbe = probes.Length == 1 ? probes[0] : null;
        }

        [UnityTearDown]
        public IEnumerator RestoreFormalResolution()
        {
            EvaluatorDisplayResolution.Restore();
            yield return null;
        }

        [Test]
        public void EVALUATOR_HEALTH_StaticResolution1280x720()
        {
            Assert.That(EvaluatorDisplayResolution.IsCurrentExact, Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Static runtime resolution drifted after setup.");
            string output = CommandLineValue("-omnigameStaticOutput");
            Assert.That(output, Is.Not.Null.And.Not.Empty,
                "[OMNIGAME_EVALUATOR_HEALTH] Static health output argument is missing.");
            Directory.CreateDirectory(output);
            string path = Path.Combine(output, "evaluator-health-static.json");
            var evidence = new StaticEvaluatorHealthEvidence
            {
                process_id = System.Diagnostics.Process.GetCurrentProcess().Id,
                screen_width = Screen.width,
                screen_height = Screen.height,
                required_width = EvaluatorDisplayResolution.RequiredWidth,
                required_height = EvaluatorDisplayResolution.RequiredHeight,
                resolution_exact = EvaluatorDisplayResolution.IsCurrentExact,
                configuration_route = EvaluatorDisplayResolution.ConfigurationRoute
            };
            File.WriteAllText(path, JsonUtility.ToJson(evidence, true));
            Assert.That(File.Exists(path), Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Static resolution evidence was not written.");
        }

        [Test]
        public void EVALUATOR_REGRESSION_Legacy640x480IsNotAcceptedAsFormalResolution()
        {
            Assert.That(EvaluatorDisplayResolution.IsExact(1280, 720), Is.True);
            Assert.That(EvaluatorDisplayResolution.IsExact(640, 480), Is.False,
                "The legacy Editor PlayMode default must never satisfy the formal contract.");
        }

        [UnityTest]
        public IEnumerator STATIC01_ProjectStartsInAPlayableRenderedScene()
        {
            RequireCandidate(SceneManager.GetActiveScene().path ==
                             ArrowEscapeContractConstants.MainScenePath,
                "The canonical gameplay scene is not the active scene after loading.");
            RequireCandidate(activeCamera != null && activeCamera.isActiveAndEnabled,
                "The gameplay camera is not active and enabled.");

            int initialFrame = Time.frameCount;
            yield return null;
            RequireCandidate(Time.frameCount > initialFrame,
                "The loaded project did not advance a normal Unity frame.");
        }

        [UnityTest]
        public IEnumerator STATIC02_CameraProducesANonEmptyFrameWithoutGuiAutomation()
        {
            // CaptureScreenshotAsTexture reads the last composited player
            // frame without relying on WaitForEndOfFrame, which is unreliable
            // in batch-mode Test Runner sessions.
            yield return null;
            yield return null;
            FrameStats frame = CaptureFrame(activeCamera);
            bool compositeCaptured = TryCaptureCompositedFrame(
                out FrameStats compositeFrame);
            ArrowEscapeGameSnapshot snapshot = readOnlyProbe?.CaptureBenchmarkSnapshot();
            bool supportedLayerVisible = IsVisiblyRendered(frame) ||
                                         (compositeCaptured && IsPixelFrameVisible(compositeFrame)) ||
                                         (HasValidVisibleRegistry(snapshot) &&
                                          HasActiveImGuiDrawingPresenter());
            RequireCandidate(supportedLayerVisible,
                "No camera/UI/composited or registry-backed visible game presentation was found.");
        }

        [UnityTest]
        public IEnumerator STATIC03_NormalInputTargetsAreExplicitAndDiscoverable()
        {
            RequireCandidate(activeReadOnlyProbeCount == 1,
                $"The public Unity v2 profile requires exactly one active " +
                $"IArrowEscapeReadOnlyProbe; found {activeReadOnlyProbeCount}.");
            RequireCandidate(readOnlyProbe != null &&
                             readOnlyProbe.ContractVersion == "3.0",
                "The read-only probe must report public contract version 3.0.");
            ArrowEscapeGameSnapshot snapshot = readOnlyProbe.CaptureBenchmarkSnapshot();
            RequireCandidate(snapshot != null && snapshot.Arrows != null,
                "The read-only probe did not return a usable player-visible snapshot.");
            RequireCandidate(HasValidVisibleRegistry(snapshot),
                "The read-only probe must expose unique finite on-screen target Rects for " +
                "visible arrows, Hint, Restart and Next Level.");
            EventSystem[] eventSystems = UnityEngine.Object
                .FindObjectsByType<EventSystem>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Where(item => item.isActiveAndEnabled)
                .ToArray();
            // EventSystem/uGUI, UI Toolkit, Collider callbacks, and direct
            // Mouse.current polling are all valid normal Input System
            // organizations. If a candidate chooses an EventSystem route it
            // must not leave duplicate enabled EventSystems, but D1 must not
            // force that component architecture on every valid solution.
            RequireCandidate(eventSystems.Length <= 1,
                $"Expected zero or one enabled EventSystem, found {eventSystems.Length}.");
            if (eventSystems.Length == 1 &&
                eventSystems[0].currentInputModule is InputSystemUIInputModule module)
            {
                RequireCandidate(module.isActiveAndEnabled,
                    "The candidate's InputSystemUIInputModule is disabled.");
            }

            int initialFrame = Time.frameCount;
            yield return null;
            yield return null;

            RequireCandidate(Time.frameCount >= initialFrame + 2,
                "The project stopped advancing normal Unity frames after startup.");
            if (HasSupportedDynamicInputSurface(snapshot)) yield break;
            RequireCandidate(false,
                "No active player-visible target uses the public Unity Input System route. " +
                "Event.current/GUI.Button-only gameplay is outside this submission profile.");
        }

        [Test]
        public void EVALUATOR_REGRESSION_EmptyOnGuiIsNotTreatedAsVisibleImGui()
        {
            MethodInfo empty = typeof(EmptyOnGuiRegressionProbe).GetMethod(
                "OnGUI", BindingFlags.Instance | BindingFlags.NonPublic);
            MethodInfo drawing = typeof(DrawingOnGuiRegressionProbe).GetMethod(
                "OnGUI", BindingFlags.Instance | BindingFlags.NonPublic);

            Assert.That(MethodUsesImmediateModeDrawing(empty,
                new HashSet<MethodBase>(), 0), Is.False,
                "An empty OnGUI method must remain an attributable candidate failure.");
            Assert.That(MethodUsesImmediateModeDrawing(drawing,
                new HashSet<MethodBase>(), 0), Is.True,
                "The conservative fallback must recognize a real immediate-mode draw call.");
        }

        private static bool IsVisiblyRendered(FrameStats cameraFrame)
        {
            if (IsPixelFrameVisible(cameraFrame)) return true;

            // Camera.Render does not composite Screen Space Overlay uGUI. A
            // UI-only implementation can therefore be fully visible and
            // playable to a human while its camera target remains a uniform
            // clear color. Accept an actually active, non-culled overlay
            // Graphic whose transformed rectangle overlaps the display.
            return UnityEngine.Object
                .FindObjectsByType<Graphic>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Any(IsVisibleOverlayGraphic) || HasVisibleUiToolkitContent();
        }

        private static bool IsPixelFrameVisible(FrameStats frame) =>
            frame.QuantizedColorCount >= 2 &&
            frame.NonDominantPixelCount >= MinimumForegroundPixels;

        private static bool HasActiveImGuiDrawingPresenter()
        {
            return UnityEngine.Object
                .FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Any(DeclaresDrawingOnGuiMessage);
        }

        private static bool DeclaresDrawingOnGuiMessage(MonoBehaviour behaviour)
        {
            if (behaviour == null || !behaviour.isActiveAndEnabled ||
                !behaviour.gameObject.activeInHierarchy)
            {
                return false;
            }

            for (Type type = behaviour.GetType();
                 type != null && type != typeof(MonoBehaviour);
                 type = type.BaseType)
            {
                MethodInfo method = type.GetMethod(
                    "OnGUI",
                    BindingFlags.Instance | BindingFlags.Public |
                    BindingFlags.NonPublic | BindingFlags.DeclaredOnly,
                    null,
                    Type.EmptyTypes,
                    null);
                if (method != null && method.ReturnType == typeof(void))
                {
                    return MethodUsesImmediateModeDrawing(
                        method, new HashSet<MethodBase>(), 0);
                }
            }

            return false;
        }

        private sealed class EmptyOnGuiRegressionProbe : MonoBehaviour
        {
            private void OnGUI() { }
        }

        private sealed class DrawingOnGuiRegressionProbe : MonoBehaviour
        {
            private void OnGUI()
            {
                GUI.Label(new Rect(0f, 0f, 10f, 10f), "probe");
            }
        }

        private static bool MethodUsesImmediateModeDrawing(
            MethodBase method,
            ISet<MethodBase> visited,
            int depth)
        {
            if (method == null || depth > 12 || !visited.Add(method)) return false;
            foreach (MethodBase called in CalledMethods(method))
            {
                if (IsImmediateModeDrawCall(called)) return true;
                if (called?.DeclaringType?.Assembly == method.DeclaringType?.Assembly &&
                    MethodUsesImmediateModeDrawing(called, visited, depth + 1))
                {
                    return true;
                }
            }
            return false;
        }

        private static bool IsImmediateModeDrawCall(MethodBase method)
        {
            Type type = method?.DeclaringType;
            string name = method?.Name ?? "";
            if (type == typeof(GUI))
            {
                return name is "Label" or "Box" or "Button" or "RepeatButton" or
                    "Toggle" or "TextField" or "PasswordField" or "TextArea" or
                    "Window" or "ModalWindow" or "DrawTexture" or
                    "DrawTextureWithTexCoords";
            }
            if (type == typeof(GUILayout))
            {
                return name is "Label" or "Box" or "Button" or "RepeatButton" or
                    "Toggle" or "TextField" or "PasswordField" or "TextArea" or
                    "Window";
            }
            return (type == typeof(GUIStyle) && name == "Draw") ||
                   (type == typeof(Graphics) && name.StartsWith(
                       "DrawTexture", StringComparison.Ordinal));
        }

        private static IEnumerable<MethodBase> CalledMethods(MethodBase method)
        {
            byte[] bytes;
            try
            {
                bytes = method?.GetMethodBody()?.GetILAsByteArray();
            }
            catch
            {
                yield break;
            }
            if (bytes == null || bytes.Length < 5) yield break;

            Type[] typeArguments = method.DeclaringType?.IsGenericType == true
                ? method.DeclaringType.GetGenericArguments()
                : Type.EmptyTypes;
            Type[] methodArguments = method is MethodInfo info && info.IsGenericMethod
                ? info.GetGenericArguments()
                : Type.EmptyTypes;
            for (int index = 0; index <= bytes.Length - 5; index++)
            {
                // call, callvirt and newobj all carry a four-byte method token.
                if (bytes[index] is not (0x28 or 0x6f or 0x73)) continue;
                int token = BitConverter.ToInt32(bytes, index + 1);
                int table = token & unchecked((int)0xff000000);
                if (table is not (0x06000000 or 0x0a000000 or 0x2b000000))
                    continue;
                MethodBase resolved;
                try
                {
                    resolved = method.Module.ResolveMethod(
                        token, typeArguments, methodArguments);
                }
                catch
                {
                    continue;
                }
                if (resolved != null) yield return resolved;
            }
        }

        private static bool HasSupportedDynamicInputSurface(
            ArrowEscapeGameSnapshot snapshot)
        {
            if (HasValidVisibleRegistry(snapshot) &&
                HasActiveInputSystemMouseConsumer()) return true;
            if (HasVisibleUiToolkitButton()) return true;

            Graphic[] graphics = UnityEngine.Object.FindObjectsByType<Graphic>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            if (graphics.Any(IsVisibleRaycastGraphic)) return true;

            Collider2D[] colliders = UnityEngine.Object.FindObjectsByType<Collider2D>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None);
            if (colliders.Any(item => item != null && item.enabled &&
                                      item.gameObject.activeInHierarchy)) return true;

            foreach (MonoBehaviour behaviour in UnityEngine.Object
                         .FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,
                             FindObjectsSortMode.None))
            {
                if (behaviour == null || !behaviour.isActiveAndEnabled ||
                    !behaviour.gameObject.activeInHierarchy) continue;

                if (behaviour is IArrowEscapeInputTarget inputTarget)
                {
                    try
                    {
                        if (inputTarget.PointerTarget != null &&
                            inputTarget.PointerTarget.activeInHierarchy) return true;
                    }
                    catch { }
                }
                if (behaviour is IArrowEscapeUiInputTarget uiTarget)
                {
                    try
                    {
                        if (uiTarget.PointerTarget != null &&
                            uiTarget.PointerTarget.activeInHierarchy) return true;
                    }
                    catch { }
                }

                bool visibleGeometry = HasVisibleGeometry(behaviour.gameObject);
                if (visibleGeometry && behaviour is IPointerClickHandler) return true;
                if (!visibleGeometry) continue;

                MethodInfo[] methods = behaviour.GetType().GetMethods(
                    BindingFlags.Instance | BindingFlags.Public |
                    BindingFlags.NonPublic);
                if (methods.Any(MethodUsesInputSystemMouse)) return true;
            }

            return false;
        }

        private static bool HasActiveInputSystemMouseConsumer() =>
            UnityEngine.Object.FindObjectsByType<MonoBehaviour>(
                    FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(behaviour => behaviour != null && behaviour.isActiveAndEnabled &&
                                    behaviour.gameObject.activeInHierarchy)
                .SelectMany(behaviour => behaviour.GetType().GetMethods(
                    BindingFlags.Instance | BindingFlags.Public |
                    BindingFlags.NonPublic))
                .Any(MethodUsesInputSystemMouse);

        private static bool HasValidVisibleRegistry(ArrowEscapeGameSnapshot snapshot)
        {
            ArrowEscapeVisibleTargetSnapshot[] targets = snapshot?.VisibleTargets;
            if (targets == null || targets.Length == 0 || targets.Any(item => item == null) ||
                targets.Any(item => string.IsNullOrWhiteSpace(item.Id)) ||
                targets.GroupBy(item => item.Kind + ":" + item.Id, StringComparer.Ordinal)
                    .Any(group => group.Count() != 1))
            {
                return false;
            }
            bool Valid(ArrowEscapeVisibleTargetSnapshot item) => !item.Visible ||
                (ArrowEscapeVisibleTargetUtility.IsFinite(item.ScreenRect) &&
                 item.ScreenRect.width >= 2f && item.ScreenRect.height >= 2f &&
                 item.ScreenRect.xMax > 0f && item.ScreenRect.yMax > 0f &&
                 item.ScreenRect.xMin < Screen.width && item.ScreenRect.yMin < Screen.height &&
                 !string.IsNullOrWhiteSpace(item.VisualState));
            if (targets.Any(item => item.Interactable && !item.Visible) ||
                targets.Any(item => !Valid(item))) return false;
            foreach (ArrowEscapeVisibleTargetKind kind in new[]
                     {
                         ArrowEscapeVisibleTargetKind.Hint,
                         ArrowEscapeVisibleTargetKind.Restart,
                         ArrowEscapeVisibleTargetKind.NextLevel
                     })
            {
                if (targets.Count(item => item.Kind == kind && item.Visible) != 1)
                    return false;
            }
            return snapshot.Arrows != null && snapshot.Arrows
                .Where(arrow => arrow != null && arrow.State != ArrowEscapeArrowState.Exited)
                .All(arrow => targets.Count(item =>
                    item.Kind == ArrowEscapeVisibleTargetKind.Arrow && item.Visible &&
                    string.Equals(item.Id, arrow.Id, StringComparison.Ordinal)) == 1);
        }

        private static bool MethodUsesInputSystemMouse(MethodInfo method)
        {
            var visited = new HashSet<MethodBase>();
            return MethodUsesInputSystemMouse(method, visited, 0);
        }

        private static bool MethodUsesInputSystemMouse(
            MethodBase method,
            ISet<MethodBase> visited,
            int depth)
        {
            if (method == null || depth > 12 || !visited.Add(method)) return false;
            foreach (MethodBase called in CalledMethods(method))
            {
                string declaringType = called?.DeclaringType?.FullName ?? "";
                if (declaringType == "UnityEngine.InputSystem.Mouse" ||
                    declaringType == "UnityEngine.InputSystem.Pointer")
                {
                    return true;
                }
                if (called?.DeclaringType?.Assembly == method.DeclaringType?.Assembly &&
                    MethodUsesInputSystemMouse(called, visited, depth + 1))
                {
                    return true;
                }
            }
            return false;
        }

        private static bool HasVisibleGeometry(GameObject root)
        {
            if (root == null || !root.activeInHierarchy) return false;
            if (root.GetComponentsInChildren<Renderer>(true).Any(item =>
                    item != null && item.enabled && item.gameObject.activeInHierarchy))
            {
                return true;
            }
            return root.GetComponentsInChildren<Graphic>(true)
                .Any(IsVisibleGraphic);
        }

        private static bool IsVisibleRaycastGraphic(Graphic graphic) =>
            graphic != null && graphic.raycastTarget && IsVisibleGraphic(graphic);

        private static bool IsVisibleGraphic(Graphic graphic)
        {
            if (graphic == null || !graphic.isActiveAndEnabled ||
                graphic.canvasRenderer == null || graphic.canvasRenderer.cull ||
                graphic.canvasRenderer.GetInheritedAlpha() <= 0.01f ||
                graphic.rectTransform == null) return false;

            var corners = new Vector3[4];
            graphic.rectTransform.GetWorldCorners(corners);
            float minX = corners.Min(corner => corner.x);
            float maxX = corners.Max(corner => corner.x);
            float minY = corners.Min(corner => corner.y);
            float maxY = corners.Max(corner => corner.y);
            return maxX - minX >= 1f && maxY - minY >= 1f;
        }

        private static bool TryCaptureCompositedFrame(out FrameStats frame)
        {
            frame = default;
            Texture2D texture = null;
            bool previousIgnore = LogAssert.ignoreFailingMessages;
            try
            {
                // Unity emits an Error log instead of throwing when the
                // batch-mode player loop cannot expose an end-of-frame screen
                // texture. Treat that documented coverage limitation as an
                // unavailable probe, not as an unhandled test failure.
                LogAssert.ignoreFailingMessages = true;
                texture = ScreenCapture.CaptureScreenshotAsTexture();
                if (texture == null || texture.width < 1 || texture.height < 1)
                    return false;
                frame = AnalyzePixels(texture.GetPixels32());
                return true;
            }
            catch
            {
                // Some batch-mode graphics backends expose no screen
                // framebuffer. The caller uses the deliberately conservative
                // IL + no-supported-route fallback in that case.
                return false;
            }
            finally
            {
                LogAssert.ignoreFailingMessages = previousIgnore;
                if (texture != null) UnityEngine.Object.DestroyImmediate(texture);
            }
        }

        private static bool HasVisibleUiToolkitButton() =>
            UiToolkitElements().Any(element =>
                element.GetType().FullName == "UnityEngine.UIElements.Button" &&
                VisibleUiToolkitRect(element));

        private static bool HasVisibleUiToolkitContent() =>
            UiToolkitElements().Any(VisibleUiToolkitRect);

        private static System.Collections.Generic.IEnumerable<object> UiToolkitElements()
        {
            Type documentType = Type.GetType(
                "UnityEngine.UIElements.UIDocument, UnityEngine.UIElementsModule");
            if (documentType == null) yield break;
            System.Reflection.PropertyInfo rootProperty =
                documentType.GetProperty("rootVisualElement");
            foreach (UnityEngine.Object documentObject in UnityEngine.Object.FindObjectsByType(
                         documentType, FindObjectsInactive.Exclude,
                         FindObjectsSortMode.None))
            {
                if (documentObject is not Component component ||
                    !component.gameObject.activeInHierarchy) continue;
                object root = rootProperty?.GetValue(documentObject);
                if (root == null) continue;
                var stack = new System.Collections.Generic.Stack<object>();
                stack.Push(root);
                while (stack.Count > 0)
                {
                    object current = stack.Pop();
                    yield return current;
                    Type type = current.GetType();
                    int count = type.GetProperty("childCount")?.GetValue(current) is int value
                        ? value
                        : 0;
                    System.Reflection.PropertyInfo indexer = type.GetProperty("Item",
                        new[] { typeof(int) });
                    for (int index = count - 1; index >= 0; index--)
                    {
                        object child = indexer?.GetValue(current, new object[] { index });
                        if (child != null) stack.Push(child);
                    }
                }
            }
        }

        private static bool VisibleUiToolkitRect(object element)
        {
            if (element == null) return false;
            object enabled = element.GetType().GetProperty("enabledInHierarchy")
                ?.GetValue(element);
            if (enabled is bool boolean && !boolean) return false;
            object value = element.GetType().GetProperty("worldBound")?.GetValue(element);
            return value is Rect rect && rect.width >= 1f && rect.height >= 1f;
        }

        private static bool IsVisibleOverlayGraphic(Graphic graphic)
        {
            if (graphic == null || !graphic.isActiveAndEnabled ||
                graphic.canvas == null ||
                graphic.canvas.renderMode != RenderMode.ScreenSpaceOverlay ||
                graphic.canvasRenderer.cull ||
                graphic.canvasRenderer.GetAlpha() <= 0.01f)
            {
                return false;
            }

            var corners = new Vector3[4];
            graphic.rectTransform.GetWorldCorners(corners);
            float minX = corners.Min(corner => corner.x);
            float maxX = corners.Max(corner => corner.x);
            float minY = corners.Min(corner => corner.y);
            float maxY = corners.Max(corner => corner.y);
            return maxX - minX >= 1f && maxY - minY >= 1f &&
                   maxX > 0f && maxY > 0f &&
                   minX < Screen.width && minY < Screen.height;
        }

        private static FrameStats CaptureFrame(Camera camera)
        {
            if (camera == null)
            {
                throw new InvalidOperationException(
                    "Static evaluator camera probe was unexpectedly null.");
            }

            var renderTexture = new RenderTexture(
                CaptureWidth, CaptureHeight, 24, RenderTextureFormat.ARGB32);
            var texture = new Texture2D(
                CaptureWidth, CaptureHeight, TextureFormat.RGBA32, false);
            RenderTexture previousActive = RenderTexture.active;
            RenderTexture previousTarget = camera.targetTexture;
            try
            {
                camera.targetTexture = renderTexture;
                renderTexture.Create();
                if (!renderTexture.IsCreated())
                {
                    throw new InvalidOperationException(
                        "Static evaluator could not create its render target.");
                }

                camera.Render();
                RenderTexture.active = renderTexture;
                texture.ReadPixels(
                    new Rect(0, 0, CaptureWidth, CaptureHeight), 0, 0, false);
                texture.Apply(false, false);

                return AnalyzePixels(texture.GetPixels32());
            }
            finally
            {
                camera.targetTexture = previousTarget;
                RenderTexture.active = previousActive;
                UnityEngine.Object.DestroyImmediate(texture);
                renderTexture.Release();
                UnityEngine.Object.DestroyImmediate(renderTexture);
            }
        }

        private static FrameStats AnalyzePixels(Color32[] pixels)
        {
            if (pixels == null || pixels.Length == 0) return default;
            var buckets = new int[1 << 15];
            int quantizedColorCount = 0;
            int dominantPixels = 0;
            foreach (Color32 pixel in pixels)
            {
                int bucket = ((pixel.r >> 3) << 10) |
                             ((pixel.g >> 3) << 5) |
                             (pixel.b >> 3);
                if (buckets[bucket] == 0) quantizedColorCount++;
                int count = ++buckets[bucket];
                if (count > dominantPixels) dominantPixels = count;
            }
            return new FrameStats(
                quantizedColorCount,
                pixels.Length - dominantPixels);
        }

        private static void RequireCandidate(bool condition, string message)
        {
            if (!condition)
            {
                Assert.Fail($"{CandidateFailureMarker} {message}");
            }
        }

        private static string CommandLineValue(string key)
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
            return null;
        }

        private readonly struct FrameStats
        {
            public FrameStats(int quantizedColorCount, int nonDominantPixelCount)
            {
                QuantizedColorCount = quantizedColorCount;
                NonDominantPixelCount = nonDominantPixelCount;
            }

            public int QuantizedColorCount { get; }
            public int NonDominantPixelCount { get; }
        }
    }

    internal static class EvaluatorDisplayResolution
    {
        public const int RequiredWidth = 1280;
        public const int RequiredHeight = 720;

        public static string ConfigurationRoute { get; private set; } = "not_attempted";
        private static object configuredGroup;
        private static int configuredCustomTotalIndex = -1;
        private static readonly List<UnityEngine.Object> configuredViews =
            new List<UnityEngine.Object>();
        private static readonly List<int> originalSelectedIndices = new List<int>();
        public static bool IsCurrentExact => IsExact(Screen.width, Screen.height);
        public static string Diagnostic =>
            $"observed {Screen.width}x{Screen.height}; route={ConfigurationRoute}";

        public static bool IsExact(int width, int height) =>
            width == RequiredWidth && height == RequiredHeight;

        public static IEnumerator Ensure1280x720()
        {
            if (!IsCurrentExact)
            {
                ConfigureEditorGameView();
            }
            Screen.SetResolution(RequiredWidth, RequiredHeight, false);

            float deadline = Time.realtimeSinceStartup + 5f;
            int stableFrames = 0;
            while (Time.realtimeSinceStartup < deadline && stableFrames < 2)
            {
                yield return null;
                stableFrames = IsCurrentExact ? stableFrames + 1 : 0;
            }
        }

        public static void Restore()
        {
            try
            {
                Type gameViewType = Type.GetType("UnityEditor.GameView, UnityEditor");
                PropertyInfo selectedSizeIndex = gameViewType?.GetProperty(
                    "selectedSizeIndex",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                for (int index = 0; index < configuredViews.Count; index++)
                {
                    if (configuredViews[index] != null &&
                        index < originalSelectedIndices.Count)
                    {
                        selectedSizeIndex?.SetValue(configuredViews[index],
                            originalSelectedIndices[index]);
                    }
                }

                if (configuredGroup != null && configuredCustomTotalIndex >= 0)
                {
                    Type groupType = configuredGroup.GetType();
                    MethodInfo removeCustom = groupType.GetMethod("RemoveCustomSize",
                        BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                    removeCustom?.Invoke(configuredGroup,
                        new object[] { configuredCustomTotalIndex });
                }
            }
            catch (Exception exception)
            {
                ConfigurationRoute += ";restore_error=" +
                                      exception.GetType().Name + ":" + exception.Message;
            }
            finally
            {
                configuredViews.Clear();
                originalSelectedIndices.Clear();
                configuredGroup = null;
                configuredCustomTotalIndex = -1;
            }
        }

        private static void ConfigureEditorGameView()
        {
            try
            {
                Type gameViewType = Type.GetType("UnityEditor.GameView, UnityEditor");
                Type playModeViewType = Type.GetType(
                    "UnityEditor.PlayModeView, UnityEditor");
                if (gameViewType == null || playModeViewType == null)
                {
                    ConfigurationRoute = "unavailable:UnityEditor.GameView";
                    return;
                }

                var views = new List<UnityEngine.Object>();
                MethodInfo getMain = playModeViewType.GetMethod(
                    "GetMainPlayModeView",
                    BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
                if (getMain?.Invoke(null, null) is UnityEngine.Object main)
                {
                    views.Add(main);
                }
                foreach (UnityEngine.Object view in Resources.FindObjectsOfTypeAll(
                             gameViewType))
                {
                    if (view != null && !views.Contains(view)) views.Add(view);
                }
                if (views.Count == 0)
                {
                    Type editorWindowType = Type.GetType(
                        "UnityEditor.EditorWindow, UnityEditor");
                    MethodInfo getWindow = editorWindowType?.GetMethod("GetWindow",
                        BindingFlags.Static | BindingFlags.Public, null,
                        new[] { typeof(Type) }, null);
                    if (getWindow?.Invoke(null, new object[] { gameViewType })
                        is UnityEngine.Object created)
                    {
                        views.Add(created);
                    }
                }

                PropertyInfo selectedSizeIndex = gameViewType.GetProperty(
                    "selectedSizeIndex",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                Type gameViewSizesType = Type.GetType(
                    "UnityEditor.GameViewSizes, UnityEditor");
                Type gameViewSizeType = Type.GetType(
                    "UnityEditor.GameViewSize, UnityEditor");
                Type gameViewSizeTypeEnum = Type.GetType(
                    "UnityEditor.GameViewSizeType, UnityEditor");
                Type groupTypeEnum = Type.GetType(
                    "UnityEditor.GameViewSizeGroupType, UnityEditor");
                PropertyInfo instance = gameViewSizesType?.GetProperty("instance",
                    BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic |
                    BindingFlags.FlattenHierarchy);
                object sizes = instance?.GetValue(null);
                MethodInfo getGroup = gameViewSizesType?.GetMethod("GetGroup",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                object standalone = groupTypeEnum == null
                    ? null
                    : Enum.Parse(groupTypeEnum, "Standalone");
                object group = sizes == null || standalone == null
                    ? null
                    : getGroup?.Invoke(sizes, new[] { standalone });
                Type groupType = group?.GetType();
                MethodInfo addCustom = groupType?.GetMethod("AddCustomSize",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                MethodInfo indexOf = groupType?.GetMethod("IndexOf",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                MethodInfo getBuiltinCount = groupType?.GetMethod("GetBuiltinCount",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                ConstructorInfo constructor = gameViewSizeType?.GetConstructor(
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                    null, new[]
                    {
                        gameViewSizeTypeEnum, typeof(int), typeof(int), typeof(string)
                    }, null);
                if (selectedSizeIndex == null || group == null || addCustom == null ||
                    indexOf == null || getBuiltinCount == null || constructor == null ||
                    views.Count == 0)
                {
                    ConfigurationRoute = "unavailable:GameViewSizes.in_memory_api";
                    return;
                }

                object fixedResolution = Enum.Parse(gameViewSizeTypeEnum,
                    "FixedResolution");
                object customSize = constructor.Invoke(new[]
                {
                    fixedResolution, RequiredWidth, RequiredHeight,
                    "OmniGame Evaluator 1280x720 " + Guid.NewGuid().ToString("N")
                });
                addCustom.Invoke(group, new[] { customSize });
                int customIndex = (int)indexOf.Invoke(group, new[] { customSize });
                int totalIndex = (int)getBuiltinCount.Invoke(group, null) + customIndex;
                if (customIndex < 0)
                {
                    ConfigurationRoute = "error:in_memory_size_index_not_found";
                    return;
                }
                configuredGroup = group;
                configuredCustomTotalIndex = totalIndex;
                foreach (UnityEngine.Object view in views)
                {
                    configuredViews.Add(view);
                    originalSelectedIndices.Add((int)selectedSizeIndex.GetValue(view));
                    selectedSizeIndex.SetValue(view, totalIndex);
                }
                ConfigurationRoute = "GameViewSizes.AddCustomSize+selectedSizeIndex";
            }
            catch (Exception exception)
            {
                ConfigurationRoute = "error:" + exception.GetType().Name + ":" +
                                     exception.Message;
            }
        }
    }

    [Serializable]
    internal sealed class StaticEvaluatorHealthEvidence
    {
        public int schema_version = 1;
        public string evaluator_health = "static";
        public int process_id;
        public int screen_width;
        public int screen_height;
        public int required_width;
        public int required_height;
        public bool resolution_exact;
        public string configuration_route;
    }
}


