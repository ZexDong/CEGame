using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;
using UnityEngine.Rendering;

namespace GameCreate.Evaluation.Rendering
{
    public sealed class ViewportCaptureUnsupportedException : InvalidOperationException
    {
        public readonly string reason;
        public ViewportCaptureUnsupportedException(string reason) : base("Observer unsupported: " + reason) { this.reason = reason; }
    }

    [Serializable] public sealed class ViewportCameraPass
    {
        public string camera, pipeline;
        public int instance_id, tile_width, tile_height, stack_overlays;
        public float depth, original_aspect;
        public Rect viewport;
    }
    [Serializable] public sealed class ViewportCaptureReport
    {
        public string method = "standalone-offscreen-viewport-composite-v1";
        public string observer_status = "pending", pipeline, unsupported_reason, error;
        public string render_configuration_before_sha256, render_configuration_after_sha256;
        public int width, height, overlay_canvases, nonblack_rgb_pixels;
        public bool valid, render_configuration_restored;
        public List<ViewportCameraPass> camera_passes = new List<ViewportCameraPass>();
    }

    // Generic render observer. No game names, state access, actor lookup or score logic.
    // Built-in and URP StandardRequest are supported on the verified desktop backend.
    // A camera renders to its own pixel-sized viewport tile using its ORIGINAL aspect;
    // the tile is copied back to the same rectangle, never stretched across the frame.
    public static class ViewportCompositeFrame
    {
        sealed class CameraState
        {
            public Camera camera; public RenderTexture target; public Rect rect; public float aspect;
            public CameraState(Camera c) { camera = c; target = c.targetTexture; rect = c.rect; aspect = c.aspect; }
            public void Restore() { if (!camera) return; camera.targetTexture = target; camera.rect = rect; camera.aspect = aspect; }
        }
        sealed class CanvasState
        {
            public Canvas canvas; public bool enabled; public RenderMode mode; public Camera camera; public float distance;
            public CanvasState(Canvas c) { canvas = c; enabled = c.enabled; mode = c.renderMode; camera = c.worldCamera; distance = c.planeDistance; }
            public void Restore() { if (!canvas) return; canvas.renderMode = mode; canvas.worldCamera = camera; canvas.planeDistance = distance; canvas.enabled = enabled; }
        }
        [Serializable] sealed class CameraConfig
        {
            public int id, target, mask, display; public bool enabled; public float aspect, depth; public Rect rect; public Matrix4x4 projection;
        }
        [Serializable] sealed class CanvasConfig
        {
            public int id, mode, camera, layer, sortingLayer, sortingOrder, display; public bool enabled, overrideSorting; public float distance; public Vector3 position, scale;
        }
        [Serializable] sealed class LayerConfig { public int id, layer; }
        [Serializable] sealed class Configuration
        {
            public int active_render_texture; public CameraConfig[] cameras; public CanvasConfig[] canvases; public LayerConfig[] layers;
        }
        static int Id(UnityEngine.Object value) => value ? value.GetInstanceID() : 0;
        static Type FindType(string fullName) => AppDomain.CurrentDomain.GetAssemblies().Select(a => a.GetType(fullName, false)).FirstOrDefault(t => t != null);
        static Component UrpData(Camera camera)
        {
            var type = FindType("UnityEngine.Rendering.Universal.UniversalAdditionalCameraData");
            return type == null ? null : camera.GetComponent(type);
        }
        static object Property(object instance, string property) => instance?.GetType().GetProperty(property, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(instance);
        static bool IsOverlay(Camera camera) => string.Equals(Property(UrpData(camera), "renderType")?.ToString(), "Overlay", StringComparison.Ordinal);
        static Camera[] Stack(Camera camera)
        {
            var list = Property(UrpData(camera), "cameraStack") as IEnumerable;
            return list == null ? Array.Empty<Camera>() : list.Cast<object>().OfType<Camera>().Where(c => c && c.isActiveAndEnabled).ToArray();
        }
        static void Unsupported(string reason) { throw new ViewportCaptureUnsupportedException(reason); }
        static string ConfigurationHash(Camera[] cameras, Canvas[] canvases, IEnumerable<GameObject> layerObjects)
        {
            var snapshot = new Configuration {
                active_render_texture = Id(RenderTexture.active),
                cameras = cameras.Where(c => c).OrderBy(c => c.GetInstanceID()).Select(c => new CameraConfig { id = Id(c), target = Id(c.targetTexture), mask = c.cullingMask, display = c.targetDisplay, enabled = c.enabled, aspect = c.aspect, depth = c.depth, rect = c.rect, projection = c.projectionMatrix }).ToArray(),
                canvases = canvases.Where(c => c).OrderBy(c => c.GetInstanceID()).Select(c => new CanvasConfig { id = Id(c), mode = (int)c.renderMode, camera = Id(c.worldCamera), layer = c.gameObject.layer, sortingLayer = c.sortingLayerID, sortingOrder = c.sortingOrder, display = c.targetDisplay, enabled = c.enabled, overrideSorting = c.overrideSorting, distance = c.planeDistance, position = c.transform.position, scale = c.transform.localScale }).ToArray(),
                layers = layerObjects.Where(g => g).Distinct().OrderBy(g => g.GetInstanceID()).Select(g => new LayerConfig { id = Id(g), layer = g.layer }).ToArray()
            };
            using (var hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(JsonUtility.ToJson(snapshot)))).Replace("-", "").ToLowerInvariant();
        }

