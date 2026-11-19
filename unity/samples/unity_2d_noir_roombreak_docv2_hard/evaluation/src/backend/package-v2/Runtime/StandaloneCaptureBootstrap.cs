using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

namespace GameCreate.NoirRoombreak.Evaluator.Standalone
{
    internal sealed class StandaloneCaptureBootstrap : MonoBehaviour
    {
        StandaloneInputDriver input;
        StandaloneOnGuiSentinel sentinel;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Install()
        {
            if (Application.isEditor) return;
            if (!string.Equals(Environment.GetEnvironmentVariable("NOIR_STANDALONE_CAPTURE_ENABLED"), "1", StringComparison.Ordinal)) return;
            var go = new GameObject("NoirStandaloneCaptureBootstrap");
            DontDestroyOnLoad(go);
            go.AddComponent<StandaloneCaptureBootstrap>();
        }

        IEnumerator Start()
        {
            Application.runInBackground = true;
            Application.targetFrameRate = 120;
            QualitySettings.vSyncCount = 0;
            var screenshotPath = StandaloneCaptureContract.ScreenshotPath;
            var receiptPath = StandaloneCaptureContract.ReceiptPath;
            var diagnosticDir = StandaloneCaptureContract.DiagnosticDir;
            if (string.IsNullOrWhiteSpace(screenshotPath) || string.IsNullOrWhiteSpace(receiptPath))
            {
                Application.Quit(3);
                yield break;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(screenshotPath));
            Directory.CreateDirectory(Path.GetDirectoryName(receiptPath));
            if (!string.IsNullOrWhiteSpace(diagnosticDir)) Directory.CreateDirectory(diagnosticDir);
            if (File.Exists(screenshotPath)) File.Delete(screenshotPath);

            Screen.SetResolution(StandaloneCaptureContract.Width, StandaloneCaptureContract.Height, FullScreenMode.Windowed);
            var resolutionDeadline = Time.realtimeSinceStartup + 10f;
            while ((Screen.width != StandaloneCaptureContract.Width || Screen.height != StandaloneCaptureContract.Height) && Time.realtimeSinceStartup < resolutionDeadline) yield return null;
            if (Screen.width != StandaloneCaptureContract.Width || Screen.height != StandaloneCaptureContract.Height)
            {
                FinishEvaluatorError(null, "", "resolution_unavailable", $"Screen remained {Screen.width}x{Screen.height}.");
                yield break;
            }

            INoirRoombreakProbe probe = null;
            var probeDeadline = Time.realtimeSinceStartup + 15f;
            while (probe == null && Time.realtimeSinceStartup < probeDeadline)
            {
                probe = FindProbe();
                if (probe == null) yield return null;
            }
            if (probe == null)
            {
                FinishCandidateUnavailable(null, "probe_missing", "No active INoirRoombreakProbe appeared within 15 seconds.", "probe_missing");
                yield break;
            }

            input = new StandaloneInputDriver();
            var inputPath = "already_playing";
            if (probe.CurrentScreen == NoirScreen.Menu)
            {
                var publicRect = probe.StartButtonScreenRect;
                if (ValidRect(publicRect))
                {
                    yield return input.Click(publicRect.center);
                    yield return WaitForPlaying(probe, 3f);
                    if (probe.CurrentScreen == NoirScreen.Playing) inputPath = "probe_public_rect";
                }
                if (probe.CurrentScreen == NoirScreen.Menu && TryFindButtonRect(publicRect, out var buttonRect))
                {
                    yield return input.Click(buttonRect.center);
                    yield return WaitForPlaying(probe, 3f);
                    if (probe.CurrentScreen == NoirScreen.Playing) inputPath = "actual_ugui_button";
                }
                if (probe.CurrentScreen == NoirScreen.Menu)
                {
                    yield return input.Press(Key.Enter);
                    yield return WaitForPlaying(probe, 3f);
                    if (probe.CurrentScreen == NoirScreen.Playing) inputPath = "enter_key";
                }
                if (probe.CurrentScreen == NoirScreen.Menu)
                {
                    yield return input.Press(Key.Space);
                    yield return WaitForPlaying(probe, 3f);
                    if (probe.CurrentScreen == NoirScreen.Playing) inputPath = "space_key";
                }
            }
            input.Dispose();
            input = null;

            var initialDeadline = Time.realtimeSinceStartup + 5f;
            while (!InitialValid(probe) && Time.realtimeSinceStartup < initialDeadline) yield return null;
            if (!InitialValid(probe))
            {
                FinishCandidateUnavailable(probe, "initial_gameplay_unavailable", "Real input did not reach the required clean initial gameplay state.", inputPath);
                yield break;
            }
            for (var i = 0; i < 24; i++) yield return null;

            var canvasStates = StandaloneCaptureRenderer.CaptureCanvases();
            sentinel = new GameObject("NoirStandaloneOnGuiSentinel").AddComponent<StandaloneOnGuiSentinel>();
            DontDestroyOnLoad(sentinel.gameObject);
            Texture2D proof = null;
            Texture2D cleanBase = null;
            Texture2D overlayTexture = null;
            Texture2D composite = null;
            var sentinelReceipt = new SentinelReceipt { rect = StandaloneOnGuiSentinel.RectFor(StandaloneCaptureContract.Width).ToString() };
            var overlayReceipt = new OverlayReceipt();
            var restoration = new RestorationReceipt();
            var captureError = "";

            SetCanvasEnabled(canvasStates, false);
            Canvas.ForceUpdateCanvases();
            sentinel.Visible = true;
            // The sentinel may be created after this frame's IMGUI event has
            // already run.  Give it two complete player-loop frames before
            // capturing the proof backbuffer; otherwise a legitimate OnGUI
            // candidate can expose a same-frame race and be misclassified as
            // an evaluator capture failure.
            yield return null;
            yield return null;
            yield return new WaitForEndOfFrame();
            try
            {
                proof = StandaloneCaptureRenderer.CaptureCurrentFrame();
                if (proof.width != StandaloneCaptureContract.Width || proof.height != StandaloneCaptureContract.Height) throw new InvalidOperationException($"Sentinel proof was {proof.width}x{proof.height}.");
                sentinelReceipt.proof_match_pixels = StandaloneOnGuiSentinel.MatchPixels(proof);
                sentinelReceipt.proof_valid = sentinelReceipt.proof_match_pixels >= 180;
                if (!string.IsNullOrWhiteSpace(diagnosticDir))
                {
                    var path = Path.Combine(diagnosticDir, "standalone-sentinel-proof.png");
                    File.WriteAllBytes(path, proof.EncodeToPNG());
                    sentinelReceipt.proof_sha256 = StandaloneCaptureContract.Sha256(path);
                }
                if (!sentinelReceipt.proof_valid) throw new InvalidOperationException("The headful backbuffer did not contain the evaluator OnGUI sentinel.");
            }
            catch (Exception ex) { captureError = ex.GetType().Name + ":" + ex.Message; }

            sentinel.Visible = false;
            if (string.IsNullOrWhiteSpace(captureError))
            {
                yield return null;
                yield return new WaitForEndOfFrame();
                try
                {
                    cleanBase = StandaloneCaptureRenderer.CaptureCurrentFrame();
                    if (cleanBase.width != StandaloneCaptureContract.Width || cleanBase.height != StandaloneCaptureContract.Height) throw new InvalidOperationException($"Clean base was {cleanBase.width}x{cleanBase.height}.");
                    sentinelReceipt.clean_match_pixels = StandaloneOnGuiSentinel.MatchPixels(cleanBase);
                    sentinelReceipt.clean_valid = sentinelReceipt.clean_match_pixels < 24;
                    if (!string.IsNullOrWhiteSpace(diagnosticDir))
                    {
                        var path = Path.Combine(diagnosticDir, "standalone-clean-base.png");
                        File.WriteAllBytes(path, cleanBase.EncodeToPNG());
                        sentinelReceipt.clean_base_sha256 = StandaloneCaptureContract.Sha256(path);
                    }
                    if (!sentinelReceipt.clean_valid) throw new InvalidOperationException("The clean base still contained the evaluator sentinel.");
                }
                catch (Exception ex) { captureError = ex.GetType().Name + ":" + ex.Message; }
            }

            SetCanvasEnabled(canvasStates, true);
            Canvas.ForceUpdateCanvases();
            if (string.IsNullOrWhiteSpace(captureError))
            {
                try
                {
                    var overlay = StandaloneCaptureRenderer.RenderOverlay(canvasStates, StandaloneCaptureContract.Width, StandaloneCaptureContract.Height);
                    overlayTexture = overlay.texture;
                    overlayReceipt.canvas_count = overlay.canvasCount;
                    overlayReceipt.moved_ui_object_count = overlay.movedUiObjects;
                    overlayReceipt.displaced_foreign_layer31_count = overlay.displacedForeign;
                    overlayReceipt.nonzero_alpha_pixels = overlay.nonzero;
                    overlayReceipt.partial_alpha_pixels = overlay.partial;
                    overlayReceipt.render_path = overlay.renderPath;
                    restoration.canvas_settings_restored = overlay.canvasRestored;
                    restoration.layers_restored = overlay.layersRestored;
                    if (overlay.canvasCount > 0 && overlay.nonzero < 32) throw new InvalidOperationException("Active screen-space canvases rendered fewer than 32 nonzero-alpha pixels.");
                    if (!string.IsNullOrWhiteSpace(diagnosticDir))
                    {
                        var path = Path.Combine(diagnosticDir, "standalone-ui-overlay.png");
                        File.WriteAllBytes(path, overlayTexture.EncodeToPNG());
                        overlayReceipt.sha256 = StandaloneCaptureContract.Sha256(path);
                    }
                    composite = StandaloneCaptureRenderer.Blend(cleanBase, overlayTexture);
                    File.WriteAllBytes(screenshotPath, composite.EncodeToPNG());
                    restoration.completed = restoration.canvas_settings_restored && restoration.layers_restored && CanvasStatesMatch(canvasStates);
                    if (!restoration.completed) throw new InvalidOperationException("Canvas or layer restoration did not complete.");
                }
                catch (Exception ex) { captureError = ex.GetType().Name + ":" + ex.Message; }
            }

            SetCanvasEnabled(canvasStates, true);
            restoration.canvas_settings_restored = restoration.canvas_settings_restored && CanvasStatesMatch(canvasStates);
            restoration.completed = restoration.canvas_settings_restored && restoration.layers_restored;
            if (sentinel != null) sentinel.Visible = false;
            DestroyTexture(proof);
            DestroyTexture(cleanBase);
            DestroyTexture(overlayTexture);
            DestroyTexture(composite);
            if (sentinel != null) Destroy(sentinel.gameObject);

            if (!string.IsNullOrWhiteSpace(captureError))
            {
                FinishEvaluatorError(probe, inputPath, "capture_error", captureError, sentinelReceipt, overlayReceipt, restoration);
                yield break;
            }

            var file = new FileInfo(screenshotPath);
            var receipt = StandaloneCaptureContract.BaseReceipt(probe, inputPath);
            receipt.status = "captured";
            receipt.classification = "valid_capture";
            receipt.valid = true;
            receipt.width = StandaloneCaptureContract.Width;
            receipt.height = StandaloneCaptureContract.Height;
            receipt.bytes = file.Length;
            receipt.sha256 = StandaloneCaptureContract.Sha256(screenshotPath);
            receipt.sentinel = sentinelReceipt;
            receipt.overlay = overlayReceipt;
            receipt.restoration = restoration;
            receipt.planned_exit_code = 0;
            StandaloneCaptureContract.Write(receipt);
            yield return null;
            Application.Quit(0);
        }

