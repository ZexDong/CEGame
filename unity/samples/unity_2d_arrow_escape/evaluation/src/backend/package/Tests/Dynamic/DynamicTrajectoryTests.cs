using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NUnit.Framework;
using OmniGame.Benchmark.ArrowEscape.V2;
using UnityEngine;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    [TestFixture]
    public sealed class DynamicTrajectoryTests
    {
        [UnitySetUp]
        public IEnumerator EnsureFormalResolution()
        {
            yield return EvaluatorDisplayResolution.Ensure1280x720();
            Assert.That(EvaluatorDisplayResolution.IsCurrentExact, Is.True,
                "[OMNIGAME_EVALUATOR_HEALTH] Dynamic trajectory runtime must execute " +
                "at real 1280x720; " + EvaluatorDisplayResolution.Diagnostic + ".");
        }

        [UnityTearDown]
        public IEnumerator RestoreFormalResolution()
        {
            EvaluatorDisplayResolution.Restore();
            yield return null;
        }

        [UnityTest]
        public IEnumerator TRAJ00_InputCommitBoundaries() =>
            Run("input_boundaries", InputCommitBoundaries);

        [UnityTest]
        public IEnumerator TRAJ01_CanonicalHintClickWinRestart() =>
            Run("canonical_success", CanonicalSuccess);

        [UnityTest]
        public IEnumerator TRAJ02_MotionCardinalsFullyExit() =>
            Run("motion_cardinals", MotionCardinals);

        [UnityTest]
        public IEnumerator TRAJ03_BlockedFailureFeedbackAndRecovery() =>
            Run("blocked_failure", BlockedFailure);

        [UnityTest]
        public IEnumerator TRAJ04_BudgetTerminalWinLossAndFreeze() =>
            Run("budget_terminal", BudgetTerminal);

        [UnityTest]
        public IEnumerator TRAJ05_SequentialDependencyChain() =>
            Run("dependency_chain", DependencyChain);

        [UnityTest]
        public IEnumerator TRAJ06_AndDependencyBothOrders() =>
            Run("and_dependency", AndDependency);

        [UnityTest]
        public IEnumerator TRAJ07_RestartInterruptsMovingState() =>
            Run("restart_interrupt", RestartInterrupt);

        [UnityTest]
        public IEnumerator TRAJ08_HintLegalityCostAndRecovery() =>
            Run("hint_stability", HintStability);

        private static IEnumerator Run(
            string trajectoryId,
            Func<ArrowEscapeTrajectoryHarness, IEnumerator> body)
        {
            var harness = new ArrowEscapeTrajectoryHarness(trajectoryId);
            yield return harness.Initialize();
            if (harness.Ready)
            {
                yield return body(harness);
            }
            yield return harness.Dispose();
            string evidencePath = harness.Complete();
            // Candidate gameplay failures are represented by per-check evidence so
            // independent checkpoints can still score. The NUnit case itself passes
            // only when the evaluator completed and sealed its evidence; unexpected
            // exceptions/teardown failures therefore remain an evaluator-invalid gate.
            Assert.That(File.Exists(evidencePath), Is.True,
                $"Trajectory {trajectoryId} did not seal evidence: {evidencePath}.");
            Assert.That(harness.Evidence.trajectory_id, Is.EqualTo(trajectoryId));
            if (!harness.Evidence.passed)
            {
                Assert.Fail("[OMNIGAME_CANDIDATE_DYNAMIC] " +
                            $"trajectory={trajectoryId}; " +
                            $"failed={harness.Evidence.checks_failed}; " +
                            $"blocked={harness.Evidence.checks_blocked}; " +
                            $"first={harness.Evidence.failure ?? "sealed non-pass evidence"}");
            }
        }

        private static IEnumerator InputCommitBoundaries(
            ArrowEscapeTrajectoryHarness harness)
        {
            PointerBoundaryGesture[] gestures =
            {
                PointerBoundaryGesture.PressOnly,
                PointerBoundaryGesture.OutsideDownInsideUp,
                PointerBoundaryGesture.InsideDownOutsideUp
            };
            string[] checkIds =
            {
                "input.press_only.no_commit",
                "input.outside_down_inside_up.no_commit",
                "input.inside_down_outside_up.no_commit"
            };

            for (int index = 0; index < gestures.Length; index++)
            {
                yield return RestartFresh(harness);
                VisibleArrowTarget target = harness.FindVisibleArrowTargets()
                    .FirstOrDefault(item => item != null && !item.HasLockBadge);
                ArrowEscapeGameSnapshot before = harness.Snapshot();
                string beforeSignature = harness.VisibleStateSignature();
                yield return harness.PerformBoundaryGesture(target, gestures[index],
                    "input.boundary." + index);
                yield return new WaitForSecondsRealtime(0.1f);
                ArrowEscapeGameSnapshot after = harness.Snapshot();
                string afterSignature = harness.VisibleStateSignature();
                bool unchanged = before != null && after != null &&
                                 before.StateRevision == after.StateRevision &&
                                 before.RemainingBudget == after.RemainingBudget &&
                                 string.Equals(beforeSignature, afterSignature,
                                     StringComparison.Ordinal);
                harness.Expect("input.boundary." + index, checkIds[index],
                    "no gameplay action committed",
                    after == null
                        ? "missing read-only snapshot"
                        : $"revision {before?.StateRevision}->{after.StateRevision}; " +
                          $"budget {before?.RemainingBudget}->{after.RemainingBudget}",
                    unchanged);
                yield return harness.CleanupBoundaryGesture();
            }

            yield return RestartFresh(harness);
            Dictionary<string, string> visuals = harness.CaptureArrowVisuals();
            VisibleArrowTarget legal = null;
            yield return harness.ClickUiContinuation(ArrowEscapeUiAction.Hint);
            yield return FindChangedArrow(harness, visuals, value => legal = value);
            ArrowEscapeGameSnapshot beforeClick = harness.Snapshot();
            int beforeCount = beforeClick?.Arrows.Count(item =>
                item != null && item.State != ArrowEscapeArrowState.Exited) ?? -1;
            VisibleExitObservation exit = null;
            yield return harness.ObserveVisibleExit(legal, "input.full_click",
                value => exit = value);
            ArrowEscapeGameSnapshot afterClick = harness.Snapshot();
            int afterCount = afterClick?.Arrows.Count(item =>
                item != null && item.State != ArrowEscapeArrowState.Exited) ?? -1;
            bool singleCommit = beforeClick != null && afterClick != null &&
                                exit?.Removed == true &&
                                afterClick.RemainingBudget == beforeClick.RemainingBudget - 1 &&
                                afterCount == beforeCount - 1;
            harness.Expect("input.full_click", "input.full_click.single_commit",
                "same-target down/up commits exactly one selection",
                afterClick == null
                    ? "missing read-only snapshot"
                    : $"budget {beforeClick?.RemainingBudget}->{afterClick.RemainingBudget}; " +
                      $"active {beforeCount}->{afterCount}",
                singleCommit);
        }

        private static IEnumerator CanonicalSuccess(ArrowEscapeTrajectoryHarness harness)
        {
            VisibleGameState initial = harness.ObserveVisibleState();
            string initialSignature = harness.VisibleStateSignature();
            int initialCount = initial?.Arrows.Count ?? 0;
            harness.Expect("canonical.initial", "canonical.initial.captured",
                "fresh tutorial with at least three visible arrows", initial?.Summary,
                initial != null && initial.LevelId == ArrowEscapeContractConstants.TutorialLevelId &&
                initial.BudgetMode == "Moves" && initialCount >= 3 && !initial.Completed && !initial.Failed);
            PlayerSurfaceObservation surface = harness.ObservePlayerSurface();
            harness.Expect("canonical.initial", "canonical.initial.surface.board",
                "the authored board and at least three arrows are fully inside the player frame",
                surface?.Summary ?? "missing", surface?.BoardAndArrowsVisible == true);
            harness.Expect("canonical.initial", "canonical.initial.surface.level",
                "current level is fully visible and not clipped",
                surface?.Summary ?? "missing", surface?.LevelFullyVisible == true);
            harness.Expect("canonical.initial", "canonical.initial.surface.mode",
                "budget mode is fully visible and not clipped",
                surface?.Summary ?? "missing", surface?.ModeFullyVisible == true);
            harness.Expect("canonical.initial", "canonical.initial.surface.budget",
                "remaining budget is fully visible and not clipped",
                surface?.Summary ?? "missing", surface?.BudgetFullyVisible == true);
            harness.Expect("canonical.initial", "canonical.initial.surface.controls",
                "Hint, Restart and Next Level are each fully inside the player frame",
                surface?.Summary ?? "missing", surface?.ControlsFullyVisible == true);
            harness.Expect("canonical.initial", "canonical.initial.surface.complete",
                "board, level, mode, budget and all three controls appear together without clipping",
                surface?.Summary ?? "missing", surface?.Complete == true);
            yield return harness.CaptureVisual("initial_gameplay");

            int completedArrows = 0;
            while (completedArrows < Math.Max(3, initialCount) &&
                   !harness.ObserveVisibleState().Completed)
            {
                int iteration = completedArrows + 1;
                VisibleGameState beforeHint = harness.ObserveVisibleState();
                Dictionary<string, string> visuals = harness.CaptureArrowVisuals();
                VisibleArrowTarget hinted = null;
                if (iteration <= 3)
                {
                    yield return harness.ClickUi(ArrowEscapeUiAction.Hint,
                        $"canonical.hint_click.{iteration}");
                    yield return FindChangedArrow(harness, visuals, value => hinted = value);
                    VisibleGameState afterHint = harness.ObserveVisibleState();
                    harness.Expect($"canonical.hint_state.{iteration}",
                        $"canonical.hint_state.{iteration}.legal",
                        "one visible arrow receives Hint feedback",
                        hinted?.StableKey ?? "<none>", hinted != null);
                    harness.Expect($"canonical.hint_state.{iteration}",
                        $"canonical.hint_state.{iteration}.budget",
                        beforeHint?.RemainingBudget?.ToString() ?? "known budget",
                        afterHint?.RemainingBudget?.ToString() ?? "unknown",
                        beforeHint?.RemainingBudget != null &&
                        afterHint?.RemainingBudget == beforeHint.RemainingBudget);
                }
                else
                {
                    yield return harness.ClickUiContinuation(ArrowEscapeUiAction.Hint);
                    yield return FindChangedArrow(harness, visuals, value => hinted = value);
                }

                if (hinted == null) yield break;
                if ((harness.ObserveVisibleState()?.Arrows.Count ?? 0) == 1)
                {
                    yield return harness.CaptureVisual("near_complete");
                }

                VisibleExitObservation exit = null;
                if (iteration <= 3)
                {
                    yield return harness.ObserveVisibleExit(hinted,
                        $"canonical.arrow_click.{iteration}", value => exit = value);
                    harness.Expect($"canonical.arrow_state.{iteration}",
                        $"canonical.arrow_state.{iteration}.player_source",
                        "normal EventSystem pointer route starts visible motion",
                        exit == null ? "<null>" : $"moving={exit.StartedMoving}",
                        exit?.StartedMoving == true);
                    harness.Expect($"canonical.arrow_state.{iteration}",
                        $"canonical.arrow_state.{iteration}.selected_id",
                        "the clicked visible top hit is the moving target",
                        hinted.StableKey, exit?.StartedMoving == true);
                    harness.Expect($"canonical.arrow_state.{iteration}",
                        $"canonical.arrow_state.{iteration}.moving",
                        "moving over normal frames", exit?.MovingFrames.ToString(),
                        exit?.Continuous == true);
                    harness.Expect($"canonical.arrow_exit.{iteration}",
                        $"canonical.arrow_exit.{iteration}.reached",
                        "visible target fully leaves and is removed",
                        exit == null ? "<null>" : $"removed={exit.Removed}",
                        exit?.Removed == true);
                }
                else
                {
                    yield return harness.ObserveVisibleExitContinuation(hinted, value => exit = value);
                }
                if (exit?.Removed != true) yield break;

                completedArrows++;
                if (completedArrows == 1)
                    yield return harness.CaptureVisual("core_interaction");
                if (completedArrows == Math.Max(2, initialCount - 2))
                    yield return harness.CaptureVisual("late_gameplay");
            }

            VisibleGameState won = harness.ObserveVisibleState();
            harness.Expect("canonical.won", "canonical.won.reached",
                "COMPLETED after all visible authored arrows leave",
                won?.Summary, won?.Completed == true && won.Failed == false &&
                won.Arrows.Count == 0);
            harness.Expect("canonical.terminal", "canonical.terminal.completed_ui",
                "COMPLETED visible and FAILED hidden", won?.Summary,
                won?.Completed == true && won.Failed == false);
            harness.Expect("canonical.terminal", "canonical.terminal.three_distinct",
                "at least three distinct authored arrows completed",
                completedArrows.ToString(), completedArrows >= 3 && completedArrows == initialCount);

            yield return harness.ClickUi(ArrowEscapeUiAction.Restart, "canonical.restart_click");
            yield return WaitForState(harness,
                state => state.LevelId == ArrowEscapeContractConstants.TutorialLevelId &&
                         !state.Completed && !state.Failed && state.Arrows.Count == initialCount,
                1f);
            VisibleGameState restarted = harness.ObserveVisibleState();
            harness.Expect("canonical.restarted", "canonical.restarted.reached",
                "fresh playable tutorial", restarted?.Summary,
                restarted != null && restarted.Arrows.Count == initialCount &&
                restarted.RemainingBudget == initial?.RemainingBudget &&
                !restarted.Completed && !restarted.Failed);
            harness.Expect("canonical.restart_equivalent",
                "canonical.restart_equivalent.snapshot",
                "visible authored initial state restored",
                harness.VisibleStateSignature(),
                string.Equals(initialSignature, harness.VisibleStateSignature(),
                    StringComparison.Ordinal));
        }

        private static IEnumerator MotionCardinals(ArrowEscapeTrajectoryHarness harness)
        {
            yield return RestartFresh(harness);
            VisibleGameState initial = harness.ObserveVisibleState();
            var discovered = new Dictionary<string, Vector2>(StringComparer.Ordinal);
            int authoredCount = initial?.Arrows.Count ?? 0;
            int completed = 0;
            while (completed < authoredCount &&
                   harness.ObserveVisibleState()?.Completed != true)
            {
                Dictionary<string, string> visuals = harness.CaptureArrowVisuals();
                VisibleArrowTarget legal = null;
                yield return harness.ClickUiContinuation(ArrowEscapeUiAction.Hint);
                yield return FindChangedArrow(harness, visuals, value => legal = value);
                if (legal == null) break;

                Vector2 origin = legal.Center;
                VisibleExitObservation observation = null;
                string sequenceStep = "motion.sequence." + (completed + 1);
                yield return harness.ObserveVisibleExit(legal, sequenceStep,
                    value => observation = value);
                if (observation?.Removed == true && observation.Forward &&
                    !string.Equals(observation.Direction, "none", StringComparison.Ordinal))
                {
                    if (!discovered.ContainsKey(observation.Direction))
                    {
                        discovered[observation.Direction] = origin;
                        harness.AliasStepChecks(sequenceStep,
                            "motion.exit." + observation.Direction);
                    }
                }
                if (observation?.Removed != true) break;
                completed++;
            }

            foreach (string direction in new[] { "right", "left", "up", "down" })
            {
                harness.Expect("motion.discover." + direction,
                    "motion.discover." + direction + ".authored",
                    "player-reachable tutorial arrow moving " + direction,
                    discovered.ContainsKey(direction) ? discovered[direction].ToString() : "missing",
                    discovered.ContainsKey(direction));
            }
        }

        private static IEnumerator BlockedFailure(ArrowEscapeTrajectoryHarness harness)
        {
            VisibleGameState initial = harness.ObserveVisibleState();
            int candidateCount = initial?.Arrows.Count ?? 0;
            Vector2? blockedCenter = null;
            for (int index = 0; index < candidateCount && !blockedCenter.HasValue; index++)
            {
                yield return RestartFresh(harness);
                List<VisibleArrowTarget> candidates = harness.FindVisibleArrowTargets();
                if (index >= candidates.Count || candidates[index].HasLockBadge) continue;
                VisibleArrowTarget target = candidates[index];
                Vector2 center = target.Center;
                int? budget = harness.ObserveVisibleState().RemainingBudget;
                float attemptStarted = Time.realtimeSinceStartup;
                yield return harness.ClickVisibleArrowContinuation(target);
                ArrowEscapeGameSnapshot discoverySnapshot = harness.Snapshot();
                if (!RequiresBlockedExitWindow(discoverySnapshot, target, budget))
                {
                    // A clear, ignored, mismatched, or otherwise non-blocked
                    // normal click cannot prove RULE-02.  Do not spend the
                    // complete four-second legal-exit window on every member
                    // of a large authored board.  The public read-only
                    // selection snapshot only chooses which attempt deserves
                    // full physical confirmation; it never invokes gameplay
                    // or proves the scored blocked result by itself.
                    continue;
                }
                // RULE-02 explicitly permits target-local feedback.  A shake
                // may move rendered pixels inside the same logical board cell,
                // so classify immobility only after the full legal exit window
                // rather than during the feedback animation.  This also keeps
                // a delayed successful exit from being mistaken for blocking.
                yield return WaitThroughExitWindow(attemptStarted);
                VisibleGameState after = harness.ObserveVisibleState();
                bool stayed = harness.IsTargetAt(target, center, 2f);
                if (stayed && budget.HasValue && after.RemainingBudget == budget.Value - 1)
                    blockedCenter = center;
            }

            harness.Expect("blocked.discover", "blocked.discover.authored",
                "geometrically blocked tutorial target found by normal play",
                blockedCenter?.ToString() ?? "missing", blockedCenter.HasValue);
            VisibleArrowTarget blocked = null;
            if (blockedCenter.HasValue)
            {
                yield return RestartFresh(harness);
                blocked = Closest(harness.FindVisibleArrowTargets(), blockedCenter.Value);
            }
            else
            {
                // CONTENT-01 still fails when tutorial lacks its authored
                // blocked case. Continue the rule/feedback journey on another
                // public authored level when possible so one content omission
                // does not erase independent D3/D4/D5 evidence.
                yield return RestartFresh(harness);
                yield return harness.ClickUiContinuation(ArrowEscapeUiAction.NextLevel);
                yield return WaitForAuthoredLevel(
                    harness, ArrowEscapeContractConstants.ModesLevelId, 1f);
                yield return FindImmobileNonLockTarget(harness, value => blocked = value);
            }
            if (blocked == null) yield break;
            string baseline = blocked.VisualSignature;
            Vector2 baselineCenter = blocked.Center;
            int initialCount = harness.FindVisibleArrowTargets().Count;
            int? beforeBudget = harness.ObserveVisibleState().RemainingBudget;

            float firstAttemptStarted = Time.realtimeSinceStartup;
            yield return harness.ClickVisibleArrow(blocked, "blocked.click.1");
            VisibleGameState afterClick = harness.ObserveVisibleState();
            yield return harness.ObserveFeedback(blocked, baseline,
                0.15f, 1.0f, "blocked.feedback");
            yield return WaitThroughExitWindow(firstAttemptStarted);
            bool immobile = harness.IsTargetAt(blocked, baselineCenter, 2f);
            harness.Expect("blocked.state.1", "blocked.state.1.outcome",
                "visible failed attempt returns to its original cell without exit motion",
                afterClick?.Summary, immobile);
            harness.Expect("blocked.state.1", "blocked.state.1.player_source",
                "normal player input route",
                "validated by blocked.click.1 native input checks", immobile);
            harness.Expect("blocked.state.1", "blocked.state.1.budget_delta",
                "-1", beforeBudget.HasValue && afterClick?.RemainingBudget.HasValue == true
                    ? (afterClick.RemainingBudget.Value - beforeBudget.Value).ToString()
                    : "unknown",
                beforeBudget.HasValue && afterClick?.RemainingBudget == beforeBudget.Value - 1);
            harness.Expect("blocked.state.1", "blocked.state.1.occupancy",
                "same active visible target position after feedback recovery",
                immobile ? "recovered in place" : "moved/removed",
                immobile);

            float repeatAttemptStarted = Time.realtimeSinceStartup;
            yield return harness.ClickVisibleArrow(blocked, "blocked.click.2");
            yield return WaitThroughExitWindow(repeatAttemptStarted);
            VisibleGameState repeated = harness.ObserveVisibleState();
            VisibleArrowTarget recoveredTarget = harness.RefreshTarget(blocked);
            bool recovered = harness.IsTargetAt(blocked, baselineCenter, 2f) &&
                             string.Equals(baseline,
                                 recoveredTarget?.VisualSignature,
                                 StringComparison.Ordinal);
            harness.Expect("blocked.repeat", "blocked.repeat.no_duplicates",
                initialCount.ToString(), repeated?.Arrows.Count.ToString(),
                repeated?.Arrows.Count == initialCount);
            harness.Expect("blocked.repeat", "blocked.repeat.recovers",
                "same active target at baseline visual", recovered ? "recovered" : "changed",
                recovered);
        }

        private static IEnumerator BudgetTerminal(ArrowEscapeTrajectoryHarness harness)
        {
            yield return RestartFresh(harness);
            VisibleGameState movesInitial = harness.ObserveVisibleState();
            int initialArrowCount = movesInitial?.Arrows.Count ?? 0;
            int initialMoves = movesInitial?.RemainingBudget ?? -1;
            int surplusAttempts = RequiredBlockedAttemptsForLastMove(
                initialMoves, initialArrowCount);
            harness.Expect("budget.moves_prep", "budget.moves_prep.capacity",
                "solvable Moves tutorial with budget >= authored arrow count",
                movesInitial?.Summary,
                initialArrowCount > 0 && surplusAttempts >= 0);
            if (surplusAttempts < 0) yield break;

            if (surplusAttempts > 0)
            {
                VisibleArrowTarget blocked = null;
                yield return FindImmobileNonLockTarget(harness, value => blocked = value);
                if (blocked == null)
                {
                    harness.Expect("budget.moves_prep", "budget.moves_prep.blocked_target",
                        "public tutorial blocked target", "missing", false);
                    yield break;
                }

                Vector2 blockedCenter = blocked.Center;
                for (int attempt = 0; attempt < surplusAttempts; attempt++)
                {
                    blocked = Closest(harness.FindVisibleArrowTargets(), blockedCenter);
                    if (blocked == null) break;
                    yield return harness.ClickVisibleArrowContinuation(blocked);
                    // RULE-02 guarantees the target-local feedback returns to
                    // normal within one second.  Continue through the complete
                    // four-second exit window so a delayed illegal exit cannot
                    // masquerade as a blocked budget-spend attempt.
                    yield return harness.Delay(4.05f);
                }

                VisibleGameState prepared = harness.ObserveVisibleState();
                harness.Expect("budget.moves_prep", "budget.moves_prep.surplus_spent",
                    $"Moves={initialArrowCount} with every authored arrow still active",
                    prepared?.Summary,
                    prepared != null && !prepared.Completed && !prepared.Failed &&
                    prepared.Arrows.Count == initialArrowCount &&
                    prepared.RemainingBudget == initialArrowCount);
                if (prepared == null || prepared.Completed || prepared.Failed ||
                    prepared.Arrows.Count != initialArrowCount ||
                    prepared.RemainingBudget != initialArrowCount)
                {
                    yield break;
                }
            }

            while ((harness.ObserveVisibleState()?.Arrows.Count ?? 0) > 1)
            {
                VisibleArrowTarget hinted = null;
                Dictionary<string, string> visuals = harness.CaptureArrowVisuals();
                yield return harness.ClickUiContinuation(ArrowEscapeUiAction.Hint);
                yield return FindChangedArrow(harness, visuals, value => hinted = value);
                if (hinted == null) yield break;
                VisibleExitObservation exit = null;
                yield return harness.ObserveVisibleExitContinuation(hinted, value => exit = value);
                if (exit?.Removed != true) yield break;
            }

            VisibleArrowTarget last = SelectUniqueCandidate(
                harness.FindVisibleArrowTargets(), item => true);
            if (last == null) yield break;
            int? beforeLast = harness.ObserveVisibleState().RemainingBudget;
            yield return harness.ClickVisibleArrow(last, "budget.moves_win.click");
            VisibleGameState moving = harness.ObserveVisibleState();
            bool lastStillVisible = harness.IsTargetVisible(last);
            harness.Expect("budget.moves_win.state", "budget.moves_win.zero_while_moving",
                "Moves=0, no FAILED, final arrow still completing motion",
                moving?.Summary,
                beforeLast == 1 && moving?.RemainingBudget == 0 && !moving.Failed &&
                lastStillVisible);
            yield return WaitForState(harness, state => state.Completed, 4f);
            harness.Expect("budget.moves_win.won", "budget.moves_win.won.reached",
                "COMPLETED after final visible exit", harness.ObserveVisibleState()?.Summary,
                harness.ObserveVisibleState()?.Completed == true);

            yield return harness.ClickUi(ArrowEscapeUiAction.NextLevel, "budget.modes.next");
            yield return WaitForAuthoredLevel(
                harness, ArrowEscapeContractConstants.ModesLevelId, 1f);
            VisibleGameState modes = harness.ObserveVisibleState();
            harness.Expect("budget.modes.loaded", "budget.modes.loaded.authored",
                "fresh player-reachable modes_and_hint Hearts level", modes?.Summary,
                modes != null && modes.LevelId == ArrowEscapeContractConstants.ModesLevelId &&
                modes.BudgetMode == "Hearts" && modes.RemainingBudget >= 2 &&
                !modes.Completed && !modes.Failed);

            VisibleArrowTarget clear = null;
            yield return FindMovableTarget(harness, value => clear = value);
            int? heartsBefore = harness.ObserveVisibleState().RemainingBudget;
            yield return harness.ClickVisibleArrow(clear, "budget.hearts_success.click");
            yield return WaitRemoved(harness, clear, 4f);
            VisibleGameState heartsAfter = harness.ObserveVisibleState();
            harness.Expect("budget.hearts_success.state", "budget.hearts_success.no_cost",
                heartsBefore?.ToString() ?? "known Hearts", heartsAfter?.RemainingBudget?.ToString(),
                clear != null && heartsBefore.HasValue &&
                heartsAfter?.RemainingBudget == heartsBefore.Value);
            harness.Expect("budget.hearts_success.won", "budget.hearts_success.won.reached",
                "successful authored Hearts arrow fully exits",
                harness.IsTargetVisible(clear) ? "still visible" : "removed",
                clear != null && !harness.IsTargetVisible(clear));

            yield return RestartFresh(harness);
            VisibleArrowTarget failedTarget = null;
            yield return FindImmobileNonLockTarget(harness, value => failedTarget = value);
            if (failedTarget == null) yield break;
            while ((harness.ObserveVisibleState()?.RemainingBudget ?? 0) > 1)
            {
                failedTarget = Closest(harness.FindVisibleArrowTargets(), failedTarget.Center);
                yield return harness.ClickVisibleArrowContinuation(failedTarget);
                yield return harness.Delay(1.05f);
            }
            failedTarget = Closest(harness.FindVisibleArrowTargets(), failedTarget.Center);
            yield return harness.ClickVisibleArrow(failedTarget, "budget.loss.click");
            yield return WaitForState(harness, state => state.Failed, 1f);
            VisibleGameState lost = harness.ObserveVisibleState();
            harness.Expect("budget.loss.lost", "budget.loss.lost.reached",
                "FAILED at zero Hearts", lost?.Summary,
                lost != null && lost.Failed && !lost.Completed && lost.RemainingBudget == 0);
            harness.Expect("budget.loss.state", "budget.loss.failed_ui",
                "FAILED visible, COMPLETED hidden, budget zero", lost?.Summary,
                lost != null && lost.Failed && !lost.Completed && lost.RemainingBudget == 0);

            // The selection that caused loss may still be completing its
            // already-earned target-local failure feedback. INPUT-02 asks
            // whether a *later terminal click* changes gameplay state; it does
            // not forbid the final pre-terminal feedback coroutine from
            // returning to baseline. Sample the frozen state only after the
            // public one-second feedback recovery window.
            yield return harness.Delay(1.05f);
            failedTarget = Closest(harness.FindVisibleArrowTargets(), failedTarget.Center);
            string frozen = harness.VisibleStateSignature();
            yield return harness.ClickVisibleArrow(failedTarget, "budget.loss.frozen_click");
            harness.Expect("budget.loss.frozen", "budget.loss.frozen.no_change",
                frozen, harness.VisibleStateSignature(),
                string.Equals(frozen, harness.VisibleStateSignature(), StringComparison.Ordinal));
        }

        private static IEnumerator DependencyChain(ArrowEscapeTrajectoryHarness harness)
        {
            yield return harness.ClickUi(ArrowEscapeUiAction.NextLevel, "dependency.next.modes");
            yield return WaitForAuthoredLevel(
                harness, ArrowEscapeContractConstants.ModesLevelId, 1f);
            yield return harness.ClickUi(ArrowEscapeUiAction.NextLevel, "dependency.next.chain");
            yield return WaitForAuthoredLevel(
                harness, ArrowEscapeContractConstants.PrerequisiteLevelId, 1f);
            VisibleGameState initial = harness.ObserveVisibleState();
            bool dependencyLevelReached = initial != null &&
                                          initial.LevelId ==
                                          ArrowEscapeContractConstants.PrerequisiteLevelId &&
                                          initial.Arrows.Count == 3;
            harness.Expect("dependency.loaded", "dependency.loaded.navigation",
                "fresh player-reachable prerequisite_chain with three authored arrows",
                initial?.Summary, dependencyLevelReached);
            harness.Expect("dependency.loaded", "dependency.loaded.badge_content",
                "one visible key badge and two visible lock badges in the fresh chain",
                initial?.Summary,
                dependencyLevelReached &&
                initial.Arrows.Count(item => item.HasKeyBadge) == 1 &&
                initial.Arrows.Count(item => item.HasLockBadge) == 2);
            if (initial == null) yield break;

            VisibleArrowTarget lockedTarget = initial.Arrows.FirstOrDefault(item => item.HasLockBadge);
            int? beforeLocked = initial.RemainingBudget;
            Vector2 lockedCenter = lockedTarget?.Center ?? Vector2.zero;
            float lockedAttemptStarted = Time.realtimeSinceStartup;
            yield return harness.ClickVisibleArrow(lockedTarget, "dependency.locked_click");
            // A locked attempt may use the same recoverable target-local shake
            // as a geometrically blocked attempt.  Judge board immobility once
            // the complete legal exit window has elapsed.
            yield return WaitThroughExitWindow(lockedAttemptStarted);
            VisibleGameState locked = harness.ObserveVisibleState();
            bool lockedStayed = harness.IsTargetAt(lockedTarget, lockedCenter, 2f);
            harness.Expect("dependency.locked_state", "dependency.locked_state.outcome",
                "locked target remains and costs one current-mode budget unit",
                locked?.Summary,
                lockedStayed && beforeLocked.HasValue &&
                locked?.RemainingBudget == beforeLocked.Value - 1);

            // The locked-click negative case must not consume budget from the
            // independent clean success journey. Restart the current authored
            // chain through its visible player control before progressing.
            yield return harness.ClickUiContinuation(ArrowEscapeUiAction.Restart);
            yield return WaitForState(harness, state =>
                state != null &&
                state.LevelId == ArrowEscapeContractConstants.PrerequisiteLevelId &&
                state.Arrows.Count == 3 &&
                state.RemainingBudget == beforeLocked &&
                state.Arrows.Count(item => item.HasKeyBadge) == 1 &&
                state.Arrows.Count(item => item.HasLockBadge) == 2,
                1f);
            VisibleGameState cleanChain = harness.ObserveVisibleState();
            VisibleArrowTarget key = SelectUniqueCandidate(
                cleanChain?.Arrows, item => item.HasKeyBadge);
            if (key == null) yield break;
            yield return harness.ClickVisibleArrow(key, "dependency.key_click");
            yield return harness.Delay(0.05f);
            VisibleGameState keyMoving = harness.ObserveVisibleState();
            harness.Expect("dependency.key_moving", "dependency.key_moving.lock_stays_locked",
                "key moves while both dependent targets remain visibly locked",
                keyMoving?.Summary,
                harness.IsTargetVisible(key) &&
                keyMoving?.Arrows.Count(item => item.HasLockBadge) == 2);
            yield return WaitRemoved(harness, key, 4f);
            VisibleGameState afterKey = harness.ObserveVisibleState();
            harness.Expect("dependency.key_exit", "dependency.key_exit.reached",
                "first key fully exits", afterKey?.Summary,
                !harness.IsTargetVisible(key));
            harness.Expect("dependency.lock_b_available",
                "dependency.lock_b_available.badges",
                "one available key-badged middle target and one locked final target",
                afterKey?.Summary,
                afterKey != null && afterKey.Arrows.Count == 2 &&
                afterKey.Arrows.Count(item => item.HasKeyBadge) == 1 &&
                afterKey.Arrows.Count(item => item.HasLockBadge) == 1);

            VisibleArrowTarget middle = SelectUniqueCandidate(
                afterKey?.Arrows, item => item.HasKeyBadge);
            if (middle == null) yield break;
            yield return harness.ClickVisibleArrow(middle, "dependency.lock_b_click");
            yield return harness.Delay(0.05f);
            VisibleGameState middleMoving = harness.ObserveVisibleState();
            harness.Expect("dependency.lock_b_moving",
                "dependency.lock_b_moving.final_locked",
                "middle moves while final target remains locked",
                middleMoving?.Summary,
                harness.IsTargetVisible(middle) &&
                middleMoving?.Arrows.Count(item => item.HasLockBadge) == 1);
            yield return WaitRemoved(harness, middle, 4f);
            VisibleGameState afterMiddle = harness.ObserveVisibleState();
            harness.Expect("dependency.lock_b_exit", "dependency.lock_b_exit.reached",
                "middle target fully exits", afterMiddle?.Summary,
                !harness.IsTargetVisible(middle));
            harness.Expect("dependency.lock_c_available",
                "dependency.lock_c_available.state",
                "one available final target with no lock badge",
                afterMiddle?.Summary,
                afterMiddle != null && afterMiddle.Arrows.Count == 1 &&
                !afterMiddle.Arrows[0].HasLockBadge);

            VisibleArrowTarget final = SelectUniqueCandidate(
                afterMiddle?.Arrows, item => true);
            if (final == null) yield break;
            yield return harness.ClickVisibleArrow(final, "dependency.lock_c_click");
            yield return WaitRemoved(harness, final, 4f);
            harness.Expect("dependency.lock_c_exit", "dependency.lock_c_exit.reached",
                "final target fully exits", harness.ObserveVisibleState()?.Summary,
                !harness.IsTargetVisible(final));
            yield return WaitForState(harness, state => state.Completed, 1f);
            harness.Expect("dependency.won", "dependency.won.reached",
                "complete dependency chain reaches COMPLETED",
                harness.ObserveVisibleState()?.Summary,
                harness.ObserveVisibleState()?.Completed == true);
        }

        private static IEnumerator AndDependency(ArrowEscapeTrajectoryHarness harness)
        {
            yield return harness.ClickUi(ArrowEscapeUiAction.NextLevel, "and.navigate.modes");
            yield return WaitForAuthoredLevel(
                harness, ArrowEscapeContractConstants.ModesLevelId, 1f);
            harness.Expect("and.loaded", "and.loaded.authored",
                "fresh player-reachable modes_and_hint AND content",
                harness.ObserveVisibleState()?.Summary,
                harness.ObserveVisibleState()?.LevelId == ArrowEscapeContractConstants.ModesLevelId);
            yield return RunAndOrder(harness, false, "and.left");
            yield return harness.ClickUi(ArrowEscapeUiAction.Restart, "and.restart");
            // RESTART-01 permits an asynchronous rebuild within one second.
            // Do not sample the opposite key order from the transient empty
            // frame immediately after the visible Restart click.
            yield return WaitForAndGroupReady(harness, 1f);
            yield return RunAndOrder(harness, true, "and.right");
        }

        internal static bool IsAndGroupReady(VisibleGameState state)
        {
            return state != null &&
                   string.Equals(state.LevelId,
                       ArrowEscapeContractConstants.ModesLevelId,
                       StringComparison.Ordinal) &&
                   !state.Completed &&
                   !state.Failed &&
                   state.Arrows.Count(item => item.HasKeyBadge) >= 2 &&
                   state.Arrows.Any(item => item.HasLockBadge);
        }

        internal static IEnumerator WaitForAndGroupReady(
            Func<VisibleGameState> observe,
            float timeout)
        {
            float deadline = Time.realtimeSinceStartup + timeout;
            VisibleGameState state = observe();
            while (!IsAndGroupReady(state) &&
                   Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                state = observe();
            }
        }

        private static IEnumerator WaitForAndGroupReady(
            ArrowEscapeTrajectoryHarness harness,
            float timeout)
        {
            return WaitForAndGroupReady(harness.ObserveVisibleState, timeout);
        }

        private static IEnumerator RunAndOrder(
            ArrowEscapeTrajectoryHarness harness,
            bool reverse,
            string prefix)
        {
            VisibleGameState initial = harness.ObserveVisibleState();
            List<VisibleArrowTarget> keys = initial.Arrows.Where(item => item.HasKeyBadge)
                .OrderBy(item => item.Center.x).ToList();
            VisibleArrowTarget dependent = initial.Arrows.FirstOrDefault(item => item.HasLockBadge);
            harness.Expect(prefix + ".group", prefix + ".group.visible",
                "two visible key-badged prerequisites and one lock-badged dependent",
                initial?.Summary,
                keys.Count >= 2 && dependent != null);
            if (keys.Count < 2 || dependent == null) yield break;
            if (reverse) keys.Reverse();
            string secondStableKey = keys[1].StableKey;
            Vector2 dependentCenter = dependent.Center;

            VisibleExitObservation firstExit = null;
            yield return harness.ObserveVisibleExit(keys[0], prefix + ".first_click",
                value => firstExit = value);
            harness.Expect(prefix + ".first_exit", prefix + ".first_exit.reached",
                "first prerequisite fully exits", firstExit?.Removed.ToString(),
                firstExit?.Removed == true);
            if (firstExit?.Removed != true) yield break;
            VisibleArrowTarget afterFirstDependent = harness.RefreshTarget(dependent);
            harness.Expect(prefix + ".after_first", prefix + ".after_first.still_locked",
                "dependent remains visibly locked after one prerequisite",
                afterFirstDependent?.HasLockBadge.ToString(),
                afterFirstDependent?.HasLockBadge == true);

            VisibleArrowTarget second = harness.FindVisibleArrowTargets()
                .FirstOrDefault(item => item.StableKey == secondStableKey);
            VisibleExitObservation secondExit = null;
            yield return harness.ObserveVisibleExit(second, prefix + ".second_click",
                value => secondExit = value);
            if (secondExit?.Removed != true) yield break;
            yield return WaitForArrowBadgeState(harness, dependent, false, 1f);
            VisibleArrowTarget available = harness.RefreshTarget(dependent);
            harness.Expect(prefix + ".after_second", prefix + ".after_second.available",
                "dependent loses lock badge only after both prerequisites exit",
                available?.HasLockBadge.ToString(),
                secondExit?.Removed == true && available != null && !available.HasLockBadge);
            if (available == null || available.HasLockBadge) yield break;

            VisibleExitObservation dependentExit = null;
            yield return harness.ObserveVisibleExit(available, prefix + ".dependent_click",
                value => dependentExit = value);
            harness.Expect(prefix + ".dependent_exit", prefix + ".dependent_exit.reached",
                "AND dependent fully exits", dependentExit?.Removed.ToString(),
                dependentExit?.Removed == true);
            if (dependentExit?.Removed != true) yield break;
            harness.Expect(prefix + ".won", prefix + ".won.reached",
                "authored AND group completes in this order",
                dependentExit?.Removed.ToString(), dependentExit?.Removed == true);
        }

        private static IEnumerator RestartInterrupt(ArrowEscapeTrajectoryHarness harness)
        {
            yield return RestartFresh(harness);
            string initialSignature = harness.VisibleStateSignature();
            int initialCount = harness.FindVisibleArrowTargets().Count;
            int? initialBudget = harness.ObserveVisibleState().RemainingBudget;
            VisibleArrowTarget target = null;
            Dictionary<string, string> visuals = harness.CaptureArrowVisuals();
            yield return harness.ClickUiContinuation(ArrowEscapeUiAction.Hint);
            yield return FindChangedArrow(harness, visuals, value => target = value);
            if (target == null) yield break;
            Vector2 start = target.Center;
            yield return harness.ClickVisibleArrow(target, "restart.key_click");
            yield return harness.Delay(0.05f);
            VisibleArrowTarget movingTarget = harness.RefreshTarget(target);
            bool moving = movingTarget != null &&
                          Vector2.Distance(movingTarget.Center, start) > 0.5f;
            harness.Expect("restart.moving", "restart.moving.state",
                "clicked arrow visibly moving", moving ? "moving" : "not moving", moving);

            yield return harness.ClickUi(ArrowEscapeUiAction.Restart, "restart.ui_click");
            yield return WaitForState(harness,
                state => !state.Completed && !state.Failed && state.Arrows.Count == initialCount,
                1f);
            VisibleGameState restored = harness.ObserveVisibleState();
            harness.Expect("restart.playing", "restart.playing.reached",
                "fresh active tutorial", restored?.Summary,
                restored != null && !restored.Completed && !restored.Failed &&
                restored.Arrows.Count == initialCount);
            harness.Expect("restart.equivalent_now", "restart.equivalent_now.snapshot",
                initialSignature, harness.VisibleStateSignature(),
                string.Equals(initialSignature, harness.VisibleStateSignature(),
                    StringComparison.Ordinal));
            harness.Expect("restart.count_now", "restart.count_now.same",
                initialCount.ToString(), restored?.Arrows.Count.ToString(),
                restored?.Arrows.Count == initialCount);
            yield return harness.Delay(1f);
            harness.Expect("restart.equivalent_late", "restart.equivalent_late.snapshot",
                initialSignature, harness.VisibleStateSignature(),
                string.Equals(initialSignature, harness.VisibleStateSignature(),
                    StringComparison.Ordinal));
            harness.Expect("restart.count_late", "restart.count_late.same",
                initialCount.ToString(), harness.FindVisibleArrowTargets().Count.ToString(),
                harness.FindVisibleArrowTargets().Count == initialCount);

            VisibleArrowTarget reusable = harness.FindVisibleArrowTargets().FirstOrDefault();
            yield return harness.ClickVisibleArrow(reusable, "restart.locked_click");
            VisibleGameState after = harness.ObserveVisibleState();
            harness.Expect("restart.single_cost", "restart.single_cost.exactly_one",
                "-1", initialBudget.HasValue && after?.RemainingBudget.HasValue == true
                    ? (after.RemainingBudget.Value - initialBudget.Value).ToString()
                    : "unknown",
                initialBudget.HasValue && after?.RemainingBudget == initialBudget.Value - 1);
        }

        private static IEnumerator HintStability(ArrowEscapeTrajectoryHarness harness)
        {
            yield return RestartFresh(harness);
            VisibleGameState initial = harness.ObserveVisibleState();
            int initialCount = initial?.Arrows.Count ?? 0;
            int? initialBudget = initial?.RemainingBudget;
            Dictionary<string, string> visuals = harness.CaptureArrowVisuals();
            VisibleArrowTarget hinted = null;
            yield return harness.ClickUi(ArrowEscapeUiAction.Hint, "hint.click.1");
            yield return FindChangedArrow(harness, visuals, value => hinted = value);
            VisibleGameState afterHint = harness.ObserveVisibleState();
            harness.Expect("hint.state.1", "hint.state.1.legal",
                "one visible playable arrow highlighted", hinted?.StableKey ?? "<none>",
                hinted != null && !hinted.HasLockBadge);
            harness.Expect("hint.state.1", "hint.state.1.no_cost",
                initialBudget?.ToString() ?? "known budget",
                afterHint?.RemainingBudget?.ToString(),
                initialBudget.HasValue && afterHint?.RemainingBudget == initialBudget.Value);
            if (hinted == null) yield break;
            string hintBaseline = visuals.TryGetValue(hinted.StableKey, out string baseline)
                ? baseline
                : hinted.VisualSignature;
            yield return harness.ObserveFeedback(hinted, hintBaseline,
                0.5f, 1.5f, "hint.feedback");

            yield return harness.ClickUi(ArrowEscapeUiAction.Hint, "hint.click.2");
            yield return harness.ClickUi(ArrowEscapeUiAction.Hint, "hint.click.3");
            VisibleGameState repeated = harness.ObserveVisibleState();
            harness.Expect("hint.repeated", "hint.repeated.no_duplicates",
                initialCount.ToString(), repeated?.Arrows.Count.ToString(),
                repeated?.Arrows.Count == initialCount);
            harness.Expect("hint.repeated", "hint.repeated.legal_no_cost",
                initialBudget?.ToString() ?? "known budget",
                repeated?.RemainingBudget?.ToString(),
                repeated?.RemainingBudget == initialBudget);

            VisibleArrowTarget currentHint = harness.RefreshTarget(hinted);
            yield return harness.ClickVisibleArrow(currentHint, "hint.clear_click");
            yield return WaitRemoved(harness, currentHint, 4f);
            harness.Expect("hint.clear_exit", "hint.clear_exit.reached",
                "hinted arrow fully exits", harness.ObserveVisibleState()?.Summary,
                currentHint != null && !harness.IsTargetVisible(currentHint));

            Dictionary<string, string> afterVisuals = harness.CaptureArrowVisuals();
            VisibleArrowTarget updated = null;
            yield return harness.ClickUi(ArrowEscapeUiAction.Hint,
                "hint.click.after_state_change");
            yield return FindChangedArrow(harness, afterVisuals, value => updated = value);
            harness.Expect("hint.after_state_change", "hint.after_state_change.new_legal",
                "a remaining visible playable arrow", updated?.StableKey ?? "<none>",
                updated != null && !harness.SameTarget(updated, currentHint));
        }

        private static IEnumerator RestartFresh(ArrowEscapeTrajectoryHarness harness)
        {
            yield return harness.ClickUiContinuation(ArrowEscapeUiAction.Restart);
            yield return WaitForState(harness,
                state => state != null && !state.Completed && !state.Failed &&
                         state.Arrows.Count > 0,
                1f);
        }

        private static IEnumerator FindChangedArrow(
            ArrowEscapeTrajectoryHarness harness,
            IReadOnlyDictionary<string, string> before,
            Action<VisibleArrowTarget> receive)
        {
            VisibleArrowTarget changed = harness.FindChangedArrow(before);
            float deadline = Time.realtimeSinceStartup + 0.6f;
            while (changed == null && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                changed = harness.FindChangedArrow(before);
            }
            receive?.Invoke(changed);
        }

        private static IEnumerator WaitRemoved(
            ArrowEscapeTrajectoryHarness harness,
            VisibleArrowTarget target,
            float timeout)
        {
            float deadline = Time.realtimeSinceStartup + timeout;
            while (harness.IsTargetVisible(target) &&
                   Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }
            // Destroy() and dependency badge refreshes become authoritative at end of frame.
            yield return null;
        }

        private static IEnumerator WaitForState(
            ArrowEscapeTrajectoryHarness harness,
            Func<VisibleGameState, bool> predicate,
            float timeout)
        {
            float deadline = Time.realtimeSinceStartup + timeout;
            VisibleGameState state = harness.ObserveVisibleState();
            while ((state == null || !predicate(state)) && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                state = harness.ObserveVisibleState();
            }
        }

        private static IEnumerator WaitForAuthoredLevel(
            ArrowEscapeTrajectoryHarness harness,
            string levelId,
            float timeout)
        {
            // A valid candidate may rebuild its visible objects with
            // Object.Destroy, whose old surfaces remain discoverable until the
            // end of the current frame.  NAV-01 grants up to one second, so do
            // not sample the new level in the same frame as the click.
            yield return null;
            yield return WaitForState(harness, state =>
                state != null && string.Equals(
                    state.LevelId, levelId, StringComparison.Ordinal), timeout);
        }

        private static IEnumerator WaitForArrowBadgeState(
            ArrowEscapeTrajectoryHarness harness,
            VisibleArrowTarget target,
            bool expectedLock,
            float timeout)
        {
            float deadline = Time.realtimeSinceStartup + timeout;
            VisibleArrowTarget arrow = harness.RefreshTarget(target);
            while (arrow != null && arrow.HasLockBadge != expectedLock &&
                   Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                arrow = harness.RefreshTarget(target);
            }
        }

        internal static VisibleArrowTarget SelectUniqueCandidate(
            IEnumerable<VisibleArrowTarget> candidates,
            Func<VisibleArrowTarget, bool> predicate)
        {
            if (candidates == null || predicate == null) return null;
            VisibleArrowTarget selected = null;
            int count = 0;
            foreach (VisibleArrowTarget candidate in candidates)
            {
                if (candidate == null || !predicate(candidate)) continue;
                count++;
                if (count > 1) return null;
                selected = candidate;
            }
            return count == 1 ? selected : null;
        }

        private static IEnumerator FindImmobileNonLockTarget(
            ArrowEscapeTrajectoryHarness harness,
            Action<VisibleArrowTarget> receive)
        {
            List<VisibleArrowTarget> starting = harness.FindVisibleArrowTargets();
            Vector2? found = null;
            for (int index = 0; index < starting.Count && !found.HasValue; index++)
            {
                yield return RestartFresh(harness);
                List<VisibleArrowTarget> targets = harness.FindVisibleArrowTargets();
                if (index >= targets.Count || targets[index].HasLockBadge) continue;
                VisibleArrowTarget target = targets[index];
                Vector2 center = target.Center;
                int? budget = harness.ObserveVisibleState().RemainingBudget;
                float attemptStarted = Time.realtimeSinceStartup;
                yield return harness.ClickVisibleArrowContinuation(target);
                ArrowEscapeGameSnapshot discoverySnapshot = harness.Snapshot();
                if (!RequiresBlockedExitWindow(discoverySnapshot, target, budget))
                {
                    continue;
                }
                // Classify the attempt after the public RULE-02 recovery
                // and full legal exit window, not at an arbitrary phase of
                // target-local feedback.
                yield return WaitThroughExitWindow(attemptStarted);
                bool stayed = harness.IsTargetAt(target, center, 2f);
                if (stayed && budget.HasValue &&
                    harness.ObserveVisibleState().RemainingBudget == budget.Value - 1)
                    found = center;
            }
            yield return RestartFresh(harness);
            receive?.Invoke(found.HasValue
                ? Closest(harness.FindVisibleArrowTargets(), found.Value)
                : null);
        }

        private static IEnumerator FindMovableTarget(
            ArrowEscapeTrajectoryHarness harness,
            Action<VisibleArrowTarget> receive)
        {
            List<VisibleArrowTarget> starting = harness.FindVisibleArrowTargets();
            Vector2? found = null;
            for (int index = 0; index < starting.Count && !found.HasValue; index++)
            {
                yield return RestartFresh(harness);
                List<VisibleArrowTarget> targets = harness.FindVisibleArrowTargets();
                if (index >= targets.Count || targets[index].HasLockBadge) continue;
                VisibleArrowTarget target = targets[index];
                Vector2 center = target.Center;
                VisibleExitObservation observation = null;
                yield return harness.ObserveVisibleExitContinuation(
                    target, value => observation = value);
                if (observation?.Removed == true && observation.Forward &&
                    observation.Continuous)
                {
                    found = center;
                }
            }
            yield return RestartFresh(harness);
            receive?.Invoke(found.HasValue
                ? Closest(harness.FindVisibleArrowTargets(), found.Value)
                : null);
        }

        private static IEnumerator WaitThroughExitWindow(float attemptStarted)
        {
            // FLOW-02 allows up to four seconds for a legal full exit.  A
            // target still active in its original cell after this small
            // epsilon cannot be a merely slow valid exit.
            float deadline = attemptStarted + 4.05f;
            while (Time.realtimeSinceStartup < deadline) yield return null;
        }

        internal static bool RequiresBlockedExitWindow(
            ArrowEscapeGameSnapshot afterClick,
            VisibleArrowTarget target,
            int? budgetBefore)
        {
            return afterClick != null && target != null &&
                   !string.IsNullOrWhiteSpace(target.SemanticId) &&
                   budgetBefore.HasValue &&
                   afterClick.LastInputSource == ArrowEscapeInputSource.PlayerPointer &&
                   string.Equals(afterClick.LastSelectedArrowId,
                       target.SemanticId, StringComparison.Ordinal) &&
                   afterClick.LastSelectionOutcome == ArrowEscapeSelectionOutcome.Blocked &&
                   afterClick.RemainingBudget == budgetBefore.Value - 1;
        }

        private static VisibleArrowTarget Closest(
            IEnumerable<VisibleArrowTarget> targets,
            Vector2 center) => targets?
            .OrderBy(item => Vector2.Distance(item.Center, center))
            .FirstOrDefault();

        internal static int CanonicalActiveArrowCount(ArrowEscapeGameSnapshot snapshot) =>
            snapshot?.Arrows == null
                ? 0
                : snapshot.Arrows.Count(item => item != null &&
                    item.State != ArrowEscapeArrowState.Exited);

        internal static int RequiredBlockedAttemptsForLastMove(
            int initialBudget, int authoredArrowCount) =>
            initialBudget >= authoredArrowCount && authoredArrowCount > 0
                ? initialBudget - authoredArrowCount
                : -1;
    }
}