        public static Texture2D Capture(int width, int height, out ViewportCaptureReport report, Action<string> diagnosticCheckpoint = null)
        {
            report = new ViewportCaptureReport { width = width, height = height };
            var allCameras = UnityEngine.Object.FindObjectsByType<Camera>(FindObjectsInactive.Include, FindObjectsSortMode.None);
            var allCanvases = UnityEngine.Object.FindObjectsByType<Canvas>(FindObjectsInactive.Include, FindObjectsSortMode.None);
            var originalActive = RenderTexture.active;
            var cameraStates = allCameras.Select(c => new CameraState(c)).ToArray();
            var canvasStates = new List<CanvasState>();
            var layers = new Dictionary<GameObject, int>();
            var ownedUiResources = new List<UnityEngine.Object>();
            GameObject uiObject = null;
            Texture2D result = null;
            Canvas.ForceUpdateCanvases();
            try
            {
                if (width <= 0 || height <= 0 || width > 8192 || height > 8192) Unsupported("unsupported_output_size");
                bool srp = GraphicsSettings.currentRenderPipeline != null;
                bool urp = srp && GraphicsSettings.currentRenderPipeline.GetType().FullName == "UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset";
                report.pipeline = !srp ? "Built-in" : GraphicsSettings.currentRenderPipeline.GetType().FullName;
                if (srp && !urp) Unsupported("render_pipeline_is_not_verified_builtin_or_urp");
                if (urp && SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D11 && SystemInfo.graphicsDeviceType != GraphicsDeviceType.Direct3D12) Unsupported("urp_backend_not_verified_for_preserved_color_load");
                var documentType = FindType("UnityEngine.UIElements.UIDocument");
                if (documentType != null)
                {
                    foreach (var item in Resources.FindObjectsOfTypeAll(documentType).OfType<Behaviour>().Where(d => d && d.isActiveAndEnabled && d.gameObject.scene.IsValid()))
                    {
                        var panel = Property(item, "panelSettings");
                        if (panel != null) Unsupported("active_ui_toolkit_panel_requires_separate_verified_observer");
                    }
                }
                if (UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Any(b => b && b.isActiveAndEnabled && b.GetType().GetMethod("OnGUI", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null, Type.EmptyTypes, null) != null)) Unsupported("active_imgui_requires_separate_verified_gui_observer");
                if (allCameras.Any(c => c.isActiveAndEnabled && c.targetTexture != null)) Unsupported("existing_camera_render_texture_requires_verified_dependency_graph");
                var displayCameras = allCameras.Where(c => c.isActiveAndEnabled && c.targetDisplay == 0 && c.targetTexture == null).ToArray();
                if (displayCameras.Any(c => c.stereoEnabled)) Unsupported("stereo_or_xr_camera");
                var cameras = displayCameras.Where(c => !urp || !IsOverlay(c)).OrderBy(c => c.depth).ThenBy(c => c.GetInstanceID()).ToArray();
                for (int i = 0; i < cameras.Length; i++)
                {
                    if (!urp && cameras[i].clearFlags == CameraClearFlags.Nothing) Unsupported("builtin_nothing_clear_requires_preserved_cross_camera_depth");
                    for (int j = i + 1; j < cameras.Length; j++) if (cameras[i].depth == cameras[j].depth && cameras[i].rect.Overlaps(cameras[j].rect)) Unsupported("overlapping_cameras_have_ambiguous_equal_depth");
                    if (urp && !RenderPipeline.SupportsRenderRequest(cameras[i], new RenderPipeline.StandardRequest())) Unsupported("urp_standard_render_request_not_supported");
                }
                var overlays = allCanvases.Where(c => c.isActiveAndEnabled && c.isRootCanvas && c.targetDisplay == 0 && (c.renderMode == RenderMode.ScreenSpaceOverlay || c.renderMode == RenderMode.ScreenSpaceCamera && !c.worldCamera)).ToArray();
                foreach (var canvas in overlays)
                {
                    if (canvas.GetComponentsInChildren<Renderer>(true).Any(r => r && r.enabled)) Unsupported("non_ui_renderer_descendant_of_overlay_canvas");
                    canvasStates.Add(new CanvasState(canvas));
                    foreach (var t in canvas.GetComponentsInChildren<Transform>(true)) layers[t.gameObject] = t.gameObject.layer;
                }
                // Any pre-existing use of the temporary UI layer is isolated for the UI pass only.
                foreach (var t in UnityEngine.Object.FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
                    if (t.gameObject.layer == 31 && !layers.ContainsKey(t.gameObject)) layers[t.gameObject] = 31;
                report.overlay_canvases = overlays.Length;
                report.render_configuration_before_sha256 = ConfigurationHash(allCameras, allCanvases, layers.Keys);
                foreach (var state in canvasStates) state.canvas.enabled = false;
                Canvas.ForceUpdateCanvases();
                var frame = Enumerable.Repeat(new Color32(0, 0, 0, 255), width * height).ToArray();
                foreach (var camera in cameras)
                {
                    var rect = camera.rect;
                    int x = Mathf.FloorToInt(rect.x * width), y = Mathf.FloorToInt(rect.y * height);
                    int right = Mathf.CeilToInt(rect.xMax * width), top = Mathf.CeilToInt(rect.yMax * height);
                    int tileWidth = right - x, tileHeight = top - y;
                    if (tileWidth <= 0 || tileHeight <= 0) continue;
                    if (tileWidth > 8192 || tileHeight > 8192) Unsupported("camera_viewport_exceeds_observer_allocation_boundary");
                    var tile = ReadRegion(frame, width, height, x, y, tileWidth, tileHeight);
                    var pass = new ViewportCameraPass { camera = camera.name, instance_id = camera.GetInstanceID(), depth = camera.depth, viewport = rect, original_aspect = camera.aspect, tile_width = tileWidth, tile_height = tileHeight, pipeline = report.pipeline, stack_overlays = urp ? Stack(camera).Length : 0 };
                    var pixels = RenderTile(camera, tileWidth, tileHeight, tile, urp, camera.aspect, diagnosticCheckpoint, "world");
                    WriteRegion(frame, width, height, x, y, tileWidth, tileHeight, pixels);
                    report.camera_passes.Add(pass);
                }
                if (overlays.Length > 0)
                {
                    var overlayObjects = new HashSet<GameObject>(overlays.SelectMany(c => c.GetComponentsInChildren<Transform>(true)).Select(t => t.gameObject));
                    foreach (var pair in layers) pair.Key.layer = overlayObjects.Contains(pair.Key) ? 31 : 30;
                    uiObject = new GameObject("PrivateViewportOverlayObserver");
                    var ui = uiObject.AddComponent<Camera>(); ui.enabled = false; ui.cullingMask = unchecked(1 << 31); ui.clearFlags = CameraClearFlags.SolidColor;
                    ui.backgroundColor = Color.clear; ui.orthographic = true; ui.orthographicSize = 5; ui.nearClipPlane = .01f; ui.farClipPlane = 100; ui.allowHDR = false; ui.allowMSAA = false; ui.rect = new Rect(0, 0, 1, 1); ui.aspect = (float)width / height; ui.transform.position = new Vector3(0, 0, -10);
                    if (urp)
                    {
                        var dataType = FindType("UnityEngine.Rendering.Universal.UniversalAdditionalCameraData");
                        if (dataType == null) Unsupported("urp_additional_camera_data_unavailable");
                        var data = uiObject.AddComponent(dataType);
                        dataType.GetProperty("renderPostProcessing")?.SetValue(data, false);
                        // Custom renderer features can alter a synthetic UI-only pass, so fail closed.
                        var renderer = Property(data, "scriptableRenderer");
                        var features = Property(renderer, "rendererFeatures") as IEnumerable;
                        if (features != null && features.Cast<object>().Any(f => f != null && !Equals(Property(f, "isActive"), false))) Unsupported("urp_overlay_pass_with_active_custom_renderer_features");
                    }
                    foreach (var state in canvasStates) { state.canvas.renderMode = RenderMode.ScreenSpaceCamera; state.canvas.worldCamera = ui; state.canvas.planeDistance = 1; state.canvas.enabled = true; }
                    // URP may discard a render request's pre-existing color attachment.
                    // Present the already rendered world as an opaque, point-sampled quad
                    // before the real UI draw, rather than relying on load actions or
                    // incorrectly multiplying a transparent render texture's alpha twice.
                    OverlayBackground(uiObject.transform, width, height, frame, ownedUiResources);
                    Canvas.ForceUpdateCanvases(); diagnosticCheckpoint?.Invoke("overlay-prepared");
                    frame = RenderTile(ui, width, height, frame, urp, (float)width / height, diagnosticCheckpoint, "overlay");
                }
                result = new Texture2D(width, height, TextureFormat.RGB24, false); result.SetPixels32(frame); result.Apply();
                report.nonblack_rgb_pixels = frame.Count(p => p.r > 16 || p.g > 16 || p.b > 16);
                report.observer_status = "captured";
                report.valid = true;
            }
            catch (ViewportCaptureUnsupportedException e) { report.observer_status = "unsupported"; report.unsupported_reason = e.reason; report.error = e.ToString(); throw; }
            catch (Exception e) { report.observer_status = "failed"; report.error = e.ToString(); throw; }
            finally
            {
                foreach (var state in cameraStates) state.Restore();
                foreach (var state in canvasStates) state.Restore();
                foreach (var pair in layers) if (pair.Key) pair.Key.layer = pair.Value;
                if (uiObject) UnityEngine.Object.DestroyImmediate(uiObject);
                foreach (var resource in ownedUiResources) if (resource) UnityEngine.Object.DestroyImmediate(resource);
                Canvas.ForceUpdateCanvases(); RenderTexture.active = originalActive;
                if (report.render_configuration_before_sha256 == null) report.render_configuration_before_sha256 = ConfigurationHash(allCameras, allCanvases, layers.Keys);
                report.render_configuration_after_sha256 = ConfigurationHash(allCameras, allCanvases, layers.Keys);
                report.render_configuration_restored = report.render_configuration_before_sha256 == report.render_configuration_after_sha256;
                if (!report.render_configuration_restored) { report.valid = false; report.observer_status = "configuration_restore_failed"; if (result) UnityEngine.Object.DestroyImmediate(result); result = null; }
            }
            if (!report.render_configuration_restored) throw new InvalidOperationException("Observer failed to restore camera/canvas/layer/render-target configuration.");
            return result;
        }

        static void OverlayBackground(Transform owner, int width, int height, Color32[] frame, List<UnityEngine.Object> resources)
        {
            var shader = Shader.Find("UI/Default"); if (!shader) Unsupported("standard_ui_shader_unavailable_for_preserved_frame_background");
            var opaque = frame.Select(p => new Color32(p.r, p.g, p.b, 255)).ToArray();
            var texture = new Texture2D(width, height, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            texture.SetPixels32(opaque); texture.Apply(); resources.Add(texture);
            var material = new Material(shader) { mainTexture = texture, renderQueue = 2000 }; material.SetColor("_Color", Color.white); resources.Add(material);
            float halfWidth = 5f * width / height;
            var mesh = new Mesh { vertices = new[] { new Vector3(-halfWidth, -5, 0), new Vector3(-halfWidth, 5, 0), new Vector3(halfWidth, 5, 0), new Vector3(halfWidth, -5, 0) }, uv = new[] { new Vector2(0, 0), new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0) }, colors = new[] { Color.white, Color.white, Color.white, Color.white }, triangles = new[] { 0, 1, 2, 0, 2, 3 } };
            mesh.RecalculateBounds(); resources.Add(mesh);
            var background = new GameObject("Observer preserved world frame"); background.transform.SetParent(owner, false); background.transform.localPosition = new Vector3(0, 0, 10); background.layer = 31;
            background.AddComponent<MeshFilter>().sharedMesh = mesh; var renderer = background.AddComponent<MeshRenderer>(); renderer.sharedMaterial = material;
        }

        static Color32[] RenderTile(Camera camera, int width, int height, Color32[] previous, bool urp, float originalAspect, Action<string> checkpoint, string phase)
        {
            var state = new CameraState(camera); var active = RenderTexture.active;
            var target = new RenderTexture(width, height, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default) { antiAliasing = 1 };
            Texture2D seed = null, output = null;
            try
            {
                target.Create(); seed = new Texture2D(width, height, TextureFormat.RGBA32, false); seed.SetPixels32(previous); seed.Apply(); Graphics.Blit(seed, target);
                camera.targetTexture = target; camera.rect = new Rect(0, 0, 1, 1); camera.aspect = originalAspect;
                Canvas.ForceUpdateCanvases(); checkpoint?.Invoke(phase + "-target-assigned");
                if (urp)
                {
                    var request = new RenderPipeline.StandardRequest { destination = target };
                    if (!RenderPipeline.SupportsRenderRequest(camera, request)) Unsupported("standard_render_request_rejected_for_camera");
                    RenderPipeline.SubmitRenderRequest(camera, request);
                }
                else camera.Render();
                RenderTexture.active = target; output = new Texture2D(width, height, TextureFormat.RGBA32, false); output.ReadPixels(new Rect(0, 0, width, height), 0, 0); output.Apply(); return output.GetPixels32();
            }
            finally
            {
                state.Restore(); RenderTexture.active = active; if (seed) UnityEngine.Object.DestroyImmediate(seed); if (output) UnityEngine.Object.DestroyImmediate(output); target.Release(); UnityEngine.Object.DestroyImmediate(target);
            }
        }
        static Color32[] ReadRegion(Color32[] frame, int width, int height, int x, int y, int tileWidth, int tileHeight)
        {
            var tile = Enumerable.Repeat(new Color32(0, 0, 0, 255), tileWidth * tileHeight).ToArray();
            for (int py = 0; py < tileHeight; py++) for (int px = 0; px < tileWidth; px++) if (x + px >= 0 && x + px < width && y + py >= 0 && y + py < height) tile[py * tileWidth + px] = frame[(y + py) * width + x + px];
            return tile;
        }
        static void WriteRegion(Color32[] frame, int width, int height, int x, int y, int tileWidth, int tileHeight, Color32[] tile)
        {
            for (int py = 0; py < tileHeight; py++) for (int px = 0; px < tileWidth; px++) if (x + px >= 0 && x + px < width && y + py >= 0 && y + py < height) frame[(y + py) * width + x + px] = tile[py * tileWidth + px];
        }
    }
}