        static IEnumerator WaitForPlaying(INoirRoombreakProbe probe, float seconds)
        {
            var deadline = Time.realtimeSinceStartup + seconds;
            while (probe != null && probe.CurrentScreen != NoirScreen.Playing && Time.realtimeSinceStartup < deadline) yield return null;
        }

        static INoirRoombreakProbe FindProbe()
        {
            try
            {
                return FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).OfType<INoirRoombreakProbe>().FirstOrDefault();
            }
            catch { return null; }
        }

        static bool ValidRect(Rect rect)
        {
            return Finite(rect.x) && Finite(rect.y) && Finite(rect.width) && Finite(rect.height) && rect.width >= 8 && rect.height >= 8 && rect.xMax > 0 && rect.yMax > 0 && rect.xMin < Screen.width && rect.yMin < Screen.height;
        }

        static bool Finite(float value) => !float.IsNaN(value) && !float.IsInfinity(value);

        static bool TryFindButtonRect(Rect preferred, out Rect rect)
        {
            rect = Rect.zero;
            try
            {
                var candidates = FindObjectsByType<Button>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Where(x => x != null && x.isActiveAndEnabled && x.interactable && x.gameObject.activeInHierarchy)
                    .Select(ButtonRect).Where(ValidRect).ToArray();
                if (candidates.Length == 0) return false;
                if (candidates.Length == 1) { rect = candidates[0]; return true; }
                if (!ValidRect(preferred)) return false;
                var ordered = candidates.OrderBy(x => Vector2.Distance(x.center, preferred.center)).ToArray();
                if (Mathf.Abs(Vector2.Distance(ordered[0].center, preferred.center) - Vector2.Distance(ordered[1].center, preferred.center)) < 2f) return false;
                rect = ordered[0];
                return true;
            }
            catch { return false; }
        }

