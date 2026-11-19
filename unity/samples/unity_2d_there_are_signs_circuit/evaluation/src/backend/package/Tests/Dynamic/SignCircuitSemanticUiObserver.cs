using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using NUnit.Framework;
using OmniGame.Benchmark.SignCircuit.Contract;
using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using UnityEngine.UIElements;
using UguiGraphic = UnityEngine.UI.Graphic;
using UguiText = UnityEngine.UI.Text;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    /// <summary>
    /// Resolves public semantic rectangles to real visible runtime UI. The
    /// candidate-published rectangle is only a locator: values, text,
    /// visibility, mutual exclusion, and gameplay consequences are observed
    /// independently from TMP/uGUI/UI Toolkit and the running world.
    /// </summary>
    public static class SignCircuitSemanticUiObserver
    {
        public const string ProgressId = "ui.progress";
        public const string TimerId = "ui.timer";
        public const string BestId = "ui.best";
        public const string StatusId = "ui.status";
        public const string PausePanelId = "panel.pause";
        public const string SuccessPanelId = "panel.success";
        public const string FailurePanelId = "panel.failure";

        static readonly Regex ProgressPattern = new Regex(
            @"(?<!\d)(?<value>[0-3])\s*/\s*3(?!\d)", RegexOptions.Compiled);
        static readonly Regex ClockPattern = new Regex(
            @"(?<!\d)(?<minutes>\d{1,2})\s*:\s*" +
            @"(?<seconds>\d{1,2}(?:[\.,]\d+)?)(?!\d)", RegexOptions.Compiled);
        static readonly Regex NumberPattern = new Regex(
            @"(?<!\d)(?<value>\d+(?:[\.,]\d+)?)(?!\d)", RegexOptions.Compiled);

        public static bool TryReadProgress(out int value, out string source)
        {
            value = -1;
            if (!TryResolveTexts(ProgressId, out SemanticTargetResolution resolution,
                    out source)) return false;
            int[] values = resolution.Texts
                .SelectMany(item => ProgressPattern.Matches(item.Text)
                    .Cast<Match>()
                    .Select(match => int.Parse(match.Groups["value"].Value,
                        CultureInfo.InvariantCulture)))
                .Distinct().ToArray();
            if (values.Length == 0)
            {
                source = resolution.Describe("visible_progress=<missing>");
                return false;
            }
            Assert.That(values.Length, Is.EqualTo(1),
                "The semantic progress rectangle overlaps contradictory x/3 values: " +
                resolution.TextSummary);
            value = values[0];
            source = resolution.Describe("visible_progress=" + value + "/3");
            return true;
        }

        public static bool TryReadTimer(out float value, out string source)
        {
            value = 0f;
            if (!TryResolveTexts(TimerId, out SemanticTargetResolution resolution,
                    out source)) return false;
            float[] values = resolution.Texts.SelectMany(ReadTimeValues)
                .Where(item => item >= 0f && item <= 300f)
                .Select(item => Mathf.Round(item * 1000f) / 1000f)
                .Distinct().ToArray();
            if (values.Length == 0)
            {
                source = resolution.Describe("visible_timer=<missing-number>");
                return false;
            }
            Assert.That(values.Length, Is.EqualTo(1),
                "The semantic timer rectangle overlaps contradictory numeric values: " +
                resolution.TextSummary);
            value = values[0];
            source = resolution.Describe("visible_timer=" +
                value.ToString("F3", CultureInfo.InvariantCulture));
            return true;
        }

        public static bool TryReadBest(
            out string text,
            out double numericValue,
            out bool hasNumericValue,
            out string source)
        {
            text = null;
            numericValue = 0d;
            hasNumericValue = false;
            if (!TryResolveTexts(BestId, out SemanticTargetResolution resolution,
                    out source)) return false;
            text = string.Join(" | ", resolution.Texts.Select(item => item.Text.Trim())
                .Where(item => !string.IsNullOrWhiteSpace(item))
                .Distinct(StringComparer.Ordinal).OrderBy(item => item,
                    StringComparer.Ordinal));
            if (string.IsNullOrWhiteSpace(text))
            {
                source = resolution.Describe("visible_best=<empty>");
                return false;
            }
            double[] numbers = resolution.Texts
                .SelectMany(item => NumberPattern.Matches(item.Text).Cast<Match>())
                .Select(match => double.Parse(
                    match.Groups["value"].Value.Replace(',', '.'),
                    CultureInfo.InvariantCulture))
                .Select(item => Math.Round(item, 4))
                .Distinct().ToArray();
            Assert.That(numbers.Length, Is.LessThanOrEqualTo(1),
                "The semantic best-time rectangle overlaps contradictory numeric values: " +
                resolution.TextSummary);
            hasNumericValue = numbers.Length == 1;
            numericValue = hasNumericValue ? numbers[0] : 0d;
            source = resolution.Describe(hasNumericValue
                ? "visible_best_numeric=" + numericValue.ToString("F4",
                    CultureInfo.InvariantCulture)
                : "visible_best_nonempty_no_numeric=true");
            return true;
        }

        public static bool TryReadStatus(out string text, out string source)
        {
            text = null;
            if (!TryResolveTexts(StatusId, out SemanticTargetResolution resolution,
                    out source)) return false;
            text = string.Join(" | ", resolution.Texts.Select(item => item.Text.Trim())
                .Where(item => !string.IsNullOrWhiteSpace(item))
                .Distinct(StringComparer.Ordinal).OrderBy(item => item,
                    StringComparer.Ordinal));
            if (string.IsNullOrWhiteSpace(text))
            {
                source = resolution.Describe("visible_status=<empty>");
                return false;
            }
            source = resolution.Describe("visible_status_text_nonempty=true");
            return true;
        }

        public static bool IsPanelVisible(string id) =>
            IsPanelVisible(id, out _, out _);

        public static bool IsPanelVisible(
            string id,
            out string signature,
            out string source)
        {
            signature = null;
            if (!TryResolveTexts(id, out SemanticTargetResolution resolution,
                    out source)) return false;
            string[] visibleText = resolution.Texts.Select(item => item.Text.Trim())
                .Where(item => !string.IsNullOrWhiteSpace(item))
                .Distinct(StringComparer.Ordinal).OrderBy(item => item,
                    StringComparer.Ordinal).ToArray();
            if (visibleText.Length == 0)
            {
                source = resolution.Describe("visible_panel_text=<empty>");
                return false;
            }
            if (!TryFindCoherentPanelContainer(
                    resolution, out string containerSource))
            {
                source = resolution.Describe(
                    "visible_panel_text_nonempty=true;" +
                    "coherent_panel_container=false");
                return false;
            }
            signature = string.Join(" | ", visibleText);
            source = resolution.Describe(
                "visible_panel_text_nonempty=true;" +
                "coherent_panel_container=true;container=" + containerSource);
            return true;
        }

        public static bool AnyStatePanelVisible() =>
            IsPanelVisible(PausePanelId) || IsPanelVisible(SuccessPanelId) ||
            IsPanelVisible(FailurePanelId);

        static IEnumerable<float> ReadTimeValues(SemanticUiText item)
        {
            Match clock = ClockPattern.Match(item.Text ?? string.Empty);
            if (clock.Success)
            {
                float minutes = float.Parse(clock.Groups["minutes"].Value,
                    CultureInfo.InvariantCulture);
                float seconds = float.Parse(
                    clock.Groups["seconds"].Value.Replace(',', '.'),
                    CultureInfo.InvariantCulture);
                yield return minutes * 60f + seconds;
                yield break;
            }
            foreach (Match match in NumberPattern.Matches(item.Text ?? string.Empty))
            {
                yield return float.Parse(
                    match.Groups["value"].Value.Replace(',', '.'),
                    CultureInfo.InvariantCulture);
            }
        }

        static bool TryResolveTexts(
            string id,
            out SemanticTargetResolution resolution,
            out string source)
        {
            resolution = null;
            source = "semantic_target=" + id + ";status=missing";
            if (!SignCircuitProbeReader.TryGetObservationTarget(
                    id, out SignCircuitObservationTarget target)) return false;
            Rect clipped = ClipToViewport(target.screenRect);
            if (!IsPlausibleSemanticRect(id, clipped, out string geometryReason))
            {
                source = "semantic_target=" + id + ";status=invalid_rect;reason=" +
                         geometryReason + ";" +
                         "probe_visible_hint=" + target.visible.ToString().ToLowerInvariant();
                return false;
            }
            SemanticUiText[] overlaps = ActiveVisibleTexts()
                .Where(item => RectsSemanticallyOverlap(clipped, item.ScreenRect))
                .OrderBy(item => item.Backend, StringComparer.Ordinal)
                .ThenBy(item => item.Text, StringComparer.Ordinal)
                .ToArray();
            if (!IsPanelId(id) && overlaps.Length > 4)
            {
                source = "semantic_target=" + id +
                         ";status=ambiguous_real_visible_ui_overlap;count=" +
                         overlaps.Length + ";rect=" + clipped;
                return false;
            }
            if (overlaps.Length == 0)
            {
                source = "semantic_target=" + id + ";status=no_real_visible_ui_overlap;" +
                         "probe_visible_hint=" + target.visible.ToString().ToLowerInvariant() +
                         ";rect=" + clipped;
                return false;
            }
            resolution = new SemanticTargetResolution
            {
                Id = id,
                TargetRect = clipped,
                ProbeVisibleHint = target.visible,
                Texts = overlaps
            };
            source = resolution.Describe("status=resolved");
            return true;
        }

        static bool RectsSemanticallyOverlap(Rect target, Rect actual)
        {
            Rect overlap = Intersect(target, actual);
            if (overlap.width < 1f || overlap.height < 1f) return false;
            float overlapArea = overlap.width * overlap.height;
            float actualArea = actual.width * actual.height;
            return actualArea > 0f && overlapArea / actualArea >= 0.50f;
        }

        static bool IsPlausibleSemanticRect(
            string id,
            Rect rect,
            out string reason)
        {
            return IsPlausibleSemanticRectForViewport(
                id, rect, Screen.width, Screen.height, out reason);
        }

        internal static bool IsPlausibleSemanticRectForViewport(
            string id,
            Rect rect,
            float viewportWidth,
            float viewportHeight,
            out string reason)
        {
            reason = string.Empty;
            viewportWidth = Mathf.Max(1f, viewportWidth);
            viewportHeight = Mathf.Max(1f, viewportHeight);
            float screenArea = viewportWidth * viewportHeight;
            float area = rect.width * rect.height;
            if (rect.width < 4f || rect.height < 4f || area < 16f)
            {
                reason = "too_small";
                return false;
            }
            bool spansMostOfViewportWidth = rect.width > viewportWidth * 0.90f;
            bool compactWideStatus =
                string.Equals(id, StatusId, StringComparison.OrdinalIgnoreCase) &&
                spansMostOfViewportWidth &&
                rect.height <= viewportHeight * 0.20f &&
                area <= screenArea * 0.20f;
            if (!IsPanelId(id) &&
                (area > screenArea * 0.35f ||
                 rect.height > viewportHeight * 0.50f ||
                 (spansMostOfViewportWidth && !compactWideStatus)))
            {
                reason = "hud_locator_too_broad";
                return false;
            }
            if (IsPanelId(id) && area < screenArea * 0.0025f)
            {
                reason = "panel_locator_too_small";
                return false;
            }
            return true;
        }

        static bool IsPanelId(string id) =>
            string.Equals(id, PausePanelId, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(id, SuccessPanelId, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(id, FailurePanelId, StringComparison.OrdinalIgnoreCase);

        static bool TryFindCoherentPanelContainer(
            SemanticTargetResolution resolution,
            out string source)
        {
            source = "<missing>";
            foreach (SemanticUiText item in resolution.Texts)
            {
                if (item.UguiGraphic != null && TryFindUguiPanelContainer(
                        resolution.TargetRect, item, out Rect uguiRect))
                {
                    source = "uGUI@" + uguiRect;
                    return true;
                }
                if (item.ToolkitText != null && item.ToolkitDocument != null &&
                    TryFindToolkitPanelContainer(
                        resolution.TargetRect, item, out Rect toolkitRect))
                {
                    source = "UI Toolkit@" + toolkitRect;
                    return true;
                }
            }
            return false;
        }

        static bool TryFindUguiPanelContainer(
            Rect target,
            SemanticUiText text,
            out Rect panelRect)
        {
            panelRect = default;
            Transform current = text.UguiGraphic.rectTransform.parent;
            while (current != null)
            {
                bool isCanvasRoot = current.GetComponent<Canvas>() != null;
                if (current is RectTransform rectTransform &&
                    TryRectScreenRect(rectTransform, out Rect candidateRect))
                {
                    foreach (UguiGraphic graphic in
                             current.GetComponents<UguiGraphic>())
                    {
                        if (graphic == null || graphic == text.UguiGraphic ||
                            !IsGraphicVisiblyRendered(graphic)) continue;
                        if (!IsCoherentPanelGeometry(
                                target, text.ScreenRect, candidateRect)) continue;
                        panelRect = candidateRect;
                        return true;
                    }
                }
                // Do not climb beyond the rendering root. A nested Canvas may
                // itself carry a bounded visible panel graphic and was checked
                // above; a plain root Canvas is not accepted on its own.
                if (isCanvasRoot) break;
                current = current.parent;
            }
            return false;
        }

        static bool TryFindToolkitPanelContainer(
            Rect target,
            SemanticUiText text,
            out Rect panelRect)
        {
            panelRect = default;
            VisualElement root = text.ToolkitText.panel?.visualTree;
            for (VisualElement current = text.ToolkitText.parent;
                 current != null && current != root;
                 current = current.parent)
            {
                if (!IsToolkitContainerVisible(current) ||
                    !TryToolkitScreenRect(
                        text.ToolkitDocument, current, out Rect candidateRect) ||
                    !IsCoherentPanelGeometry(
                        target, text.ScreenRect, candidateRect)) continue;
                panelRect = candidateRect;
                return true;
            }
            return false;
        }

        static bool IsCoherentPanelGeometry(
            Rect target,
            Rect text,
            Rect container)
        {
            float screenArea = Mathf.Max(1f, Screen.width * Screen.height);
            float targetArea = target.width * target.height;
            float textArea = text.width * text.height;
            float containerArea = container.width * container.height;
            if (targetArea <= 0f || textArea <= 0f ||
                containerArea < screenArea * 0.0025f ||
                containerArea < textArea * 1.15f ||
                containerArea > screenArea * 0.95f) return false;

            Rect textOverlap = Intersect(container, text);
            Rect targetOverlap = Intersect(container, target);
            float textOverlapArea = textOverlap.width * textOverlap.height;
            float targetOverlapArea = targetOverlap.width * targetOverlap.height;
            return textOverlapArea / textArea >= 0.90f &&
                   targetOverlapArea / targetArea >= 0.60f &&
                   targetOverlapArea / containerArea >= 0.35f;
        }

        static IEnumerable<SemanticUiText> ActiveVisibleTexts()
        {
            Scene scene = SceneManager.GetActiveScene();
            foreach (TMP_Text item in UnityEngine.Object
                         .FindObjectsByType<TMP_Text>(FindObjectsInactive.Exclude,
                             FindObjectsSortMode.None)
                         .Where(item => item.gameObject.scene == scene &&
                                        item.isActiveAndEnabled &&
                                        item.gameObject.activeInHierarchy &&
                                        !string.IsNullOrWhiteSpace(item.text) &&
                                        item is UguiGraphic graphic &&
                                        IsGraphicVisiblyRendered(graphic) &&
                                        TryRectScreenRect(item.rectTransform, out _)))
            {
                TryRectScreenRect(item.rectTransform, out Rect rect);
                yield return new SemanticUiText
                {
                    Backend = "TMP/uGUI",
                    Text = item.text,
                    ScreenRect = rect,
                    UguiGraphic = item
                };
            }
            foreach (UguiText item in UnityEngine.Object
                         .FindObjectsByType<UguiText>(FindObjectsInactive.Exclude,
                             FindObjectsSortMode.None)
                         .Where(item => item.gameObject.scene == scene &&
                                        item.isActiveAndEnabled &&
                                        item.gameObject.activeInHierarchy &&
                                        !string.IsNullOrWhiteSpace(item.text) &&
                                        IsGraphicVisiblyRendered(item) &&
                                        TryRectScreenRect(item.rectTransform, out _)))
            {
                TryRectScreenRect(item.rectTransform, out Rect rect);
                yield return new SemanticUiText
                {
                    Backend = "uGUI",
                    Text = item.text,
                    ScreenRect = rect,
                    UguiGraphic = item
                };
            }
            foreach (UIDocument document in ActiveUiDocuments())
            foreach (TextElement item in document.rootVisualElement.Query<TextElement>()
                         .ToList().Where(IsToolkitElementVisible))
            {
                if (string.IsNullOrWhiteSpace(item.text) ||
                    !TryToolkitScreenRect(document, item, out Rect rect)) continue;
                yield return new SemanticUiText
                {
                    Backend = "UI Toolkit",
                    Text = item.text,
                    ScreenRect = rect,
                    ToolkitText = item,
                    ToolkitDocument = document
                };
            }
        }

        static bool IsGraphicVisiblyRendered(UguiGraphic graphic)
        {
            if (graphic == null || !graphic.isActiveAndEnabled ||
                graphic.color.a <= 0.001f || graphic.canvasRenderer == null ||
                graphic.canvasRenderer.cull ||
                graphic.color.a * graphic.canvasRenderer.GetInheritedAlpha() <= 0.001f)
                return false;
            return true;
        }

        static bool TryRectScreenRect(RectTransform rect, out Rect screenRect)
        {
            screenRect = default;
            if (rect == null || !rect.gameObject.activeInHierarchy) return false;
            Canvas canvas = rect.GetComponentInParent<Canvas>();
            if (canvas == null || !canvas.isActiveAndEnabled) return false;
            var corners = new Vector3[4];
            rect.GetWorldCorners(corners);
            Camera camera = canvas.rootCanvas.renderMode == RenderMode.ScreenSpaceOverlay
                ? null
                : canvas.rootCanvas.worldCamera ?? Camera.main;
            Vector2[] screen = corners.Select(point =>
                RectTransformUtility.WorldToScreenPoint(camera, point)).ToArray();
            screenRect = ClipToViewport(Rect.MinMaxRect(
                screen.Min(point => point.x), screen.Min(point => point.y),
                screen.Max(point => point.x), screen.Max(point => point.y)));
            return screenRect.width >= 1f && screenRect.height >= 1f;
        }

        static IEnumerable<UIDocument> ActiveUiDocuments() => UnityEngine.Object
            .FindObjectsByType<UIDocument>(FindObjectsInactive.Exclude,
                FindObjectsSortMode.None)
            .Where(item => item.gameObject.scene == SceneManager.GetActiveScene() &&
                           item.isActiveAndEnabled && item.gameObject.activeInHierarchy &&
                           item.rootVisualElement?.panel != null);

        static bool IsToolkitElementVisible(TextElement element)
        {
            if (element == null || element.panel == null || !element.visible ||
                !element.enabledInHierarchy || string.IsNullOrWhiteSpace(element.text))
                return false;
            float inheritedOpacity = 1f;
            for (VisualElement current = element; current != null; current = current.parent)
            {
                IResolvedStyle style = current.resolvedStyle;
                if (style.display == DisplayStyle.None ||
                    style.visibility == Visibility.Hidden || style.opacity <= 0.001f)
                    return false;
                inheritedOpacity *= style.opacity;
            }
            inheritedOpacity *= element.resolvedStyle.color.a;
            Rect rect = element.worldBound;
            return inheritedOpacity > 0.001f && rect.width >= 1f && rect.height >= 1f &&
                   rect.Overlaps(element.panel.visualTree.worldBound, true);
        }

        static bool IsToolkitContainerVisible(VisualElement element)
        {
            if (element == null || element.panel == null || !element.visible ||
                !element.enabledInHierarchy) return false;
            float inheritedOpacity = 1f;
            for (VisualElement current = element; current != null; current = current.parent)
            {
                IResolvedStyle style = current.resolvedStyle;
                if (style.display == DisplayStyle.None ||
                    style.visibility == Visibility.Hidden || style.opacity <= 0.001f)
                    return false;
                inheritedOpacity *= style.opacity;
            }
            Rect rect = element.worldBound;
            if (inheritedOpacity <= 0.001f || rect.width < 1f || rect.height < 1f ||
                !rect.Overlaps(element.panel.visualTree.worldBound, true)) return false;

            IResolvedStyle ownStyle = element.resolvedStyle;
            bool visibleBackgroundColor =
                ownStyle.backgroundColor.a * inheritedOpacity > 0.001f;
            Background background = ownStyle.backgroundImage;
            bool visibleBackgroundImage =
                (background.texture != null || background.sprite != null ||
                 background.renderTexture != null || background.vectorImage != null) &&
                ownStyle.unityBackgroundImageTintColor.a * inheritedOpacity > 0.001f;
            bool visibleBorder =
                (ownStyle.borderLeftWidth > 0.01f &&
                 ownStyle.borderLeftColor.a * inheritedOpacity > 0.001f) ||
                (ownStyle.borderRightWidth > 0.01f &&
                 ownStyle.borderRightColor.a * inheritedOpacity > 0.001f) ||
                (ownStyle.borderTopWidth > 0.01f &&
                 ownStyle.borderTopColor.a * inheritedOpacity > 0.001f) ||
                (ownStyle.borderBottomWidth > 0.01f &&
                 ownStyle.borderBottomColor.a * inheritedOpacity > 0.001f);
            return visibleBackgroundColor || visibleBackgroundImage || visibleBorder;
        }

        static bool TryToolkitScreenRect(
            UIDocument document,
            VisualElement element,
            out Rect screenRect)
        {
            screenRect = default;
            if (document == null || element?.panel == null) return false;
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

        static Rect ClipToViewport(Rect rect) => Rect.MinMaxRect(
            Mathf.Clamp(rect.xMin, 0f, Screen.width),
            Mathf.Clamp(rect.yMin, 0f, Screen.height),
            Mathf.Clamp(rect.xMax, 0f, Screen.width),
            Mathf.Clamp(rect.yMax, 0f, Screen.height));

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

        sealed class SemanticUiText
        {
            public string Backend;
            public string Text;
            public Rect ScreenRect;
            public UguiGraphic UguiGraphic;
            public TextElement ToolkitText;
            public UIDocument ToolkitDocument;
        }

        sealed class SemanticTargetResolution
        {
            public string Id;
            public Rect TargetRect;
            public bool ProbeVisibleHint;
            public SemanticUiText[] Texts;

            public string TextSummary => string.Join(" | ", Texts.Select(item =>
                item.Backend + ":'" + item.Text + "'@" + item.ScreenRect));

            public string Describe(string observation) =>
                "semantic_target=" + Id + ";" + observation +
                ";real_visible_ui_overlap=true;probe_visible_hint=" +
                ProbeVisibleHint.ToString().ToLowerInvariant() +
                ";target_rect=" + TargetRect + ";texts=" + TextSummary;
        }
    }
}
