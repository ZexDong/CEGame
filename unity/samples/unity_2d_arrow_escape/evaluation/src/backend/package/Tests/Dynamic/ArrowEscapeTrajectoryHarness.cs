using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using OmniGame.Benchmark.ArrowEscape.V2;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    internal sealed partial class ArrowEscapeTrajectoryHarness
    {
        [Serializable]
        private sealed class VisualCaptureReceipt
        {
            public int schema_version = 1;
            public string state_id;
            public string status;
            public string file;
            public int width;
            public int height;
            public long bytes;
            public string sha256;
            public string capture_method;
            public bool includes_screen_space_overlay;
            public int process_id;
            public int frame;
            public string captured_utc;
        }

        private const float StateTimeoutSeconds = 4f;
        private readonly TrajectoryDefinition definition;
        private readonly Dictionary<string, TrajectoryStepEvidence> stepById =
            new Dictionary<string, TrajectoryStepEvidence>(StringComparer.Ordinal);
        private readonly Dictionary<string, ArrowEscapeGameSnapshot> captures =
            new Dictionary<string, ArrowEscapeGameSnapshot>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> sceneCaptures =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly InputSystemPlayerDriver driver = new InputSystemPlayerDriver();
        private IArrowEscapeReadOnlyProbe probe;
        private bool sceneReady;
        private string lastObservationFailure;
        private string firstFailureCheck;

        public ArrowEscapeTrajectoryHarness(string trajectoryId)
        {
            definition = TrajectoryDefinitionLoader.Load(trajectoryId, out string hash);
            Evidence = new TrajectoryRunEvidence
            {
                trajectory_id = definition.id,
                title = definition.title,
                definition_sha256 = hash,
                started_utc = DateTime.UtcNow.ToString("O")
            };
        }

        public TrajectoryRunEvidence Evidence { get; }
        public bool Ready => sceneReady;
        public string ObservationFailure => lastObservationFailure;

        public IEnumerator Initialize()
        {
            TrajectoryStepEvidence step = Step("setup.scene");
            step.operation = "load_canonical_scene";
            step.frame_start = Time.frameCount;
            float started = Time.realtimeSinceStartup;
            if (!Application.CanStreamedLevelBeLoaded(
                    ArrowEscapeContractConstants.MainScenePath))
            {
                Check(step, "setup.scene_load", "loadable main scene",
                    "not present in active build profile or shared scene list", false,
                    "The canonical scene is missing from the active build profile or shared scene list.");
                FinishStep(step, started);
                yield break;
            }
            AsyncOperation load = null;
            try
            {
                load = SceneManager.LoadSceneAsync(
                    ArrowEscapeContractConstants.MainScenePath, LoadSceneMode.Single);
            }
            catch (Exception exception)
            {
                Check(step, "setup.scene_load", "loadable main scene", exception.GetType().Name,
                    false, exception.Message);
            }
            if (load == null)
            {
                if (step.checks.All(check => check.check_id != "setup.scene_load"))
                {
                    Check(step, "setup.scene_load", "loadable main scene", "null AsyncOperation", false,
                        "SceneManager could not start loading the canonical scene.");
                }
                FinishStep(step, started);
                yield break;
            }
            while (!load.isDone)
            {
                yield return null;
            }
            yield return null;
            Check(step, "setup.scene_load", "loaded canonical main scene",
                SceneManager.GetActiveScene().path,
                string.Equals(SceneManager.GetActiveScene().path,
                    ArrowEscapeContractConstants.MainScenePath, StringComparison.Ordinal));

            IArrowEscapeReadOnlyProbe[] activeProbes = FindAllMonoBehaviours()
                .Where(item => item.isActiveAndEnabled)
                .OfType<IArrowEscapeReadOnlyProbe>()
                .ToArray();
            probe = activeProbes.Length == 1 ? activeProbes[0] : null;
            Check(step, "setup.probe",
                "exactly one active public read-only semantic probe",
                probe != null
                    ? "probe=" + probe.GetType().FullName
                    : "active probes=" + activeProbes.Length,
                probe != null,
                probe == null
                    ? "The public Unity v2 submission profile requires exactly one " +
                      "IArrowEscapeReadOnlyProbe."
                    : null);

            float deadline = Time.realtimeSinceStartup + StateTimeoutSeconds;
            VisibleGameState visible = ObserveVisibleState();
            while ((visible == null || visible.Arrows.Count == 0 ||
                    ResolveVisibleUiTarget(ArrowEscapeUiAction.Hint) == null ||
                    ResolveVisibleUiTarget(ArrowEscapeUiAction.Restart) == null ||
                    ResolveVisibleUiTarget(ArrowEscapeUiAction.NextLevel) == null) &&
                   Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                visible = ObserveVisibleState();
            }
            VisibleUiTarget visibleHint = ResolveVisibleUiTarget(
                ArrowEscapeUiAction.Hint, out string hintDiagnostic);
            VisibleUiTarget visibleRestart = ResolveVisibleUiTarget(
                ArrowEscapeUiAction.Restart, out string restartDiagnostic);
            VisibleUiTarget visibleNext = ResolveVisibleUiTarget(
                ArrowEscapeUiAction.NextLevel, out string nextDiagnostic);
            sceneReady = visible != null && visible.Arrows.Count > 0 &&
                         visibleHint != null && visibleRestart != null &&
                         visibleNext != null;
            string visibleSummary = visible == null ? "no visible state" : visible.Summary;
            if (!sceneReady)
            {
                visibleSummary += $"; hint={hintDiagnostic}; " +
                                  $"restart={restartDiagnostic}; " +
                                  $"next={nextDiagnostic}";
            }
            if (!sceneReady && !string.IsNullOrWhiteSpace(lastObservationFailure))
            {
                visibleSummary += "; scene_cross_check=" + lastObservationFailure;
            }
            Check(step, "setup.playable",
                "visible arrows plus Hint, Restart and Next Level normal-input controls",
                visibleSummary,
                sceneReady);
            FinishStep(step, started);
        }

        public void Capture(string alias, string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "capture_snapshot";
            float started = StartStep(step);
            ArrowEscapeGameSnapshot snapshot = Snapshot();
            if (snapshot == null)
            {
                Check(step, stepId + ".captured", "non-null snapshot", "null", false);
            }
            else
            {
                captures[alias] = Clone(snapshot);
                sceneCaptures[alias] = SceneStateSignature();
                step.post_snapshot = SnapshotJson(snapshot);
                Check(step, stepId + ".captured", "snapshot alias " + alias,
                    SnapshotSummary(snapshot), true);
            }
            FinishStep(step, started);
        }

        public IEnumerator ClickArrow(string arrowId, string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "player_pointer_click_arrow";
            step.target = "arrow:" + arrowId;
            step.pre_snapshot = SnapshotJson(Snapshot());
            IArrowEscapeInputTarget[] targets = FindAllMonoBehaviours()
                .Where(item => item.isActiveAndEnabled)
                .OfType<IArrowEscapeInputTarget>()
                .Where(item => string.Equals(item.ArrowId, arrowId, StringComparison.Ordinal))
                .ToArray();
            IArrowEscapeInputTarget target = targets.Length == 1 ? targets[0] : null;
            yield return driver.Click(target?.PointerTarget, stepId + ".input", step);
            step.post_snapshot = SnapshotJson(Snapshot());
            MergeStepStatus(step);
        }

        public IEnumerator ClickUi(ArrowEscapeUiAction action, string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "player_pointer_click_ui";
            step.target = "ui:" + action.ToString().ToLowerInvariant();
            step.pre_snapshot = SnapshotJson(Snapshot());

            VisibleUiTarget target = ResolveVisibleUiTarget(action,
                out string uiResolution);
            step.ui_resolution = target == null
                ? "failed: " + uiResolution
                : "visible semantic control via " + target.Technology + "; " +
                  uiResolution;
            yield return driver.Click(target, stepId + ".input", step);
            step.post_snapshot = SnapshotJson(Snapshot());
            MergeStepStatus(step);
        }

        public IEnumerator PerformBoundaryGesture(
            VisibleArrowTarget target,
            PointerBoundaryGesture gesture,
            string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "player_pointer_boundary";
            step.target = target?.StableKey ?? "<null>";
            step.pre_snapshot = SnapshotJson(Snapshot());
            yield return driver.BoundaryGesture(target?.PointerTarget,
                target?.Bounds, target?.SemanticId ?? target?.StableKey, gesture,
                stepId + ".input", step);
            step.post_snapshot = SnapshotJson(Snapshot());
            MergeStepStatus(step);
        }

        public IEnumerator CleanupBoundaryGesture() =>
            driver.CleanupBoundaryGesture();

        public IEnumerator ClickArrowContinuation(string arrowId)
        {
            IArrowEscapeInputTarget[] targets = FindAllMonoBehaviours()
                .Where(item => item.isActiveAndEnabled)
                .OfType<IArrowEscapeInputTarget>()
                .Where(item => string.Equals(item.ArrowId, arrowId, StringComparison.Ordinal))
                .ToArray();
            IArrowEscapeInputTarget target = targets.Length == 1 ? targets[0] : null;
            var diagnostic = new TrajectoryStepEvidence
            {
                step_id = "canonical.continuation.arrow",
                operation = "player_pointer_click_arrow",
                target = "arrow:" + arrowId
            };
            yield return driver.Click(target?.PointerTarget,
                "canonical.continuation.arrow.input", diagnostic);
        }

        public IEnumerator ClickUiContinuation(ArrowEscapeUiAction action)
        {
            VisibleUiTarget target = ResolveVisibleUiTarget(action,
                out string uiResolution);
            var diagnostic = new TrajectoryStepEvidence
            {
                step_id = "canonical.continuation.ui",
                operation = "player_pointer_click_ui",
                target = "ui:" + action.ToString().ToLowerInvariant(),
                ui_resolution = target == null
                    ? "failed: " + uiResolution
                    : "visible semantic control via " + target.Technology + "; " +
                      uiResolution
            };
            yield return driver.Click(target,
                "canonical.continuation.ui.input", diagnostic);
        }

        public IEnumerator WaitArrowStateContinuation(
            string arrowId,
            ArrowEscapeArrowState state)
        {
            float deadline = Time.realtimeSinceStartup + StateTimeoutSeconds;
            ArrowEscapeArrowSnapshot arrow = Snapshot()?.FindArrow(arrowId);
            while ((arrow == null || arrow.State != state) &&
                   Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                arrow = Snapshot()?.FindArrow(arrowId);
            }
        }

        public IEnumerator WaitArrowState(string arrowId, ArrowEscapeArrowState state, string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "wait_arrow_state";
            step.target = "arrow:" + arrowId;
            float started = StartStep(step);
            float deadline = Time.realtimeSinceStartup + StateTimeoutSeconds;
            ArrowEscapeArrowSnapshot arrow = Snapshot()?.FindArrow(arrowId);
            while ((arrow == null || arrow.State != state) && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                arrow = Snapshot()?.FindArrow(arrowId);
            }
            Check(step, stepId + ".reached", state.ToString(),
                arrow == null ? ObservationFailure ?? "missing" : arrow.State.ToString(),
                arrow != null && arrow.State == state);
            step.post_snapshot = SnapshotJson(Snapshot());
            FinishStep(step, started);
        }

        public IEnumerator WaitPhase(ArrowEscapeGamePhase phase, string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "wait_game_phase";
            float started = StartStep(step);
            float deadline = Time.realtimeSinceStartup + StateTimeoutSeconds;
            ArrowEscapeGameSnapshot snapshot = Snapshot();
            while ((snapshot == null || snapshot.Phase != phase) && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                snapshot = Snapshot();
            }
            Check(step, stepId + ".reached", phase.ToString(),
                snapshot == null ? "null" : snapshot.Phase.ToString(),
                snapshot != null && snapshot.Phase == phase);
            step.post_snapshot = SnapshotJson(snapshot);
            FinishStep(step, started);
        }

        public void Expect(
            string stepId, string checkId, string expected, string observed, bool passed, string message = null)
        {
            TrajectoryStepEvidence step = Step(stepId);
            if (string.IsNullOrEmpty(step.operation)) step.operation = "assert_state";
            float started = step.frame_start == 0 ? StartStep(step) : Time.realtimeSinceStartup;
            Check(step, checkId, expected, observed, passed, message);
            if (step.frame_end == 0) FinishStep(step, started);
            else MergeStepStatus(step);
        }

        public void AliasStepChecks(string sourceStepId, string destinationPrefix)
        {
            if (string.IsNullOrWhiteSpace(sourceStepId) ||
                string.IsNullOrWhiteSpace(destinationPrefix) ||
                !stepById.TryGetValue(sourceStepId, out TrajectoryStepEvidence source))
            {
                return;
            }

            TrajectoryStepEvidence destination = Step("declared.scoring_checks");
            foreach (TrajectoryCheckEvidence check in source.checks.ToArray())
            {
                if (check == null || string.IsNullOrWhiteSpace(check.check_id) ||
                    !check.check_id.StartsWith(sourceStepId, StringComparison.Ordinal))
                {
                    continue;
                }

                string alias = destinationPrefix + check.check_id.Substring(sourceStepId.Length);
                if (string.Equals(check.status, "blocked", StringComparison.Ordinal))
                {
                    Block(destination, alias, check.blocked_by);
                }
                else
                {
                    Check(destination, alias, check.expected, check.observed,
                        string.Equals(check.status, "pass", StringComparison.Ordinal), check.message);
                }
            }
            MergeStepStatus(destination);
        }

        public void ExpectSnapshotEquivalent(string baseline, string stepId, string checkId)
        {
            ArrowEscapeGameSnapshot expected = captures.TryGetValue(baseline, out ArrowEscapeGameSnapshot value)
                ? value
                : null;
            ArrowEscapeGameSnapshot actual = Snapshot();
            string expectedScene = sceneCaptures.TryGetValue(baseline, out string sceneValue)
                ? sceneValue
                : null;
            string actualScene = SceneStateSignature();
            bool same = RestartEquivalent(expected, actual) && expectedScene != null &&
                        string.Equals(expectedScene, actualScene, StringComparison.Ordinal);
            Expect(stepId, checkId, expected == null ? "captured baseline" : SnapshotSummary(expected),
                actual == null ? lastObservationFailure ?? "null" :
                    SnapshotSummary(actual) + "; scene=" +
                    (string.Equals(expectedScene, actualScene, StringComparison.Ordinal)
                        ? "equivalent"
                        : "different"), same,
                "Restart did not restore the authored level, budget, arrows, locks, badges, Hint, " +
                "recent-input state, UI state, real scene geometry, and a newer public revision.");
        }

        public IEnumerator ObserveFeedback(
            GameObject visualTarget,
            string baseline,
            float minVisibleSeconds,
            float recoverWithinSeconds,
            string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "observe_visual_feedback";
            step.target = visualTarget == null ? "<null>" : visualTarget.name;
            float started = StartStep(step);
            if (visualTarget == null)
            {
                Check(step, stepId + ".changed", "visible change", "missing target", false);
                Block(step, stepId + ".duration", stepId + ".changed");
                Block(step, stepId + ".recovered", stepId + ".changed");
                FinishStep(step, started);
                yield break;
            }

            bool changed = !string.Equals(VisualSignature(visualTarget), baseline, StringComparison.Ordinal);
            float changeDeadline = Time.realtimeSinceStartup + 0.6f;
            while (!changed && Time.realtimeSinceStartup < changeDeadline)
            {
                yield return null;
                changed = !string.Equals(VisualSignature(visualTarget), baseline, StringComparison.Ordinal);
            }
            Check(step, stepId + ".changed", "visual differs from baseline",
                changed ? "changed" : "unchanged", changed);

            if (changed)
            {
                float feedbackStart = Time.realtimeSinceStartup;
                float remainUntil = feedbackStart + minVisibleSeconds;
                bool remained = true;
                while (Time.realtimeSinceStartup < remainUntil)
                {
                    yield return null;
                    remained &= !string.Equals(VisualSignature(visualTarget), baseline, StringComparison.Ordinal);
                }
                Check(step, stepId + ".duration", $">={minVisibleSeconds:F2}s",
                    remained ? "visible" : "recovered too early", remained);

                float recoverDeadline = feedbackStart + recoverWithinSeconds;
                while (!string.Equals(VisualSignature(visualTarget), baseline, StringComparison.Ordinal) &&
                       Time.realtimeSinceStartup < recoverDeadline)
                {
                    yield return null;
                }
                bool recovered = string.Equals(VisualSignature(visualTarget), baseline, StringComparison.Ordinal);
                Check(step, stepId + ".recovered", $"baseline within {recoverWithinSeconds:F2}s",
                    recovered ? "baseline" : "still changed", recovered);
            }
            else
            {
                Block(step, stepId + ".duration", stepId + ".changed");
                Block(step, stepId + ".recovered", stepId + ".changed");
            }
            FinishStep(step, started);
        }

        public IEnumerator ObserveFeedback(
            VisibleArrowTarget target,
            string baseline,
            float minVisibleSeconds,
            float recoverWithinSeconds,
            string stepId)
        {
            if (target?.PointerTarget != null)
            {
                yield return ObserveFeedback(target.PointerTarget, baseline,
                    minVisibleSeconds, recoverWithinSeconds, stepId);
                yield break;
            }

            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "observe_visible_geometry_feedback";
            step.target = target?.SemanticId ?? target?.StableKey ?? "<null>";
            float started = StartStep(step);
            Check(step, stepId + ".changed",
                "real visible target geometry available for feedback observation",
                "missing physical target", false);
            Block(step, stepId + ".duration", stepId + ".changed");
            Block(step, stepId + ".recovered", stepId + ".changed");
            FinishStep(step, started);
        }

        public IEnumerator ClickAndObserveExit(
            ArrowEscapeLevelSpec level,
            string arrowId,
            string stepId)
        {
            TrajectoryStepEvidence step = Step(stepId);
            step.operation = "player_click_and_observe_complete_exit";
            step.target = "arrow:" + arrowId;
            IArrowEscapeInputTarget[] inputTargets = FindAllMonoBehaviours()
                .Where(item => item.isActiveAndEnabled)
                .OfType<IArrowEscapeInputTarget>()
                .Where(item => string.Equals(item.ArrowId, arrowId, StringComparison.Ordinal))
                .ToArray();
            IArrowEscapeInputTarget inputTarget = inputTargets.Length == 1 ? inputTargets[0] : null;
            GameObject target = inputTarget?.PointerTarget;
            Rect initialBounds = target == null ? default : VisibleScreenRect(target);
            ArrowEscapeArrowSpec spec = level.Arrows.First(item => item.Id == arrowId);
            Vector2 expectedDirection = HeadDirection(spec);
            float started = StartStep(step);
            step.pre_snapshot = SnapshotJson(Snapshot());

            yield return driver.Click(target, stepId + ".input", step);
            ArrowEscapeArrowSnapshot afterClick = Snapshot()?.FindArrow(arrowId);
            Check(step, stepId + ".moving", ArrowEscapeArrowState.Moving.ToString(),
                afterClick == null ? "missing" : afterClick.State.ToString(),
                afterClick != null && (afterClick.State == ArrowEscapeArrowState.Moving ||
                                       afterClick.State == ArrowEscapeArrowState.Exited));

            int samples = 0;
            int forwardSamples = 0;
            float lastDistinctProjection = 0f;
            if (afterClick != null && afterClick.State == ArrowEscapeArrowState.Moving)
            {
                float deadline = Time.realtimeSinceStartup + StateTimeoutSeconds;
                while (Time.realtimeSinceStartup < deadline)
                {
                    ArrowEscapeArrowSnapshot current = Snapshot()?.FindArrow(arrowId);
                    if (current == null || current.State != ArrowEscapeArrowState.Moving) break;
                    yield return null;
                    current = Snapshot()?.FindArrow(arrowId);
                    if (current == null || current.State != ArrowEscapeArrowState.Moving) break;
                    Rect bounds = VisibleScreenRect(target);
                    Vector2 displacement = bounds.center - initialBounds.center;
                    float projection = Vector2.Dot(displacement, expectedDirection);
                    if (projection > lastDistinctProjection + 0.5f)
                    {
                        forwardSamples++;
                        lastDistinctProjection = projection;
                    }
                    samples++;
                }
            }
            ArrowEscapeArrowSnapshot exited = Snapshot()?.FindArrow(arrowId);
            Check(step, stepId + ".continuous_frames", ">=3 moving frames",
                samples.ToString(), samples >= 3);
            Check(step, stepId + ".forward_motion", ">=2 distinct forward samples",
                forwardSamples.ToString(), forwardSamples >= 2);
            Check(step, stepId + ".full_exit", "Exited with empty occupancy",
                exited == null ? ObservationFailure ?? "missing" : exited.State + "/cells=" +
                    (exited.OccupiedCells == null ? -1 : exited.OccupiedCells.Length),
                IsCompleteExit(exited));
            step.post_snapshot = SnapshotJson(Snapshot());
            FinishStep(step, started);
        }

        public IArrowEscapeInputTarget FindArrowTarget(string arrowId)
        {
            IArrowEscapeInputTarget[] targets = FindAllMonoBehaviours()
                .Where(item => item.isActiveAndEnabled)
                .OfType<IArrowEscapeInputTarget>()
                .Where(item => string.Equals(item.ArrowId, arrowId, StringComparison.Ordinal))
                .ToArray();
            return targets.Length == 1 ? targets[0] : null;
        }

        public ArrowEscapeGameSnapshot Snapshot()
        {
            ArrowEscapeGameSnapshot snapshot = probe?.CaptureBenchmarkSnapshot();
            if (ValidateSnapshotAgainstScene(snapshot, out string failure))
            {
                lastObservationFailure = null;
                return snapshot;
            }

            lastObservationFailure = failure;
            return null;
        }

        public int InputTargetCount() =>
            FindAllMonoBehaviours()
                .Where(item => item.isActiveAndEnabled)
                .OfType<IArrowEscapeInputTarget>()
                .Count();

        public string VisualSignatureForArrow(string arrowId) =>
            VisualSignature(FindArrowTarget(arrowId)?.PointerTarget);

        public string SpatialSignatureForArrow(string arrowId) =>
            SpatialSignature(FindArrowTarget(arrowId)?.PointerTarget);

        public IEnumerator Delay(float seconds)
        {
            float until = Time.realtimeSinceStartup + seconds;
            while (Time.realtimeSinceStartup < until) yield return null;
        }

        public IEnumerator CaptureVisual(string stateId)
        {
            // WaitForEndOfFrame does not advance reliably in headless/batchmode
            // Test Runner sessions. Two normal player-loop frames settle layout
            // without turning the D6 side capture into a Dynamic hang.
            yield return null;
            yield return null;
            string directory = Path.Combine(
                TrajectoryEvidenceWriter.ResolveOutputDirectory(), "visual");
            Directory.CreateDirectory(directory);
            string path = Path.Combine(directory, stateId + ".png");
            Texture2D texture = null;
            string captureMethod = null;
            bool includesOverlay = false;
            try
            {
                // Camera.Render() only captures world-space content and silently
                // omits a ScreenSpaceOverlay Canvas. The formal visual state is a
                // player Game view, so use Unity's back-buffer capture first; it
                // includes the candidate's real overlay HUD and controls.
                texture = ScreenCapture.CaptureScreenshotAsTexture();
                if (texture == null || texture.width != 1280 || texture.height != 720)
                {
                    if (texture != null) UnityEngine.Object.Destroy(texture);
                    texture = null;
                    File.WriteAllText(path + ".error.txt",
                        "ScreenCapture.CaptureScreenshotAsTexture did not return the formal 1280x720 Game view.");
                    yield break;
                }
                captureMethod = "ScreenCapture.CaptureScreenshotAsTexture";
                includesOverlay = true;
                byte[] png = texture.EncodeToPNG();
                File.WriteAllBytes(path, png);
                string hash;
                using (var sha = System.Security.Cryptography.SHA256.Create())
                {
                    hash = BitConverter.ToString(sha.ComputeHash(png))
                        .Replace("-", string.Empty)
                        .ToLowerInvariant();
                }
                var receipt = new VisualCaptureReceipt
                {
                    state_id = stateId,
                    status = "captured",
                    file = Path.GetFileName(path),
                    width = texture.width,
                    height = texture.height,
                    bytes = png.LongLength,
                    sha256 = hash,
                    capture_method = captureMethod,
                    includes_screen_space_overlay = includesOverlay,
                    process_id = System.Diagnostics.Process.GetCurrentProcess().Id,
                    frame = Time.frameCount,
                    captured_utc = DateTime.UtcNow.ToString("O")
                };
                File.WriteAllText(path + ".receipt.json",
                    JsonUtility.ToJson(receipt, true));
            }
            catch (Exception exception)
            {
                File.WriteAllText(path + ".error.txt", exception.ToString());
            }
            finally
            {
                if (texture != null) UnityEngine.Object.Destroy(texture);
            }
        }

        public IEnumerator Dispose() => driver.Dispose();

        public string Complete()
        {
            SealEvidence();
            return TrajectoryEvidenceWriter.Write(Evidence);
        }

        internal void SealEvidenceForEvaluatorRegression() => SealEvidence();

        private void SealEvidence()
        {
            CompleteMissingEvidence();
            IEnumerable<TrajectoryCheckEvidence> checks = Evidence.steps.SelectMany(step => step.checks);
            Evidence.checks_passed = checks.Count(check => check.status == "pass");
            Evidence.checks_failed = checks.Count(check => check.status == "fail");
            Evidence.checks_blocked = checks.Count(check => check.status == "blocked");
            Evidence.passed = Evidence.checks_failed == 0 && Evidence.checks_blocked == 0;
            Evidence.failure = Evidence.steps.SelectMany(step => step.checks)
                .FirstOrDefault(check => check.status == "fail")?.message;
        }

        private TrajectoryStepEvidence Step(string id)
        {
            if (stepById.TryGetValue(id, out TrajectoryStepEvidence existing)) return existing;
            TrajectoryDefinitionStep declared = definition.steps?
                .FirstOrDefault(item => string.Equals(item.step_id, id, StringComparison.Ordinal));
            var step = new TrajectoryStepEvidence
            {
                step_id = id,
                operation = declared?.operation,
                target = declared?.target
            };
            stepById.Add(id, step);
            Evidence.steps.Add(step);
            return step;
        }

        private float StartStep(TrajectoryStepEvidence step)
        {
            step.frame_start = Time.frameCount;
            return Time.realtimeSinceStartup;
        }

        private void FinishStep(TrajectoryStepEvidence step, float started)
        {
            step.frame_end = Time.frameCount;
            step.elapsed_ms = Math.Max(0.0, (Time.realtimeSinceStartup - started) * 1000.0);
            MergeStepStatus(step);
        }

        private void MergeStepStatus(TrajectoryStepEvidence step)
        {
            step.status = step.checks.Any(check => check.status == "fail")
                ? "fail"
                : step.checks.Any(check => check.status == "blocked")
                    ? "blocked"
                    : step.checks.Count > 0 ? "pass" : step.status;
            step.message = step.checks.FirstOrDefault(check => check.status == "fail")?.message;
        }

        private void Check(TrajectoryStepEvidence step, string id, string expected,
            string observed, bool passed, string message = null)
        {
            TrajectoryCheckEvidence existing = step.checks
                .FirstOrDefault(check => string.Equals(check.check_id, id, StringComparison.Ordinal));
            if (existing != null) return;
            step.checks.Add(new TrajectoryCheckEvidence
            {
                check_id = id,
                expected = expected,
                observed = observed,
                status = passed ? "pass" : "fail",
                message = passed ? null : message ?? $"Expected {expected}, observed {observed}."
            });
            if (!passed && string.IsNullOrEmpty(firstFailureCheck)) firstFailureCheck = id;
        }

        private void Block(TrajectoryStepEvidence step, string id, string blockedBy)
        {
            if (step.checks.Any(check => string.Equals(check.check_id, id, StringComparison.Ordinal))) return;
            step.checks.Add(new TrajectoryCheckEvidence
            {
                check_id = id,
                status = "blocked",
                blocked_by = blockedBy,
                message = "Check was not executable after an earlier trajectory failure."
            });
        }

        private void CompleteMissingEvidence()
        {
            string blocker = firstFailureCheck ?? "trajectory.not_executed";
            HashSet<string> observed = Evidence.steps
                .SelectMany(item => item.checks)
                .Where(item => item != null && !string.IsNullOrWhiteSpace(item.check_id))
                .Select(item => item.check_id)
                .ToHashSet(StringComparer.Ordinal);
            foreach (TrajectoryDefinitionStep declared in definition.steps ?? Array.Empty<TrajectoryDefinitionStep>())
            {
                TrajectoryStepEvidence step = Step(declared.step_id);
                foreach (string checkId in declared.check_ids ?? Array.Empty<string>())
                {
                    if (!observed.Contains(checkId))
                    {
                        Block(step, checkId, blocker);
                    }
                }
                MergeStepStatus(step);
            }
        }

        private bool ValidateSnapshotAgainstScene(
            ArrowEscapeGameSnapshot snapshot,
            out string failure)
        {
            failure = null;
            try
            {
                Scene activeScene = SceneManager.GetActiveScene();
                if (!activeScene.IsValid() || !activeScene.isLoaded ||
                    !string.Equals(activeScene.path,
                        ArrowEscapeContractConstants.MainScenePath,
                        StringComparison.Ordinal))
                {
                    failure = "The snapshot was not captured from the active canonical scene.";
                    return false;
                }

                if (snapshot == null || snapshot.Arrows == null ||
                    snapshot.VisibleTargets == null)
                {
                    failure = "CaptureBenchmarkSnapshot returned null or omitted arrows/visible targets.";
                    return false;
                }

                ArrowEscapeArrowSnapshot[] arrows = snapshot.Arrows
                    .Where(item => item != null)
                    .ToArray();
                if (arrows.Length != snapshot.Arrows.Length ||
                    arrows.Any(item => string.IsNullOrWhiteSpace(item.Id)) ||
                    arrows.Select(item => item.Id)
                        .Distinct(StringComparer.Ordinal).Count() != arrows.Length)
                {
                    failure = "The snapshot contains null, empty, or duplicate arrow IDs.";
                    return false;
                }

                ArrowEscapeVisibleTargetSnapshot[] registry = snapshot.VisibleTargets
                    .Where(item => item != null)
                    .ToArray();
                if (registry.Length != snapshot.VisibleTargets.Length ||
                    registry.Any(item => string.IsNullOrWhiteSpace(item.Id)) ||
                    registry.GroupBy(item => item.Kind + ":" + item.Id,
                            StringComparer.Ordinal)
                        .Any(group => group.Count() != 1))
                {
                    failure = "The visible-target registry contains null, empty, or duplicate semantic entries.";
                    return false;
                }
                foreach (ArrowEscapeVisibleTargetSnapshot item in registry)
                {
                    if (item.Interactable && !item.Visible)
                    {
                        failure = $"Visible target '{item.Id}' is interactable while hidden.";
                        return false;
                    }
                    if (item.Visible && (!ArrowEscapeVisibleTargetUtility.IsFinite(item.ScreenRect) ||
                        item.ScreenRect.width < 2f || item.ScreenRect.height < 2f ||
                        item.ScreenRect.xMax <= 0f || item.ScreenRect.yMax <= 0f ||
                        item.ScreenRect.xMin >= Screen.width ||
                        item.ScreenRect.yMin >= Screen.height ||
                        string.IsNullOrWhiteSpace(item.VisualState)))
                    {
                        failure = $"Visible target '{item.Id}' has an invalid on-screen Rect or visual state.";
                        return false;
                    }
                }

                foreach (ArrowEscapeVisibleTargetKind kind in new[]
                         {
                             ArrowEscapeVisibleTargetKind.Hint,
                             ArrowEscapeVisibleTargetKind.Restart,
                             ArrowEscapeVisibleTargetKind.NextLevel
                         })
                {
                    ArrowEscapeVisibleTargetSnapshot[] controls = registry
                        .Where(item => item.Kind == kind)
                        .ToArray();
                    if (controls.Length != 1 || !controls[0].Visible)
                    {
                        failure = $"The public registry must expose one visible {kind} control.";
                        return false;
                    }

                    ArrowEscapeUiAction action = kind switch
                    {
                        ArrowEscapeVisibleTargetKind.Hint => ArrowEscapeUiAction.Hint,
                        ArrowEscapeVisibleTargetKind.Restart => ArrowEscapeUiAction.Restart,
                        ArrowEscapeVisibleTargetKind.NextLevel => ArrowEscapeUiAction.NextLevel,
                        _ => ArrowEscapeUiAction.Hint
                    };
                    VisibleUiTarget realControl = ResolveVisibleUiTarget(
                        action, controls[0], out _);
                    if (realControl == null)
                    {
                        failure = $"Visible {kind} registry entry does not map to exactly one " +
                                  "real visible player-input surface.";
                        return false;
                    }
                    if (realControl.Interactable != controls[0].Interactable)
                    {
                        failure = $"Visible {kind} registry Interactable=" +
                                  $"{controls[0].Interactable} disagrees with the real control.";
                        return false;
                    }
                }

                IArrowEscapeInputTarget[] allTargets = FindAllMonoBehaviours()
                    .OfType<IArrowEscapeInputTarget>()
                    .Where(item => item != null &&
                                   !string.IsNullOrWhiteSpace(item.ArrowId) &&
                                   item.PointerTarget != null &&
                                   item.PointerTarget.scene == activeScene)
                    .ToArray();
                IArrowEscapeInputTarget[] activeTargets = allTargets
                    .Where(item => item is MonoBehaviour behaviour &&
                                   behaviour.isActiveAndEnabled &&
                                   item.PointerTarget.activeInHierarchy)
                    .ToArray();

                if (activeTargets.GroupBy(item => item.ArrowId, StringComparer.Ordinal)
                    .Any(group => group.Count() != 1))
                {
                    failure = "The real scene exposes duplicate active pointer targets for one arrow ID.";
                    return false;
                }

                if (activeTargets.Any(target => arrows.All(arrow => !string.Equals(
                        arrow.Id, target.ArrowId, StringComparison.Ordinal))))
                {
                    failure = "A real active arrow target is absent from the public snapshot.";
                    return false;
                }

                List<VisibleArrowTarget> physicalArrows = DiscoverPhysicalArrowTargets();
                var claimedPhysicalArrows = new HashSet<int>();

                foreach (ArrowEscapeArrowSnapshot arrow in arrows)
                {
                    ArrowEscapeVisibleTargetSnapshot[] registered = registry
                        .Where(item => item.Kind == ArrowEscapeVisibleTargetKind.Arrow &&
                            string.Equals(item.Id, arrow.Id, StringComparison.Ordinal))
                        .ToArray();
                    IArrowEscapeInputTarget[] matchingActive = activeTargets
                        .Where(item => string.Equals(item.ArrowId, arrow.Id,
                            StringComparison.Ordinal))
                        .ToArray();
                    bool shouldBeActive = arrow.State != ArrowEscapeArrowState.Exited;
                    if (registered.Length != (shouldBeActive ? 1 : 0) ||
                        (shouldBeActive && !registered[0].Visible))
                    {
                        failure = $"Arrow '{arrow.Id}' reports {arrow.State}, but its visible " +
                                  $"semantic registry count is {registered.Length}.";
                        return false;
                    }

                    if (shouldBeActive)
                    {
                        ArrowEscapeVisibleTargetSnapshot semantic = registered[0];
                        bool shouldInteract = snapshot.Phase == ArrowEscapeGamePhase.Playing &&
                                              arrow.State != ArrowEscapeArrowState.Moving;
                        if (semantic.Interactable != shouldInteract)
                        {
                            failure = $"Arrow '{arrow.Id}' registry Interactable={semantic.Interactable} " +
                                      $"does not match phase/state {snapshot.Phase}/{arrow.State}.";
                            return false;
                        }
                        if (matchingActive.Length > 1)
                        {
                            failure = $"Arrow '{arrow.Id}' exposes duplicate optional GameObject adapters.";
                            return false;
                        }

                        VisibleArrowTarget physical = matchingActive.Length == 1
                            ? physicalArrows.FirstOrDefault(item =>
                                item.PointerTarget == matchingActive[0].PointerTarget)
                            : null;
                        if (physical == null)
                        {
                            VisibleArrowTarget[] geometryMatches = physicalArrows
                                .Where(item => PhysicalRectMatchesSemantic(
                                    item.Bounds, semantic.ScreenRect))
                                .ToArray();
                            physical = geometryMatches.Length == 1
                                ? geometryMatches[0]
                                : null;
                        }
                        bool rectCorroborated = matchingActive.Length == 1
                            ? PhysicalRectCorroboratesSemantic(
                                physical?.Bounds ?? default, semantic.ScreenRect)
                            : PhysicalRectMatchesSemantic(
                                physical?.Bounds ?? default, semantic.ScreenRect);
                        if (physical?.PointerTarget == null ||
                            !HasVisibleGeometry(physical.PointerTarget) ||
                            !rectCorroborated)
                        {
                            failure = $"Arrow '{arrow.Id}' semantic registry entry has no " +
                                      "independently visible matching GameObject geometry.";
                            return false;
                        }
                        if (!claimedPhysicalArrows.Add(
                                physical.PointerTarget.GetInstanceID()))
                        {
                            failure = $"Multiple arrow IDs map to the same real visible target " +
                                      $"('{arrow.Id}').";
                            return false;
                        }

                        bool realKey = HasVisibleBadge(physical.PointerTarget, "key");
                        bool realLock = HasVisibleBadge(physical.PointerTarget, "lock");
                        if (arrow.HasKeyBadge != realKey || arrow.HasLockBadge != realLock)
                        {
                            failure = $"Arrow '{arrow.Id}' snapshot badges disagree with real " +
                                      $"visible badge objects (key={realKey}, lock={realLock}).";
                            return false;
                        }
                    }
                    else if (arrow.HasKeyBadge || arrow.HasLockBadge)
                    {
                        failure = $"Exited arrow '{arrow.Id}' still reports a visible badge.";
                        return false;
                    }
                }

                VisibleArrowTarget unclaimedPhysical = physicalArrows.FirstOrDefault(item =>
                    item?.PointerTarget != null &&
                    !claimedPhysicalArrows.Contains(item.PointerTarget.GetInstanceID()));
                if (unclaimedPhysical != null)
                {
                    failure = "A real visible arrow-like player target is absent from the " +
                              "truthful semantic registry: " + unclaimedPhysical.PointerTarget.name;
                    return false;
                }

                List<string> visibleTexts = VisibleUiTexts();
                bool completedVisible = visibleTexts.Any(text =>
                    string.Equals(text.Trim(), "COMPLETED",
                        StringComparison.OrdinalIgnoreCase));
                bool failedVisible = visibleTexts.Any(text =>
                    string.Equals(text.Trim(), "FAILED",
                        StringComparison.OrdinalIgnoreCase));
                if (snapshot.CompletedUiVisible != completedVisible ||
                    snapshot.FailedUiVisible != failedVisible)
                {
                    failure = "Terminal snapshot flags disagree with real visible UI text.";
                    return false;
                }

                int activeArrowCount = arrows.Count(item =>
                    item.State != ArrowEscapeArrowState.Exited);
                bool phaseConsistent = snapshot.Phase switch
                {
                    ArrowEscapeGamePhase.Playing => !completedVisible && !failedVisible &&
                                                    activeArrowCount > 0,
                    ArrowEscapeGamePhase.Won => completedVisible && !failedVisible &&
                                                activeArrowCount == 0,
                    ArrowEscapeGamePhase.Lost => failedVisible && !completedVisible &&
                                                 activeArrowCount > 0,
                    _ => false
                };
                if (!phaseConsistent)
                {
                    failure = "Game phase disagrees with real terminal UI and active arrow objects.";
                    return false;
                }

                if (!VisibleLevelMatchesSnapshot(visibleTexts, snapshot.LevelId) ||
                    !VisibleBudgetMatchesSnapshot(visibleTexts,
                        snapshot.BudgetMode, snapshot.RemainingBudget))
                {
                    failure = "Level or budget snapshot values disagree with the visible HUD.";
                    return false;
                }

                return true;
            }
            catch (Exception exception)
            {
                failure = "Scene cross-check threw " + exception.GetType().Name +
                          ": " + exception.Message;
                return false;
            }
        }

        private string SceneStateSignature()
        {
            ArrowEscapeGameSnapshot snapshot = probe?.CaptureBenchmarkSnapshot();
            IEnumerable<string> semantic = (snapshot?.VisibleTargets ??
                    Array.Empty<ArrowEscapeVisibleTargetSnapshot>())
                .Where(item => item != null)
                .OrderBy(item => item.Kind)
                .ThenBy(item => item.Id, StringComparer.Ordinal)
                .Select(item => $"SEM:{item.Kind}:{item.Id}:{item.Visible}:" +
                    $"{item.Interactable}:{item.ScreenRect.x:F1},{item.ScreenRect.y:F1}," +
                    $"{item.ScreenRect.width:F1},{item.ScreenRect.height:F1}:" +
                    (item.VisualState ?? "<null>"));
            IEnumerable<string> physicalArrows = FindVisibleArrowTargets()
                .OrderBy(item => item.SemanticId, StringComparer.Ordinal)
                .Select(item => "PHYSICAL:" + item.SemanticId + ":" +
                                SpatialSignature(item.PointerTarget) +
                                ":bounds=" + item.Bounds +
                                ":key=" + item.HasKeyBadge +
                                ":lock=" + item.HasLockBadge +
                                ":style=" + item.StyleSignature);
            IEnumerable<string> physicalUi = Enum.GetValues(typeof(ArrowEscapeUiAction))
                .Cast<ArrowEscapeUiAction>()
                .SelectMany(action => DiscoverPhysicalUiTargets(action)
                    .Select(item => "UI:" + action + ":" + item.Interactable + ":" +
                                    item.Bounds + ":" + SpatialSignature(item.PointerTarget)))
                .OrderBy(item => item, StringComparer.Ordinal);
            return string.Join("|", semantic.Concat(physicalArrows).Concat(physicalUi)
                .Concat(VisibleUiTexts().OrderBy(item => item, StringComparer.Ordinal)
                    .Select(item => "TEXT:" + item)));
        }

        private static string SpatialSignature(GameObject target)
        {
            if (target == null) return "<null>";
            var parts = new List<string>
            {
                $"root={target.activeInHierarchy}:{target.transform.position:F2}:" +
                $"{target.transform.localPosition:F2}"
            };
            foreach (Transform transform in target.GetComponentsInChildren<Transform>(true)
                         .OrderBy(item => item.name, StringComparer.Ordinal))
            {
                parts.Add($"T:{transform.name}:{transform.gameObject.activeInHierarchy}:" +
                          $"{transform.position:F2}:{transform.localPosition:F2}");
            }
            foreach (Collider2D collider in target.GetComponentsInChildren<Collider2D>(true)
                         .OrderBy(item => item.name, StringComparer.Ordinal))
            {
                parts.Add($"C2:{collider.name}:{collider.enabled}:{collider.offset:F2}");
            }
            return string.Join(";", parts);
        }

        private static bool HasVisibleGeometry(GameObject target)
        {
            if (target == null) return false;
            return target.GetComponentsInChildren<Renderer>(true).Any(item =>
                       item != null && item.enabled && item.gameObject.activeInHierarchy) ||
                   target.GetComponentsInChildren<Graphic>(true).Any(item =>
                       item != null && item.enabled && item.gameObject.activeInHierarchy &&
                       item.canvasRenderer != null &&
                       item.canvasRenderer.GetAlpha() > 0.01f);
        }

        private static bool HasEnabledPointerSurface(GameObject target)
        {
            if (target == null) return false;
            return target.GetComponentsInChildren<Collider2D>(true).Any(item =>
                       item != null && item.enabled && item.gameObject.activeInHierarchy) ||
                   target.GetComponentsInChildren<Graphic>(true).Any(item =>
                       item != null && item.enabled && item.raycastTarget &&
                        item.gameObject.activeInHierarchy);
        }

        private static bool HasArrowInputSurfaceIdentity(GameObject target)
        {
            if (target == null) return false;
            return target.GetComponent<IArrowEscapeInputTarget>() != null ||
                   target.GetComponentsInChildren<Collider2D>(true).Any(item =>
                       item != null) ||
                   target.GetComponentsInChildren<Graphic>(true).Any(item =>
                       item != null && item.raycastTarget);
        }

        private static bool HasVisibleBadge(GameObject target, string keyword)
        {
            if (target == null) return false;
            return target.GetComponentsInChildren<Transform>(true)
                .Where(item => item != target.transform && item.gameObject.activeInHierarchy)
                .Any(item =>
                {
                    bool named = item.name.IndexOf(keyword,
                        StringComparison.OrdinalIgnoreCase) >= 0;
                    SpriteRenderer spriteRenderer = item.GetComponent<SpriteRenderer>();
                    Image image = item.GetComponent<Image>();
                    bool spriteNamed = spriteRenderer != null &&
                        spriteRenderer.sprite != null &&
                        spriteRenderer.sprite.name.IndexOf(keyword,
                            StringComparison.OrdinalIgnoreCase) >= 0;
                    bool imageNamed = image != null && image.sprite != null &&
                        image.sprite.name.IndexOf(keyword,
                            StringComparison.OrdinalIgnoreCase) >= 0;
                    bool visible = (spriteRenderer != null && spriteRenderer.enabled) ||
                                   (image != null && image.enabled &&
                                    image.canvasRenderer.GetAlpha() > 0.01f);
                    return visible && (named || spriteNamed || imageNamed);
                });
        }

        private static List<string> VisibleUiTexts()
        {
            return VisibleUiTextSurfaces().Select(item => item.Text).ToList();
        }

        private static List<VisibleTextSurface> VisibleUiTextSurfaces()
        {
            var surfaces = new List<VisibleTextSurface>();
            foreach (Text text in UnityEngine.Object.FindObjectsByType<Text>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (text != null && text.isActiveAndEnabled &&
                    text.canvasRenderer.GetAlpha() > 0.01f &&
                    RectOverlapsScreen(text.rectTransform) &&
                    !string.IsNullOrWhiteSpace(text.text))
                {
                    surfaces.Add(new VisibleTextSurface
                    {
                        Text = text.text,
                        Bounds = VisibleScreenRect(text.gameObject)
                    });
                }
            }

            foreach (MonoBehaviour component in FindAllMonoBehaviours())
            {
                if (component == null || !component.isActiveAndEnabled ||
                    component is Text ||
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
                if (!string.IsNullOrWhiteSpace(value) &&
                    component.transform is RectTransform rect && RectOverlapsScreen(rect))
                {
                    surfaces.Add(new VisibleTextSurface
                    {
                        Text = value,
                        Bounds = VisibleScreenRect(component.gameObject)
                    });
                }
            }

            Type documentType = Type.GetType(
                "UnityEngine.UIElements.UIDocument, UnityEngine.UIElementsModule");
            if (documentType != null)
            {
                System.Reflection.PropertyInfo rootProperty =
                    documentType.GetProperty("rootVisualElement");
                foreach (UnityEngine.Object document in UnityEngine.Object.FindObjectsByType(
                             documentType, FindObjectsInactive.Exclude,
                             FindObjectsSortMode.None))
                {
                    object root = rootProperty?.GetValue(document);
                    if (root == null) continue;
                    Rect rootRect = ReflectionRect(root, "contentRect");
                    foreach (object element in TraverseVisualElements(root))
                    {
                        string value = ReflectionString(element, "text");
                        Rect panelRect = ReflectionRect(element, "worldBound");
                        Rect screenRect = PanelRectToScreen(panelRect, rootRect);
                        if (!string.IsNullOrWhiteSpace(value) &&
                            screenRect.width >= 1f && screenRect.height >= 1f &&
                            screenRect.xMax > 0f && screenRect.yMax > 0f &&
                            screenRect.xMin < Screen.width && screenRect.yMin < Screen.height)
                        {
                            surfaces.Add(new VisibleTextSurface
                            {
                                Text = value,
                                Bounds = screenRect
                            });
                        }
                    }
                }
            }
            return surfaces;
        }

        private static bool FullyInsidePlayerFrame(Rect rect)
        {
            const float margin = 2f;
            return ArrowEscapeVisibleTargetUtility.IsFinite(rect) &&
                   rect.width >= 2f && rect.height >= 2f &&
                   rect.xMin >= margin && rect.yMin >= margin &&
                   rect.xMax <= Screen.width - margin &&
                   rect.yMax <= Screen.height - margin;
        }

        // A Button's interactive root may include a small transparent label/layout
        // overhang even when the rendered control is fully readable in the Game
        // view. Keep text/board checks strict, but allow a bounded five-pixel edge
        // tolerance for the control envelope. Larger overhangs remain a real
        // player-surface failure.
        internal static bool PlayerSurfaceControlWithinFrame(Rect rect)
        {
            const float edgeTolerance = 5f;
            return ArrowEscapeVisibleTargetUtility.IsFinite(rect) &&
                   rect.width >= 2f && rect.height >= 2f &&
                   rect.xMin >= -edgeTolerance &&
                   rect.yMin >= -edgeTolerance &&
                   rect.xMax <= Screen.width + edgeTolerance &&
                   rect.yMax <= Screen.height + edgeTolerance;
        }

        private static bool RectOverlapsScreen(RectTransform rectTransform)
        {
            var corners = new Vector3[4];
            rectTransform.GetWorldCorners(corners);
            Canvas canvas = rectTransform.GetComponentInParent<Canvas>();
            Camera camera = ResolveScreenCamera(canvas);
            Vector2[] screenCorners = corners
                .Select(item => RectTransformUtility.WorldToScreenPoint(camera, item))
                .ToArray();
            float minX = screenCorners.Min(item => item.x);
            float maxX = screenCorners.Max(item => item.x);
            float minY = screenCorners.Min(item => item.y);
            float maxY = screenCorners.Max(item => item.y);
            return maxX - minX >= 1f && maxY - minY >= 1f &&
                   maxX > 0f && maxY > 0f &&
                   minX < Screen.width && minY < Screen.height;
        }

        private static bool ContainsIntegerToken(string text, int value)
        {
            string token = value.ToString();
            for (int index = 0; index <= text.Length - token.Length; index++)
            {
                if (!string.Equals(text.Substring(index, token.Length), token,
                        StringComparison.Ordinal)) continue;
                bool leftBoundary = index == 0 || !char.IsDigit(text[index - 1]);
                int right = index + token.Length;
                bool rightBoundary = right >= text.Length || !char.IsDigit(text[right]);
                if (leftBoundary && rightBoundary) return true;
            }
            return false;
        }

        internal static bool RestartEquivalent(
            ArrowEscapeGameSnapshot expected, ArrowEscapeGameSnapshot actual)
        {
            if (expected == null || actual == null || expected.LevelId != actual.LevelId ||
                expected.Phase != actual.Phase || expected.BudgetMode != actual.BudgetMode ||
                expected.InitialBudget != actual.InitialBudget ||
                expected.RemainingBudget != actual.RemainingBudget ||
                !SameOptionalId(expected.LastSelectedArrowId, actual.LastSelectedArrowId) ||
                expected.LastSelectionOutcome != actual.LastSelectionOutcome ||
                expected.LastInputSource != actual.LastInputSource ||
                !SameOptionalId(expected.LastHintArrowId, actual.LastHintArrowId) ||
                expected.CompletedUiVisible != actual.CompletedUiVisible ||
                expected.FailedUiVisible != actual.FailedUiVisible ||
                actual.StateRevision <= expected.StateRevision ||
                expected.Arrows == null || actual.Arrows == null ||
                expected.Arrows.Length != actual.Arrows.Length) return false;
            foreach (ArrowEscapeArrowSnapshot arrow in expected.Arrows)
            {
                ArrowEscapeArrowSnapshot other = actual.FindArrow(arrow.Id);
                if (other == null || other.State != arrow.State ||
                    other.HasKeyBadge != arrow.HasKeyBadge ||
                    other.HasLockBadge != arrow.HasLockBadge ||
                    other.OccupiedCells == null || arrow.OccupiedCells == null ||
                    !other.OccupiedCells.SequenceEqual(arrow.OccupiedCells)) return false;
            }
            return true;
        }

        private static bool SameOptionalId(string left, string right) =>
            string.Equals(left ?? string.Empty, right ?? string.Empty,
                StringComparison.Ordinal);

        internal static string VisualSignature(GameObject target)
        {
            if (target == null) return "<null>";
            var parts = new List<string>();
            foreach (Transform transform in target.GetComponentsInChildren<Transform>(true))
            {
                parts.Add($"T:{transform.name}:{transform.gameObject.activeSelf}:" +
                          $"{transform.localPosition:F3}:{transform.localScale:F3}");
            }
            foreach (SpriteRenderer renderer in target.GetComponentsInChildren<SpriteRenderer>(true))
            {
                if (!renderer.enabled || !renderer.gameObject.activeInHierarchy ||
                    renderer.color.a <= 0.001f)
                {
                    continue;
                }
                parts.Add($"S:{renderer.enabled}:{renderer.color}:{renderer.sprite?.name}");
            }
            foreach (LineRenderer line in target.GetComponentsInChildren<LineRenderer>(true))
            {
                if (!line.enabled || !line.gameObject.activeInHierarchy ||
                    (line.startColor.a <= 0.001f && line.endColor.a <= 0.001f))
                {
                    continue;
                }
                parts.Add($"L:{line.enabled}:{line.startColor}:{line.endColor}:" +
                          $"{line.startWidth:F3}:{line.positionCount}");
            }
            foreach (Graphic graphic in target.GetComponentsInChildren<Graphic>(true))
            {
                if (!graphic.enabled || !graphic.gameObject.activeInHierarchy ||
                    graphic.color.a <= 0.001f || graphic.canvasRenderer.GetAlpha() <= 0.001f ||
                    graphic is Text text && string.IsNullOrWhiteSpace(text.text))
                {
                    continue;
                }
                parts.Add($"G:{graphic.enabled}:{graphic.color}:{graphic.raycastTarget}");
            }
            return string.Join("|", parts);
        }

        internal static bool IsCompleteExit(ArrowEscapeArrowSnapshot arrow) =>
            arrow != null && arrow.State == ArrowEscapeArrowState.Exited &&
            arrow.OccupiedCells != null && arrow.OccupiedCells.Length == 0;

        internal static Rect VisibleScreenRect(GameObject target)
        {
            if (target == null) return default;
            Vector2 min = new Vector2(float.PositiveInfinity, float.PositiveInfinity);
            Vector2 max = new Vector2(float.NegativeInfinity, float.NegativeInfinity);
            bool found = false;
            foreach (Renderer renderer in target.GetComponentsInChildren<Renderer>(true)
                         .Where(item => item.enabled && item.gameObject.activeInHierarchy))
            {
                Camera camera = ResolveScreenCamera(null);
                if (camera == null) continue;
                Bounds bounds = renderer.bounds;
                for (int x = -1; x <= 1; x += 2)
                for (int y = -1; y <= 1; y += 2)
                for (int z = -1; z <= 1; z += 2)
                {
                    Vector3 screen = camera.WorldToScreenPoint(bounds.center +
                        Vector3.Scale(bounds.extents, new Vector3(x, y, z)));
                    if (screen.z < 0f) continue;
                    min = Vector2.Min(min, screen);
                    max = Vector2.Max(max, screen);
                    found = true;
                }
            }

            Graphic[] graphics = target.GetComponentsInChildren<Graphic>(true)
                .Where(item => item.enabled && item.gameObject.activeInHierarchy)
                .ToArray();
            foreach (Graphic graphic in graphics)
            {
                RectTransform rectTransform = graphic.rectTransform;
                Canvas canvas = graphic.canvas;
                Camera camera = ResolveScreenCamera(canvas);
                if (canvas != null && canvas.rootCanvas.renderMode != RenderMode.ScreenSpaceOverlay &&
                    camera == null)
                {
                    continue;
                }

                AddRectTransformScreenCorners(rectTransform, camera, ref min, ref max, ref found);
            }

            if (graphics.Length == 0 && target.transform is RectTransform targetRect &&
                target.activeInHierarchy)
            {
                Canvas canvas = target.GetComponentInParent<Canvas>();
                Camera camera = ResolveScreenCamera(canvas);
                if (canvas == null || canvas.rootCanvas.renderMode == RenderMode.ScreenSpaceOverlay ||
                    camera != null)
                {
                    AddRectTransformScreenCorners(targetRect, camera, ref min, ref max, ref found);
                }
            }

            if (!found) return new Rect(0f, 0f, 0f, 0f);
            return Rect.MinMaxRect(min.x, min.y, max.x, max.y);
        }

        private static void AddRectTransformScreenCorners(
            RectTransform rectTransform,
            Camera camera,
            ref Vector2 min,
            ref Vector2 max,
            ref bool found)
        {
            if (rectTransform == null) return;
            var corners = new Vector3[4];
            rectTransform.GetWorldCorners(corners);
            foreach (Vector3 corner in corners)
            {
                Vector2 screen = RectTransformUtility.WorldToScreenPoint(camera, corner);
                if (float.IsNaN(screen.x) || float.IsInfinity(screen.x) ||
                    float.IsNaN(screen.y) || float.IsInfinity(screen.y)) continue;
                min = Vector2.Min(min, screen);
                max = Vector2.Max(max, screen);
                found = true;
            }
        }

        private static Camera ResolveScreenCamera(Canvas canvas)
        {
            Canvas rootCanvas = canvas == null ? null : canvas.rootCanvas;
            if (rootCanvas != null && rootCanvas.renderMode == RenderMode.ScreenSpaceOverlay)
            {
                return null;
            }

            if (rootCanvas != null && rootCanvas.worldCamera != null &&
                rootCanvas.worldCamera.isActiveAndEnabled)
            {
                return rootCanvas.worldCamera;
            }

            if (Camera.main != null && Camera.main.isActiveAndEnabled)
            {
                return Camera.main;
            }

            return UnityEngine.Object.FindObjectsByType<Camera>(
                    FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
        }

        private static Vector2 HeadDirection(ArrowEscapeArrowSpec spec)
        {
            ArrowEscapeGridCell head = spec.Path[0];
            ArrowEscapeGridCell neck = spec.Path[1];
            return new Vector2(head.X - neck.X, head.Y - neck.Y).normalized;
        }

        private static ArrowEscapeGameSnapshot Clone(ArrowEscapeGameSnapshot snapshot) =>
            snapshot == null
                ? null
                : JsonUtility.FromJson<ArrowEscapeGameSnapshot>(JsonUtility.ToJson(snapshot));

        private static string SnapshotJson(ArrowEscapeGameSnapshot snapshot) =>
            snapshot == null ? null : JsonUtility.ToJson(snapshot);

        private static string SnapshotSummary(ArrowEscapeGameSnapshot snapshot) =>
            snapshot == null
                ? "null"
                : $"{snapshot.LevelId}/{snapshot.Phase}/budget={snapshot.RemainingBudget}/" +
                  $"arrows={snapshot.Arrows?.Length ?? 0}/revision={snapshot.StateRevision}";

        private static MonoBehaviour[] FindAllMonoBehaviours() =>
            UnityEngine.Object.FindObjectsByType<MonoBehaviour>(
                FindObjectsInactive.Include, FindObjectsSortMode.None);
    }
}
