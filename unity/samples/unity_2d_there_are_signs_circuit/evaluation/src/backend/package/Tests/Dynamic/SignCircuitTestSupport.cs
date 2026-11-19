using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using NUnit.Framework;
using OmniGame.Benchmark.SignCircuit.Contract;
using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;
using UnityEngine.UIElements;
using UguiButton = UnityEngine.UI.Button;
using UguiText = UnityEngine.UI.Text;
using ToolkitButton = UnityEngine.UIElements.Button;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    internal static class SignCircuitContract
    {
        public const string MainScenePath =
            "Assets/Scenes/Benchmark/SignCircuit.unity";
        public const string MenuScenePath = "Assets/Scenes/Menu.unity";
        public const string RegressionScenePath = "Assets/Scenes/Levels/Level1+2.unity";
    }

    /// <summary>
    /// A player-facing avatar discovered from its response to ordinary keyboard input.
    /// Rigidbody2D, Collider2D, PlayerInput, tags, names and controller types are optional
    /// diagnostics only; Position is observed from the moved visible renderer.
    /// </summary>
    internal sealed class SignCircuitPlayer
    {
        public GameObject Root;
        public Renderer Visual;
        public Rigidbody2D OptionalBody;
        public Collider2D[] OptionalColliders;

        public Vector2 Position => Visual != null
            ? (Vector2)Visual.bounds.center
            : Root == null ? Vector2.zero : (Vector2)Root.transform.position;

        public Bounds Bounds => Visual != null
            ? Visual.bounds
            : new Bounds(Root == null ? Vector3.zero : Root.transform.position,
                Vector3.one * 0.1f);

        public Vector2 Velocity => OptionalBody != null && OptionalBody.simulated
            ? OptionalBody.linearVelocity
            : Vector2.zero;

        public string ObservationPath => Visual == null
            ? "<none>"
            : SignCircuitTestSupport.HierarchyPath(Visual.transform);
    }

    internal enum UiClickBackend
    {
        Ugui,
        UiToolkit,
        ScreenPoint
    }

    internal sealed class UiClickTarget
    {
        public UiClickBackend Backend;
        public string Name;
        public string Label;
        public UguiButton UguiButton;
        public UIDocument Document;
        public ToolkitButton ToolkitButton;
        public Vector2 ScreenPoint;
        public Rect ProbeRect;
        public bool HasProbeRect;
        public GameObject ExpectedPointerHandler;
        public VisualElement ExpectedToolkitHit;
        public string RouteDescription;
    }

    internal sealed class VisibleUiText
    {
        public string Backend;
        public string Name;
        public string Text;
        public RectTransform RectTransform;
        public UIDocument Document;
        public TextElement ToolkitElement;

        public override string ToString() => $"{Backend}:{Name}='{Text}'";
    }

    internal sealed class RouteBlockObservation
    {
        public float StartX;
        public float BlockedX;
        public float Displacement;
        public float StableSeconds;
        public float MaximumFrameStep;
    }

    internal static class SignCircuitTestSupport
    {
        public static IEnumerator LoadScene(string path)
        {
            Assert.That(Application.CanStreamedLevelBeLoaded(path), Is.True,
                $"Required scene is not enabled and loadable: {path}");
            Time.timeScale = 1f;
            AsyncOperation load = SceneManager.LoadSceneAsync(path, LoadSceneMode.Single);
            Assert.That(load, Is.Not.Null, $"SceneManager could not start loading {path}.");
            float deadline = Time.realtimeSinceStartup + 15f;
            while (!load.isDone && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }
            Assert.That(load.isDone, Is.True, $"Scene load timed out: {path}");
            yield return null;
            yield return null;
            Assert.That(SceneManager.GetActiveScene().path, Is.EqualTo(path));
        }

        /// <summary>
        /// Discovers the visible avatar by the bidirectional world-space response to D then A.
        /// No candidate component, class name, tag, physics body or input wrapper is required.
        /// </summary>
        public static IEnumerator DiscoverPlayer(
            NativeInputDriver driver,
            Action<SignCircuitPlayer> receive,
            float rightSeconds = 0.38f,
            float leftSeconds = 0.46f)
        {
            yield return driver.Initialize();
            Renderer[] candidates = ObservableWorldRenderers().ToArray();
            Assert.That(candidates, Is.Not.Empty,
                "The playable scene exposed no visible world renderer to observe as the avatar.");
            var start = candidates.ToDictionary(item => item, item => (Vector2)item.bounds.center);

            yield return driver.Hold(Key.D, rightSeconds, false);
            var afterRight = candidates.Where(IsObservableRenderer)
                .ToDictionary(item => item, item => (Vector2)item.bounds.center);
            yield return driver.Hold(Key.A, leftSeconds, false);
            var afterLeft = candidates.Where(IsObservableRenderer)
                .ToDictionary(item => item, item => (Vector2)item.bounds.center);

            var ranked = candidates
                .Where(item => start.ContainsKey(item) && afterRight.ContainsKey(item) &&
                               afterLeft.ContainsKey(item))
                .Select(item =>
                {
                    float right = afterRight[item].x - start[item].x;
                    float reverse = afterRight[item].x - afterLeft[item].x;
                    float verticalNoise = Mathf.Abs(afterRight[item].y - start[item].y) +
                                          Mathf.Abs(afterLeft[item].y - afterRight[item].y);
                    float semanticHint = HasPlayerTagInParents(item.transform) ? 0.05f : 0f;
                    return new
                    {
                        Renderer = item,
                        Right = right,
                        Reverse = reverse,
                        Score = Mathf.Min(right, reverse) - verticalNoise * 0.05f + semanticHint
                    };
                })
                .Where(item => item.Right > 0.08f && item.Reverse > 0.08f)
                .OrderByDescending(item => item.Score)
                .ThenBy(item => item.Renderer.bounds.size.sqrMagnitude)
                .ToArray();

            Assert.That(ranked, Is.Not.Empty,
                "Normal D/A input did not reveal a visible object that moved right and then left. " +
                "The evaluator does not require Rigidbody2D, Collider2D, PlayerInput, tags or names.");
            Renderer visual = ranked[0].Renderer;
            GameObject root = FindObservedRoot(visual);
            var player = new SignCircuitPlayer
            {
                Root = root,
                Visual = visual,
                OptionalBody = root.GetComponentInParent<Rigidbody2D>() ??
                               root.GetComponentInChildren<Rigidbody2D>(true),
                OptionalColliders = root.GetComponentsInChildren<Collider2D>(true)
            };
            receive?.Invoke(player);
        }

        static IEnumerable<Renderer> ObservableWorldRenderers()
        {
            Scene scene = SceneManager.GetActiveScene();
            return UnityEngine.Object.FindObjectsByType<Renderer>(
                    FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(item => item.gameObject.scene == scene && IsObservableRenderer(item));
        }

        static bool IsObservableRenderer(Renderer item)
        {
            if (item == null || !item.enabled || item.forceRenderingOff ||
                !item.gameObject.activeInHierarchy ||
                item.shadowCastingMode == UnityEngine.Rendering.ShadowCastingMode.ShadowsOnly)
                return false;
            Bounds bounds = item.bounds;
            if (bounds.size.x < 0.02f || bounds.size.y < 0.02f) return false;
            if (bounds.size.x > 8f || bounds.size.y > 8f ||
                bounds.size.x * bounds.size.y > 36f) return false;
            if (item.GetComponentInParent<Canvas>() != null ||
                EffectiveRendererAlpha(item) <= 0.001f) return false;

            Scene activeScene = SceneManager.GetActiveScene();
            return Camera.allCameras.Any(camera =>
                camera != null && camera.isActiveAndEnabled &&
                camera.gameObject.activeInHierarchy &&
                camera.gameObject.scene == activeScene &&
                (camera.cullingMask & (1 << item.gameObject.layer)) != 0 &&
                GeometryUtility.TestPlanesAABB(
                    GeometryUtility.CalculateFrustumPlanes(camera), bounds));
        }

        static float EffectiveRendererAlpha(Renderer renderer)
        {
            float rendererAlpha = renderer is SpriteRenderer sprite
                ? Mathf.Clamp01(sprite.color.a)
                : 1f;

            var propertyBlock = new MaterialPropertyBlock();
            renderer.GetPropertyBlock(propertyBlock);
            int baseColorId = Shader.PropertyToID("_BaseColor");
            int colorId = Shader.PropertyToID("_Color");
            if (propertyBlock.HasColor(baseColorId))
                rendererAlpha *= Mathf.Clamp01(propertyBlock.GetColor(baseColorId).a);
            else if (propertyBlock.HasColor(colorId))
                rendererAlpha *= Mathf.Clamp01(propertyBlock.GetColor(colorId).a);

            Material[] materials = renderer.sharedMaterials;
            if (materials == null || materials.Length == 0) return rendererAlpha;

            float mostVisibleMaterialAlpha = 0f;
            bool foundColor = false;
            foreach (Material material in materials)
            {
                if (material == null) continue;
                float alpha = 1f;
                if (material.HasProperty("_BaseColor"))
                {
                    alpha = Mathf.Clamp01(material.GetColor("_BaseColor").a);
                    foundColor = true;
                }
                else if (material.HasProperty("_Color"))
                {
                    alpha = Mathf.Clamp01(material.GetColor("_Color").a);
                    foundColor = true;
                }
                mostVisibleMaterialAlpha = Mathf.Max(mostVisibleMaterialAlpha, alpha);
            }
            return rendererAlpha * (foundColor ? mostVisibleMaterialAlpha : 1f);
        }

        static GameObject FindObservedRoot(Renderer visual)
        {
            Rigidbody2D body = visual.GetComponentInParent<Rigidbody2D>();
            if (body != null && body.simulated) return body.gameObject;
            for (Transform current = visual.transform; current != null; current = current.parent)
            {
                if (HasPlayerTag(current.gameObject)) return current.gameObject;
            }
            return visual.gameObject;
        }

        static bool HasPlayerTagInParents(Transform item)
        {
            for (Transform current = item; current != null; current = current.parent)
            {
                if (HasPlayerTag(current.gameObject)) return true;
            }
            return false;
        }

        static bool HasPlayerTag(GameObject item)
        {
            try { return item != null && item.CompareTag("Player"); }
            catch (UnityException) { return false; }
        }

        public static string WorldVisualSignature(SignCircuitPlayer player)
        {
            string[] records = ObservableWorldRenderers()
                .Where(item => !BelongsToPlayer(item.transform, player))
                .Select(StableRendererRecord)
                .OrderBy(item => item, StringComparer.Ordinal)
                .ToArray();
            return string.Join("|", records);
        }

        /// <summary>
        /// Captures only visible world feedback close enough to be causally related to
        /// the avatar's current interaction.  This deliberately excludes the avatar,
        /// candidate names/types/tags/colliders and the read-only benchmark probe.
        /// Keeping the observation local also prevents camera-follow/frustum settling
        /// elsewhere in the scene from masquerading as an E-key response.
        /// </summary>
        public static string NearbyWorldVisualSignature(
            SignCircuitPlayer player,
            float radius = 4f)
        {
            Vector3 center = player.Bounds.center;
            float radiusSquared = Mathf.Max(0.25f, radius) * Mathf.Max(0.25f, radius);
            string[] records = ObservableWorldRenderers()
                .Where(item => !BelongsToPlayer(item.transform, player))
                .Where(item => item.bounds.SqrDistance(center) <= radiusSquared)
                .Select(StableRendererRecord)
                .OrderBy(item => item, StringComparer.Ordinal)
                .ToArray();
            return string.Join("|", records);
        }

        static string StableRendererRecord(Renderer renderer)
        {
            Transform transform = renderer.transform;
            Bounds bounds = renderer.bounds;
            var builder = new StringBuilder();
            // Names, hierarchy, component types, instance identity and asset names
            // are deliberately excluded: renaming or replacing a renderer with a
            // visually identical one must not fabricate player-visible feedback.
            builder.Append(renderer.enabled ? '1' : '0').Append(':')
                .Append(transform.gameObject.activeSelf ? '1' : '0').Append(':')
                .Append(transform.gameObject.activeInHierarchy ? '1' : '0').Append(':');
            AppendQuantizedVector3(builder, transform.position, 100f);
            builder.Append(':');
            AppendQuantizedVector3(builder, transform.eulerAngles, 10f);
            builder.Append(':');
            AppendQuantizedVector3(builder, transform.lossyScale, 100f);
            builder.Append(':');
            AppendQuantizedVector3(builder, bounds.center, 100f);
            builder.Append(':');
            AppendQuantizedVector3(builder, bounds.size, 100f);
            builder.Append(":sort=").Append(renderer.sortingLayerID)
                .Append(',').Append(renderer.sortingOrder)
                .Append(":alpha=").Append(Quantize(EffectiveRendererAlpha(renderer), 1000f));
            AppendMaterialColors(builder, renderer.sharedMaterials);

            if (renderer is SpriteRenderer sprite)
            {
                builder.Append(":sprite-geometry=");
                if (sprite.sprite == null)
                {
                    builder.Append("none");
                }
                else
                {
                    Rect rect = sprite.sprite.rect;
                    builder.Append(Quantize(rect.width, 10f)).Append(',')
                        .Append(Quantize(rect.height, 10f)).Append(',')
                        .Append(Quantize(sprite.sprite.pixelsPerUnit, 10f));
                }
                builder.Append(":color=");
                AppendQuantizedColor(builder, sprite.color);
                builder.Append(":flip=").Append(sprite.flipX ? '1' : '0')
                    .Append(',').Append(sprite.flipY ? '1' : '0');
            }
            return builder.ToString();
        }

        static void AppendMaterialColors(StringBuilder builder, Material[] materials)
        {
            builder.Append(":colors=");
            if (materials == null || materials.Length == 0) return;
            for (int index = 0; index < materials.Length; index++)
            {
                if (index > 0) builder.Append(',');
                Material material = materials[index];
                if (material == null) continue;
                if (material.HasProperty("_BaseColor"))
                    AppendQuantizedColor(builder, material.GetColor("_BaseColor"));
                else if (material.HasProperty("_Color"))
                    AppendQuantizedColor(builder, material.GetColor("_Color"));
            }
        }

        static void AppendQuantizedVector3(StringBuilder builder, Vector3 value, float scale)
        {
            builder.Append(Quantize(value.x, scale)).Append(',')
                .Append(Quantize(value.y, scale)).Append(',')
                .Append(Quantize(value.z, scale));
        }

        static void AppendQuantizedColor(StringBuilder builder, Color value)
        {
            builder.Append(Quantize(value.r, 255f)).Append(',')
                .Append(Quantize(value.g, 255f)).Append(',')
                .Append(Quantize(value.b, 255f)).Append(',')
                .Append(Quantize(value.a, 255f));
        }

        static int Quantize(float value, float scale) => Mathf.RoundToInt(value * scale);

        public static int VisibleWorldContentCount(SignCircuitPlayer player) =>
            ObservableWorldRenderers().Count(item => !BelongsToPlayer(item.transform, player));

        static bool BelongsToPlayer(Transform item, SignCircuitPlayer player)
        {
            if (item == null || player?.Root == null) return false;
            return item == player.Root.transform || item.IsChildOf(player.Root.transform) ||
                   player.Root.transform.IsChildOf(item);
        }

        public static IEnumerator DriveDistance(
            NativeInputDriver driver,
            SignCircuitPlayer player,
            float signedDistance,
            float timeoutSeconds = 4f)
        {
            yield return driver.Initialize();
            float start = player.Position.x;
            float target = start + signedDistance;
            Key key = signedDistance >= 0f ? Key.D : Key.A;
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            try
            {
                while ((signedDistance >= 0f ? player.Position.x < target : player.Position.x > target) &&
                       Time.realtimeSinceStartup < deadline)
                {
                    driver.SetHeldKey(key);
                    yield return null;
                }
            }
            finally
            {
                driver.ReleaseKeyboard();
            }
            yield return null;
            float achieved = player.Position.x - start;
            Assert.That(signedDistance >= 0f ? achieved : -achieved,
                Is.GreaterThan(Mathf.Abs(signedDistance) * 0.65f),
                $"Ordinary {key} input did not move the observed avatar the requested distance. " +
                $"requested={signedDistance:F2}, achieved={achieved:F2}");
        }

        public static IEnumerator DriveRightUntilBlocked(
            NativeInputDriver driver,
            SignCircuitPlayer player,
            Action<RouteBlockObservation> receive,
            float timeoutSeconds = 8f)
        {
            yield return driver.Initialize();
            float startX = player.Position.x;
            float furthestX = startX;
            float priorX = startX;
            float lastAdvance = Time.realtimeSinceStartup;
            float maximumStep = 0f;
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            try
            {
                while (Time.realtimeSinceStartup < deadline && !IsFinishedVisible() &&
                       !FailureIsVisible())
                {
                    driver.SetHeldKey(Key.D);
                    yield return null;
                    float currentX = player.Position.x;
                    maximumStep = Mathf.Max(maximumStep, Mathf.Abs(currentX - priorX));
                    priorX = currentX;
                    if (currentX > furthestX + 0.015f)
                    {
                        furthestX = currentX;
                        lastAdvance = Time.realtimeSinceStartup;
                    }
                    if (furthestX - startX > 0.8f &&
                        Time.realtimeSinceStartup - lastAdvance >= 0.70f)
                    {
                        break;
                    }
                }
            }
            finally
            {
                driver.ReleaseKeyboard();
            }
            yield return null;
            float stable = Time.realtimeSinceStartup - lastAdvance;
            Assert.That(IsFinishedVisible(), Is.False,
                "The run reached success before the ordered route was complete.");
            Assert.That(FailureIsVisible(), Is.False,
                "The route-blocking probe timed out instead of reaching the closed barrier.");
            Assert.That(furthestX - startX, Is.GreaterThan(0.8f),
                "The avatar did not travel far enough to exercise a downstream route barrier.");
            Assert.That(stable, Is.GreaterThanOrEqualTo(0.65f),
                "Holding ordinary right movement never produced a stable blocked position.");
            receive?.Invoke(new RouteBlockObservation
            {
                StartX = startX,
                BlockedX = furthestX,
                Displacement = furthestX - startX,
                StableSeconds = stable,
                MaximumFrameStep = maximumStep
            });
        }

        public static IEnumerator DriveRightUntilFinished(
            NativeInputDriver driver,
            SignCircuitPlayer player,
            float mustCrossX,
            Action<float> receiveMaximumFrameStep,
            float timeoutSeconds = 10f)
        {
            yield return driver.Initialize();
            float priorX = player.Position.x;
            float maximumStep = 0f;
            float furthest = priorX;
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            try
            {
                while (!IsFinishedVisible() && Time.realtimeSinceStartup < deadline)
                {
                    driver.SetHeldKey(Key.D);
                    yield return null;
                    float currentX = player.Position.x;
                    maximumStep = Mathf.Max(maximumStep, Mathf.Abs(currentX - priorX));
                    furthest = Mathf.Max(furthest, currentX);
                    priorX = currentX;
                }
            }
            finally
            {
                driver.ReleaseKeyboard();
            }
            yield return null;
            Assert.That(IsFinishedVisible(), Is.True,
                "Ordinary right movement after 3/3 did not reach a visible success state.");
            Assert.That(furthest, Is.GreaterThan(mustCrossX + 0.20f),
                "The avatar did not cross the position that blocked the incomplete route.");
            Assert.That(maximumStep, Is.LessThan(3.0f),
                "The route appears to have teleported the avatar instead of allowing movement through it.");
            receiveMaximumFrameStep?.Invoke(maximumStep);
        }

        public static int ReadProgress(out string sourceText)
        {
            if (TryReadProgress(out int value, out sourceText)) return value;
            FailForMissingCandidateFeature(
                "The public ui.progress locator did not overlap one independently " +
                "readable active visible x/3 field. Probe data cannot replace real UI. " +
                sourceText);
            return -1;
        }

        public static bool TryReadProgress(out int value, out string sourceText)
        {
            bool found = SignCircuitSemanticUiObserver.TryReadProgress(
                out value, out sourceText);
            bool probeAvailable = TryReadProbe(out SignCircuitSnapshot snapshot) &&
                string.Equals(snapshot.scene, "circuit", StringComparison.OrdinalIgnoreCase);
            bool staleProbeHint = !found || !probeAvailable || !snapshot.hudVisible ||
                                  snapshot.progress != value;
            sourceText += ";probe_progress_hint=" +
                          (probeAvailable ? $"{snapshot.progress}/3" : "<unavailable>") +
                          ";stale_probe_progress_hint=" +
                          staleProbeHint.ToString().ToLowerInvariant() + ";" +
                          ProbeDiagnostic();
            return found;
        }

        public static string ReadBestTimeText() => ReadBestTimeText(out _);

        public static string ReadBestTimeText(out string sourceText)
        {
            if (!SignCircuitSemanticUiObserver.TryReadBest(
                    out string text, out double numericValue,
                    out bool hasNumericValue, out sourceText))
            {
                FailForMissingCandidateFeature("The public ui.best locator did not " +
                    "overlap a non-empty independently visible best-time field. " +
                    "Probe best-time values cannot substitute for real UI.");
            }
            bool probeAvailable = TryReadProbe(out SignCircuitSnapshot snapshot) &&
                string.Equals(snapshot.scene, "circuit", StringComparison.OrdinalIgnoreCase);
            bool staleProbeHint = !probeAvailable || !snapshot.hudVisible ||
                (hasNumericValue
                    ? !snapshot.hasBestTime ||
                      Math.Abs(numericValue - snapshot.bestTimeSeconds) > 0.03d
                    : snapshot.hasBestTime);
            sourceText += ";probe_best_hint=" +
                         (probeAvailable && snapshot.hasBestTime
                             ? snapshot.bestTimeSeconds.ToString("F2",
                                 CultureInfo.InvariantCulture)
                             : "<none>") +
                         ";stale_probe_best_hint=" +
                         staleProbeHint.ToString().ToLowerInvariant() + ";" +
                         ProbeDiagnostic();
            return text;
        }

        public static float ReadTimerSeconds(out string sourceText)
        {
            if (!SignCircuitSemanticUiObserver.TryReadTimer(
                    out float visibleValue, out sourceText))
            {
                FailForMissingCandidateFeature(
                    "The public ui.timer locator did not overlap one independently " +
                    "readable active visible time value. Probe time cannot replace real UI.");
            }
            bool probeAvailable = TryReadProbe(out SignCircuitSnapshot snapshot) &&
                string.Equals(snapshot.scene, "circuit", StringComparison.OrdinalIgnoreCase);
            bool staleProbeHint = !probeAvailable || !snapshot.hudVisible ||
                                  Mathf.Abs(visibleValue - snapshot.remainingSeconds) > 0.35f;
            sourceText += ";probe_timer_hint=" +
                         (probeAvailable
                             ? snapshot.remainingSeconds.ToString("F2",
                                 CultureInfo.InvariantCulture)
                             : "<unavailable>") +
                         ";stale_probe_timer_hint=" +
                         staleProbeHint.ToString().ToLowerInvariant() + ";" +
                         ProbeDiagnostic();
            return visibleValue;
        }

        public static bool IsFinishedVisible()
        {
            bool visibleSuccess = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.SuccessPanelId);
            bool visibleFailure = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.FailurePanelId);
            bool visiblePause = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.PausePanelId);
            return visibleSuccess && !visibleFailure && !visiblePause;
        }

        public static bool PauseIsVisible()
        {
            bool visiblePause = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.PausePanelId);
            bool visibleSuccess = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.SuccessPanelId);
            bool visibleFailure = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.FailurePanelId);
            return visiblePause && !visibleSuccess && !visibleFailure;
        }

        public static bool FailureIsVisible()
        {
            bool visibleFailure = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.FailurePanelId);
            bool visibleSuccess = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.SuccessPanelId);
            bool visiblePause = SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.PausePanelId);
            return visibleFailure && !visibleSuccess && !visiblePause;
        }

        public static string ReadStatusText() => ReadStatusText(out _);

        public static string ReadStatusText(out string sourceText)
        {
            if (!SignCircuitSemanticUiObserver.TryReadStatus(
                    out string visibleText, out sourceText))
            {
                FailForMissingCandidateFeature(
                    "The public ui.status locator did not overlap non-empty real visible " +
                    "status/feedback text. Probe text cannot replace real UI.");
            }
            bool probeAvailable = TryReadProbe(out SignCircuitSnapshot snapshot) &&
                string.Equals(snapshot.scene, "circuit", StringComparison.OrdinalIgnoreCase) &&
                !string.IsNullOrWhiteSpace(snapshot.statusText);
            string visibleNormalized = NormalizeForDiagnostic(visibleText);
            string probeNormalized = probeAvailable
                ? NormalizeForDiagnostic(snapshot.statusText)
                : string.Empty;
            bool usableProbeHint = probeAvailable && !string.IsNullOrWhiteSpace(snapshot.statusText);
            bool staleProbeHint = !usableProbeHint ||
                (!visibleNormalized.Contains(probeNormalized) &&
                 !probeNormalized.Contains(visibleNormalized));
            sourceText += ";probe_status_hint=" +
                         (usableProbeHint ? snapshot.statusText : "<unavailable>") +
                         ";stale_probe_status_hint=" +
                         staleProbeHint.ToString().ToLowerInvariant() + ";" +
                         ProbeDiagnostic();
            return visibleText;
        }

        public static UiClickTarget FindVisibleActionTarget(string targetId)
        {
            if (!SignCircuitProbeReader.TryGetActionTarget(
                    targetId, out SignCircuitActionTarget probeTarget))
            {
                FailForMissingCandidateFeature(
                    $"The required public action locator '{targetId}' was not published.");
            }
            Rect locator = ClipToViewport(probeTarget.screenRect);
            if (locator.width < 1f || locator.height < 1f)
            {
                FailForMissingCandidateFeature(
                    $"The public action locator '{targetId}' has no usable Game View area.");
            }
            string probeDiagnostic = "action_target=" + targetId +
                ";probe_visible_hint=" + probeTarget.visible.ToString().ToLowerInvariant() +
                ";probe_interactable_hint=" +
                probeTarget.interactable.ToString().ToLowerInvariant() +
                ";probe_label_hint=" + (probeTarget.label ?? "<none>");

            foreach (UguiButton button in UnityEngine.Object
                         .FindObjectsByType<UguiButton>(FindObjectsInactive.Exclude,
                             FindObjectsSortMode.None)
                         .Where(item => item.gameObject.scene ==
                                        SceneManager.GetActiveScene() &&
                                        item.isActiveAndEnabled && item.interactable &&
                                        IsRectVisible(item.transform as RectTransform)))
            {
                if (!TryRectScreenRect(button.transform as RectTransform,
                        out Rect actualRect)) continue;
                Rect allowed = Intersect(actualRect, locator);
                if (allowed.width < 1f || allowed.height < 1f) continue;
                string visibleLabel = GetUguiButtonLabel(button, allowed);
                if (string.IsNullOrWhiteSpace(visibleLabel)) continue;
                EventSystem eventSystem = EventSystem.current;
                if (eventSystem == null) continue;
                GameObject handler = ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                    button.gameObject);
                if (handler == null || !NativeInputDriver.TryFindTopHitPoint(
                        button.transform as RectTransform, handler, eventSystem, allowed,
                        out Vector2 point, out string sampledHits)) continue;
                return new UiClickTarget
                {
                    Backend = UiClickBackend.Ugui,
                    Name = button.name,
                    Label = visibleLabel,
                    UguiButton = button,
                    ScreenPoint = point,
                    ProbeRect = locator,
                    HasProbeRect = true,
                    RouteDescription = "semantic action locator + real uGUI " +
                        "EventSystem top hit;" + probeDiagnostic +
                        ";actual_rect=" + actualRect + ";sampled_hits=" + sampledHits
                };
            }

            foreach (UIDocument document in ActiveUiDocuments())
            foreach (ToolkitButton button in document.rootVisualElement.Query<ToolkitButton>()
                         .ToList().Where(item => item.enabledInHierarchy &&
                                                 item.clickable != null &&
                                                 IsToolkitElementVisible(item)))
            {
                if (string.IsNullOrWhiteSpace(button.text)) continue;
                if (!TryToolkitScreenRect(document, button, out Rect actualRect)) continue;
                Rect allowed = Intersect(actualRect, locator);
                if (allowed.width < 1f || allowed.height < 1f) continue;
                if (!NativeInputDriver.TryFindToolkitTopHitPoint(
                        button, button.panel, allowed,
                        out Vector2 point, out string sampledHits)) continue;
                return new UiClickTarget
                {
                    Backend = UiClickBackend.UiToolkit,
                    Name = string.IsNullOrWhiteSpace(button.name)
                        ? button.GetType().Name
                        : button.name,
                    Label = button.text,
                    Document = document,
                    ToolkitButton = button,
                    ScreenPoint = point,
                    ProbeRect = locator,
                    HasProbeRect = true,
                    RouteDescription = "semantic action locator + real UI Toolkit " +
                        "panel top hit;" + probeDiagnostic + ";actual_rect=" + actualRect +
                        ";sampled_hits=" + sampledHits
                };
            }

            foreach (VisibleUiText visible in ActiveVisibleUiTexts())
            {
                Rect actualRect;
                bool hasRect = visible.RectTransform != null
                    ? TryRectScreenRect(visible.RectTransform, out actualRect)
                    : TryToolkitScreenRect(visible.Document, visible.ToolkitElement,
                        out actualRect);
                if (!hasRect) continue;
                Rect allowed = Intersect(actualRect, locator);
                if (allowed.width < 1f || allowed.height < 1f) continue;
                if (visible.RectTransform != null)
                {
                    EventSystem eventSystem = EventSystem.current;
                    GameObject handler = eventSystem == null
                        ? null
                        : ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                            visible.RectTransform.gameObject);
                    if (handler != null && NativeInputDriver.TryFindTopHitPoint(
                            visible.RectTransform, handler, eventSystem, allowed,
                            out Vector2 point, out string sampledHits))
                    {
                        return new UiClickTarget
                        {
                            Backend = UiClickBackend.ScreenPoint,
                            Name = visible.Name,
                            Label = visible.Text,
                            ScreenPoint = point,
                            ProbeRect = locator,
                            HasProbeRect = true,
                            ExpectedPointerHandler = handler,
                            RouteDescription = "semantic action locator + real custom " +
                                "uGUI top hit;" + probeDiagnostic +
                                ";actual_rect=" + actualRect +
                                ";sampled_hits=" + sampledHits
                        };
                    }
                }
                else if (visible.ToolkitElement?.panel != null &&
                         NativeInputDriver.TryFindToolkitTopHitPoint(
                             visible.ToolkitElement, visible.ToolkitElement.panel,
                             allowed, out Vector2 point, out string sampledHits))
                {
                    return new UiClickTarget
                    {
                        Backend = UiClickBackend.ScreenPoint,
                        Name = visible.Name,
                        Label = visible.Text,
                        ScreenPoint = point,
                        ProbeRect = locator,
                        HasProbeRect = true,
                        ExpectedToolkitHit = visible.ToolkitElement,
                        RouteDescription = "semantic action locator + real custom " +
                            "UI Toolkit top hit;" + probeDiagnostic +
                            ";actual_rect=" + actualRect +
                            ";sampled_hits=" + sampledHits
                    };
                }
            }

            if (HasOpaqueImmediateModeUi())
            {
                FailForOpaqueCandidateUi(
                    $"'{targetId}' exists only on an opaque immediate-mode/custom " +
                    "surface, so a real visible top-hit route cannot be confirmed.");
            }
            FailForMissingCandidateFeature(
                $"No real visible and top-hittable control overlapped '{targetId}'. " +
                probeDiagnostic);
            return null;
        }

        public static UiClickTarget FindRestartButton() =>
            FindVisibleActionTarget("ui.restart");

        static Rect ClipToViewport(Rect rect)
        {
            return Rect.MinMaxRect(
                Mathf.Clamp(rect.xMin, 0f, Screen.width),
                Mathf.Clamp(rect.yMin, 0f, Screen.height),
                Mathf.Clamp(rect.xMax, 0f, Screen.width),
                Mathf.Clamp(rect.yMax, 0f, Screen.height));
        }

        static Rect Intersect(Rect left, Rect right)
        {
            float xMin = Mathf.Max(left.xMin, right.xMin);
            float yMin = Mathf.Max(left.yMin, right.yMin);
            float xMax = Mathf.Min(left.xMax, right.xMax);
            float yMax = Mathf.Min(left.yMax, right.yMax);
            return xMax <= xMin || yMax <= yMin
                ? new Rect(xMin, yMin, 0f, 0f)
                : Rect.MinMaxRect(xMin, yMin, xMax, yMax);
        }

        public static bool IsRectVisible(RectTransform rect)
        {
            if (rect == null || !rect.gameObject.activeInHierarchy) return false;
            Canvas canvas = rect.GetComponentInParent<Canvas>();
            if (canvas == null || !canvas.isActiveAndEnabled) return false;
            var corners = new Vector3[4];
            rect.GetWorldCorners(corners);
            Camera camera = canvas.renderMode == RenderMode.ScreenSpaceOverlay
                ? null
                : canvas.worldCamera;
            Vector2[] screen = corners.Select(point =>
                RectTransformUtility.WorldToScreenPoint(camera, point)).ToArray();
            float minX = screen.Min(point => point.x);
            float maxX = screen.Max(point => point.x);
            float minY = screen.Min(point => point.y);
            float maxY = screen.Max(point => point.y);
            return maxX - minX >= 1f && maxY - minY >= 1f &&
                   maxX > 0f && maxY > 0f &&
                   minX < Screen.width && minY < Screen.height;
        }

        static bool TryRectScreenRect(RectTransform rect, out Rect screenRect)
        {
            screenRect = default;
            if (!IsRectVisible(rect)) return false;
            var corners = new Vector3[4];
            rect.GetWorldCorners(corners);
            Canvas canvas = rect.GetComponentInParent<Canvas>();
            Camera camera = canvas != null &&
                            canvas.rootCanvas.renderMode != RenderMode.ScreenSpaceOverlay
                ? canvas.rootCanvas.worldCamera ?? Camera.main
                : null;
            Vector2[] screen = corners.Select(point =>
                RectTransformUtility.WorldToScreenPoint(camera, point)).ToArray();
            screenRect = ClipToViewport(Rect.MinMaxRect(
                screen.Min(point => point.x), screen.Min(point => point.y),
                screen.Max(point => point.x), screen.Max(point => point.y)));
            return screenRect.width >= 1f && screenRect.height >= 1f;
        }

        static IEnumerable<VisibleUiText> ActiveVisibleUiTexts()
        {
            Scene scene = SceneManager.GetActiveScene();
            foreach (TMP_Text item in UnityEngine.Object
                         .FindObjectsByType<TMP_Text>(FindObjectsInactive.Exclude,
                             FindObjectsSortMode.None)
                         .Where(item => item.gameObject.scene == scene &&
                                        item.isActiveAndEnabled &&
                                        item.gameObject.activeInHierarchy &&
                                        item is UnityEngine.UI.Graphic graphic &&
                                        IsUguiGraphicVisible(graphic) &&
                                        IsRectVisible(item.rectTransform) &&
                                        !string.IsNullOrWhiteSpace(item.text)))
            {
                yield return new VisibleUiText
                {
                    Backend = "TMP/uGUI",
                    Name = item.name,
                    Text = item.text,
                    RectTransform = item.rectTransform
                };
            }
            foreach (UguiText item in UnityEngine.Object
                         .FindObjectsByType<UguiText>(FindObjectsInactive.Exclude,
                             FindObjectsSortMode.None)
                         .Where(item => item.gameObject.scene == scene &&
                                        item.isActiveAndEnabled &&
                                        item.gameObject.activeInHierarchy &&
                                        IsUguiGraphicVisible(item) &&
                                        IsRectVisible(item.rectTransform) &&
                                        !string.IsNullOrWhiteSpace(item.text)))
            {
                yield return new VisibleUiText
                {
                    Backend = "uGUI",
                    Name = item.name,
                    Text = item.text,
                    RectTransform = item.rectTransform
                };
            }
            foreach (UIDocument document in ActiveUiDocuments())
            foreach (TextElement element in document.rootVisualElement.Query<TextElement>()
                         .ToList().Where(item => IsToolkitElementVisible(item) &&
                                                !string.IsNullOrWhiteSpace(item.text)))
            {
                yield return new VisibleUiText
                {
                    Backend = "UI Toolkit",
                    Name = string.IsNullOrWhiteSpace(element.name)
                        ? element.GetType().Name
                        : element.name,
                    Text = element.text,
                    Document = document,
                    ToolkitElement = element
                };
            }
        }

        static IEnumerable<UIDocument> ActiveUiDocuments() => UnityEngine.Object
            .FindObjectsByType<UIDocument>(FindObjectsInactive.Exclude,
                FindObjectsSortMode.None)
            .Where(item => item.gameObject.scene == SceneManager.GetActiveScene() &&
                           item.isActiveAndEnabled && item.gameObject.activeInHierarchy &&
                           item.rootVisualElement != null &&
                           item.rootVisualElement.panel != null);

        public static bool IsToolkitElementVisible(VisualElement element)
        {
            if (element == null || element.panel == null || !element.visible ||
                !element.enabledInHierarchy) return false;
            float inheritedOpacity = 1f;
            for (VisualElement current = element; current != null; current = current.parent)
            {
                IResolvedStyle style = current.resolvedStyle;
                if (style.display == DisplayStyle.None ||
                    style.visibility == Visibility.Hidden || style.opacity <= 0.001f)
                {
                    return false;
                }
                inheritedOpacity *= style.opacity;
            }
            if (element is TextElement textElement)
                inheritedOpacity *= textElement.resolvedStyle.color.a;
            if (inheritedOpacity <= 0.001f) return false;
            Rect rect = element.worldBound;
            Rect root = element.panel.visualTree.worldBound;
            return rect.width >= 1f && rect.height >= 1f && rect.Overlaps(root, true);
        }

        static bool TryToolkitScreenRect(
            UIDocument document,
            VisualElement element,
            out Rect screenRect)
        {
            screenRect = default;
            if (document == null || !IsToolkitElementVisible(element)) return false;
            Rect target = element.worldBound;
            Rect root = element.panel.visualTree.worldBound;
            if (root.width < 1f || root.height < 1f) return false;
            float xMin = Mathf.InverseLerp(root.xMin, root.xMax, target.xMin) * Screen.width;
            float xMax = Mathf.InverseLerp(root.xMin, root.xMax, target.xMax) * Screen.width;
            float yMin = Screen.height -
                         Mathf.InverseLerp(root.yMin, root.yMax, target.yMax) * Screen.height;
            float yMax = Screen.height -
                         Mathf.InverseLerp(root.yMin, root.yMax, target.yMin) * Screen.height;
            screenRect = ClipToViewport(Rect.MinMaxRect(xMin, yMin, xMax, yMax));
            return screenRect.width >= 1f && screenRect.height >= 1f;
        }

        static string GetUguiButtonLabel(UguiButton button, Rect requiredScreenArea)
        {
            string[] labels = button.GetComponentsInChildren<TMP_Text>(true)
                .Where(item => item.gameObject.activeInHierarchy &&
                               !string.IsNullOrWhiteSpace(item.text) &&
                               item is UnityEngine.UI.Graphic graphic &&
                               IsUguiGraphicVisible(graphic) &&
                               TryRectScreenRect(item.rectTransform, out Rect labelRect) &&
                               Intersect(labelRect, requiredScreenArea).width >= 1f &&
                               Intersect(labelRect, requiredScreenArea).height >= 1f)
                .Select(item => item.text.Trim())
                .Concat(button.GetComponentsInChildren<UguiText>(true)
                    .Where(item => item.gameObject.activeInHierarchy &&
                                   !string.IsNullOrWhiteSpace(item.text) &&
                                   IsUguiGraphicVisible(item) &&
                                   TryRectScreenRect(item.rectTransform, out Rect labelRect) &&
                                   Intersect(labelRect, requiredScreenArea).width >= 1f &&
                                   Intersect(labelRect, requiredScreenArea).height >= 1f)
                    .Select(item => item.text.Trim()))
                .Distinct().ToArray();
            return string.Join(" ", labels);
        }

        static bool IsUguiGraphicVisible(UnityEngine.UI.Graphic graphic)
        {
            if (graphic == null || !graphic.isActiveAndEnabled ||
                graphic.color.a <= 0.001f || graphic.canvasRenderer == null ||
                graphic.canvasRenderer.cull ||
                graphic.color.a * graphic.canvasRenderer.GetInheritedAlpha() <= 0.001f)
                return false;
            return true;
        }

        static void FailForMissingCandidateFeature(string message)
        {
            Assert.Fail("[OMNIGAME_CANDIDATE_FEATURE_MISSING] " + message);
        }

        static void FailForOpaqueCandidateUi(string message)
        {
            Assert.Fail("[OMNIGAME_CANDIDATE_FEATURE_MISSING] " + message +
                        " This violates the public observable-UI submission contract.");
        }

        static bool TryReadProbe(out SignCircuitSnapshot snapshot) =>
            SignCircuitProbeReader.TryRead(out snapshot);

        /// <summary>
        /// Uses the mandatory public read-only snapshot only to locate a real
        /// interaction range. The caller must still prove the E result through
        /// ordinary input plus persistent visible world/status feedback.
        /// </summary>
        public static bool TryReadInteractionAvailableHint(
            out bool available,
            out string source)
        {
            if (!TryReadProbe(out SignCircuitSnapshot snapshot))
            {
                available = false;
                source = "probe_unavailable;" + ProbeDiagnostic();
                return false;
            }

            available = snapshot.interactionAvailable;
            source = "public_read_only_locator=true;interaction_available=" +
                     available.ToString().ToLowerInvariant() + ";" +
                     ProbeDiagnostic();
            return true;
        }

        static string ProbeDiagnostic() =>
            $"probe_frame={SignCircuitProbeReader.LastPublishedFrame};" +
            $"current_frame={Time.frameCount};scene={SceneManager.GetActiveScene().name}";

        static bool HasOpaqueImmediateModeUi()
        {
            Scene scene = SceneManager.GetActiveScene();
            const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public |
                                       BindingFlags.NonPublic | BindingFlags.DeclaredOnly;
            return UnityEngine.Object.FindObjectsByType<MonoBehaviour>(
                    FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(item => item != null && item.gameObject.scene == scene &&
                               item.isActiveAndEnabled)
                .Any(item => item.GetType().GetMethod("OnGUI", flags) != null);
        }

        public static IEnumerator WaitForProgress(int expected, float timeoutSeconds = 3f)
        {
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            while (Time.realtimeSinceStartup < deadline)
            {
                if (TryReadProgress(out int value, out _) && value == expected) yield break;
                yield return null;
            }
            int actual = ReadProgress(out string source);
            Assert.That(actual, Is.EqualTo(expected),
                $"Sequence progress did not reach {expected}/3. Source: {source}");
        }

        public static IEnumerator WaitForFinished(float timeoutSeconds = 3f)
        {
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            while (Time.realtimeSinceStartup < deadline && !IsFinishedVisible())
            {
                yield return null;
            }
            Assert.That(IsFinishedVisible(), Is.True,
                "Success UI did not become visible after ordinary route traversal.");
        }

        public static IEnumerable<GameObject> ActiveSceneObjects()
        {
            Scene scene = SceneManager.GetActiveScene();
            return Resources.FindObjectsOfTypeAll<GameObject>()
                .Where(item => item != null && item.scene == scene);
        }

        public static string HierarchyPath(Transform item)
        {
            if (item == null) return "<null>";
            var parts = new Stack<string>();
            for (Transform current = item; current != null; current = current.parent)
            {
                parts.Push(current.name);
            }
            return string.Join("/", parts);
        }

        public static string Normalize(string value) => Regex.Replace(
            (value ?? string.Empty).ToLowerInvariant(), @"[^a-z0-9]+", string.Empty);

        static string NormalizeForDiagnostic(string value) => string.Concat(
            (value ?? string.Empty).ToLowerInvariant().Where(char.IsLetterOrDigit));
    }
}
