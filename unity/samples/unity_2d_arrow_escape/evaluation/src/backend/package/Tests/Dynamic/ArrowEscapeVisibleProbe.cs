using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using OmniGame.Benchmark.ArrowEscape.V2;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    internal sealed class VisibleArrowTarget
    {
        public GameObject PointerTarget;
        public Rect Bounds;
        public string SemanticId;
        public string StableKey;
        public string VisualSignature;
        public string StyleSignature;
        public bool HasKeyBadge;
        public bool HasLockBadge;
        public bool Interactable = true;

        public Vector2 Center => Bounds.center;
    }

    internal sealed class VisibleUiTarget
    {
        public GameObject PointerTarget;
        public Rect Bounds;
        public string SemanticId;
        public string Label;
        public string Technology;
        public bool Interactable = true;
    }

    internal sealed class VisibleGameState
    {
        public string LevelId;
        public string BudgetMode;
        public int? RemainingBudget;
        public bool Completed;
        public bool Failed;
        public List<string> Texts = new List<string>();
        public List<VisibleArrowTarget> Arrows = new List<VisibleArrowTarget>();

        public string Summary =>
            $"level={LevelId ?? "<unknown>"},mode={BudgetMode ?? "<unknown>"}," +
            $"budget={(RemainingBudget.HasValue ? RemainingBudget.Value.ToString() : "?")}," +
            $"arrows={Arrows.Count},completed={Completed},failed={Failed}";
    }

    internal sealed class PlayerSurfaceObservation
    {
        public bool BoardAndArrowsVisible;
        public bool LevelFullyVisible;
        public bool ModeFullyVisible;
        public bool BudgetFullyVisible;
        public bool HintFullyVisible;
        public bool RestartFullyVisible;
        public bool NextLevelFullyVisible;

        public bool ControlsFullyVisible => HintFullyVisible && RestartFullyVisible &&
                                            NextLevelFullyVisible;
        public bool Complete => BoardAndArrowsVisible && LevelFullyVisible &&
                                ModeFullyVisible && BudgetFullyVisible &&
                                ControlsFullyVisible;
        public string Summary =>
            $"board={BoardAndArrowsVisible};level={LevelFullyVisible};" +
            $"mode={ModeFullyVisible};budget={BudgetFullyVisible};" +
            $"hint={HintFullyVisible};restart={RestartFullyVisible};" +
            $"next={NextLevelFullyVisible}";
    }

    internal sealed class VisibleTextSurface
    {
        public string Text;
        public Rect Bounds;
    }

    internal sealed class VisibleExitObservation
    {
        public bool StartedMoving;
        public bool Removed;
        public bool Continuous;
        public bool Forward;
        public bool ShapePreserved;
        public string Direction;
        public int MovingFrames;
        public float TravelPixels;
    }

    internal sealed partial class ArrowEscapeTrajectoryHarness
    {
        private static readonly Regex BudgetRegex = new Regex(
            @"\b(Moves|Hearts)\b[^\d\r\n]{0,32}(\d+)\b",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex BudgetReverseRegex = new Regex(
            @"\b(\d+)\b[^\d\r\n]{0,32}\b(Moves|Hearts)\b",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

        public VisibleGameState ObserveVisibleState()
        {
            List<string> texts = VisibleUiTexts();
            string joined = string.Join(" | ", texts);
            bool hasBudget = TryParseVisibleBudget(texts, out string budgetMode,
                out int remainingBudget);
            string levelId = ResolveVisibleLevelId(joined);
            return new VisibleGameState
            {
                LevelId = levelId,
                BudgetMode = hasBudget ? budgetMode : null,
                RemainingBudget = hasBudget ? remainingBudget : (int?)null,
                Completed = texts.Any(text => string.Equals(
                    text.Trim(), "COMPLETED", StringComparison.OrdinalIgnoreCase)),
                Failed = texts.Any(text => string.Equals(
                    text.Trim(), "FAILED", StringComparison.OrdinalIgnoreCase)),
                Texts = texts,
                Arrows = FindVisibleArrowTargets()
            };
        }

        internal static bool TryParseVisibleBudget(
            string visibleText,
            out string mode,
            out int remaining)
        {
            Match match = BudgetRegex.Match(visibleText ?? string.Empty);
            if (match.Success && int.TryParse(match.Groups[2].Value, out remaining))
            {
                mode = NormalizeMode(match.Groups[1].Value);
                return true;
            }

            match = BudgetReverseRegex.Match(visibleText ?? string.Empty);
            if (match.Success && int.TryParse(match.Groups[1].Value, out remaining))
            {
                mode = NormalizeMode(match.Groups[2].Value);
                return true;
            }

            mode = null;
            remaining = 0;
            return false;
        }

        internal static bool TryParseVisibleBudget(
            IEnumerable<string> visibleTexts,
            out string mode,
            out int remaining)
        {
            string[] texts = (visibleTexts ?? Array.Empty<string>())
                .Where(text => !string.IsNullOrWhiteSpace(text))
                .ToArray();
            var paired = new List<(string mode, int remaining)>();
            foreach (string text in texts)
            {
                if (TryParseVisibleBudget(text, out string pairedMode,
                        out int pairedRemaining))
                {
                    paired.Add((pairedMode, pairedRemaining));
                }
            }

            var distinctPairs = paired.Distinct().ToArray();
            if (distinctPairs.Length == 1)
            {
                mode = distinctPairs[0].mode;
                remaining = distinctPairs[0].remaining;
                return true;
            }
            if (distinctPairs.Length > 1)
            {
                mode = null;
                remaining = 0;
                return false;
            }

            string[] modes = texts.SelectMany(text => Regex.Matches(text,
                        @"\b(Moves|Hearts)\b",
                        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)
                    .Cast<Match>().Select(match => NormalizeMode(match.Groups[1].Value)))
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            if (modes.Length != 1)
            {
                mode = null;
                remaining = 0;
                return false;
            }

            var numericCandidates = new List<int>();
            foreach (string text in texts)
            {
                if (ResolveVisibleLevelId(text) != null ||
                    Regex.IsMatch(text, @"\b\d+\s*/\s*\d+\b"))
                {
                    continue;
                }
                bool budgetSemantic = Regex.IsMatch(text,
                    @"\b(Moves|Hearts|Remaining|Budget)\b",
                    RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                bool numberOnly = Regex.IsMatch(text.Trim(), @"^\D*\d+\D*$");
                if (!budgetSemantic && !numberOnly) continue;
                foreach (Match number in Regex.Matches(text, @"\b\d+\b"))
                {
                    if (int.TryParse(number.Value, out int value))
                        numericCandidates.Add(value);
                }
            }

            int[] distinctNumbers = numericCandidates.Distinct().ToArray();
            if (distinctNumbers.Length == 1)
            {
                mode = modes[0];
                remaining = distinctNumbers[0];
                return true;
            }

            mode = null;
            remaining = 0;
            return false;
        }

        internal static string ResolveVisibleLevelId(string visibleText)
        {
            string normalized = NormalizeUi(visibleText);
            if (normalized.Contains("tutorial"))
                return ArrowEscapeContractConstants.TutorialLevelId;
            if (normalized.Contains("modesandhint") ||
                (normalized.Contains("modes") && normalized.Contains("hint")))
            {
                return ArrowEscapeContractConstants.ModesLevelId;
            }
            if (normalized.Contains("prerequisitechain") ||
                normalized.Contains("keychain") ||
                (normalized.Contains("prerequisite") && normalized.Contains("chain")))
            {
                return ArrowEscapeContractConstants.PrerequisiteLevelId;
            }
            return null;
        }

        internal static bool VisibleLevelMatchesSnapshot(
            IEnumerable<string> visibleTexts, string levelId)
        {
            if (string.IsNullOrWhiteSpace(levelId)) return false;
            return (visibleTexts ?? Array.Empty<string>()).Any(text => string.Equals(
                ResolveVisibleLevelId(text), levelId, StringComparison.Ordinal));
        }

        internal static bool VisibleBudgetMatchesSnapshot(
            IEnumerable<string> visibleTexts,
            ArrowEscapeBudgetMode budgetMode,
            int remainingBudget)
        {
            string mode = budgetMode.ToString();
            string[] texts = (visibleTexts ?? Array.Empty<string>())
                .Where(text => !string.IsNullOrWhiteSpace(text))
                .ToArray();
            bool ContainsMode(string text) => Regex.IsMatch(text,
                $@"\b{Regex.Escape(mode)}\b",
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
            bool modeVisible = texts.Any(ContainsMode);
            bool budgetVisible = texts.Any(text => ContainsIntegerToken(
                    text, remainingBudget) &&
                (ContainsMode(text) || ResolveVisibleLevelId(text) == null));
            return modeVisible && budgetVisible;
        }

        public PlayerSurfaceObservation ObservePlayerSurface()
        {
            VisibleGameState state = ObserveVisibleState();
            List<VisibleTextSurface> surfaces = VisibleUiTextSurfaces();
            string expectedMode = state?.BudgetMode;
            int? expectedBudget = state?.RemainingBudget;

            bool levelVisible = state != null && !string.IsNullOrWhiteSpace(state.LevelId) &&
                surfaces.Any(item => FullyInsidePlayerFrame(item.Bounds) &&
                    string.Equals(ResolveVisibleLevelId(item.Text), state.LevelId,
                        StringComparison.Ordinal));
            bool modeVisible = !string.IsNullOrWhiteSpace(expectedMode) &&
                surfaces.Any(item => FullyInsidePlayerFrame(item.Bounds) &&
                    Regex.IsMatch(item.Text ?? string.Empty,
                        $@"\b{Regex.Escape(expectedMode)}\b",
                        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant));
            bool budgetVisible = expectedBudget.HasValue &&
                surfaces.Any(item => FullyInsidePlayerFrame(item.Bounds) &&
                    ContainsIntegerToken(item.Text ?? string.Empty, expectedBudget.Value) &&
                    (ResolveVisibleLevelId(item.Text) == null ||
                     Regex.IsMatch(item.Text ?? string.Empty,
                         @"\b(Moves|Hearts|Remaining|Budget)\b",
                         RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)));

            VisibleUiTarget hint = ResolveVisibleUiTarget(ArrowEscapeUiAction.Hint);
            VisibleUiTarget restart = ResolveVisibleUiTarget(ArrowEscapeUiAction.Restart);
            VisibleUiTarget next = ResolveVisibleUiTarget(ArrowEscapeUiAction.NextLevel);
            List<VisibleArrowTarget> arrows = FindVisibleArrowTargets();
            bool boardVisible = arrows.Count >= 3 && arrows.All(item =>
                item != null && FullyInsidePlayerFrame(item.Bounds));

            return new PlayerSurfaceObservation
            {
                BoardAndArrowsVisible = boardVisible,
                LevelFullyVisible = levelVisible,
                ModeFullyVisible = modeVisible,
                BudgetFullyVisible = budgetVisible,
                HintFullyVisible = hint != null &&
                    PlayerSurfaceControlWithinFrame(hint.Bounds),
                RestartFullyVisible = restart != null &&
                    PlayerSurfaceControlWithinFrame(restart.Bounds),
                NextLevelFullyVisible = next != null &&
                    PlayerSurfaceControlWithinFrame(next.Bounds)
            };
        }

        public List<VisibleArrowTarget> FindVisibleArrowTargets()
        {
            List<VisibleArrowTarget> discovered = DiscoverPhysicalArrowTargets();
            // Scored visibility is owned by independently discovered, currently
            // rendered player-input surfaces.  The candidate probe is only a
            // locator hint: one stale/off-screen registry entry must not erase
            // unrelated real arrows from the observed board.
            ArrowEscapeGameSnapshot locatorSnapshot = null;
            try
            {
                locatorSnapshot = probe?.CaptureBenchmarkSnapshot();
            }
            catch (Exception exception)
            {
                lastObservationFailure = "Arrow locator probe threw " +
                    exception.GetType().Name + ": " + exception.Message;
            }

            var claimedTargets = new HashSet<int>();
            foreach (ArrowEscapeVisibleTargetSnapshot semantic in
                     locatorSnapshot?.VisibleTargets ??
                     Array.Empty<ArrowEscapeVisibleTargetSnapshot>())
            {
                if (semantic == null || semantic.Kind != ArrowEscapeVisibleTargetKind.Arrow ||
                    string.IsNullOrWhiteSpace(semantic.Id))
                {
                    continue;
                }

                IArrowEscapeInputTarget[] adapters = FindAllMonoBehaviours()
                    .OfType<IArrowEscapeInputTarget>()
                    .Where(item => item != null &&
                        string.Equals(item.ArrowId, semantic.Id,
                            StringComparison.Ordinal) &&
                        item.PointerTarget != null && item.PointerTarget.activeInHierarchy)
                    .ToArray();
                VisibleArrowTarget existing = adapters.Length == 1
                    ? ResolveExactArrowAdapterPhysicalTarget(adapters[0], semantic)
                    : null;
                if (existing == null && semantic.Visible &&
                    ValidSemanticRect(semantic.ScreenRect))
                {
                    VisibleArrowTarget[] geometryMatches = discovered
                        .Where(item => PhysicalRectMatchesSemantic(
                            item.Bounds, semantic.ScreenRect))
                        .OrderBy(item => Vector2.Distance(
                            item.Bounds.center, semantic.ScreenRect.center))
                        .ToArray();
                    existing = geometryMatches.Length == 1
                        ? geometryMatches[0]
                        : null;
                }

                // A self-reported entry can label an independently discovered
                // surface, but it cannot create one.  Its Rect is deliberately not
                // a veto when the exact live adapter points at the real GameObject:
                // registry data may trail normal movement by a frame.
                if (existing?.PointerTarget == null ||
                    !claimedTargets.Add(existing.PointerTarget.GetInstanceID()))
                {
                    continue;
                }

                existing.SemanticId = semantic.Id;
                existing.StableKey = semantic.Id;
            }

            // A public arrow adapter is also only a locator.  It may provide a
            // stable key for a real surface that the registry omitted or reported
            // stale, but the scored target remains the independently visible
            // GameObject and later must pass the actual EventSystem top-hit route.
            foreach (VisibleArrowTarget physical in discovered.Where(item =>
                         item?.PointerTarget != null &&
                         string.IsNullOrWhiteSpace(item.SemanticId)))
            {
                string[] ids = FindAllMonoBehaviours()
                    .OfType<IArrowEscapeInputTarget>()
                    .Where(item => item != null &&
                                   item.PointerTarget == physical.PointerTarget &&
                                   item.PointerTarget.activeInHierarchy &&
                                   !string.IsNullOrWhiteSpace(item.ArrowId))
                    .Select(item => item.ArrowId)
                    .Distinct(StringComparer.Ordinal)
                    .ToArray();
                if (ids.Length == 1)
                {
                    physical.SemanticId = ids[0];
                    physical.StableKey = ids[0];
                }
            }

            // Duplicate candidate-owned IDs are not allowed to turn evaluator
            // bookkeeping (for example CaptureArrowVisuals.ToDictionary) into an
            // infrastructure exception.  Fall back to real object identity; the
            // duplicate submission will simply lack trustworthy semantic labels.
            foreach (IGrouping<string, VisibleArrowTarget> duplicate in discovered
                         .Where(item => item?.PointerTarget != null &&
                                        !string.IsNullOrWhiteSpace(item.SemanticId))
                         .GroupBy(item => item.SemanticId, StringComparer.Ordinal)
                         .Where(group => group.Count() > 1))
            {
                foreach (VisibleArrowTarget item in duplicate)
                {
                    item.SemanticId = null;
                    item.StableKey = "physical-arrow@" +
                        item.PointerTarget.GetInstanceID();
                }
            }

            return discovered
                .Where(item => item?.PointerTarget != null)
                .GroupBy(item => item.PointerTarget.GetInstanceID())
                .Select(group => group.First())
                .OrderByDescending(item => item.Center.y)
                .ThenBy(item => item.Center.x)
                .ToList();
        }

        internal static VisibleArrowTarget ResolveExactArrowAdapterPhysicalTarget(
            IArrowEscapeInputTarget adapter,
            ArrowEscapeVisibleTargetSnapshot semantic)
        {
            GameObject root = adapter?.PointerTarget;
            if (root == null || !root.activeInHierarchy || semantic == null ||
                semantic.Kind != ArrowEscapeVisibleTargetKind.Arrow || !semantic.Visible ||
                string.IsNullOrWhiteSpace(semantic.Id) ||
                !ValidSemanticRect(semantic.ScreenRect) ||
                !HasVisibleGeometry(root) || !HasEnabledPointerSurface(root))
            {
                return null;
            }

            VisibleArrowTarget physical = CreateVisibleArrow(root);
            if (physical == null || !PhysicalRectCorroboratesSemantic(
                    physical.Bounds, semantic.ScreenRect))
            {
                return null;
            }

            physical.SemanticId = semantic.Id;
            physical.StableKey = semantic.Id;
            // Candidate-owned Interactable is diagnostic metadata, not input
            // authority.  The real player route (visible geometry, top-hit and
            // the resulting state change) decides whether the target can be
            // used.  A stale registry frame must not hide an otherwise real
            // target from the evaluator.
            return physical;
        }

        // Evaluator-health must validate the engine-facing visibility probe
        // without depending on candidate-owned semantic registry entries. The
        // scored path remains FindVisibleArrowTargets(), which always requires
        // an independent physical surface; semantic IDs are optional locator
        // labels and may fall back to evaluator-side real-object identity.
        internal static List<VisibleArrowTarget>
            DiscoverPhysicalArrowTargetsForEvaluatorHealth()
        {
            return DiscoverPhysicalArrowTargets();
        }

        private static List<VisibleArrowTarget> DiscoverPhysicalArrowTargets()
        {
            var targets = new HashSet<GameObject>();
            // Discover independently visible engine surfaces first. The semantic
            // registry may label these surfaces later, but it cannot create one.
            foreach (MonoBehaviour behaviour in FindAllMonoBehaviours())
            {
                if (behaviour is IPointerClickHandler && behaviour.gameObject != null)
                {
                    targets.Add(behaviour.gameObject);
                }
            }

            foreach (Collider2D collider in UnityEngine.Object.FindObjectsByType<Collider2D>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (collider != null && collider.enabled) targets.Add(collider.gameObject);
            }
            foreach (Graphic graphic in UnityEngine.Object.FindObjectsByType<Graphic>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (graphic == null || !graphic.isActiveAndEnabled || !graphic.raycastTarget)
                    continue;
                GameObject handler = ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                    graphic.gameObject);
                if (handler != null) targets.Add(handler);
            }
            foreach (Renderer renderer in UnityEngine.Object.FindObjectsByType<Renderer>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (renderer == null || !renderer.enabled) continue;
                GameObject root = ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                    renderer.gameObject);
                if (root == null)
                {
                    Collider2D collider2D = renderer.GetComponentInParent<Collider2D>();
                    root = collider2D != null ? collider2D.gameObject : null;
                }
                if (root == null)
                {
                    LineRenderer line = renderer.GetComponentInParent<LineRenderer>();
                    root = line != null && line.positionCount >= 2
                        ? line.gameObject
                        : null;
                }
                if (root != null) targets.Add(root);
            }

            IArrowEscapeInputTarget[] adapters = FindAllMonoBehaviours()
                .OfType<IArrowEscapeInputTarget>()
                .Where(item => item?.PointerTarget != null)
                .ToArray();
            foreach (IArrowEscapeInputTarget adapter in adapters)
            {
                targets.Add(adapter.PointerTarget);
            }

            List<VisibleArrowTarget> discovered = targets
                .Where(IsVisibleArrowCandidate)
                .Select(CreateVisibleArrow)
                .Where(item => item != null)
                .OrderByDescending(item => item.Center.y)
                .ThenBy(item => item.Center.x)
                .ToList();

            // The optional adapter names the one real GameObject used by the
            // ordinary pointer route. Some implementations keep the adapter and
            // the rendered line body on a parent while PointerTarget is a visible
            // collider-backed head child. Raw renderer/collider discovery then
            // sees both objects even though they are two pieces of one arrow.
            // Collapse only that exact one-adapter owner wrapper, preserving the
            // adapter's real click target while carrying over independently
            // observed body/badge evidence from the wrapper.
            var removeWrapperIds = new HashSet<int>();
            foreach (IArrowEscapeInputTarget adapter in adapters)
            {
                if (adapter is not Component component ||
                    component.gameObject == adapter.PointerTarget ||
                    !adapter.PointerTarget.transform.IsChildOf(component.transform))
                {
                    continue;
                }

                int ownerBindingCount = adapters.Count(item =>
                    item is Component owner && owner.gameObject == component.gameObject);
                if (ownerBindingCount != 1) continue;

                VisibleArrowTarget pointer = discovered.FirstOrDefault(item =>
                    item.PointerTarget == adapter.PointerTarget);
                VisibleArrowTarget wrapper = discovered.FirstOrDefault(item =>
                    item.PointerTarget == component.gameObject);
                if (pointer == null || wrapper == null) continue;

                pointer.HasKeyBadge |= wrapper.HasKeyBadge;
                pointer.HasLockBadge |= wrapper.HasLockBadge;
                if (!string.IsNullOrWhiteSpace(wrapper.VisualSignature))
                    pointer.VisualSignature = wrapper.VisualSignature;
                if (!string.IsNullOrWhiteSpace(wrapper.StyleSignature))
                    pointer.StyleSignature = wrapper.StyleSignature;
                removeWrapperIds.Add(component.gameObject.GetInstanceID());
            }

            return discovered
                .Where(item => item?.PointerTarget != null &&
                               !removeWrapperIds.Contains(
                                   item.PointerTarget.GetInstanceID()))
                .OrderByDescending(item => item.Center.y)
                .ThenBy(item => item.Center.x)
                .ToList();
        }

        public VisibleUiTarget ResolveVisibleUiTarget(ArrowEscapeUiAction action) =>
            ResolveVisibleUiTarget(action, out _);

        public VisibleUiTarget ResolveVisibleUiTarget(
            ArrowEscapeUiAction action,
            out string diagnostic)
        {
            ArrowEscapeVisibleTargetKind kind = action switch
            {
                ArrowEscapeUiAction.Hint => ArrowEscapeVisibleTargetKind.Hint,
                ArrowEscapeUiAction.Restart => ArrowEscapeVisibleTargetKind.Restart,
                ArrowEscapeUiAction.NextLevel => ArrowEscapeVisibleTargetKind.NextLevel,
                _ => ArrowEscapeVisibleTargetKind.Hint
            };
            // UI actions are independently discovered from real visible input
            // surfaces.  The public registry and optional adapter may label or
            // disambiguate those surfaces, but neither is allowed to create a
            // surface or veto a unique real one. Do not make a terminal
            // Restart/Next Level click
            // depend on an unrelated whole-scene Snapshot() cross-check: once all
            // arrows have exited, a transient or unrelated scene diagnostic must
            // not make an otherwise real player control disappear from the input
            // path. The click's EventSystem top-hit and resulting state change are
            // still required by InputSystemPlayerDriver and the trajectory checks.
            ArrowEscapeGameSnapshot locatorSnapshot = null;
            try
            {
                locatorSnapshot = probe?.CaptureBenchmarkSnapshot();
            }
            catch (Exception exception)
            {
                lastObservationFailure = "UI locator probe threw " +
                    exception.GetType().Name + ": " + exception.Message;
            }
            ArrowEscapeVisibleTargetSnapshot[] registered =
                (locatorSnapshot?.VisibleTargets ??
                 Array.Empty<ArrowEscapeVisibleTargetSnapshot>())
                .Where(item => item != null && item.Kind == kind && item.Visible &&
                               ValidSemanticRect(item.ScreenRect))
                .ToArray();

            VisibleUiTarget[] physical = DiscoverPhysicalUiTargets(action).ToArray();
            IArrowEscapeUiInputTarget[] adapters = FindAllMonoBehaviours()
                .OfType<IArrowEscapeUiInputTarget>()
                .Where(item => item != null && item.Action == action &&
                               item.PointerTarget != null &&
                               item.PointerTarget.activeInHierarchy)
                .ToArray();

            if (adapters.Length == 1)
            {
                ArrowEscapeVisibleTargetSnapshot semantic = registered.Length == 1
                    ? registered[0]
                    : null;
                VisibleUiTarget exact = ResolveExactAdapterPhysicalTarget(
                    adapters[0], semantic);
                if (exact != null)
                {
                    diagnostic = semantic == null
                        ? $"exact public locator with independent real geometry; " +
                          $"registry {kind} count={registered.Length}"
                        : $"exact public locator; physical={exact.Bounds}; " +
                          $"semantic={semantic.ScreenRect}";
                    return exact;
                }
            }

            if (registered.Length == 1)
            {
                VisibleUiTarget matched = ResolveVisibleUiTarget(
                    action, registered[0], out string registryDiagnostic);
                if (matched != null)
                {
                    diagnostic = registryDiagnostic;
                    return matched;
                }
            }

            // A unique implementation-neutral control found through uGUI,
            // UI Toolkit, pointer handlers or visible direct-polling geometry is
            // sufficient for an input attempt. InputSystemPlayerDriver still has
            // to prove the actual top hit, complete Mouse route and state change.
            VisibleUiTarget[] unique = physical
                .Where(item => item?.PointerTarget != null)
                .GroupBy(item => item.PointerTarget.GetInstanceID())
                .Select(group => group.First())
                .ToArray();
            if (unique.Length == 1)
            {
                diagnostic = $"unique independent {unique[0].Technology} surface; " +
                             $"registry {kind} count={registered.Length}; " +
                             $"adapters={adapters.Length}";
                return unique[0];
            }

            diagnostic = $"ambiguous/missing real {action} surface; " +
                         $"physical={unique.Length}; registry {kind}=" +
                         $"{registered.Length}; adapters={adapters.Length}";
            return null;
        }

        private static VisibleUiTarget ResolveVisibleUiTarget(
            ArrowEscapeUiAction action,
            ArrowEscapeVisibleTargetSnapshot registered,
            out string diagnostic)
        {
            if (registered == null || !registered.Visible ||
                !ValidSemanticRect(registered.ScreenRect))
            {
                diagnostic = "registered target is missing, hidden, or off-screen";
                return null;
            }

            VisibleUiTarget[] physical = DiscoverPhysicalUiTargets(action).ToArray();
            IArrowEscapeUiInputTarget[] adapters = FindAllMonoBehaviours()
                .OfType<IArrowEscapeUiInputTarget>()
                .Where(item => item != null && item.Action == action &&
                               item.PointerTarget != null &&
                               item.PointerTarget.activeInHierarchy)
                .ToArray();
            if (adapters.Length == 1)
            {
                // The public adapter identifies a real player-facing GameObject, but
                // it remains only a locator hint. Corroborate that exact object using
                // independently discovered live geometry and an overlapping screen
                // Rect, then let the input driver prove top-hit and normal Mouse
                // routing. Do not require the label/technology discovery pass to
                // produce the same aggregate bounds: a Button root and its child
                // graphics can legitimately yield different extents.
                VisibleUiTarget exact = ResolveExactAdapterPhysicalTarget(
                    adapters[0], registered);
                if (exact != null)
                {
                    diagnostic = $"exact public locator; physical={exact.Bounds}; " +
                                 $"semantic={registered.ScreenRect}";
                    return exact;
                }
            }

            VisibleUiTarget[] matches = physical
                .Where(item => item?.PointerTarget != null &&
                               PhysicalRectMatchesSemantic(
                                    item.Bounds, registered.ScreenRect))
                .ToArray();
            if (matches.Length != 1)
            {
                diagnostic = $"physical {action} matches={matches.Length}; " +
                             $"adapters={adapters.Length}; semantic={registered.ScreenRect}; " +
                             "physical=" + string.Join(", ", physical.Select(item =>
                                 item == null
                                     ? "<null>"
                                     : $"{item.Technology}:{item.PointerTarget?.name}:{item.Bounds}"));
                return null;
            }
            matches[0].SemanticId = registered.Id;
            diagnostic = $"unique implementation-neutral physical match via " +
                         $"{matches[0].Technology}; physical={matches[0].Bounds}; " +
                         $"semantic={registered.ScreenRect}";
            return matches[0];
        }

        internal static VisibleUiTarget ResolveExactAdapterPhysicalTarget(
            IArrowEscapeUiInputTarget adapter,
            ArrowEscapeVisibleTargetSnapshot registered)
        {
            GameObject root = adapter?.PointerTarget;
            if (root == null || !root.activeInHierarchy ||
                !HasVisibleGeometry(root))
            {
                return null;
            }

            Rect exactBounds = VisibleScreenRect(root);
            if (!ValidSemanticRect(exactBounds) ||
                (registered != null &&
                 (!registered.Visible || !ValidSemanticRect(registered.ScreenRect) ||
                  !PhysicalRectCorroboratesSemantic(
                      exactBounds, registered.ScreenRect))))
            {
                return null;
            }

            Button button = root.GetComponent<Button>();
            return new VisibleUiTarget
            {
                PointerTarget = root,
                Bounds = exactBounds,
                SemanticId = registered?.Id,
                Label = UiLabel(root),
                Technology = button != null
                    ? "public locator + real uGUI.Button geometry"
                    : "public locator + real visible GameObject geometry",
                Interactable = button == null || button.interactable
            };
        }

        private static IEnumerable<VisibleUiTarget> DiscoverPhysicalUiTargets(
            ArrowEscapeUiAction action)
        {
            var semantic = new List<VisibleUiTarget>();
            foreach (Button button in UnityEngine.Object.FindObjectsByType<Button>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (button != null && button.isActiveAndEnabled &&
                    MatchesUiAction(button.gameObject, action))
                {
                    semantic.Add(new VisibleUiTarget
                    {
                        PointerTarget = button.gameObject,
                        Bounds = VisibleScreenRect(button.gameObject),
                        Label = UiLabel(button.gameObject),
                        Technology = "uGUI.Button",
                        Interactable = button.interactable
                    });
                }
            }

            // Mouse.current/InputAction implementations may intentionally use a
            // raycastable uGUI Graphic as the visible control while polling the
            // Input System from a scene-level controller. The public contract does
            // not require a Button, pointer-handler, or adapter component to live on
            // that Graphic. Treat the independently rendered/raycastable Graphic as
            // a candidate physical surface; the input driver and trajectory state
            // checks still have to prove a complete normal Mouse click and the
            // expected gameplay outcome. Skip surfaces already represented by a
            // Button or pointer handler so an ordinary control and its child label do
            // not become ambiguous duplicates.
            foreach (Graphic graphic in UnityEngine.Object.FindObjectsByType<Graphic>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (!IsPlayerVisibleGraphic(graphic) || !graphic.raycastTarget ||
                    graphic.GetComponentInParent<Button>() != null ||
                    ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                        graphic.gameObject) != null ||
                    !MatchesUiAction(graphic.gameObject, action))
                {
                    continue;
                }

                Graphic parentGraphic = graphic.transform.parent == null
                    ? null
                    : graphic.transform.parent.GetComponentInParent<Graphic>();
                if (parentGraphic != null && IsPlayerVisibleGraphic(parentGraphic) &&
                    parentGraphic.raycastTarget &&
                    MatchesUiAction(parentGraphic.gameObject, action))
                {
                    // The independently visible parent is the larger player-facing
                    // control and will be discovered by this same pass.
                    continue;
                }

                semantic.Add(new VisibleUiTarget
                {
                    PointerTarget = graphic.gameObject,
                    Bounds = VisibleScreenRect(graphic.gameObject),
                    Label = UiLabel(graphic.gameObject),
                    Technology = "uGUI.Graphic (direct Input System polling candidate surface)",
                    Interactable = true
                });
            }

            foreach (MonoBehaviour behaviour in FindAllMonoBehaviours())
            {
                if (behaviour == null || !behaviour.isActiveAndEnabled ||
                    behaviour is Button || behaviour is IArrowEscapeUiInputTarget ||
                    !IsIndependentUiInputBehaviour(behaviour) ||
                    !MatchesUiAction(behaviour.gameObject, action) ||
                    !HasVisibleGeometry(behaviour.gameObject))
                {
                    continue;
                }
                semantic.Add(new VisibleUiTarget
                {
                    PointerTarget = behaviour.gameObject,
                    Bounds = VisibleScreenRect(behaviour.gameObject),
                    Label = UiLabel(behaviour.gameObject),
                    Technology = behaviour is IPointerClickHandler
                        ? behaviour.GetType().FullName
                        : behaviour.GetType().FullName + " (direct Input System polling)",
                    Interactable = true
                });
            }

            semantic.AddRange(FindUiToolkitTargets(action));
            IArrowEscapeUiInputTarget[] adapters = FindAllMonoBehaviours()
                .OfType<IArrowEscapeUiInputTarget>()
                .Where(item => item != null && item.Action == action &&
                               item.PointerTarget != null && item.PointerTarget.activeInHierarchy &&
                               MatchesUiAction(item.PointerTarget, action) &&
                               HasVisibleGeometry(item.PointerTarget))
                .ToArray();
            foreach (IArrowEscapeUiInputTarget adapter in adapters)
            {
                GameObject root = adapter.PointerTarget;
                semantic.Add(new VisibleUiTarget
                {
                    PointerTarget = root,
                    Bounds = VisibleScreenRect(root),
                    Label = UiLabel(root),
                    Technology = "optional Contract adapter with real visible geometry",
                    Interactable = true
                });
            }

            return semantic
                .Where(item => item != null && item.PointerTarget != null &&
                               item.PointerTarget.activeInHierarchy &&
                               item.Bounds.width >= 2f && item.Bounds.height >= 2f &&
                               item.Bounds.xMax > 0f && item.Bounds.yMax > 0f &&
                               item.Bounds.xMin < Screen.width &&
                               item.Bounds.yMin < Screen.height)
                .GroupBy(item => item.PointerTarget.GetInstanceID() + ":" +
                                 Mathf.RoundToInt(item.Bounds.center.x) + ":" +
                                 Mathf.RoundToInt(item.Bounds.center.y))
                .Select(group => group.First())
                .ToArray();
        }

        // The generic branch above exists for implementation-neutral pointer
        // handlers and candidate-authored direct Input System polling surfaces.
        // Unity's passive UI components are not input routes. Treating Text,
        // CanvasScaler or GraphicRaycaster as direct-polling behaviours creates
        // duplicate physical targets for an ordinary Button + child label and
        // makes a valid control look ambiguous.
        internal static bool IsIndependentUiInputBehaviour(MonoBehaviour behaviour)
        {
            if (behaviour == null) return false;
            if (behaviour is IPointerClickHandler) return true;

            Type type = behaviour.GetType();
            string assembly = type.Assembly.GetName().Name ?? string.Empty;
            string typeNamespace = type.Namespace ?? string.Empty;
            bool engineAssembly =
                assembly.Equals("UnityEngine", StringComparison.OrdinalIgnoreCase) ||
                assembly.StartsWith("UnityEngine.", StringComparison.OrdinalIgnoreCase) ||
                assembly.StartsWith("Unity.", StringComparison.OrdinalIgnoreCase) ||
                assembly.StartsWith("UnityEditor", StringComparison.OrdinalIgnoreCase) ||
                assembly.StartsWith("TMPro", StringComparison.OrdinalIgnoreCase);
            return !engineAssembly &&
                   !typeNamespace.StartsWith("UnityEngine", StringComparison.Ordinal) &&
                   !typeNamespace.StartsWith("UnityEditor", StringComparison.Ordinal) &&
                   !typeNamespace.StartsWith("TMPro", StringComparison.Ordinal);
        }

        internal static VisibleUiTarget[]
            DiscoverPhysicalUiTargetsForEvaluatorRegression(
                ArrowEscapeUiAction action) =>
            DiscoverPhysicalUiTargets(action).ToArray();

        private static bool PhysicalRectMatchesSemantic(Rect physical, Rect semantic) =>
            ValidSemanticRect(physical) && ValidSemanticRect(semantic) &&
            Vector2.Distance(physical.center, semantic.center) <= 12f &&
            Mathf.Abs(physical.width - semantic.width) <= 20f &&
            Mathf.Abs(physical.height - semantic.height) <= 20f;

        // When the public locator adapter identifies the exact real GameObject,
        // renderer and contract utilities may legitimately compute different
        // bounding extents (for example a line body plus a sprite head). Require
        // both Rects to be valid and to overlap, while reserving the stricter
        // size/center match for candidates without an object-identity adapter.
        internal static bool PhysicalRectCorroboratesSemantic(
            Rect physical, Rect semantic)
        {
            if (!ValidSemanticRect(physical) || !ValidSemanticRect(semantic))
                return false;
            float overlapWidth = Mathf.Min(physical.xMax, semantic.xMax) -
                                 Mathf.Max(physical.xMin, semantic.xMin);
            float overlapHeight = Mathf.Min(physical.yMax, semantic.yMax) -
                                  Mathf.Max(physical.yMin, semantic.yMin);
            return overlapWidth >= 1f && overlapHeight >= 1f;
        }

        private static bool ValidSemanticRect(Rect rect) =>
            ArrowEscapeVisibleTargetUtility.IsFinite(rect) &&
            rect.width >= 2f && rect.height >= 2f &&
            rect.xMax > 0f && rect.yMax > 0f &&
            rect.xMin < Screen.width && rect.yMin < Screen.height;

        public GameObject ResolveUiTarget(ArrowEscapeUiAction action) =>
            ResolveVisibleUiTarget(action)?.PointerTarget;

        public IEnumerator ClickVisibleArrow(VisibleArrowTarget target, string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "player_pointer_click_visible_arrow";
            step.target = target?.StableKey ?? "<missing>";
            step.pre_snapshot = VisibleStateString(ObserveVisibleState());
            yield return driver.Click(target?.PointerTarget, stepId + ".input", step);
            step.post_snapshot = VisibleStateString(ObserveVisibleState());
            MergeStepStatus(step);
        }

        public IEnumerator ClickVisibleArrowContinuation(VisibleArrowTarget target)
        {
            var diagnostic = new TrajectoryStepEvidence
            {
                step_id = "visible.continuation.arrow",
                operation = "player_pointer_click_visible_arrow",
                target = target?.StableKey ?? "<missing>"
            };
            yield return driver.Click(target?.PointerTarget,
                "visible.continuation.arrow.input", diagnostic);
        }

        public IEnumerator ObserveVisibleExit(
            VisibleArrowTarget target,
            string stepId,
            Action<VisibleExitObservation> receive,
            string expectedDirection = null)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "player_click_and_observe_visible_exit";
            step.target = target?.StableKey ?? "<missing>";
            float started = StartStep(step);
            step.pre_snapshot = VisibleStateString(ObserveVisibleState());
            if (target?.PointerTarget == null ||
                !target.PointerTarget.activeInHierarchy ||
                !HasVisibleGeometry(target.PointerTarget))
            {
                Check(step, stepId + ".moving",
                    "independently visible arrow target", "missing", false);
                FinishStep(step, started);
                receive?.Invoke(new VisibleExitObservation());
                yield break;
            }

            GameObject root = target.PointerTarget;
            Rect initial = VisibleScreenRect(root);
            string style = VisibleStyleSignature(root);
            yield return driver.Click(root, stepId + ".input", step);

            var centers = new List<Vector2> { initial.center };
            bool stylePreserved = true;
            string firstStyleDifference = null;
            bool removed = false;
            float observationStarted = Time.realtimeSinceStartup;
            while (ExitObservationWindowOpen(
                       Time.realtimeSinceStartup - observationStarted, removed))
            {
                yield return null;
                if (root == null || !root.activeInHierarchy || !HasVisibleGeometry(root))
                {
                    removed = true;
                    break;
                }
                Rect bounds = VisibleScreenRect(root);
                centers.Add(bounds.center);
                string currentStyle = VisibleStyleSignature(root);
                if (stylePreserved && !VisibleStylePreserved(style, currentStyle))
                {
                    firstStyleDifference = VisibleStyleDifference(style, currentStyle);
                    stylePreserved = false;
                }
            }

            Vector2 displacement = centers.Last() - centers.First();
            string direction = CardinalDirection(displacement);
            Vector2 axis = CardinalAxis(direction);
            float travel = axis == Vector2.zero ? 0f :
                centers.Max(point => Vector2.Dot(point - centers[0], axis));
            int distinctForward = 0;
            float lastProjection = 0f;
            foreach (Vector2 center in centers.Skip(1))
            {
                float projection = Vector2.Dot(center - centers[0], axis);
                if (projection > lastProjection + 0.5f)
                {
                    distinctForward++;
                    lastProjection = projection;
                }
            }
            int movingFrames = centers.Skip(1)
                .Count(center => Vector2.Distance(center, centers[0]) > 0.5f);
            bool startedMoving = movingFrames > 0;
            bool continuous = movingFrames >= 3 && distinctForward >= 2;
            bool forward = QualifiesCardinalForward(direction, expectedDirection,
                travel, movingFrames, distinctForward);
            var result = new VisibleExitObservation
            {
                StartedMoving = startedMoving,
                Removed = removed,
                Continuous = continuous,
                Forward = forward,
                ShapePreserved = stylePreserved,
                Direction = direction,
                MovingFrames = movingFrames,
                TravelPixels = travel
            };

            Check(step, stepId + ".moving", "movement begins after click",
                $"movingFrames={movingFrames}", startedMoving);
            Check(step, stepId + ".continuous_frames",
                ">=3 displaced frames and >=2 distinct forward samples",
                $"movingFrames={movingFrames},distinctForward={distinctForward}",
                continuous);
            Check(step, stepId + ".forward_motion", "cardinal forward travel",
                $"direction={direction},expected={expectedDirection ?? "any"},pixels={travel:F1}", forward);
            Check(step, stepId + ".full_exit", "target removed after visible travel",
                removed ? "removed" : "still visible", removed && forward);
            Check(step, stepId + ".shape_preserved", "visible style preserved while moving",
                stylePreserved ? "preserved" : "changed; " + firstStyleDifference,
                stylePreserved);
            step.post_snapshot = VisibleStateString(ObserveVisibleState());
            FinishStep(step, started);
            receive?.Invoke(result);
        }

        public IEnumerator ObserveVisibleExitContinuation(
            VisibleArrowTarget target,
            Action<VisibleExitObservation> receive)
        {
            if (target?.PointerTarget == null ||
                !target.PointerTarget.activeInHierarchy ||
                !HasVisibleGeometry(target.PointerTarget))
            {
                receive?.Invoke(new VisibleExitObservation());
                yield break;
            }
            GameObject root = target.PointerTarget;
            Rect initial = VisibleScreenRect(root);
            string style = VisibleStyleSignature(root);
            yield return ClickVisibleArrowContinuation(target);

            var centers = new List<Vector2> { initial.center };
            bool stylePreserved = true;
            bool removed = false;
            float observationStarted = Time.realtimeSinceStartup;
            while (ExitObservationWindowOpen(
                       Time.realtimeSinceStartup - observationStarted, removed))
            {
                yield return null;
                if (root == null || !root.activeInHierarchy || !HasVisibleGeometry(root))
                {
                    removed = true;
                    break;
                }
                centers.Add(VisibleScreenRect(root).center);
                string currentStyle = VisibleStyleSignature(root);
                if (stylePreserved && !VisibleStylePreserved(style, currentStyle))
                {
                    stylePreserved = false;
                }
            }

            Vector2 displacement = centers.Last() - centers.First();
            string direction = CardinalDirection(displacement);
            Vector2 axis = CardinalAxis(direction);
            float travel = axis == Vector2.zero ? 0f :
                centers.Max(point => Vector2.Dot(point - centers[0], axis));
            int distinctForward = 0;
            float lastProjection = 0f;
            foreach (Vector2 center in centers.Skip(1))
            {
                float projection = Vector2.Dot(center - centers[0], axis);
                if (projection > lastProjection + 0.5f)
                {
                    distinctForward++;
                    lastProjection = projection;
                }
            }
            int movingFrames = centers.Skip(1)
                .Count(center => Vector2.Distance(center, centers[0]) > 0.5f);
            receive?.Invoke(new VisibleExitObservation
            {
                StartedMoving = movingFrames > 0,
                Removed = removed,
                Continuous = movingFrames >= 3 && distinctForward >= 2,
                Forward = QualifiesCardinalForward(direction, null,
                    travel, movingFrames, distinctForward),
                ShapePreserved = stylePreserved,
                Direction = direction,
                MovingFrames = movingFrames,
                TravelPixels = travel
            });
        }

        public VisibleArrowTarget FindChangedArrow(
            IReadOnlyDictionary<string, string> before)
        {
            return FindVisibleArrowTargets().FirstOrDefault(item =>
                before.TryGetValue(item.StableKey, out string signature) &&
                !string.Equals(signature, item.VisualSignature, StringComparison.Ordinal));
        }

        public Dictionary<string, string> CaptureArrowVisuals() =>
            FindVisibleArrowTargets().ToDictionary(
                item => item.StableKey,
                item => item.VisualSignature);

        public string VisibleStateSignature() => VisibleStateString(ObserveVisibleState(), true);

        public VisibleArrowTarget RefreshTarget(VisibleArrowTarget target)
        {
            if (target == null) return null;
            List<VisibleArrowTarget> current = FindVisibleArrowTargets();
            if (!string.IsNullOrWhiteSpace(target.SemanticId))
            {
                return current.FirstOrDefault(item => string.Equals(
                    item.SemanticId, target.SemanticId, StringComparison.Ordinal));
            }
            if (target.PointerTarget != null)
            {
                return current.FirstOrDefault(item =>
                    item.PointerTarget == target.PointerTarget);
            }
            return current.FirstOrDefault(item => string.Equals(
                item.StableKey, target.StableKey, StringComparison.Ordinal));
        }

        public bool IsTargetVisible(VisibleArrowTarget target) =>
            RefreshTarget(target) != null;

        public bool IsTargetAt(
            VisibleArrowTarget target, Vector2 center, float tolerancePixels)
        {
            VisibleArrowTarget current = RefreshTarget(target);
            return current != null &&
                   Vector2.Distance(current.Center, center) <= tolerancePixels;
        }

        public bool SameTarget(VisibleArrowTarget left, VisibleArrowTarget right)
        {
            if (left == null || right == null) return false;
            if (!string.IsNullOrWhiteSpace(left.SemanticId) ||
                !string.IsNullOrWhiteSpace(right.SemanticId))
            {
                return string.Equals(left.SemanticId, right.SemanticId,
                    StringComparison.Ordinal);
            }
            return left.PointerTarget != null &&
                   left.PointerTarget == right.PointerTarget;
        }

        public void ExpectVisibleState(
            string stepId, string checkId, string expected, bool passed)
        {
            VisibleGameState state = ObserveVisibleState();
            Expect(stepId, checkId, expected, state?.Summary ?? "<null>", passed);
        }

        private static VisibleArrowTarget CreateVisibleArrow(GameObject target)
        {
            if (target == null) return null;
            Rect bounds = VisibleScreenRect(target);
            return new VisibleArrowTarget
            {
                PointerTarget = target,
                Bounds = bounds,
                StableKey = "physical-arrow@" + target.GetInstanceID(),
                VisualSignature = VisualSignature(target),
                StyleSignature = VisibleStyleSignature(target),
                HasKeyBadge = HasVisibleBadge(target, "key"),
                HasLockBadge = HasVisibleBadge(target, "lock")
            };
        }

        private static bool IsVisibleArrowCandidate(GameObject target)
        {
            if (target == null || !target.activeInHierarchy ||
                target.GetComponentInParent<Button>() != null ||
                target.GetComponent<IArrowEscapeUiInputTarget>() != null ||
                !HasVisibleGeometry(target) || !HasArrowInputSurfaceIdentity(target))
            {
                return false;
            }
            Rect rect = VisibleScreenRect(target);
            if (rect.width < 2f || rect.height < 2f ||
                rect.xMax <= 0f || rect.yMax <= 0f ||
                rect.xMin >= Screen.width || rect.yMin >= Screen.height)
            {
                return false;
            }
            // A real world-space arrow adapter wins over label heuristics.  Arrow
            // IDs such as "hint_clear" are gameplay content, not the Hint button.
            bool hasArrowAdapter = target.GetComponent<IArrowEscapeInputTarget>() != null;
            string label = UiLabel(target);
            return !ShouldRejectArrowByUiLabel(hasArrowAdapter, label);
        }

        internal static bool ShouldRejectArrowByUiLabel(
            bool hasArrowAdapter, string label) =>
            !hasArrowAdapter && LooksLikeUiAction(label);

        private static bool MatchesUiAction(GameObject target, ArrowEscapeUiAction action)
        {
            string label = NormalizeUi(UiLabel(target));
            return action switch
            {
                ArrowEscapeUiAction.Hint => label.Contains("hint"),
                ArrowEscapeUiAction.Restart => label.Contains("restart") || label.Contains("retry"),
                ArrowEscapeUiAction.NextLevel => label.Contains("nextlevel") ||
                                                     (label.Contains("next") && label.Contains("level")),
                _ => false
            };
        }

        private static string UiLabel(GameObject target)
        {
            if (target == null) return string.Empty;
            var text = target.GetComponentsInChildren<Text>(true)
                .Where(item => item != null && !string.IsNullOrWhiteSpace(item.text))
                .Select(item => item.text)
                .ToList();
            foreach (MonoBehaviour component in target.GetComponentsInChildren<MonoBehaviour>(true))
            {
                if (component == null || component is Text ||
                    component.GetType().FullName?.StartsWith("TMPro.",
                        StringComparison.Ordinal) != true)
                {
                    continue;
                }
                System.Reflection.PropertyInfo property =
                    component.GetType().GetProperty("text");
                string value = property?.CanRead == true
                    ? property.GetValue(component) as string
                    : null;
                if (!string.IsNullOrWhiteSpace(value)) text.Add(value);
            }
            return target.name + " " + string.Join(" ", text);
        }

        private static IEnumerable<VisibleUiTarget> FindUiToolkitTargets(
            ArrowEscapeUiAction action)
        {
            Type documentType = Type.GetType(
                "UnityEngine.UIElements.UIDocument, UnityEngine.UIElementsModule");
            Type visualElementType = Type.GetType(
                "UnityEngine.UIElements.VisualElement, UnityEngine.UIElementsModule");
            Type buttonType = Type.GetType(
                "UnityEngine.UIElements.Button, UnityEngine.UIElementsModule");
            if (documentType == null || visualElementType == null || buttonType == null)
                yield break;

            System.Reflection.PropertyInfo rootProperty =
                documentType.GetProperty("rootVisualElement");
            foreach (UnityEngine.Object documentObject in UnityEngine.Object.FindObjectsByType(
                         documentType, FindObjectsInactive.Exclude,
                         FindObjectsSortMode.None))
            {
                if (documentObject is not Component document ||
                    !document.gameObject.activeInHierarchy)
                {
                    continue;
                }
                object root = rootProperty?.GetValue(documentObject);
                if (root == null) continue;
                Rect rootRect = ReflectionRect(root, "contentRect");
                foreach (object element in TraverseVisualElements(root))
                {
                    if (!buttonType.IsInstanceOfType(element) ||
                        !ReflectionBool(element, "enabledInHierarchy", true))
                    {
                        continue;
                    }
                    string label = ReflectionString(element, "name") + " " +
                                   ReflectionString(element, "text") + " " +
                                   ReflectionString(element, "tooltip");
                    if (!MatchesUiActionLabel(label, action)) continue;
                    Rect panelRect = ReflectionRect(element, "worldBound");
                    Rect screenRect = PanelRectToScreen(panelRect, rootRect);
                    if (screenRect.width < 2f || screenRect.height < 2f) continue;
                    yield return new VisibleUiTarget
                    {
                        PointerTarget = document.gameObject,
                        Bounds = screenRect,
                        Label = label,
                        Technology = "UI Toolkit Button",
                        Interactable = true
                    };
                }
            }
        }

        private static IEnumerable<object> TraverseVisualElements(object root)
        {
            if (root == null) yield break;
            var stack = new Stack<object>();
            stack.Push(root);
            while (stack.Count > 0)
            {
                object current = stack.Pop();
                yield return current;
                Type type = current.GetType();
                System.Reflection.PropertyInfo countProperty =
                    type.GetProperty("childCount");
                int count = countProperty?.GetValue(current) is int value ? value : 0;
                System.Reflection.PropertyInfo indexer = type.GetProperty("Item",
                    new[] { typeof(int) });
                for (int index = count - 1; index >= 0; index--)
                {
                    object child = indexer?.GetValue(current, new object[] { index });
                    if (child != null) stack.Push(child);
                }
            }
        }

        private static Rect PanelRectToScreen(Rect panelRect, Rect rootRect)
        {
            float scaleX = rootRect.width > 0.01f ? Screen.width / rootRect.width : 1f;
            float scaleY = rootRect.height > 0.01f ? Screen.height / rootRect.height : 1f;
            return new Rect(
                (panelRect.x - rootRect.x) * scaleX,
                Screen.height - (panelRect.yMax - rootRect.y) * scaleY,
                panelRect.width * scaleX,
                panelRect.height * scaleY);
        }

        private static Rect ReflectionRect(object value, string propertyName)
        {
            object result = value?.GetType().GetProperty(propertyName)?.GetValue(value);
            return result is Rect rect ? rect : default;
        }

        private static bool ReflectionBool(object value, string propertyName,
            bool fallback)
        {
            object result = value?.GetType().GetProperty(propertyName)?.GetValue(value);
            return result is bool boolean ? boolean : fallback;
        }

        private static string ReflectionString(object value, string propertyName)
        {
            object result = value?.GetType().GetProperty(propertyName)?.GetValue(value);
            return result as string ?? string.Empty;
        }

        private static string NormalizeUi(string value) => new string(
            (value ?? string.Empty).ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());

        private static bool LooksLikeUiAction(string value)
        {
            string normalized = NormalizeUi(value);
            return normalized.Contains("hint") || normalized.Contains("restart") ||
                   normalized.Contains("retry") || normalized.Contains("nextlevel");
        }

        private static bool MatchesUiActionLabel(string value,
            ArrowEscapeUiAction action)
        {
            string label = NormalizeUi(value);
            return action switch
            {
                ArrowEscapeUiAction.Hint => label.Contains("hint"),
                ArrowEscapeUiAction.Restart => label.Contains("restart") ||
                                                   label.Contains("retry"),
                ArrowEscapeUiAction.NextLevel => label.Contains("nextlevel") ||
                                                  (label.Contains("next") &&
                                                   label.Contains("level")),
                _ => false
            };
        }

        private static string NormalizeMode(string value) =>
            value.StartsWith("heart", StringComparison.OrdinalIgnoreCase) ? "Hearts" : "Moves";

        private static string CardinalDirection(Vector2 displacement)
        {
            if (displacement.sqrMagnitude < 4f) return "none";
            if (Mathf.Abs(displacement.x) >= Mathf.Abs(displacement.y))
                return displacement.x >= 0f ? "right" : "left";
            return displacement.y >= 0f ? "up" : "down";
        }

        private static Vector2 CardinalAxis(string direction) => direction switch
        {
            "right" => Vector2.right,
            "left" => Vector2.left,
            "up" => Vector2.up,
            "down" => Vector2.down,
            _ => Vector2.zero
        };

        internal static bool QualifiesCardinalForward(
            string direction,
            string expectedDirection,
            float travelPixels,
            int movingFrames,
            int distinctForwardSamples)
        {
            return CardinalAxis(direction) != Vector2.zero &&
                   (string.IsNullOrEmpty(expectedDirection) || string.Equals(
                       direction, expectedDirection, StringComparison.Ordinal)) &&
                   movingFrames >= 3 && distinctForwardSamples >= 2 &&
                   travelPixels >= 1f;
        }

        internal static bool ExitObservationWindowOpen(float elapsedSeconds, bool removed) =>
            !removed && elapsedSeconds < StateTimeoutSeconds;

        internal static string VisibleStyleSignature(GameObject target)
        {
            if (target == null) return "<null>";
            var parts = new List<string>();
            Text[] visibleTexts = target.GetComponentsInChildren<Text>(true)
                .Where(IsPlayerVisibleGraphic).ToArray();
            bool hasDirectionText = visibleTexts.Any(text =>
                LooksLikeDirectionMarker(text.text));
            bool hasNonTextCore = target.GetComponentsInChildren<SpriteRenderer>(true)
                                      .Any(renderer => renderer.enabled &&
                                          renderer.gameObject.activeInHierarchy &&
                                          renderer.color.a > 0.05f &&
                                          !IsBadgeVisual(renderer.transform,
                                              renderer.sprite?.name)) ||
                                  target.GetComponentsInChildren<LineRenderer>(true)
                                      .Any(line => line.enabled &&
                                          line.gameObject.activeInHierarchy &&
                                          (line.startColor.a > 0.05f ||
                                           line.endColor.a > 0.05f) &&
                                          !IsBadgeVisual(line.transform, null)) ||
                                  target.GetComponentsInChildren<Graphic>(true)
                                      .OfType<Image>()
                                      .Any(image => IsPlayerVisibleGraphic(image) &&
                                          !IsBadgeVisual(image.transform,
                                              image.sprite?.name)) ||
                                  target.GetComponentsInChildren<Renderer>(true)
                                      .Any(renderer => renderer is not SpriteRenderer &&
                                          renderer is not LineRenderer && renderer.enabled &&
                                          renderer.gameObject.activeInHierarchy &&
                                          !IsBadgeVisual(renderer.transform, null));
            foreach (SpriteRenderer renderer in target.GetComponentsInChildren<SpriteRenderer>(true))
            {
                if (!renderer.enabled || !renderer.gameObject.activeInHierarchy ||
                    renderer.color.a <= 0.05f ||
                    IsBadgeVisual(renderer.transform, renderer.sprite?.name))
                {
                    continue;
                }
                parts.Add($"S:{ShapeTransformSignature(target.transform, renderer.transform)}:" +
                          $"sprite={Token(renderer.sprite?.name)}:draw={renderer.drawMode}:" +
                          $"size={ShapeVector(renderer.size)}:flip={renderer.flipX},{renderer.flipY}");
            }
            foreach (LineRenderer line in target.GetComponentsInChildren<LineRenderer>(true))
            {
                if (!line.enabled || !line.gameObject.activeInHierarchy ||
                    (line.startColor.a <= 0.05f && line.endColor.a <= 0.05f) ||
                    IsBadgeVisual(line.transform, null))
                {
                    continue;
                }
                parts.Add($"L:{ShapeTransformSignature(target.transform, line.transform)}:" +
                          $"width={ShapeFloat(line.startWidth)},{ShapeFloat(line.endWidth)}:" +
                          $"points={LineShapeSignature(target.transform, line)}");
            }
            foreach (Graphic graphic in target.GetComponentsInChildren<Graphic>(true))
            {
                if (!IsPlayerVisibleGraphic(graphic))
                {
                    continue;
                }
                if (graphic is Text shapeText &&
                    (hasNonTextCore || hasDirectionText) &&
                    !LooksLikeDirectionMarker(shapeText.text))
                {
                    // Hint/failure captions and IDs are allowed to appear or clear while
                    // the arrow's real core geometry remains recognizable. A directional
                    // glyph/word remains part of the core, including text-only arrows.
                    continue;
                }
                string spriteName = graphic is Image badgeImage ? badgeImage.sprite?.name : null;
                if (IsBadgeVisual(graphic.transform, spriteName)) continue;
                string content = graphic switch
                {
                    Text text => $"text={Token(text.text)}:font={text.fontSize}:" +
                                 $"style={text.fontStyle}:align={text.alignment}",
                    Image image => $"sprite={Token(image.sprite?.name)}:type={image.type}:" +
                                   $"aspect={image.preserveAspect}",
                    _ => ""
                };
                parts.Add($"G:{ShapeTransformSignature(target.transform, graphic.transform)}:" +
                          $"type={graphic.GetType().FullName}:rect={ShapeRect(graphic.rectTransform.rect)}:" +
                          content);
            }

            foreach (Renderer renderer in target.GetComponentsInChildren<Renderer>(true))
            {
                if (renderer is SpriteRenderer || renderer is LineRenderer ||
                    !renderer.enabled || !renderer.gameObject.activeInHierarchy ||
                    IsBadgeVisual(renderer.transform, null))
                {
                    continue;
                }
                MeshFilter filter = renderer.GetComponent<MeshFilter>();
                Mesh mesh = filter != null ? filter.sharedMesh : null;
                parts.Add($"R:{ShapeTransformSignature(target.transform, renderer.transform)}:" +
                          $"type={renderer.GetType().FullName}:mesh={Token(mesh?.name)}:" +
                          $"vertices={(mesh == null ? -1 : mesh.vertexCount)}:" +
                          $"size={ShapeVector(renderer.bounds.size)}");
            }

            parts.Sort(StringComparer.Ordinal);
            return string.Join("|", parts);
        }

        internal static bool VisibleStylePreserved(string baseline, string current)
        {
            string[] required = ShapeParts(baseline);
            string[] observed = ShapeParts(current);
            if (required.Length == 0)
            {
                return string.Equals(baseline, current, StringComparison.Ordinal);
            }

            var available = observed.GroupBy(part => part, StringComparer.Ordinal)
                .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);
            foreach (string part in required)
            {
                if (!available.TryGetValue(part, out int count) || count <= 0) return false;
                available[part] = count - 1;
            }
            return true;
        }

        internal static string VisibleStyleDifference(string baseline, string current)
        {
            string[] required = ShapeParts(baseline);
            string[] observed = ShapeParts(current);
            var available = observed.GroupBy(part => part, StringComparer.Ordinal)
                .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);
            foreach (string part in required)
            {
                if (!available.TryGetValue(part, out int count) || count <= 0)
                {
                    string observedSummary = current ?? "<null>";
                    if (observedSummary.Length > 900)
                        observedSummary = observedSummary.Substring(0, 900);
                    return "missing=" + (part.Length <= 600 ? part : part.Substring(0, 600)) +
                           "; current=" + observedSummary;
                }
                available[part] = count - 1;
            }
            return required.Length == 0 ? "no baseline core geometry" : "no missing core token";
        }

        private static string[] ShapeParts(string signature) =>
            string.IsNullOrEmpty(signature) || signature == "<null>"
                ? Array.Empty<string>()
                : signature.Split('|');

        private static bool IsPlayerVisibleGraphic(Graphic graphic)
        {
            if (graphic == null || !graphic.enabled || !graphic.gameObject.activeInHierarchy ||
                graphic.color.a <= 0.05f || graphic.canvasRenderer.GetAlpha() <= 0.05f)
            {
                return false;
            }
            return graphic is not Text text || !string.IsNullOrWhiteSpace(text.text);
        }

        private static bool LooksLikeDirectionMarker(string value)
        {
            string text = (value ?? string.Empty).Trim();
            if (text.Length == 0) return false;
            string normalized = text.ToLowerInvariant();
            if (normalized is "up" or "down" or "left" or "right" or
                "u" or "d" or "l" or "r" or "^" or "v" or "<" or ">")
            {
                return true;
            }
            return text.Any(character =>
                "▲△▼▽◀◁▶▷↑↓←→⬆⬇⬅➡".IndexOf(character) >= 0);
        }

        private static string ShapeTransformSignature(Transform root, Transform transform)
        {
            var path = new Stack<string>();
            Transform current = transform;
            while (current != null && current != root)
            {
                path.Push(Token(current.name));
                current = current.parent;
            }
            string relativePath = current == root
                ? (path.Count == 0 ? "." : string.Join("/", path))
                : "<external>";
            Vector3 position = transform == root ? Vector3.zero : transform.localPosition;
            return $"path={relativePath}:pos={ShapeVector(position)}:" +
                   $"rot={ShapeVector(transform.localEulerAngles)}:" +
                   $"scale={ShapeVector(transform.localScale)}";
        }

        private static string LineShapeSignature(Transform root, LineRenderer line)
        {
            if (line.positionCount <= 0) return "0";
            var points = new Vector3[line.positionCount];
            line.GetPositions(points);
            Vector3 first = line.useWorldSpace
                ? root.InverseTransformPoint(points[0])
                : root.InverseTransformPoint(line.transform.TransformPoint(points[0]));
            var relative = new List<string> { "0,0,0" };
            for (int index = 1; index < points.Length; index++)
            {
                Vector3 point = line.useWorldSpace
                    ? root.InverseTransformPoint(points[index])
                    : root.InverseTransformPoint(line.transform.TransformPoint(points[index]));
                relative.Add(ShapeVector(point - first));
            }
            return line.positionCount + ":" + string.Join(";", relative);
        }

        private static string ShapeRect(Rect value) =>
            $"{ShapeFloat(value.width)},{ShapeFloat(value.height)}";

        private static string ShapeVector(Vector2 value) =>
            $"{ShapeFloat(value.x)},{ShapeFloat(value.y)}";

        private static string ShapeVector(Vector3 value) =>
            $"{ShapeFloat(value.x)},{ShapeFloat(value.y)},{ShapeFloat(value.z)}";

        private static string ShapeFloat(float value)
        {
            // World/local transform round-trips can perturb an unchanged 0.95f
            // coordinate to 0.949999... . One-decimal midpoint rounding then
            // flips between 1.0 and 0.9 while the rendered shape merely moves.
            // Two-decimal quantization keeps sub-pixel noise stable and still
            // rejects meaningful deformation of the arrow core.
            double rounded = Math.Abs(value) < 0.005f
                ? 0d
                : Math.Round((double)value, 2, MidpointRounding.AwayFromZero);
            return rounded.ToString("F2",
                System.Globalization.CultureInfo.InvariantCulture);
        }

        private static string Token(string value) => Convert.ToBase64String(
            System.Text.Encoding.UTF8.GetBytes(value ?? string.Empty));

        private static bool IsBadgeVisual(Transform transform, string spriteName)
        {
            if (!string.IsNullOrEmpty(spriteName) &&
                (spriteName.IndexOf("key", StringComparison.OrdinalIgnoreCase) >= 0 ||
                 spriteName.IndexOf("lock", StringComparison.OrdinalIgnoreCase) >= 0))
                return true;
            for (Transform current = transform; current != null; current = current.parent)
            {
                if (current.name.IndexOf("badge", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    current.name.IndexOf("key", StringComparison.OrdinalIgnoreCase) >= 0 ||
                    current.name.IndexOf("lock", StringComparison.OrdinalIgnoreCase) >= 0)
                    return true;
            }
            return false;
        }

        private static string VisibleStateString(VisibleGameState state, bool includeGeometry = false)
        {
            if (state == null) return "<null>";
            IEnumerable<string> arrows = includeGeometry
                ? state.Arrows.Select(item =>
                    $"{Mathf.RoundToInt(item.Bounds.center.x)},{Mathf.RoundToInt(item.Bounds.center.y)}:" +
                    $"{Mathf.RoundToInt(item.Bounds.width)}x{Mathf.RoundToInt(item.Bounds.height)}:" +
                    $"key={item.HasKeyBadge}:lock={item.HasLockBadge}:{item.StyleSignature}")
                : state.Arrows.Select(item => item.StableKey);
            return state.Summary + ";" + string.Join(";", arrows.OrderBy(item => item));
        }
    }
}
