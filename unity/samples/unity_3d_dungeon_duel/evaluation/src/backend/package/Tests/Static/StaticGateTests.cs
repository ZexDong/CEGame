using System;
using System.Collections;
using System.Linq;
using NUnit.Framework;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    [TestFixture]
    public sealed class StaticGateTests
    {
        private const string CandidateFailureMarker = "[OMNIGAME_CANDIDATE_STATIC]";
        private const int CaptureWidth = 256;
        private const int CaptureHeight = 144;
        private const int MinimumForegroundPixels = 24;

        private Camera activeCamera;

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            AsyncOperation load = null;
            try
            {
                load = SceneManager.LoadSceneAsync(
                    DungeonDuelContractConstants.MainScenePath,
                    LoadSceneMode.Single);
            }
            catch (Exception exception)
            {
                RequireCandidate(false,
                    "The canonical scene could not be loaded: " + exception.Message);
            }

            RequireCandidate(load != null,
                "The canonical scene must be enabled in Build Settings and loadable by path.");
            float deadline = Time.realtimeSinceStartup + 10f;
            while (!load.isDone && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }
            RequireCandidate(load.isDone,
                "The canonical scene did not finish loading within ten seconds.");

            yield return null;
            yield return null;
            activeCamera = UnityEngine.Object
                .FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(camera => camera.isActiveAndEnabled);
            RequireCandidate(activeCamera != null,
                "The playable scene must have an active enabled camera.");
        }

        [UnityTest]
        public IEnumerator STATIC01_ProjectStartsInAPlayableBenchmarkScene()
        {
            RequireCandidate(SceneManager.GetActiveScene().path ==
                             DungeonDuelContractConstants.MainScenePath,
                "The canonical gameplay scene is not active after loading.");
            RequireCandidate(activeCamera != null && activeCamera.isActiveAndEnabled,
                "The gameplay camera is not active and enabled.");

            int initialFrame = Time.frameCount;
            yield return null;
            RequireCandidate(Time.frameCount > initialFrame,
                "The loaded project did not advance a normal Unity frame.");
        }

        [UnityTest]
        public IEnumerator STATIC02_GameplayCameraRendersANonEmpty3DFrame()
        {
            yield return null;
            FrameStats frame = CaptureFrame(activeCamera);
            RequireCandidate(IsVisiblyRendered(frame),
                "The gameplay view is effectively a uniform clear frame with no visible 3D or overlay content.");
        }

        [UnityTest]
        public IEnumerator STATIC03_NormalWorldAndActorInputTargetsAreDiscoverable()
        {
            // Preserve the historical method ID for scorer compatibility. The
            // eligibility semantics are now implementation-neutral: actual
            // world/input routing is assessed only by Dynamic trajectories.
            FrameStats first = CaptureFrame(activeCamera);
            int initialFrame = Time.frameCount;
            yield return null;
            yield return null;
            FrameStats second = CaptureFrame(activeCamera);

            RequireCandidate(Time.frameCount >= initialFrame + 2,
                "The project stopped advancing normal Unity frames after startup.");
            RequireCandidate(IsVisiblyRendered(first) && IsVisiblyRendered(second),
                "The gameplay view did not remain visibly renderable across frames.");
        }

        private static bool IsVisiblyRendered(FrameStats cameraFrame)
        {
            if (cameraFrame.QuantizedColorCount >= 2 &&
                cameraFrame.NonDominantPixelCount >= MinimumForegroundPixels)
            {
                return true;
            }

            // Camera.Render omits Screen Space Overlay uGUI. Accept active,
            // non-culled CanvasRenderer geometry on an overlay Canvas so a
            // manually playable UI-composited 3D view is not falsely gated out.
            return UnityEngine.Object
                .FindObjectsByType<CanvasRenderer>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Any(IsVisibleOverlayRenderer);
        }

        private static bool IsVisibleOverlayRenderer(CanvasRenderer renderer)
        {
            if (renderer == null || renderer.cull || renderer.GetAlpha() <= 0.01f)
            {
                return false;
            }

            Canvas canvas = renderer.GetComponentInParent<Canvas>();
            RectTransform rectTransform = renderer.GetComponent<RectTransform>();
            if (canvas == null || !canvas.isActiveAndEnabled ||
                canvas.renderMode != RenderMode.ScreenSpaceOverlay ||
                rectTransform == null || !rectTransform.gameObject.activeInHierarchy)
            {
                return false;
            }

            var corners = new Vector3[4];
            rectTransform.GetWorldCorners(corners);
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

                Color32[] pixels = texture.GetPixels32();
                int[] bucketSizes = pixels
                    .GroupBy(pixel => ((pixel.r >> 3) << 10) |
                                      ((pixel.g >> 3) << 5) |
                                      (pixel.b >> 3))
                    .Select(group => group.Count())
                    .ToArray();
                int dominantPixels = bucketSizes.Length == 0
                    ? pixels.Length
                    : bucketSizes.Max();
                return new FrameStats(
                    bucketSizes.Length,
                    pixels.Length - dominantPixels);
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

        private static void RequireCandidate(bool condition, string message)
        {
            if (!condition)
            {
                Assert.Fail($"{CandidateFailureMarker} {message}");
            }
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
}
