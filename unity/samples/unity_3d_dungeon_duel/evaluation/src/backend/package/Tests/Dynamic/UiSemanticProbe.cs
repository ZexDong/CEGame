using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using UnityEngine.UIElements;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    internal enum HudSemanticState
    {
        Initial,
        CombatDamage,
        GateLocked,
        GateOpen,
        DashCooldown,
        DashReady,
        Victory,
        Defeat,
        Restarted
    }

    internal sealed class VisibleTextRecord
    {
        public string Text;
        public string Source;
        public Rect ScreenRect;
        public float FontSize;
        public float Alpha;
    }

    internal sealed class UiSemanticSnapshot
    {
        public List<VisibleTextRecord> Texts { get; } =
            new List<VisibleTextRecord>();

        public string Corpus => string.Join(" | ", Texts.Select(item => item.Text));

        public bool Any(Func<VisibleTextRecord, bool> predicate) =>
            Texts.Any(predicate);

        public string Describe() =>
            $"visibleTextCount={Texts.Count}; " +
            string.Join(" || ", Texts.Take(40).Select(item =>
                $"[{item.Source}] '{item.Text}' rect={item.ScreenRect} " +
                $"font={item.FontSize:F1} alpha={item.Alpha:F2}"));
    }

    internal static class UiSemanticProbe
    {
        static readonly Regex NumberRegex = new Regex(
            @"(?<!\d)(\d+(?:\.\d+)?)(?!\d)", RegexOptions.Compiled);

        public static UiSemanticSnapshot Capture()
        {
            return Capture(default);
        }

        public static UiSemanticSnapshot Capture(Scene requiredScene)
        {
            var result = new UiSemanticSnapshot();
            CaptureUgui(result, requiredScene);
            CaptureTmpByReflection(result, requiredScene);
            CaptureUiToolkit(result, requiredScene);
            return result;
        }

        /// <summary>
        /// Reads the player-facing health contract without requiring a
        /// candidate component, field, property, or hierarchy name.  The HUD
        /// is only accepted when a visible player/health label exists and a
        /// plausible current/maximum pair is present on the rendered surface.
        /// </summary>
        public static bool TryReadPlayerHealth(
            UiSemanticSnapshot ui,
            out float current,
            out float maximum,
            out string observation)
        {
            current = maximum = float.NaN;
            observation = "missing";
            if (ui == null || ui.Texts.Count == 0) return false;

            bool playerLabel = ui.Any(item => ContainsAny(
                item.Text, "hero", "player", "health", "hp", "tank", "vanguard"));
            if (!playerLabel) return false;

            var pairs = new List<(float current, float maximum, string text, int priority)>();
            foreach (VisibleTextRecord item in ui.Texts)
            {
                float[] values = NumberRegex.Matches(item.Text)
                    .Cast<Match>()
                    .Select(match =>
                    {
                        float.TryParse(match.Groups[1].Value,
                            System.Globalization.NumberStyles.Float,
                            System.Globalization.CultureInfo.InvariantCulture,
                            out float value);
                        return value;
                    })
                    .Where(value => value >= 0f && value <= 100000f)
                    .ToArray();
                for (int index = 0; index + 1 < values.Length; index++)
                {
                    float left = values[index];
                    float right = values[index + 1];
                    float candidateCurrent = Mathf.Min(left, right);
                    float candidateMaximum = Mathf.Max(left, right);
                    if (candidateMaximum < 5f || candidateCurrent > candidateMaximum)
                        continue;
                    bool ownPlayerLabel = ContainsAny(
                        item.Text, "hero", "player", "health", "hp", "tank", "vanguard");
                    bool explicitHealthLabel = ContainsAny(item.Text, "health", "hp");
                    bool explicitEnemyLabel = ContainsAny(
                        item.Text, "boss", "threat", "imp", "imps", "minion");
                    // Prefer explicit health labels when a fixture and candidate HUD coexist.
                    int priority = explicitHealthLabel ? 120 :
                        ownPlayerLabel ? 100 : explicitEnemyLabel ? -100 : 0;
                    pairs.Add((candidateCurrent, candidateMaximum, item.Text, priority));
                }
            }

            if (pairs.Count == 0) return false;
            var selected = pairs
                .OrderByDescending(item => item.priority)
                .ThenByDescending(item => item.maximum)
                .First();
            current = selected.current;
            maximum = selected.maximum;
            observation = $"visible HUD health {current:F1}/{maximum:F1} from '{selected.text}'";
            return true;
        }

        public static bool TryReadLivingImpCount(
            UiSemanticSnapshot ui,
            out int count,
            out string observation)
        {
            count = -1;
            observation = "missing";
            if (ui == null) return false;
            foreach (VisibleTextRecord item in ui.Texts)
            {
                if (!ContainsAny(item.Text, "imp", "imps", "minion")) continue;
                Match match = NumberRegex.Match(item.Text);
                if (!match.Success || !int.TryParse(match.Groups[1].Value, out int parsed) ||
                    parsed < 0 || parsed > 20)
                    continue;
                count = parsed;
                observation = $"visible living-threat count {count} from '{item.Text}'";
                return true;
            }
            return false;
        }

        public static bool TryReadGateOpen(
            UiSemanticSnapshot ui,
            out bool open,
            out string observation)
        {
            open = false;
            observation = "missing";
            if (ui == null) return false;
            foreach (VisibleTextRecord item in ui.Texts)
            {
                if (!ContainsAny(item.Text, "gate", "door", "seal")) continue;
                if (ContainsAny(item.Text, "open", "clear", "unlocked"))
                {
                    open = true;
                    observation = "visible open-gate text: '" + item.Text + "'";
                    return true;
                }
                if (ContainsAny(item.Text, "locked", "closed", "sealed"))
                {
                    open = false;
                    observation = "visible closed-gate text: '" + item.Text + "'";
                    return true;
                }
            }
            return false;
        }

        public static bool TryReadDashCooldown(
            UiSemanticSnapshot ui,
            out float remaining,
            out string observation)
        {
            remaining = float.NaN;
            observation = "missing";
            if (ui == null) return false;
            foreach (VisibleTextRecord item in ui.Texts.Where(item =>
                         ContainsAny(item.Text, "dash", "burst")))
            {
                if (ContainsAny(item.Text, "ready", "available"))
                {
                    remaining = 0f;
                    observation = "visible Dash-ready text: '" + item.Text + "'";
                    return true;
                }
                Match seconds = Regex.Match(item.Text,
                    @"(?<!\d)(\d+(?:\.\d+)?)\s*s\b", RegexOptions.IgnoreCase);
                if (seconds.Success && float.TryParse(seconds.Groups[1].Value,
                        System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture,
                        out float parsed))
                {
                    remaining = Mathf.Max(0f, parsed);
                    observation = $"visible Dash cooldown {remaining:F2}s from '{item.Text}'";
                    return true;
                }
                if (ContainsAny(item.Text, "cooldown", "ready in", "wait"))
                {
                    remaining = 1f;
                    observation = "visible non-numeric Dash cooldown text: '" + item.Text + "'";
                    return true;
                }
            }
            return false;
        }

        public static bool TryReadTerminalPhase(
            UiSemanticSnapshot ui,
            out DungeonDuelGamePhase phase,
            out string observation)
        {
            phase = DungeonDuelGamePhase.Playing;
            observation = "no terminal result";
            if (ui == null) return false;
            bool victory = ui.Any(item => IsTerminalOutcomeText(item.Text, true));
            bool defeat = ui.Any(item => IsTerminalOutcomeText(item.Text, false));
            if (victory == defeat) return false;
            phase = victory ? DungeonDuelGamePhase.Won : DungeonDuelGamePhase.Lost;
            observation = victory ? "visible Victory result" : "visible Defeat result";
            return true;
        }

        public static bool Validate(
            UiSemanticSnapshot ui,
            DungeonDuelGameSnapshot state,
            HudSemanticState expectation,
            out string failure)
        {
            var failures = new List<string>();
            if (ui == null || ui.Texts.Count == 0)
            {
                failure = "No visible readable runtime text was discovered.";
                return false;
            }
            if (state == null || state.Player == null)
            {
                failure = "No independently observed gameplay state was available.";
                return false;
            }

            bool terminal = expectation == HudSemanticState.Victory ||
                            expectation == HudSemanticState.Defeat;
            bool requireCore = !terminal || ui.Any(item =>
                ContainsAny(item.Text, "hero", "player", "hp", "health"));

            if (requireCore)
            {
                if (!HasPlayerHealth(ui, state.Player.Health, state.Player.MaxHealth))
                    failures.Add("Player HP/max HP not visibly synchronized");
                if (!HasLabeledCount(ui, new[] { "imp", "imps" }, state.ImpsAlive))
                    failures.Add($"living Imp count {state.ImpsAlive} not visibly synchronized");
                if (!HasGateState(ui, state.GateOpen))
                    failures.Add(state.GateOpen
                        ? "Gate OPEN state not visible"
                        : "Gate LOCKED/CLOSED state not visible");
                if (!HasDashState(ui, state.DashCooldownRemaining,
                        expectation == HudSemanticState.DashCooldown))
                    failures.Add("Dash ready/cooldown state not visibly synchronized");
                if (!HasControlHints(ui))
                    failures.Add("Move, Attack, Dash, and Restart control hints are not all visible");
            }

            // Outcome words can legitimately appear inside an active objective
            // (for example "Defeat both Imps"). Only a short standalone result
            // message is terminal UI; an instruction sentence is not.
            bool victoryVisible = ui.Any(item => IsTerminalOutcomeText(
                item.Text, true));
            bool defeatVisible = ui.Any(item => IsTerminalOutcomeText(
                item.Text, false));
            if (expectation == HudSemanticState.Victory)
            {
                if (!victoryVisible) failures.Add("Victory label is not visible");
                if (defeatVisible) failures.Add("Defeat is visible together with Victory");
                if (!HasRestartLabel(ui)) failures.Add("Restart/Retry control label is not visible");
            }
            else if (expectation == HudSemanticState.Defeat)
            {
                if (!defeatVisible) failures.Add("Defeat label is not visible");
                if (victoryVisible) failures.Add("Victory is visible together with Defeat");
                if (!HasRestartLabel(ui)) failures.Add("Restart/Retry control label is not visible");
            }
            else if (victoryVisible || defeatVisible)
            {
                failures.Add("A stale terminal label is visible during active play");
            }

            failure = string.Join("; ", failures);
            return failures.Count == 0;
        }

        static void CaptureUgui(UiSemanticSnapshot result, Scene requiredScene)
        {
            foreach (Text text in UnityEngine.Object.FindObjectsByType<Text>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (text == null || !text.isActiveAndEnabled ||
                    !text.gameObject.activeInHierarchy ||
                    !MatchesScene(text.gameObject, requiredScene) ||
                    string.IsNullOrWhiteSpace(text.text))
                    continue;
                Canvas canvas = text.canvas;
                Camera camera = canvas == null ||
                                canvas.renderMode == RenderMode.ScreenSpaceOverlay
                    ? null
                    : canvas.worldCamera ?? Camera.main;
                if (!TryScreenRect(text.rectTransform, camera, out Rect rect)) continue;
                float alpha = text.color.a * text.canvasRenderer.GetAlpha();
                if (alpha <= 0.08f || text.fontSize < 8) continue;
                result.Texts.Add(new VisibleTextRecord
                {
                    Text = text.text.Trim(),
                    Source = "uGUI.Text",
                    ScreenRect = rect,
                    FontSize = text.fontSize,
                    Alpha = alpha
                });
            }
        }

        static void CaptureTmpByReflection(UiSemanticSnapshot result, Scene requiredScene)
        {
            foreach (MonoBehaviour component in UnityEngine.Object
                         .FindObjectsByType<MonoBehaviour>(
                             FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (component == null || !component.isActiveAndEnabled ||
                    !component.gameObject.activeInHierarchy ||
                    !MatchesScene(component.gameObject, requiredScene) ||
                    component.GetType().FullName?.Contains("TMPro.TMP_Text") != true)
                    continue;
                PropertyInfo textProperty = component.GetType().GetProperty(
                    "text", BindingFlags.Instance | BindingFlags.Public);
                string value = textProperty?.GetValue(component) as string;
                RectTransform rectTransform = component.GetComponent<RectTransform>();
                if (string.IsNullOrWhiteSpace(value) || rectTransform == null) continue;
                Canvas canvas = component.GetComponentInParent<Canvas>();
                Camera camera = canvas == null ||
                                canvas.renderMode == RenderMode.ScreenSpaceOverlay
                    ? null
                    : canvas.worldCamera ?? Camera.main;
                if (!TryScreenRect(rectTransform, camera, out Rect rect)) continue;
                float fontSize = ReadFloatProperty(component, "fontSize", 12f);
                float alpha = ReadColorAlpha(component, "color", 1f);
                if (alpha <= 0.08f || fontSize < 8f) continue;
                result.Texts.Add(new VisibleTextRecord
                {
                    Text = value.Trim(),
                    Source = component.GetType().Name,
                    ScreenRect = rect,
                    FontSize = fontSize,
                    Alpha = alpha
                });
            }
        }

        static void CaptureUiToolkit(UiSemanticSnapshot result, Scene requiredScene)
        {
            foreach (UIDocument document in UnityEngine.Object
                         .FindObjectsByType<UIDocument>(
                             FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (document == null || !document.isActiveAndEnabled ||
                    !MatchesScene(document.gameObject, requiredScene) ||
                    document.rootVisualElement == null)
                    continue;
                foreach (TextElement element in document.rootVisualElement
                             .Query<TextElement>().ToList())
                {
                    if (element == null || string.IsNullOrWhiteSpace(element.text) ||
                        element.resolvedStyle.display == DisplayStyle.None ||
                        element.resolvedStyle.visibility == Visibility.Hidden ||
                        element.resolvedStyle.opacity <= 0.08f)
                        continue;
                    Rect world = element.worldBound;
                    var screen = new Rect(
                        world.xMin,
                        Screen.height - world.yMax,
                        world.width,
                        world.height);
                    if (!IsVisibleRect(screen)) continue;
                    result.Texts.Add(new VisibleTextRecord
                    {
                        Text = element.text.Trim(),
                        Source = "UIElements." + element.GetType().Name,
                        ScreenRect = screen,
                        FontSize = element.resolvedStyle.fontSize,
                        Alpha = element.resolvedStyle.opacity
                    });
                }
            }
        }

        static bool HasPlayerHealth(UiSemanticSnapshot ui, float health, float maxHealth)
        {
            return TryReadPlayerHealth(ui, out float visibleHealth,
                       out float visibleMaximum, out _) &&
                   Mathf.Abs(Mathf.Ceil(visibleHealth) -
                             Mathf.Ceil(Mathf.Max(0f, health))) <= 1f &&
                   Mathf.Abs(Mathf.Ceil(visibleMaximum) -
                             Mathf.Ceil(maxHealth)) <= 1f;
        }

        static bool HasLabeledCount(UiSemanticSnapshot ui, string[] labels, int count) =>
            ui.Any(item => labels.Any(label =>
                    item.Text.IndexOf(label, StringComparison.OrdinalIgnoreCase) >= 0) &&
                NumberRegex.Matches(item.Text).Cast<Match>().Any(match =>
                    Mathf.RoundToInt(float.Parse(match.Groups[1].Value,
                        System.Globalization.CultureInfo.InvariantCulture)) == count));

        static bool HasGateState(UiSemanticSnapshot ui, bool open) =>
            ui.Any(item => ContainsAny(item.Text, "gate", "door") &&
                (open
                    ? ContainsAny(item.Text, "open", "clear", "unlocked")
                    : ContainsAny(item.Text, "locked", "closed", "sealed")));

        static bool HasDashState(
            UiSemanticSnapshot ui,
            float cooldown,
            bool requireCooldown)
        {
            VisibleTextRecord[] dash = ui.Texts
                .Where(item => ContainsAny(item.Text, "dash"))
                .ToArray();
            if (dash.Length == 0) return false;
            if (requireCooldown || cooldown > 0.1f)
            {
                return dash.Any(item =>
                    ContainsAny(item.Text, "cooldown", "ready in", "wait") ||
                    Regex.IsMatch(item.Text, @"\d+(?:\.\d+)?\s*s",
                        RegexOptions.IgnoreCase));
            }
            return dash.Any(item => ContainsAny(item.Text, "ready", "available") ||
                NumberRegex.Matches(item.Text).Cast<Match>().Any(match =>
                    float.TryParse(match.Groups[1].Value,
                        System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture,
                        out float seconds) && seconds <= 0.1f));
        }

        static bool HasControlHints(UiSemanticSnapshot ui)
        {
            string corpus = ui.Corpus;
            bool move = ContainsAny(corpus, "move", "lmb", "left mouse");
            bool attack = ContainsAny(corpus, "attack", "engage", "rmb", "right mouse");
            bool dash = ContainsAny(corpus, "dash") && Regex.IsMatch(corpus, @"\b2\b");
            bool restart = HasRestartLabel(ui) ||
                           (ContainsAny(corpus, "restart") &&
                            Regex.IsMatch(corpus, @"\br\b", RegexOptions.IgnoreCase));
            return move && attack && dash && restart;
        }

        static bool HasRestartLabel(UiSemanticSnapshot ui) =>
            ui.Any(item => ContainsAny(
                item.Text, "restart", "retry", "play again", "try again") ||
                item.Text.Contains("Restart") || item.Text.Contains("Restart"));

        static bool IsTerminalOutcomeText(string value, bool victory)
        {
            string raw = (value ?? string.Empty).Trim().ToLowerInvariant();
            string normalized = Regex.Replace(raw, @"\s+", " ")
                .Trim('-', ':', '!', '.', ' ');
            if (normalized.Length == 0 || normalized.Length > 32 ||
                ContainsAny(normalized, "objective", "mission", "goal", "controls"))
                return false;
            if (victory)
            {
                return normalized == "victory" || normalized == "won" ||
                       normalized == "you win" || normalized == "victory achieved" ||
                       HasTerminalSubtitle(raw, "victory");
            }
            return normalized == "defeat" || normalized == "lost" ||
                   normalized == "you lose" || normalized == "game over" ||
                   HasTerminalSubtitle(raw, "defeat");
        }

        static bool HasTerminalSubtitle(string raw, string outcome) =>
            Regex.IsMatch(raw ?? string.Empty,
                "^" + Regex.Escape(outcome) +
                @"(?:\s*[:!|]\s*|\s*[-\u2013\u2014]\s*|\s*\r?\n\s*)\S+",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        static bool ContainsAny(string value, params string[] tokens) =>
            tokens.Any(token => (value ?? string.Empty).IndexOf(
                token, StringComparison.OrdinalIgnoreCase) >= 0);

        static bool TryScreenRect(
            RectTransform transform,
            Camera camera,
            out Rect rect)
        {
            var corners = new Vector3[4];
            transform.GetWorldCorners(corners);
            Vector2 min = new Vector2(float.PositiveInfinity, float.PositiveInfinity);
            Vector2 max = new Vector2(float.NegativeInfinity, float.NegativeInfinity);
            foreach (Vector3 corner in corners)
            {
                Vector2 screen = RectTransformUtility.WorldToScreenPoint(camera, corner);
                min = Vector2.Min(min, screen);
                max = Vector2.Max(max, screen);
            }
            rect = Rect.MinMaxRect(min.x, min.y, max.x, max.y);
            return IsVisibleRect(rect);
        }

        static bool IsVisibleRect(Rect rect) =>
            rect.width >= 2f && rect.height >= 2f &&
            rect.xMax > 0f && rect.yMax > 0f &&
            rect.xMin < Screen.width && rect.yMin < Screen.height;

        static bool MatchesScene(GameObject target, Scene requiredScene) =>
            !requiredScene.IsValid() || target.scene == requiredScene;

        static float ReadFloatProperty(object instance, string name, float fallback)
        {
            object value = instance.GetType().GetProperty(name,
                BindingFlags.Instance | BindingFlags.Public)?.GetValue(instance);
            return value is float number ? number : fallback;
        }

        static float ReadColorAlpha(object instance, string name, float fallback)
        {
            object value = instance.GetType().GetProperty(name,
                BindingFlags.Instance | BindingFlags.Public)?.GetValue(instance);
            return value is Color color ? color.a : fallback;
        }
    }
}
