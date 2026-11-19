using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEngine;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    /// <summary>
    /// Captures comparable 16:9 frames without relying on an Editor GameView.
    /// Screen-space overlay canvases are temporarily rendered by the gameplay
    /// camera so the output contains both the world and ordinary player UI.
    /// </summary>
    internal static class VisualEvidenceCapture
    {
        const int Width = 1280;
        const int Height = 720;

        public static IEnumerator Capture(string fileName)
        {
            string directory = SignCircuitEvidenceWriter.OutputDirectory;
            if (string.IsNullOrWhiteSpace(directory)) yield break;

            Camera camera = UnityEngine.Object
                .FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
            if (camera == null)
            {
                throw new InvalidOperationException(
                    "Visual evidence capture found no active gameplay camera.");
            }

            bool previousIgnore = LogAssert.ignoreFailingMessages;
            LogAssert.ignoreFailingMessages = true;
            try
            {
                Directory.CreateDirectory(directory);
                yield return null;
                // WaitForEndOfFrame can stall indefinitely in headless/batchmode
                // when no Editor GameView is focused. A normal player-loop frame
                // plus explicit Canvas/camera rendering is deterministic here.
                yield return null;
                Canvas.ForceUpdateCanvases();

                var canvases = UnityEngine.Object
                    .FindObjectsByType<Canvas>(FindObjectsInactive.Exclude,
                        FindObjectsSortMode.None)
                    .Where(item => item.isActiveAndEnabled &&
                                   item.renderMode == RenderMode.ScreenSpaceOverlay)
                    .ToArray();
                var states = new List<CanvasState>();
                foreach (Canvas canvas in canvases)
                {
                    states.Add(new CanvasState(canvas));
                    canvas.renderMode = RenderMode.ScreenSpaceCamera;
                    canvas.worldCamera = camera;
                    canvas.planeDistance = 1f;
                }

                var target = new RenderTexture(
                    Width, Height, 24, RenderTextureFormat.ARGB32);
                var texture = new Texture2D(
                    Width, Height, TextureFormat.RGBA32, false);
                RenderTexture previousActive = RenderTexture.active;
                RenderTexture previousTarget = camera.targetTexture;
                float previousAspect = camera.aspect;
                Rect previousRect = camera.rect;
                try
                {
                    target.Create();
                    if (!target.IsCreated())
                    {
                        throw new InvalidOperationException(
                            "Visual evidence render target could not be created.");
                    }
                    camera.aspect = Width / (float)Height;
                    camera.rect = new Rect(0f, 0f, 1f, 1f);
                    camera.targetTexture = target;
                    Canvas.ForceUpdateCanvases();
                    camera.Render();
                    RenderTexture.active = target;
                    texture.ReadPixels(new Rect(0, 0, Width, Height), 0, 0, false);
                    texture.Apply(false, false);
                    string path = Path.Combine(directory, fileName);
                    File.WriteAllBytes(path, texture.EncodeToPNG());
                    string rendererPath = Path.Combine(directory,
                        Path.GetFileNameWithoutExtension(fileName) + ".renderers.txt");
                    string[] rendererLines = UnityEngine.Object
                        .FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude,
                            FindObjectsSortMode.None)
                        .Where(item => item.enabled && item.gameObject.activeInHierarchy)
                        .OrderBy(item => item.sortingOrder)
                        .Select(item =>
                            $"{item.name}|sprite={(item.sprite == null ? "<null>" : item.sprite.name)}" +
                            $"|position={item.transform.position}|scale={item.transform.lossyScale}" +
                            $"|bounds={item.bounds.size}|order={item.sortingOrder}")
                        .ToArray();
                    File.WriteAllLines(rendererPath, rendererLines);
                }
                finally
                {
                    camera.targetTexture = previousTarget;
                    camera.aspect = previousAspect;
                    camera.rect = previousRect;
                    RenderTexture.active = previousActive;
                    foreach (CanvasState state in states) state.Restore();
                    // CanvasScaler/RectTransform geometry may still describe the
                    // temporary 1280x720 render target until the next forced layout.
                    // Restore viewport geometry before any probe publishes a click rect.
                    Canvas.ForceUpdateCanvases();
                    UnityEngine.Object.DestroyImmediate(texture);
                    target.Release();
                    UnityEngine.Object.DestroyImmediate(target);
                }

                // Unity reports deferred protected render-pipeline shader asset
                // loads on the following frame. Keep LogAssert suppression active
                // through that frame; the fixture callback still rejects every
                // error except the narrowly classified package/shader messages.
                yield return null;
            }
            finally
            {
                LogAssert.ignoreFailingMessages = previousIgnore;
            }
        }

        internal static bool IsAllowedRenderPipelineAssetDatabaseLog(string condition)
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

        sealed class CanvasState
        {
            readonly Canvas canvas;
            readonly RenderMode renderMode;
            readonly Camera worldCamera;
            readonly float planeDistance;

            public CanvasState(Canvas source)
            {
                canvas = source;
                renderMode = source.renderMode;
                worldCamera = source.worldCamera;
                planeDistance = source.planeDistance;
            }

            public void Restore()
            {
                if (canvas == null) return;
                canvas.renderMode = renderMode;
                canvas.worldCamera = worldCamera;
                canvas.planeDistance = planeDistance;
            }
        }
    }
}
