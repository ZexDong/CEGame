using System;
using System.Collections.Generic;
using System.Collections;
using System.IO;
using System.Linq;
using System.Reflection;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace GameCreate.NoirRoombreak.Evaluator.Standalone
{
    internal sealed class StandaloneInputDriver : IDisposable
    {
        Keyboard keyboard;
        Mouse mouse;
        Keyboard previousKeyboard;
        Mouse previousMouse;
        InputSettings.BackgroundBehavior previousBackground;
        readonly List<InputDevice> disabled = new List<InputDevice>();

        public IEnumerator Ready()
        {
            if (keyboard != null && mouse != null) yield break;
            previousKeyboard = Keyboard.current;
            previousBackground = InputSystem.settings.backgroundBehavior;
            InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
            previousMouse = Mouse.current;
            foreach (var device in InputSystem.devices.Where(x => x.enabled && (x is Keyboard || x is Mouse)).ToArray())
            {
                InputSystem.DisableDevice(device);
                disabled.Add(device);
            }
            keyboard = InputSystem.AddDevice<Keyboard>("NoirStandaloneCaptureKeyboard");
            mouse = InputSystem.AddDevice<Mouse>("NoirStandaloneCaptureMouse");
            keyboard.MakeCurrent();
            mouse.MakeCurrent();
            yield return null;
        }

        public IEnumerator Click(Vector2 position)
        {
            yield return Ready();
            mouse.MakeCurrent();
            InputSystem.QueueStateEvent(mouse, new MouseState { position = position, buttons = 1 });
            yield return null;
            mouse.MakeCurrent();
            InputSystem.QueueStateEvent(mouse, new MouseState { position = position, buttons = 0 });
            yield return null;
        }

        public IEnumerator Press(Key key)
        {
            yield return Ready();
            keyboard.MakeCurrent();
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(key));
            yield return null;
            var deliveryDeadline=Time.realtimeSinceStartup+.5f;
            while(!keyboard[key].isPressed&&Time.realtimeSinceStartup<deliveryDeadline)yield return null;
            if(!keyboard[key].isPressed)throw new InvalidOperationException("Evaluator keyboard transport did not deliver the requested press.");
            keyboard.MakeCurrent();
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            yield return null;
        }

        public void Dispose()
        {
            if (keyboard != null && keyboard.added) InputSystem.RemoveDevice(keyboard);
            if (mouse != null && mouse.added) InputSystem.RemoveDevice(mouse);
            foreach (var device in disabled.Where(x => x != null && x.added)) InputSystem.EnableDevice(device);
            if (previousKeyboard != null && previousKeyboard.added) previousKeyboard.MakeCurrent();
            if (previousMouse != null && previousMouse.added) previousMouse.MakeCurrent();
            keyboard = null;
            mouse = null;
            disabled.Clear();
            InputSystem.settings.backgroundBehavior = previousBackground;
        }
    }

    internal static class StandaloneCaptureRenderer
    {
        public static List<CanvasState> CaptureCanvases()
        {
            return UnityEngine.Object.FindObjectsByType<Canvas>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(x => x != null && x.gameObject.activeInHierarchy && x.isActiveAndEnabled && x.renderMode != RenderMode.WorldSpace)
                .Select(x => new CanvasState { canvas = x, enabled = x.enabled, mode = x.renderMode, worldCamera = x.worldCamera, planeDistance = x.planeDistance })
                .ToList();
        }

        public static Texture2D CaptureCurrentFrame()
        {
            var texture = ScreenCapture.CaptureScreenshotAsTexture();
            if (texture == null) throw new InvalidOperationException("CaptureScreenshotAsTexture returned null.");
            return texture;
        }

        public static OverlayResult RenderOverlay(List<CanvasState> canvasStates, int width, int height)
        {
            var result = new OverlayResult { canvasCount = canvasStates.Count };
            var layerStates = new List<LayerState>();
            var foreignStates = new List<LayerState>();
            var uiObjects = new HashSet<GameObject>();
            GameObject cameraObject = null;
            RenderTexture render = null;
            var priorActive = RenderTexture.active;
            try
            {
                foreach (var state in canvasStates)
                {
                    if (state.canvas == null) continue;
                    foreach (var transform in state.canvas.GetComponentsInChildren<Transform>(true))
                    {
                        if (transform == null || !uiObjects.Add(transform.gameObject)) continue;
                        layerStates.Add(new LayerState { gameObject = transform.gameObject, layer = transform.gameObject.layer });
                        transform.gameObject.layer = StandaloneCaptureContract.UiLayer;
                    }
                }
                result.movedUiObjects = layerStates.Count;
                foreach (var transform in UnityEngine.Object.FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                {
                    if (transform == null || uiObjects.Contains(transform.gameObject) || transform.gameObject.layer != StandaloneCaptureContract.UiLayer) continue;
                    foreignStates.Add(new LayerState { gameObject = transform.gameObject, layer = StandaloneCaptureContract.UiLayer });
                    transform.gameObject.layer = 0;
                }
                result.displacedForeign = foreignStates.Count;

                cameraObject = new GameObject("NoirStandaloneUiOnlyCamera");
                var camera = cameraObject.AddComponent<Camera>();
                camera.enabled = false;
                camera.clearFlags = CameraClearFlags.SolidColor;
                camera.backgroundColor = new Color(0, 0, 0, 0);
                camera.cullingMask = StandaloneCaptureContract.UiMask;
                camera.orthographic = true;
                camera.orthographicSize = 5;
                camera.nearClipPlane = .01f;
                camera.farClipPlane = 100f;
                camera.allowHDR = false;
                camera.allowMSAA = false;
                camera.aspect = (float)width / height;
                camera.transform.position = new Vector3(0, 0, -10);
                render = new RenderTexture(width, height, 24, RenderTextureFormat.ARGB32) { antiAliasing = 1 };
                render.Create();
                camera.targetTexture = render;
                foreach (var state in canvasStates)
                {
                    if (state.canvas == null) continue;
                    state.canvas.enabled = true;
                    state.canvas.renderMode = RenderMode.ScreenSpaceCamera;
                    state.canvas.worldCamera = camera;
                    state.canvas.planeDistance = 1f;
                }
                Canvas.ForceUpdateCanvases();
                if (RenderPipelineManager.currentPipeline != null)
                {
                    var request = new RenderPipeline.StandardRequest { destination = render, mipLevel = 0, slice = 0, face = CubemapFace.Unknown };
                    if (!RenderPipeline.SupportsRenderRequest(camera, request)) throw new InvalidOperationException("Active render pipeline does not support the standard UI render request.");
                    RenderPipeline.SubmitRenderRequest(camera, request);
                    result.renderPath = "srp_standard_request_layer31";
                }
                else
                {
                    camera.Render();
                    result.renderPath = "camera_render_layer31";
                }
                RenderTexture.active = render;
                result.texture = new Texture2D(width, height, TextureFormat.RGBA32, false);
                result.texture.ReadPixels(new Rect(0, 0, width, height), 0, 0, false);
                result.texture.Apply(false, false);
                CountAlpha(result.texture, out result.nonzero, out result.partial);
            }
            finally
            {
                RenderTexture.active = priorActive;
                foreach (var state in canvasStates)
                {
                    if (state.canvas == null) continue;
                    state.canvas.enabled = state.enabled;
                    state.canvas.renderMode = state.mode;
                    state.canvas.worldCamera = state.worldCamera;
                    state.canvas.planeDistance = state.planeDistance;
                }
                result.canvasRestored = canvasStates.All(x => x.canvas != null && x.canvas.enabled == x.enabled && x.canvas.renderMode == x.mode && x.canvas.worldCamera == x.worldCamera && Mathf.Abs(x.canvas.planeDistance - x.planeDistance) < .001f);
                foreach (var state in layerStates)
                    if (state.gameObject != null) state.gameObject.layer = state.layer;
                foreach (var state in foreignStates)
                    if (state.gameObject != null) state.gameObject.layer = state.layer;
                result.layersRestored = layerStates.All(x => x.gameObject == null || x.gameObject.layer == x.layer) && foreignStates.All(x => x.gameObject == null || x.gameObject.layer == x.layer);
                if (render != null) { render.Release(); UnityEngine.Object.Destroy(render); }
                if (cameraObject != null) UnityEngine.Object.Destroy(cameraObject);
                Canvas.ForceUpdateCanvases();
            }
            return result;
        }

        public static Texture2D Blend(Texture2D bottom, Texture2D top)
        {
            if (bottom.width != top.width || bottom.height != top.height) throw new InvalidOperationException("Capture layers have different dimensions.");
            var basePixels = bottom.GetPixels32();
            var overlayPixels = top.GetPixels32();
            for (var i = 0; i < basePixels.Length; i++)
            {
                var alpha = overlayPixels[i].a;
                var inverse = 255 - alpha;
                basePixels[i] = new Color32(
                    (byte)((overlayPixels[i].r * alpha + basePixels[i].r * inverse + 127) / 255),
                    (byte)((overlayPixels[i].g * alpha + basePixels[i].g * inverse + 127) / 255),
                    (byte)((overlayPixels[i].b * alpha + basePixels[i].b * inverse + 127) / 255), 255);
            }
            var result = new Texture2D(bottom.width, bottom.height, TextureFormat.RGB24, false);
            result.SetPixels32(basePixels);
            result.Apply(false, false);
            return result;
        }

        static void CountAlpha(Texture2D texture, out int nonzero, out int partial)
        {
            nonzero = 0;
            partial = 0;
            foreach (var pixel in texture.GetPixels32())
            {
                if (pixel.a > 0) nonzero++;
                if (pixel.a > 0 && pixel.a < 255) partial++;
            }
        }
    }
}