        static Rect ButtonRect(Button button)
        {
            var transform = button.transform as RectTransform;
            if (transform == null) return Rect.zero;
            var corners = new Vector3[4];
            transform.GetWorldCorners(corners);
            var canvas = button.GetComponentInParent<Canvas>();
            Camera camera = null;
            if (canvas != null && canvas.renderMode != RenderMode.ScreenSpaceOverlay) camera = canvas.worldCamera;
            var a = RectTransformUtility.WorldToScreenPoint(camera, corners[0]);
            var b = RectTransformUtility.WorldToScreenPoint(camera, corners[2]);
            return Rect.MinMaxRect(Mathf.Min(a.x, b.x), Mathf.Min(a.y, b.y), Mathf.Max(a.x, b.x), Mathf.Max(a.y, b.y));
        }

        static void SetCanvasEnabled(IEnumerable<CanvasState> states, bool enabled)
        {
            foreach (var state in states)
                if (state.canvas != null) state.canvas.enabled = enabled ? state.enabled : false;
        }

        static bool CanvasStatesMatch(IEnumerable<CanvasState> states)
        {
            return states.All(x => x.canvas != null && x.canvas.enabled == x.enabled && x.canvas.renderMode == x.mode && x.canvas.worldCamera == x.worldCamera && Mathf.Abs(x.canvas.planeDistance - x.planeDistance) < .001f);
        }

