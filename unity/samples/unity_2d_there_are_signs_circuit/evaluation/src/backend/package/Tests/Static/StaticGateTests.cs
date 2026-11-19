using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    [TestFixture]
    public sealed class StaticGateTests
    {
        internal const string MainScenePath =
            "Assets/Scenes/Benchmark/SignCircuit.unity";
        const string CandidateFailureMarker = "[OMNIGAME_SIGN_CIRCUIT_CANDIDATE_STATIC]";
        const int CaptureWidth = 192;
        const int CaptureHeight = 108;
        const int MinimumForegroundPixels = 16;

        Camera activeCamera;
        Scene activeScene;

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            RequireCandidate(Application.CanStreamedLevelBeLoaded(MainScenePath),
                $"The canonical scene is not enabled and loadable: {MainScenePath}");

            AsyncOperation load = SceneManager.LoadSceneAsync(MainScenePath, LoadSceneMode.Single);
            RequireCandidate(load != null,
                "SceneManager did not start loading the canonical scene.");

            float deadline = Time.realtimeSinceStartup + 15f;
            while (!load.isDone && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }

            RequireCandidate(load.isDone,
                "The canonical scene did not load within fifteen seconds.");
            yield return null;
            yield return null;

            activeScene = SceneManager.GetActiveScene();
            RequireCandidate(activeScene.path == MainScenePath,
                $"The wrong scene became active: {activeScene.path}");

            activeCamera = UnityEngine.Object
                .FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled &&
                                        item.gameObject.scene == activeScene);
            RequireCandidate(activeCamera != null,
                "The canonical scene has no active enabled camera.");
        }

        [UnityTest]
        public IEnumerator STATIC01_CanonicalSceneLoadsCameraAndAdvancesFrames()
        {
            RequireCandidate(activeScene.IsValid() && activeScene.isLoaded,
                "The canonical scene is not valid and loaded.");
            RequireCandidate(activeCamera != null && activeCamera.isActiveAndEnabled,
                "The canonical camera is not active and enabled.");

            int initialFrame = Time.frameCount;
            yield return null;
            yield return null;
            RequireCandidate(Time.frameCount >= initialFrame + 2,
                "The project did not advance two normal player-loop frames.");
        }

        [UnityTest]
        public IEnumerator STATIC02_CameraProducesAVisibleFrame()
        {
            if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null)
            {
                throw new InvalidOperationException(
                    "Evaluation infrastructure has a Null graphics device; render qualification cannot be attributed to the candidate.");
            }

            var unexpectedLogs = new List<string>();
            Application.LogCallback callback = (condition, stackTrace, type) =>
            {
                if (type != LogType.Error && type != LogType.Exception &&
                    type != LogType.Assert)
                {
                    return;
                }
                if (!IsAllowedColdRenderInfrastructureLog(condition))
                {
                    unexpectedLogs.Add($"[{type}] {condition}");
                }
            };
            bool previousIgnore = LogAssert.ignoreFailingMessages;
            FrameStats frame;
            Application.logMessageReceived += callback;
            LogAssert.ignoreFailingMessages = true;
            try
            {
                yield return null;
                frame = CaptureFrame(activeCamera);
                yield return null;
            }
            finally
            {
                LogAssert.ignoreFailingMessages = previousIgnore;
                Application.logMessageReceived -= callback;
            }

            if (unexpectedLogs.Count > 0)
            {
                RequireCandidate(false,
                    "Unexpected candidate runtime error during render qualification: " +
                    string.Join(" | ", unexpectedLogs.Take(5)));
            }
            RequireCandidate(IsVisiblyRendered(frame),
                "The canonical scene rendered only a uniform clear frame and has no visible overlay UI.");
        }

        [UnityTest]
        public IEnumerator STATIC03_CanonicalSceneContainsNoMissingScripts()
        {
            yield return null;
            var missing = new List<string>();
            foreach (GameObject root in activeScene.GetRootGameObjects())
            {
                foreach (Transform transform in root.GetComponentsInChildren<Transform>(true))
                {
                    Component[] components = transform.gameObject.GetComponents<Component>();
                    for (int index = 0; index < components.Length; index++)
                    {
                        if (components[index] == null)
                        {
                            missing.Add(HierarchyPath(transform));
                        }
                    }
                }
            }

            RequireCandidate(missing.Count == 0,
                "Missing script references were found at: " +
                string.Join(", ", missing.Distinct().Take(20)));
        }

        static string HierarchyPath(Transform transform)
        {
            var names = new Stack<string>();
            for (Transform current = transform; current != null; current = current.parent)
            {
                names.Push(current.name);
            }
            return "/" + string.Join("/", names);
        }

        static bool IsVisiblyRendered(FrameStats frame)
        {
            if (frame.QuantizedColorCount >= 2 &&
                frame.NonDominantPixelCount >= MinimumForegroundPixels)
            {
                return true;
            }

            return UnityEngine.Object
                .FindObjectsByType<Graphic>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Any(IsVisibleOverlayGraphic);
        }

        static bool IsVisibleOverlayGraphic(Graphic graphic)
        {
            if (graphic == null || !graphic.isActiveAndEnabled ||
                graphic.canvas == null ||
                graphic.canvas.rootCanvas.renderMode != RenderMode.ScreenSpaceOverlay ||
                graphic.canvasRenderer.cull ||
                graphic.canvasRenderer.GetAlpha() <= 0.01f)
            {
                return false;
            }

            var corners = new Vector3[4];
            graphic.rectTransform.GetWorldCorners(corners);
            float minX = corners.Min(item => item.x);
            float maxX = corners.Max(item => item.x);
            float minY = corners.Min(item => item.y);
            float maxY = corners.Max(item => item.y);
            return maxX - minX >= 1f && maxY - minY >= 1f &&
                   maxX > 0f && maxY > 0f &&
                   minX < Screen.width && minY < Screen.height;
        }

        static bool IsAllowedColdRenderInfrastructureLog(string condition)
        {
            const string messagePrefix = "Cannot load. Path ";
            const string suffix =
                " is correct but AssetDatabase cannot load now.";
            if (condition == null ||
                !condition.StartsWith(messagePrefix, StringComparison.Ordinal) ||
                !condition.EndsWith(suffix, StringComparison.Ordinal))
            {
                return false;
            }

            string packagePath = condition.Substring(
                messagePrefix.Length,
                condition.Length - messagePrefix.Length - suffix.Length);
            bool protectedRenderPipelinePackage =
                packagePath.StartsWith(
                    "Packages/com.unity.render-pipelines.universal/",
                    StringComparison.Ordinal) ||
                packagePath.StartsWith(
                    "Packages/com.unity.render-pipelines.core/",
                    StringComparison.Ordinal);
            bool shaderAsset =
                packagePath.EndsWith(".shadergraph", StringComparison.Ordinal) ||
                packagePath.EndsWith(".urtshader", StringComparison.Ordinal);
            return protectedRenderPipelinePackage && shaderAsset;
        }

        static FrameStats CaptureFrame(Camera camera)
        {
            if (camera == null)
            {
                throw new InvalidOperationException(
                    "The evaluator camera probe was unexpectedly null.");
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
                        "The evaluator could not create a GPU render target.");
                }

                camera.Render();
                RenderTexture.active = renderTexture;
                texture.ReadPixels(
                    new Rect(0, 0, CaptureWidth, CaptureHeight), 0, 0, false);
                texture.Apply(false, false);

                Color32[] pixels = texture.GetPixels32();
                int[] buckets = pixels
                    .GroupBy(pixel => ((pixel.r >> 3) << 10) |
                                      ((pixel.g >> 3) << 5) |
                                      (pixel.b >> 3))
                    .Select(group => group.Count())
                    .ToArray();
                int dominant = buckets.Length == 0 ? pixels.Length : buckets.Max();
                return new FrameStats(buckets.Length, pixels.Length - dominant);
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

        static void RequireCandidate(bool condition, string message)
        {
            if (!condition)
            {
                Assert.Fail($"{CandidateFailureMarker} {message}");
            }
        }

        readonly struct FrameStats
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
}