        static bool InitialValid(INoirRoombreakProbe probe)
        {
            // Visual quality is independent of resource/progression correctness.
            return probe != null && probe.CurrentScreen == NoirScreen.Playing;
        }

        void FinishCandidateUnavailable(INoirRoombreakProbe probe, string status, string error, string inputPath)
        {
            input?.Dispose();
            input = null;
            var receipt = StandaloneCaptureContract.BaseReceipt(probe, inputPath);
            receipt.status = status;
            receipt.classification = "candidate_state_unavailable";
            receipt.valid = false;
            receipt.error = error;
            receipt.planned_exit_code = 0;
            StandaloneCaptureContract.Write(receipt);
            Application.Quit(0);
        }

        void FinishEvaluatorError(INoirRoombreakProbe probe, string inputPath, string status, string error, SentinelReceipt sentinelState = null, OverlayReceipt overlayState = null, RestorationReceipt restorationState = null)
        {
            input?.Dispose();
            input = null;
            var receipt = StandaloneCaptureContract.BaseReceipt(probe, inputPath);
            receipt.status = status;
            receipt.classification = "evaluator_capture_error";
            receipt.valid = false;
            receipt.error = error;
            if (sentinelState != null) receipt.sentinel = sentinelState;
            if (overlayState != null) receipt.overlay = overlayState;
            if (restorationState != null) receipt.restoration = restorationState;
            receipt.planned_exit_code = 3;
            StandaloneCaptureContract.Write(receipt);
            Application.Quit(3);
        }

        static void DestroyTexture(Texture2D texture)
        {
            if (texture != null) Destroy(texture);
        }

        void OnDestroy()
        {
            input?.Dispose();
        }
    }
}
