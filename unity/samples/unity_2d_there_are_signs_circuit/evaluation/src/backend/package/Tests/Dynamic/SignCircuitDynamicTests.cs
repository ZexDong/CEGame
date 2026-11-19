using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    [TestFixture]
    public sealed class SignCircuitDynamicTests
    {
        NativeInputDriver driver;
        InputAction healthKeyboardProbe;
        InputActionMap healthChangedLayout;
        GameObject healthRoot;
        readonly List<string> unexpectedRuntimeErrors = new List<string>();
        readonly List<string> interactionTrace = new List<string>();
        bool previousIgnoreFailingMessages;
        static float observedClosedBarrierX = float.NaN;
        static string successPanelSignature;
        static string pausePanelSignature;
        static string failurePanelSignature;

        static bool IsKnownUnityPackageNoise(string condition) =>
            VisualEvidenceCapture.IsAllowedRenderPipelineAssetDatabaseLog(condition);

        void OnRuntimeLog(string condition, string stackTrace, LogType type)
        {
            if (type != LogType.Error && type != LogType.Exception &&
                type != LogType.Assert) return;
            if (IsKnownUnityPackageNoise(condition)) return;
            unexpectedRuntimeErrors.Add($"[{type}] {condition}\n{stackTrace}");
        }

        void AssertNoUnexpectedCandidateRuntimeErrors()
        {
            if (unexpectedRuntimeErrors.Count == 0) return;
            Assert.Fail("[OMNIGAME_CANDIDATE_BLOCKED] Candidate runtime error " +
                        "log(s) blocked this trajectory:\n" +
                        string.Join("\n---\n", unexpectedRuntimeErrors));
        }

        void AssertNoUnexpectedEvaluatorRuntimeErrors()
        {
            if (unexpectedRuntimeErrors.Count == 0) return;
            Assert.Fail("[OMNIGAME_EVALUATOR_INFRASTRUCTURE] Evaluator health " +
                        "emitted runtime error/assert log(s):\n" +
                        string.Join("\n---\n", unexpectedRuntimeErrors));
        }

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            unexpectedRuntimeErrors.Clear();
            interactionTrace.Clear();
            previousIgnoreFailingMessages = LogAssert.ignoreFailingMessages;
            Application.logMessageReceived += OnRuntimeLog;
            LogAssert.ignoreFailingMessages = true;
            Time.timeScale = 1f;
            driver = new NativeInputDriver();
            yield return null;
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            Time.timeScale = 1f;
            try
            {
                if (driver != null) yield return driver.Dispose();
            }
            finally
            {
                driver = null;
                try
                {
                    healthKeyboardProbe?.Dispose();
                    healthKeyboardProbe = null;
                    if (healthChangedLayout != null)
                    {
                        healthChangedLayout.Disable();
                        healthChangedLayout = null;
                    }
                    if (healthRoot != null)
                    {
                        UnityEngine.Object.Destroy(healthRoot);
                        healthRoot = null;
                    }
                }
                finally
                {
                    Application.logMessageReceived -= OnRuntimeLog;
                    LogAssert.ignoreFailingMessages = previousIgnoreFailingMessages;
                }
            }
        }

        [UnityTest, Order(0)]
        public IEnumerator EVALUATOR_REGRESSION_DynamicRuntimeHealth()
        {
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] health_begin");
            int firstFrame = Time.frameCount;
            yield return null;
            yield return null;
            Assert.That(Time.frameCount, Is.GreaterThan(firstFrame),
                "PlayMode frames did not advance inside the evaluator process.");

            InputSettings.BackgroundBehavior hostBackgroundBehavior =
                InputSystem.settings.backgroundBehavior;
#if UNITY_EDITOR
            InputSettings.EditorInputBehaviorInPlayMode hostEditorInputBehavior =
                InputSystem.settings.editorInputBehaviorInPlayMode;
#endif
            Mouse hostMouse = Mouse.current;
            Keyboard hostKeyboard = Keyboard.current;
            int pairCreationsBefore =
                NativeInputDriver.ProcessDevicePairCreationCount;
            int leasesBefore = NativeInputDriver.ProcessLeaseCount;

            yield return SignCircuitEvaluatorHealthSupport.ReplaceWithIsolatedScene(
                "first", root => healthRoot = root);
            SignCircuitEvaluatorHealthSupport.AssertSemanticStatusLocatorRegression(
                healthRoot);
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] first_lease_initialize");
            yield return driver.Initialize();
            Assert.That(driver.Ready, Is.True,
                "The first evaluator input-driver lease was not ready.");
            Assert.That(NativeInputDriver.ProcessDevicePairCreationCount,
                Is.EqualTo(pairCreationsBefore + 1),
                "The first health lease did not create exactly one process device pair.");
            int firstMouseId = NativeInputDriver.ProcessMouseDeviceId;
            int firstKeyboardId = NativeInputDriver.ProcessKeyboardDeviceId;
            Assert.That(firstMouseId, Is.GreaterThan(0));
            Assert.That(firstKeyboardId, Is.GreaterThan(0));

            bool firstKeyboardPerformed = false;
            healthKeyboardProbe = new InputAction(
                "EvaluatorHealthKeyboardFirst", InputActionType.Button,
                "<Keyboard>/k");
            healthKeyboardProbe.performed += _ => firstKeyboardPerformed = true;
            healthKeyboardProbe.Enable();
            yield return driver.Press(Key.K);
            Assert.That(firstKeyboardPerformed, Is.True,
                "The first lease did not propagate Keyboard state through InputAction.");

            int clickCount = 0;
            UiClickTarget firstTarget =
                SignCircuitEvaluatorHealthSupport.CreateUguiHealthTarget(
                    healthRoot, "first", () => clickCount++);
            yield return null;
            firstTarget = SignCircuitEvaluatorHealthSupport.RequireTopHit(firstTarget);
            yield return driver.ClickButton(firstTarget);
            Assert.That(clickCount, Is.EqualTo(1),
                "The first lease did not reach the EventSystem top-hit callback.");
            string firstRoute = driver.LastUiRoute;

            healthKeyboardProbe.Dispose();
            healthKeyboardProbe = null;
            yield return driver.Dispose();
            driver = null;
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] first_lease_disposed");
            Assert.That(NativeInputDriver.ProcessDevicesNeutral, Is.True,
                "The first lease left a key or pointer button pressed.");
            AssertHostInputRestored(hostBackgroundBehavior,
#if UNITY_EDITOR
                hostEditorInputBehavior,
#endif
                hostMouse, hostKeyboard, "first");

            // Change both scene-owned UI action maps and an explicit action-map
            // layout before the second lease. Re-adding a device here reproduced
            // the old Input System action/map/binding/composite-count assertion.
            healthChangedLayout = new InputActionMap(
                "EvaluatorHealthChangedLayout");
            bool secondKeyboardPerformed = false;
            InputAction changedKeyboard = healthChangedLayout.AddAction(
                "ChangedKeyboard", InputActionType.Button, "<Keyboard>/k");
            changedKeyboard.performed += _ => secondKeyboardPerformed = true;
            healthChangedLayout.AddAction(
                "ChangedPointer", InputActionType.PassThrough,
                "<Pointer>/position");
            healthChangedLayout.AddAction(
                "ChangedClick", InputActionType.Button,
                "<Mouse>/leftButton");
            healthChangedLayout.Enable();
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] changed_layout_enabled");

            yield return SignCircuitEvaluatorHealthSupport.ReplaceWithIsolatedScene(
                "second", root => healthRoot = root);
            UiClickTarget secondTarget =
                SignCircuitEvaluatorHealthSupport.CreateUguiHealthTarget(
                    healthRoot, "second", () => clickCount++);
            yield return null;
            secondTarget = SignCircuitEvaluatorHealthSupport.RequireTopHit(secondTarget);

            driver = new NativeInputDriver();
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] second_lease_initialize");
            yield return driver.Initialize();
            Assert.That(driver.Ready, Is.True,
                "The second evaluator input-driver lease was not ready.");
            Assert.That(NativeInputDriver.ProcessDevicePairCreationCount,
                Is.EqualTo(pairCreationsBefore + 1),
                "The second lease added a new process device pair.");
            Assert.That(NativeInputDriver.ProcessMouseDeviceId,
                Is.EqualTo(firstMouseId),
                "The process Mouse changed across independent leases.");
            Assert.That(NativeInputDriver.ProcessKeyboardDeviceId,
                Is.EqualTo(firstKeyboardId),
                "The process Keyboard changed across independent leases.");
            Assert.That(NativeInputDriver.ProcessLeaseCount,
                Is.EqualTo(leasesBefore + 2),
                "The health testcase did not acquire two independent leases.");

            yield return driver.Press(Key.K);
            Assert.That(secondKeyboardPerformed, Is.True,
                "The changed InputAction layout did not receive the reused Keyboard.");
            yield return driver.ClickButton(secondTarget);
            Assert.That(clickCount, Is.EqualTo(2),
                "The second lease did not reach the reloaded top-hit callback.");
            string secondRoute = driver.LastUiRoute;

            yield return driver.Dispose();
            driver = null;
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] second_lease_disposed");
            Assert.That(NativeInputDriver.ProcessDevicesNeutral, Is.True,
                "The second lease left a key or pointer button pressed.");
            AssertHostInputRestored(hostBackgroundBehavior,
#if UNITY_EDITOR
                hostEditorInputBehavior,
#endif
                hostMouse, hostKeyboard, "second");
            AssertNoUnexpectedEvaluatorRuntimeErrors();
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] health_evidence_write");

            string outputDirectory = SignCircuitEvidenceWriter.OutputDirectory;
            Assert.That(string.IsNullOrWhiteSpace(outputDirectory), Is.False,
                "The evaluator evidence output argument is missing.");
            const string evidenceId =
                "EVALUATOR_REGRESSION_DynamicRuntimeHealth";
            SignCircuitEvidenceWriter.Write(evidenceId, new[]
            {
                "frame_advance=true",
                "independent_driver_leases=2",
                "process_device_pair_creations=1",
                "process_mouse_device_id_stable=true",
                "process_keyboard_device_id_stable=true",
                "input_action_layout_changed_between_leases=true",
                "scene_reloaded_between_leases=true",
                "keyboard_and_pointer_neutral_after_each=true",
                "host_input_restored_after_each=true",
                "eventsystem_top_hit=true",
                "compact_wide_real_status_locator_regression=true",
                "oversized_and_ambiguous_status_locators_rejected=true",
                "button_callback_count=2",
                "first_ui_route=" + firstRoute,
                "second_ui_route=" + secondRoute
            });
            string evidencePath = Path.Combine(
                outputDirectory, evidenceId + ".json");
            Assert.That(File.Exists(evidencePath), Is.True,
                "The evaluator evidence writer did not create its health record.");
            string evidence = File.ReadAllText(evidencePath);
            Assert.That(evidence, Does.Contain(evidenceId));
            Assert.That(evidence, Does.Contain("independent_driver_leases=2"));
            Debug.Log(
                "[OMNIGAME_EVALUATOR_HEALTH_PROGRESS] health_complete");
        }

        static void AssertHostInputRestored(
            InputSettings.BackgroundBehavior expectedBackground,
#if UNITY_EDITOR
            InputSettings.EditorInputBehaviorInPlayMode expectedEditorBehavior,
#endif
            Mouse expectedMouse,
            Keyboard expectedKeyboard,
            string lease)
        {
            Assert.That(InputSystem.settings.backgroundBehavior,
                Is.EqualTo(expectedBackground),
                $"The {lease} lease did not restore background input behavior.");
#if UNITY_EDITOR
            Assert.That(InputSystem.settings.editorInputBehaviorInPlayMode,
                Is.EqualTo(expectedEditorBehavior),
                $"The {lease} lease did not restore Editor input behavior.");
#endif
            if (expectedMouse != null && expectedMouse.added)
            {
                Assert.That(expectedMouse.enabled, Is.True,
                    $"The {lease} lease did not re-enable the host Mouse.");
                Assert.That(Mouse.current, Is.SameAs(expectedMouse),
                    $"The {lease} lease did not restore the current host Mouse.");
            }
            if (expectedKeyboard != null && expectedKeyboard.added)
            {
                Assert.That(expectedKeyboard.enabled, Is.True,
                    $"The {lease} lease did not re-enable the host Keyboard.");
                Assert.That(Keyboard.current, Is.SameAs(expectedKeyboard),
                    $"The {lease} lease did not restore the current host Keyboard.");
            }
        }

        [UnityTest, Order(1)]
        public IEnumerator DYN01_NativeKeyboardMovesAndJumps()
        {
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            Vector2 start = player.Position;

            yield return driver.Hold(Key.D, 0.60f, false);
            Vector2 afterMove = player.Position;
            Assert.That(afterMove.x, Is.GreaterThan(start.x + 0.25f),
                "Holding virtual D did not visibly move the observed avatar right.");

            float jumpStartY = player.Position.y;
            float peakY = jumpStartY;
            float peakVelocityY = player.Velocity.y;
            yield return driver.Press(Key.Space, false);
            float deadline = Time.realtimeSinceStartup + 1.1f;
            while (Time.realtimeSinceStartup < deadline)
            {
                // A realtime watchdog must keep advancing even if a candidate
                // freezes scaled simulation time in a visible terminal state.
                yield return null;
                peakY = Mathf.Max(peakY, player.Position.y);
                peakVelocityY = Mathf.Max(peakVelocityY, player.Velocity.y);
            }
            Assert.That(peakY > jumpStartY + 0.15f || peakVelocityY > 0.5f, Is.True,
                "Virtual Space produced no visible jump response. Rigidbody2D is not required.");

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.Write(nameof(DYN01_NativeKeyboardMovesAndJumps),
                new[]
                {
                    "avatar_discovery=bidirectional visible movement",
                    "avatar_path=" + player.ObservationPath,
                    $"start={start:F3}",
                    $"after_d={afterMove:F3}",
                    $"jump_peak_y={peakY:F3}",
                    $"optional_velocity_peak_y={peakVelocityY:F3}",
                    "input_route=virtual Keyboard device -> candidate-observed behavior"
                });
        }

        [UnityTest, Order(2)]
        public IEnumerator DYN02_RemoteInteractDoesNotAdvance()
        {
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            Assert.That(SignCircuitTestSupport.ReadProgress(out _), Is.EqualTo(0));
            string routeBefore = SignCircuitTestSupport.WorldVisualSignature(player);
            Vector2 positionBefore = player.Position;

            yield return driver.Press(Key.E, false);
            yield return null;
            yield return null;

            int progress = SignCircuitTestSupport.ReadProgress(out string source);
            string routeAfter = SignCircuitTestSupport.WorldVisualSignature(player);
            Assert.That(progress, Is.EqualTo(0),
                $"Pressing E at spawn advanced the circuit without proximity. Source: {source}");
            Assert.That(routeAfter, Is.EqualTo(routeBefore),
                "Pressing E at spawn changed visible route state without proximity.");
            Assert.That(Vector2.Distance(player.Position, positionBefore), Is.LessThan(0.08f),
                "Remote interaction moved or teleported the avatar.");
            Assert.That(SignCircuitTestSupport.IsFinishedVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.FailureIsVisible(), Is.False);

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.Write(nameof(DYN02_RemoteInteractDoesNotAdvance),
                new[]
                {
                    $"spawn={positionBefore:F3}",
                    "remote_e=true",
                    "visible_route_changed=false",
                    $"progress={progress}/3",
                    "terminal_state=false",
                    "input_route=virtual Keyboard E"
                });
        }

        [UnityTest, Order(3)]
        public IEnumerator DYN03_WrongStateDoesNotAdvance()
        {
            observedClosedBarrierX = float.NaN;
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            var observations = new List<string>();
            yield return CompleteNextStage("STOP", 1, player, observations);

            PenaltyObservation firstWrong = null;
            yield return DriveRightUntilPenalty(1, player, value => firstWrong = value);
            Assert.That(firstWrong, Is.Not.Null);
            Assert.That(firstWrong.ProgressAfter, Is.EqualTo(1),
                "The second checkpoint advanced while its route object remained unconfigured.");
            Assert.That(firstWrong.VisibleFeedbackChanged, Is.True,
                "The invalid checkpoint produced no distinguishable visible feedback.");
            yield return VisualEvidenceCapture.Capture("visual-03-core-interaction.png");

            float repeatedJump = 0f;
            yield return ObserveNoRepeatedPenalty(value => repeatedJump = value);
            Assert.That(repeatedJump, Is.LessThan(1.0f),
                "Remaining in one checkpoint entry repeatedly applied the 3-second penalty.");

            yield return SignCircuitTestSupport.DriveDistance(driver, player, -2.4f);
            PenaltyObservation reentry = null;
            yield return DriveRightUntilPenalty(1, player, value => reentry = value);
            Assert.That(reentry, Is.Not.Null,
                "Leaving and re-entering did not re-arm exactly one invalid-entry penalty.");

            yield return SignCircuitTestSupport.DriveDistance(driver, player, 1.2f);
            InteractionObservation configuredThird = null;
            yield return ConfigureNextVisibleInteraction(
                1, player, value => configuredThird = value);
            Assert.That(configuredThird, Is.Not.Null);
            Assert.That(SignCircuitTestSupport.ReadProgress(out _), Is.EqualTo(1),
                "Configuring the later route object advanced progress before crossing.");

            PenaltyObservation wrongOrder = null;
            yield return DriveRightUntilPenalty(1, player, value => wrongOrder = value);
            Assert.That(wrongOrder, Is.Not.Null);
            Assert.That(wrongOrder.ProgressAfter, Is.EqualTo(1),
                "A configured later checkpoint advanced before the missing middle stage.");

            RouteBlockObservation block = null;
            yield return SignCircuitTestSupport.DriveRightUntilBlocked(
                driver, player, value => block = value);
            observedClosedBarrierX = block.BlockedX;

            observations.Add($"wrong_state_penalty={firstWrong.PenaltySeconds:F2}");
            observations.Add("wrong_state_timer_before=" + firstWrong.TimerBeforeSource);
            observations.Add("wrong_state_timer_after=" + firstWrong.TimerAfterSource);
            observations.Add("wrong_state_status_before=" + firstWrong.StatusBeforeSource);
            observations.Add("wrong_state_status_after=" + firstWrong.StatusAfterSource);
            observations.Add($"continuous_entry_extra_penalty={repeatedJump:F2}");
            observations.Add($"reentry_penalty={reentry.PenaltySeconds:F2}");
            observations.Add($"wrong_order_penalty={wrongOrder.PenaltySeconds:F2}");
            observations.Add("progress_after_wrong_actions=1/3");
            observations.Add($"closed_route_block_x={block.BlockedX:F3}");
            observations.Add($"closed_route_stable_seconds={block.StableSeconds:F2}");
            observations.Add("route_discovery=visible changes + HUD progress; no sign type/collider query");
            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.Write(nameof(DYN03_WrongStateDoesNotAdvance),
                observations);
            DeleteInteractionTrace(nameof(DYN03_WrongStateDoesNotAdvance));
        }

        [UnityTest, Order(4)]
        public IEnumerator DYN04_StopUpRightOpensGateAndFinishes()
        {
            const string testId = nameof(DYN04_StopUpRightOpensGateAndFinishes);
            SignCircuitEvidenceWriter.BeginCheckpoints(testId, new[]
            {
                "D2-03_CORE_CIRCUIT_CONTENT_USABLE",
                "D3-03_SEQUENCE_GATE_FINISH_RULES",
                "D4-02_COMPLETE_SUCCESS_JOURNEY",
                "D5-02_CORE_FEEDBACK"
            });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D2-03_CORE_CIRCUIT_CONTENT_USABLE");
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            SignCircuitPersistenceSnapshot persistenceBefore =
                SignCircuitPersistenceProbe.Capture();
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            var observations = new List<string>();
            yield return CompleteNextStage("STOP", 1, player, observations);
            yield return CompleteNextStage("UP", 2, player, observations);
            yield return CompleteNextStage("RIGHT", 3, player, observations);
            Assert.That(SignCircuitTestSupport.ReadProgress(out _), Is.EqualTo(3));

            float crossingReference = float.IsNaN(observedClosedBarrierX)
                ? player.Position.x - 0.5f
                : observedClosedBarrierX;
            float maximumStep = 0f;
            yield return SignCircuitTestSupport.DriveRightUntilFinished(
                driver, player, crossingReference, value => maximumStep = value);
            yield return SignCircuitTestSupport.WaitForFinished();
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D2-03_CORE_CIRCUIT_CONTENT_USABLE", new[]
                {
                    "progress=3/3",
                    $"crossed_closed_route_reference_x={crossingReference:F3}",
                    $"maximum_frame_step={maximumStep:F3}",
                    "finish_reached=true"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(testId,
                "D3-03_SEQUENCE_GATE_FINISH_RULES");
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D3-03_SEQUENCE_GATE_FINISH_RULES", new[]
                {
                    "ordered_sequence=STOP-UP-RIGHT",
                    "gate_blocked_before_and_crossed_after=true",
                    "physical_finish_without_teleport=true"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(testId,
                "D4-02_COMPLETE_SUCCESS_JOURNEY");
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D4-02_COMPLETE_SUCCESS_JOURNEY", new[]
                {
                    "clean_start_to_physical_finish=true",
                    "success_visible=true"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(testId, "D5-02_CORE_FEEDBACK");
            Assert.That(SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.SuccessPanelId,
                    out successPanelSignature, out string successPanelSource), Is.True,
                "Success did not expose non-empty visible state text inside a " +
                "coherent real UI panel container matching " +
                "the public semantic rectangle. " + successPanelSource);
            Assert.That(SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.PausePanelId), Is.False);
            Assert.That(SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.FailurePanelId), Is.False);
            yield return VisualEvidenceCapture.Capture("visual-04-success.png");
            string bestTime = SignCircuitTestSupport.ReadBestTimeText(
                out string bestTimeSource);
            Assert.That(SignCircuitPersistenceProbe.TryParseNumber(
                bestTime, out _), Is.True,
                $"The visible best-time text has no numeric seconds: '{bestTime}'");

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.PassCheckpoint(testId, "D5-02_CORE_FEEDBACK",
                new[]
                {
                    "success_panel_signature=" + successPanelSignature,
                    "success_panel_source=" + successPanelSource,
                    "best_time_text=" + bestTime,
                    "best_time_source=" + bestTimeSource
                });

            observations.Add("progress=3/3");
            observations.Add($"crossed_closed_route_reference_x={crossingReference:F3}");
            observations.Add($"maximum_frame_step={maximumStep:F3}");
            observations.Add("success_visible=true");
            observations.Add("success_panel_signature=" + successPanelSignature);
            observations.Add("success_panel_source=" + successPanelSource);
            observations.Add("best_time_text=" + bestTime);
            observations.Add("best_time_source=" + bestTimeSource);
            SignCircuitEvidenceWriter.CompleteCheckpoints(testId, observations);

            SignCircuitPersistenceSnapshot persistenceAfter = null;
            SignCircuitPersistenceRecord persistedRecord = null;
            float persistenceDeadline = Time.realtimeSinceStartup + 3f;
            while (Time.realtimeSinceStartup < persistenceDeadline)
            {
                persistenceAfter = SignCircuitPersistenceProbe.Capture();
                persistedRecord = SignCircuitPersistenceProbe.FindChangedRecord(
                    persistenceBefore, persistenceAfter);
                if (persistedRecord != null) break;
                yield return new WaitForSecondsRealtime(0.1f);
            }
            // Persistence has its own scored trajectory. Keep the complete gameplay
            // journey independent when a no-persistence mutant is calibrated.
            SignCircuitEvidenceWriter.WriteFreshSeed(
                bestTime, persistenceBefore, persistenceAfter, persistedRecord);
            DeleteInteractionTrace(testId);
        }

        [UnityTest, Order(5)]
        public IEnumerator DYN05_PauseAndUiRestartUseNativeInput()
        {
            const string testId = nameof(DYN05_PauseAndUiRestartUseNativeInput);
            SignCircuitEvidenceWriter.BeginCheckpoints(testId, new[]
            {
                "D3-04_PAUSE_RULES",
                "D2-04_PAUSE_AND_RESTART_CONTENT",
                "D5-05_PAUSE_RESTART_USABILITY",
                "D4-03_PAUSE_RESUME_UI_RESTART"
            });
            SignCircuitEvidenceWriter.EnterCheckpoint(testId, "D3-04_PAUSE_RULES");
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            Vector2 spawn = player.Position;
            yield return CompleteNextStage("STOP", 1, player, new List<string>());

            yield return driver.Press(Key.Escape, false);
            yield return null;
            Assert.That(SignCircuitTestSupport.PauseIsVisible(), Is.True,
                "Escape did not show a visible pause state.");
            Assert.That(SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.PausePanelId,
                    out pausePanelSignature, out string pausePanelSource), Is.True,
                "Pause did not expose non-empty visible state text inside a " +
                "coherent real UI panel container matching " +
                "the public semantic rectangle. " + pausePanelSource);
            if (!string.IsNullOrWhiteSpace(successPanelSignature))
            {
                Assert.That(pausePanelSignature, Is.Not.EqualTo(successPanelSignature),
                    "Pause and success expose indistinguishable player-facing panel text.");
            }
            float pausedTimerStart = SignCircuitTestSupport.ReadTimerSeconds(out _);
            int pausedProgress = SignCircuitTestSupport.ReadProgress(out _);
            Vector2 pausedPosition = player.Position;
            yield return driver.Hold(Key.D, 0.35f, false);
            float pausedTimerEnd = SignCircuitTestSupport.ReadTimerSeconds(out _);
            float pausedMovementDelta = Vector2.Distance(player.Position, pausedPosition);
            Assert.That(pausedMovementDelta, Is.LessThan(0.06f),
                "Horizontal movement was not frozen while paused.");
            Assert.That(Mathf.Abs(pausedTimerStart - pausedTimerEnd), Is.LessThan(0.15f),
                "The visible countdown advanced while paused.");
            Assert.That(SignCircuitTestSupport.ReadProgress(out _), Is.EqualTo(pausedProgress));

            yield return driver.Press(Key.Escape, false);
            yield return null;
            Assert.That(SignCircuitTestSupport.PauseIsVisible(), Is.False,
                "The second Escape did not visibly resume the same run.");
            Assert.That(SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.PausePanelId), Is.False,
                "The pause locator still overlapped real visible panel text after resume.");
            float resumedTimerStart = SignCircuitTestSupport.ReadTimerSeconds(out _);
            yield return new WaitForSecondsRealtime(0.25f);
            float resumedTimerEnd = SignCircuitTestSupport.ReadTimerSeconds(out _);
            Assert.That(resumedTimerEnd, Is.LessThan(resumedTimerStart - 0.08f),
                "The countdown did not continue after leaving pause.");
            SignCircuitEvidenceWriter.PassCheckpoint(testId, "D3-04_PAUSE_RULES",
                new[]
                {
                    "pause_visible=true",
                    $"pause_timer_delta={pausedTimerStart - pausedTimerEnd:F2}",
                    $"pause_avatar_delta={pausedMovementDelta:F3}",
                    "second_escape_resumed_same_run=true"
                });

            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D2-04_PAUSE_AND_RESTART_CONTENT");
            yield return driver.Press(Key.Escape, false);
            yield return null;
            UiClickTarget restart = SignCircuitTestSupport.FindRestartButton();
            int beforeBoundaryProgress = SignCircuitTestSupport.ReadProgress(out _);
            yield return driver.PressOutsideReleaseTarget(restart.ScreenPoint);
            Assert.That(SignCircuitTestSupport.PauseIsVisible(), Is.True,
                "Pressing outside and releasing over Restart activated the control.");
            Assert.That(SignCircuitTestSupport.ReadProgress(out _),
                Is.EqualTo(beforeBoundaryProgress));
            yield return driver.PressTargetReleaseOutside(restart.ScreenPoint);
            Assert.That(SignCircuitTestSupport.PauseIsVisible(), Is.True,
                "Pressing Restart but releasing outside activated the control.");
            Assert.That(SignCircuitTestSupport.ReadProgress(out _),
                Is.EqualTo(beforeBoundaryProgress));
            yield return driver.ClickButton(restart);
            yield return SignCircuitTestSupport.WaitForProgress(0, 4f);
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D2-04_PAUSE_AND_RESTART_CONTENT", new[]
                {
                    "pause_content_present=true",
                    "visible_restart_activated=true",
                    "restart_progress=0/3"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D5-05_PAUSE_RESTART_USABILITY");
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D5-05_PAUSE_RESTART_USABILITY", new[]
                {
                    "pause_panel_signature=" + pausePanelSignature,
                    "ui_restart_label=" + restart.Label,
                    "press_outside_release_inside_did_not_restart=true",
                    "press_inside_release_outside_did_not_restart=true",
                    "ui_point=" + driver.LastUiPoint,
                    "ui_route=" + driver.LastUiRoute
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D4-03_PAUSE_RESUME_UI_RESTART");
            SignCircuitPlayer restarted = null;
            yield return AcquirePlayer(value => restarted = value);
            Assert.That(SignCircuitTestSupport.PauseIsVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.ReadTimerSeconds(out _), Is.InRange(28f, 30.1f));
            Assert.That(Vector2.Distance(restarted.Position, spawn), Is.LessThan(1.2f));

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D4-03_PAUSE_RESUME_UI_RESTART", new[]
                {
                    "pause_resume_completed=true",
                    "restart_clean_progress=0/3",
                    "restart_timer=30",
                    "restart_spawn_restored=true"
                });
            SignCircuitEvidenceWriter.CompleteCheckpoints(testId,
                new[]
                {
                    "pause_visible=true",
                    "pause_panel_signature=" + pausePanelSignature,
                    "pause_panel_source=" + pausePanelSource,
                    $"pause_timer_delta={pausedTimerStart - pausedTimerEnd:F2}",
                    $"pause_avatar_delta={pausedMovementDelta:F3}",
                    "resume_timer_running=true",
                    "ui_restart_label=" + restart.Label,
                    "press_outside_release_inside_did_not_restart=true",
                    "press_inside_release_outside_did_not_restart=true",
                    "ui_point=" + driver.LastUiPoint,
                    "ui_route=" + driver.LastUiRoute,
                    "restart_progress=0/3",
                    "restart_timer=30",
                    "timescale_implementation_not_required=true"
                });
            DeleteInteractionTrace(testId);
        }

        [UnityTest, Order(6)]
        public IEnumerator DYN06_RRestartResetsCircuit()
        {
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            Vector2 spawn = player.Position;
            string initialRouteVisual = SignCircuitTestSupport.WorldVisualSignature(player);
            string bestBefore = SignCircuitTestSupport.ReadBestTimeText();
            yield return CompleteNextStage("STOP", 1, player, new List<string>());

            yield return driver.Press(Key.R, false);
            yield return SignCircuitTestSupport.WaitForProgress(0, 4f);
            SignCircuitPlayer restarted = null;
            yield return AcquirePlayer(value => restarted = value);
            string restartedVisual = SignCircuitTestSupport.WorldVisualSignature(restarted);
            Assert.That(Vector2.Distance(restarted.Position, spawn), Is.LessThan(1.2f));
            Assert.That(SignCircuitTestSupport.ReadTimerSeconds(out _), Is.InRange(28f, 30.1f));
            Assert.That(restartedVisual, Is.EqualTo(initialRouteVisual),
                "Keyboard restart did not restore the authored visible route state.");
            Assert.That(SignCircuitTestSupport.ReadBestTimeText(), Is.EqualTo(bestBefore),
                "Keyboard restart cleared or changed the saved best-time display.");
            Assert.That(SignCircuitTestSupport.PauseIsVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.IsFinishedVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.FailureIsVisible(), Is.False);

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.Write(nameof(DYN06_RRestartResetsCircuit),
                new[]
                {
                    "keyboard_r=true",
                    "progress=0/3",
                    "timer=30",
                    "spawn_restored=true",
                    "route_visual_restored=true",
                    "terminal_panels_hidden=true",
                    "best_preserved=true"
                });
            DeleteInteractionTrace(nameof(DYN06_RRestartResetsCircuit));
        }

        [UnityTest, Order(7)]
        public IEnumerator DYN07_OriginalLevel1Plus2StillMoves()
        {
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.RegressionScenePath);
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            JumpAttempt jump = new JumpAttempt();
            yield return AttemptUpstreamJump(Key.Space, player, jump);
            if (!jump.Success)
            {
                yield return SignCircuitTestSupport.LoadScene(
                    SignCircuitContract.RegressionScenePath);
                player = null;
                yield return AcquirePlayer(value => player = value);
                jump = new JumpAttempt();
                yield return AttemptUpstreamJump(Key.W, player, jump);
            }
            Assert.That(jump.Success, Is.True,
                "Neither documented upstream jump key produced a visible jump response. " +
                jump.Summary);

            Vector2 start = player.Position;
            yield return driver.Hold(Key.D, 0.45f, false);
            Vector2 afterRight = player.Position;
            yield return driver.Hold(Key.A, 0.65f, false);
            Vector2 afterLeft = player.Position;
            Assert.That(afterRight.x - start.x > 0.2f ||
                        afterLeft.x - afterRight.x < -0.2f, Is.True,
                "The preserved Level1+2 avatar did not visibly move horizontally.");
            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.Write(nameof(DYN07_OriginalLevel1Plus2StillMoves),
                new[]
                {
                    $"start={start:F3}",
                    $"after_d={afterRight:F3}",
                    $"after_a={afterLeft:F3}",
                    jump.Summary,
                    "player_component_contract=none"
                });
        }

        [UnityTest, Order(8)]
        public IEnumerator DYN08_MenuEntryLoadsCanonicalScene()
        {
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MenuScenePath);
            UiClickTarget entry =
                SignCircuitTestSupport.FindVisibleActionTarget("menu.sign_circuit");
            // Resolve the actual player-facing target before evidence capture. The
            // capture helper temporarily switches overlay canvases to a fixed
            // camera/render target and must never become part of click discovery.
            yield return VisualEvidenceCapture.Capture("visual-01-menu.png");
            yield return driver.ClickButton(entry);

            float deadline = Time.realtimeSinceStartup + 8f;
            while (SceneManager.GetActiveScene().path != SignCircuitContract.MainScenePath &&
                   Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }
            Assert.That(SceneManager.GetActiveScene().path,
                Is.EqualTo(SignCircuitContract.MainScenePath),
                "The visible SIGN CIRCUIT menu entry did not load the challenge scene.");
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            Assert.That(player, Is.Not.Null);

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.Write(nameof(DYN08_MenuEntryLoadsCanonicalScene),
                new[]
                {
                    "menu_entry_visible=true",
                    "menu_entry_label=" + entry.Label,
                    "ui_backend=" + entry.Backend,
                    "ui_point=" + driver.LastUiPoint,
                    "ui_route=" + driver.LastUiRoute,
                    "loaded_scene=" + SignCircuitContract.MainScenePath
                });
        }

        [UnityTest, Order(9)]
        public IEnumerator DYN09_InitialContentAndHudAreComplete()
        {
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            yield return VisualEvidenceCapture.Capture("visual-02-initial-gameplay.png");
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);

            int progress = SignCircuitTestSupport.ReadProgress(out string progressText);
            float timer = SignCircuitTestSupport.ReadTimerSeconds(out string timerText);
            string best = SignCircuitTestSupport.ReadBestTimeText(
                out string bestSource);
            string status = SignCircuitTestSupport.ReadStatusText(
                out string statusSource);
            int visibleWorldContent =
                SignCircuitTestSupport.VisibleWorldContentCount(player);
            string routeSignature = SignCircuitTestSupport.WorldVisualSignature(player);
            Assert.That(progress, Is.EqualTo(0));
            Assert.That(timer, Is.InRange(28f, 30.1f));
            Assert.That(visibleWorldContent, Is.GreaterThanOrEqualTo(6),
                "The running challenge did not expose a visibly assembled route.");
            Assert.That(string.IsNullOrWhiteSpace(routeSignature), Is.False);
            Assert.That(SignCircuitTestSupport.PauseIsVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.IsFinishedVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.FailureIsVisible(), Is.False);

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.Write(nameof(DYN09_InitialContentAndHudAreComplete),
                new[]
                {
                    "visible_route_assembly=true",
                    $"visible_world_content_count={visibleWorldContent}",
                    "route functionality independently exercised by DYN03/DYN04",
                    "progress_text=" + progressText,
                    "timer_text=" + timerText,
                    "best_text=" + best,
                    "best_source=" + bestSource,
                    "status_text=" + status,
                    "status_source=" + statusSource,
                    "terminal_panels_hidden=true",
                    "component_type_requirements=none"
                });
        }

        [UnityTest, Order(10)]
        public IEnumerator DYN10_TimeoutFailureAndUiRestart()
        {
            const string testId = nameof(DYN10_TimeoutFailureAndUiRestart);
            SignCircuitEvidenceWriter.BeginCheckpoints(testId, new[]
            {
                "D3-05_TIMEOUT_EXCLUSIVITY",
                "D2-05_FAILURE_CONTENT",
                "D5-06_FAILURE_RESTART_USABILITY",
                "D4-05_FAILURE_RETRY_FLOW"
            });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D3-05_TIMEOUT_EXCLUSIVITY");
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            Vector2 spawn = player.Position;
            Assert.That(SignCircuitTestSupport.ReadProgress(out _), Is.EqualTo(0));
            Assert.That(SignCircuitTestSupport.FailureIsVisible(), Is.False);

            float countdownStarted = Time.realtimeSinceStartup;
            float timeoutDeadline = countdownStarted + 35f;
            while (!SignCircuitTestSupport.FailureIsVisible() &&
                   Time.realtimeSinceStartup < timeoutDeadline)
            {
                SignCircuitTestSupport.ReadTimerSeconds(out _);
                yield return null;
            }
            float countdownElapsed = Time.realtimeSinceStartup - countdownStarted;
            Assert.That(SignCircuitTestSupport.FailureIsVisible(), Is.True,
                "Natural countdown expiry did not show the required failure state.");
            Assert.That(SignCircuitSemanticUiObserver.IsPanelVisible(
                SignCircuitSemanticUiObserver.FailurePanelId,
                    out failurePanelSignature, out string failurePanelSource), Is.True,
                "Failure did not expose non-empty visible state text inside a " +
                "coherent real UI panel container matching " +
                "the public semantic rectangle. " + failurePanelSource);
            if (!string.IsNullOrWhiteSpace(successPanelSignature))
            {
                Assert.That(failurePanelSignature, Is.Not.EqualTo(successPanelSignature),
                    "Failure and success expose indistinguishable player-facing panel text.");
            }
            if (!string.IsNullOrWhiteSpace(pausePanelSignature))
            {
                Assert.That(failurePanelSignature, Is.Not.EqualTo(pausePanelSignature),
                    "Failure and pause expose indistinguishable player-facing panel text.");
            }
            Assert.That(SignCircuitTestSupport.IsFinishedVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.ReadProgress(out _), Is.EqualTo(0));
            Assert.That(SignCircuitTestSupport.ReadTimerSeconds(out _), Is.InRange(0f, 0.1f));
            yield return VisualEvidenceCapture.Capture("visual-05-failure.png");

            Vector2 terminalPosition = player.Position;
            yield return driver.Hold(Key.D, 0.30f, false);
            Assert.That(Vector2.Distance(player.Position, terminalPosition), Is.LessThan(0.06f),
                "Gameplay movement continued after timeout failure.");
            Assert.That(SignCircuitTestSupport.ReadTimerSeconds(out _), Is.InRange(0f, 0.1f));
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D3-05_TIMEOUT_EXCLUSIVITY", new[]
                {
                    $"natural_countdown_elapsed={countdownElapsed:F2}",
                    "failure_visible=true",
                    "success_visible=false",
                    "terminal_movement_frozen=true",
                    "terminal_timer_zero=true"
                });

            SignCircuitEvidenceWriter.EnterCheckpoint(testId, "D2-05_FAILURE_CONTENT");
            UiClickTarget restart = SignCircuitTestSupport.FindRestartButton();
            SignCircuitEvidenceWriter.PassCheckpoint(testId, "D2-05_FAILURE_CONTENT",
                new[]
                {
                    "failure_panel_signature=" + failurePanelSignature,
                    "failure_panel_source=" + failurePanelSource,
                    "visible_top_hit_restart_present=true"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D5-06_FAILURE_RESTART_USABILITY");
            yield return driver.ClickButton(restart);
            yield return SignCircuitTestSupport.WaitForProgress(0, 4f);
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D5-06_FAILURE_RESTART_USABILITY", new[]
                {
                    "failure_feedback_visible=true",
                    "restart_label=" + restart.Label,
                    "ui_point=" + driver.LastUiPoint,
                    "ui_route=" + driver.LastUiRoute,
                    "restart_progress=0/3"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(testId, "D4-05_FAILURE_RETRY_FLOW");
            SignCircuitPlayer restarted = null;
            yield return AcquirePlayer(value => restarted = value);
            Assert.That(SignCircuitTestSupport.FailureIsVisible(), Is.False);
            Assert.That(SignCircuitTestSupport.ReadTimerSeconds(out _), Is.InRange(28f, 30.1f));
            Assert.That(Vector2.Distance(restarted.Position, spawn), Is.LessThan(1.2f));

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.PassCheckpoint(testId, "D4-05_FAILURE_RETRY_FLOW",
                new[]
                {
                    "failure_retry_completed=true",
                    "restart_timer=30",
                    "restart_spawn_restored=true"
                });
            SignCircuitEvidenceWriter.CompleteCheckpoints(testId,
                new[]
                {
                    "setup_progress=0/3",
                    $"natural_countdown_elapsed={countdownElapsed:F2}",
                    "failure_visible=true",
                    "failure_panel_signature=" + failurePanelSignature,
                    "failure_panel_source=" + failurePanelSource,
                    "success_visible=false",
                    "terminal_movement_frozen=true",
                    "terminal_timer_zero=true",
                    "ui_restart=true",
                    "restart_progress=0/3",
                    "restart_timer=30",
                    "timescale_implementation_not_required=true"
                });
        }

        [UnityTest, Order(11)]
        public IEnumerator DYN11_SlowerRunDoesNotOverwriteBestTime()
        {
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MainScenePath);
            string seedPath = Path.Combine(
                SignCircuitEvidenceWriter.OutputDirectory, "fresh-seed.json");
            if (!File.Exists(seedPath))
            {
                Assert.Fail("[OMNIGAME_CANDIDATE_BLOCKED] The prior canonical success " +
                            "did not create persistence seed evidence; the slower-run " +
                            "persistence check is blocked by a missing candidate prerequisite.");
            }
            SignCircuitFreshSeed priorSeed = JsonUtility.FromJson<SignCircuitFreshSeed>(
                File.ReadAllText(seedPath));
            Assert.That(priorSeed?.persisted_record, Is.Not.Null,
                "The canonical success had no new or changed durable backing record.");
            string firstText = SignCircuitTestSupport.ReadBestTimeText();
            Assert.That(SignCircuitPersistenceProbe.TryParseNumber(
                firstText, out double firstBest), Is.True);
            SignCircuitPersistenceSnapshot beforeSlower =
                SignCircuitPersistenceProbe.Capture();

            // The same normal route is deliberately delayed, making it slower than
            // the earlier DYN04 route without altering candidate internals.
            yield return driver.Initialize();
            float visibleTimerBeforeDelay =
                SignCircuitTestSupport.ReadTimerSeconds(out _);
            float delay = Mathf.Clamp((float)firstBest * 0.25f, 2.0f, 6.0f);
            float delayDeadline = Time.realtimeSinceStartup + delay;
            while (Time.realtimeSinceStartup < delayDeadline) yield return null;
            float visibleTimerAfterDelay =
                SignCircuitTestSupport.ReadTimerSeconds(out _);
            Assert.That(visibleTimerAfterDelay,
                Is.LessThanOrEqualTo(visibleTimerBeforeDelay - 1.0f),
                "The deliberate slower-run delay did not materially advance the " +
                "visible game timer after native input initialization.");

            SignCircuitPlayer player = null;
            yield return AcquirePlayer(value => player = value);
            yield return CompleteNextStage("STOP", 1, player, new List<string>());
            yield return CompleteNextStage("UP", 2, player, new List<string>());
            yield return CompleteNextStage("RIGHT", 3, player, new List<string>());
            yield return SignCircuitTestSupport.DriveRightUntilFinished(
                driver, player, player.Position.x - 0.5f, _ => { });
            yield return SignCircuitTestSupport.WaitForFinished();
            string secondText = SignCircuitTestSupport.ReadBestTimeText();
            Assert.That(SignCircuitPersistenceProbe.TryParseNumber(
                secondText, out double secondBest), Is.True);
            Assert.That(secondBest, Is.EqualTo(firstBest).Within(0.025d),
                "A deliberately slower later run overwrote the faster best-time display.");

            SignCircuitPersistenceSnapshot afterSlower =
                SignCircuitPersistenceProbe.Capture();
            SignCircuitPersistenceRecord currentRecord =
                SignCircuitPersistenceProbe.FindRecordByIdentity(
                    afterSlower, priorSeed.persisted_record);
            Assert.That(currentRecord, Is.Not.Null,
                "The durable record selected after canonical success disappeared during " +
                "the slower-run comparison. Its encoding/value representation is not interpreted.");
            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.WriteFreshSeed(
                secondText, beforeSlower, afterSlower, currentRecord);
            SignCircuitEvidenceWriter.Write(nameof(DYN11_SlowerRunDoesNotOverwriteBestTime),
                new[]
                {
                    $"first_best={firstBest:F2}",
                    $"slower_run_delay={delay:F2}",
                    $"delay_timer_before={visibleTimerBeforeDelay:F2}",
                    $"delay_timer_after={visibleTimerAfterDelay:F2}",
                    $"delay_timer_progress={visibleTimerBeforeDelay - visibleTimerAfterDelay:F2}",
                    $"second_visible_best={secondBest:F2}",
                    "best_unchanged=true",
                    "persisted_record=" + currentRecord.id,
                    "persisted_record_kind=" + currentRecord.kind,
                    "backing_numeric_equivalence_required=false"
                });
            DeleteInteractionTrace(nameof(DYN11_SlowerRunDoesNotOverwriteBestTime));
        }

        [UnityTest, Order(12)]
        public IEnumerator DYN12_OriginalMenuLevelAndContinueRemainUsable()
        {
            const string testId = nameof(DYN12_OriginalMenuLevelAndContinueRemainUsable);
            SignCircuitEvidenceWriter.BeginCheckpoints(testId, new[]
            {
                "D2-07_LEGACY_MENU_CONTENT_USABLE",
                "D5-07_LEGACY_MENU_CONTROLS_USABLE",
                "D4-08_LEGACY_MENU_LEVEL_CONTINUE_FLOW"
            });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D2-07_LEGACY_MENU_CONTENT_USABLE");
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MenuScenePath);
            UiClickTarget levels =
                SignCircuitTestSupport.FindVisibleActionTarget("menu.levels");
            Assert.That(string.IsNullOrWhiteSpace(levels.Label), Is.False,
                "The preserved Levels control has no real visible readable label.");
            yield return driver.ClickButton(levels);
            yield return null;

            UiClickTarget originalLevel =
                SignCircuitTestSupport.FindVisibleActionTarget("menu.original_level");
            Assert.That(string.IsNullOrWhiteSpace(originalLevel.Label), Is.False,
                "The preserved original level entry has no real visible readable label.");
            yield return driver.ClickButton(originalLevel);

            float levelDeadline = Time.realtimeSinceStartup + 10f;
            while (SceneManager.GetActiveScene().path == SignCircuitContract.MenuScenePath &&
                   Time.realtimeSinceStartup < levelDeadline)
            {
                yield return null;
            }
            string selectedLevelPath = SceneManager.GetActiveScene().path;
            Assert.That(selectedLevelPath, Is.EqualTo(SignCircuitContract.RegressionScenePath),
                "The preserved original Level 1 entry did not load the supplied Level1+2 scene.");

            // Reloading Menu is isolated testcase setup. Continue itself is still
            // activated only through a real visible top-hit pointer sequence.
            yield return SignCircuitTestSupport.LoadScene(SignCircuitContract.MenuScenePath);
            UiClickTarget continueTarget =
                SignCircuitTestSupport.FindVisibleActionTarget("menu.continue");
            Assert.That(string.IsNullOrWhiteSpace(continueTarget.Label), Is.False,
                "The preserved Continue control has no real visible readable label.");
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D2-07_LEGACY_MENU_CONTENT_USABLE", new[]
                {
                    "levels_label=" + levels.Label,
                    "original_level_label=" + originalLevel.Label,
                    "selected_level_scene=" + selectedLevelPath,
                    "continue_label=" + continueTarget.Label,
                    "all_controls_visible_and_top_hit=true"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D5-07_LEGACY_MENU_CONTROLS_USABLE");
            yield return driver.ClickButton(continueTarget);

            float continueDeadline = Time.realtimeSinceStartup + 10f;
            while (SceneManager.GetActiveScene().path == SignCircuitContract.MenuScenePath &&
                   Time.realtimeSinceStartup < continueDeadline)
            {
                yield return null;
            }
            Assert.That(SceneManager.GetActiveScene().path,
                Is.Not.EqualTo(SignCircuitContract.MenuScenePath),
                "Continue did not respond to normal top-hit pointer input.");
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D5-07_LEGACY_MENU_CONTROLS_USABLE", new[]
                {
                    "levels_route=" + levels.RouteDescription,
                    "original_level_route=" + originalLevel.RouteDescription,
                    "continue_route=" + continueTarget.RouteDescription,
                    "normal_pointer_down_frame_up=true",
                    "all_three_controls_operable=true"
                });
            SignCircuitEvidenceWriter.EnterCheckpoint(
                testId, "D4-08_LEGACY_MENU_LEVEL_CONTINUE_FLOW");
            Assert.That(SceneManager.GetActiveScene().path, Is.EqualTo(selectedLevelPath),
                "Continue did not return through normal UI to the selected original level.");

            AssertNoUnexpectedCandidateRuntimeErrors();
            SignCircuitEvidenceWriter.PassCheckpoint(testId,
                "D4-08_LEGACY_MENU_LEVEL_CONTINUE_FLOW", new[]
                {
                    "selected_level_scene=" + selectedLevelPath,
                    "continue_returned_to_same_scene=true"
                });
            SignCircuitEvidenceWriter.CompleteCheckpoints(testId,
                new[]
                {
                    "levels_label=" + levels.Label,
                    "levels_backend=" + levels.Backend,
                    "levels_route=" + levels.RouteDescription,
                    "original_level_label=" + originalLevel.Label,
                    "original_level_backend=" + originalLevel.Backend,
                    "original_level_route=" + originalLevel.RouteDescription,
                    "selected_level_scene=" + selectedLevelPath,
                    "continue_label=" + continueTarget.Label,
                    "continue_backend=" + continueTarget.Backend,
                    "continue_route=" + continueTarget.RouteDescription,
                    "normal_pointer_down_frame_up=true",
                    "business_method_invocation=false"
                });
        }

        IEnumerator AcquirePlayer(Action<SignCircuitPlayer> receive)
        {
            SignCircuitPlayer player = null;
            yield return SignCircuitTestSupport.DiscoverPlayer(
                driver, value => player = value);
            Assert.That(player, Is.Not.Null);
            receive(player);
        }

        IEnumerator ConfigureNextVisibleInteraction(
            int expectedProgressBefore,
            SignCircuitPlayer player,
            Action<InteractionObservation> receive,
            float timeoutSeconds = 14f)
        {
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            int attempts = 0;
            int unstableControlSamples = 0;
            int attemptsInsideCurrentLocator = 0;
            bool observedUnavailable = false;
            TraceInteraction(
                $"discovery_start progress={expectedProgressBefore},x={player.Position.x:F3}");
            while (Time.realtimeSinceStartup < deadline)
            {
                Assert.That(SignCircuitTestSupport.ReadProgress(out _),
                    Is.EqualTo(expectedProgressBefore),
                    "Progress changed before a nearby visible interaction was established.");

                Assert.That(SignCircuitTestSupport.TryReadInteractionAvailableHint(
                        out bool interactionAvailable, out string locatorSource), Is.True,
                    "The mandatory public read-only locator is unavailable or stale. " +
                    "It is used only to find a real interaction range, never as score proof.");

                // Each stage must leave the previous interaction range before a later
                // true range can be selected. This prevents E from toggling an already
                // completed sign when its large proximity trigger overlaps a checkpoint.
                if (!observedUnavailable)
                {
                    if (!interactionAvailable)
                    {
                        observedUnavailable = true;
                        TraceInteraction(
                            $"locator_unavailable_seen x={player.Position.x:F3};{locatorSource}");
                        continue;
                    }
                    yield return MoveRightDuringInteractionDiscovery(
                        expectedProgressBefore, player, 0.08f,
                        "leaving_previous_locator");
                    continue;
                }

                if (!interactionAvailable)
                {
                    attemptsInsideCurrentLocator = 0;
                    yield return MoveRightDuringInteractionDiscovery(
                        expectedProgressBefore, player, 0.08f,
                        "seeking_next_locator");
                    continue;
                }

                // The probe is now done: it only stopped movement inside a published
                // interaction range. Establish a long, real no-input visible baseline
                // before sending E, so the prompt/trigger transition cannot be mistaken
                // for the second, E-caused persistent sign response.
                InteractionControlWindow control = null;
                yield return CaptureStableInteractionControl(
                    expectedProgressBefore, player, value => control = value);
                if (control == null)
                {
                    unstableControlSamples++;
                    TraceInteraction(
                        $"locator_lost_while_settling x={player.Position.x:F3}");
                    continue;
                }

                string statusBefore = control.PreInput.Status;
                SignCircuitTestSupport.ReadStatusText(out string statusBeforeSource);
                float x = control.PreInput.PositionX;
                yield return driver.Press(Key.E, false);
                attempts++;
                attemptsInsideCurrentLocator++;
                InteractionResponseDecision decision = null;
                InteractionResponseSample acceptedSample = null;
                yield return ObservePersistentInteractionResponse(
                    control, player, (result, sample) =>
                    {
                        decision = result;
                        acceptedSample = sample;
                    });
                Assert.That(decision, Is.Not.Null,
                    "The evaluator did not produce an interaction-response decision.");
                TraceInteraction(
                    $"e_attempt={attempts},zone_attempt={attemptsInsideCurrentLocator}," +
                    $"x={x:F3},decision={decision.Reason}," +
                    $"status_changed={decision.StatusChanged}," +
                    $"nearby_changed={decision.NearbyVisualChanged}," +
                    $"penalty_jump={decision.MaximumPenaltyDiscontinuity:F3}");

                Assert.That(decision.Reason, Is.Not.EqualTo("progress_changed"),
                    "Progress changed during interaction discovery before route crossing.");
                Assert.That(decision.Reason, Is.Not.EqualTo("rejected_penalty_detected"),
                    "The interaction sweep reached a rejected checkpoint before " +
                    "a stable E-caused configuration response was established.");
                Assert.That(decision.Reason, Is.Not.EqualTo("invalid_sample")
                    .And.Not.EqualTo("invalid_configuration")
                    .And.Not.EqualTo("missing_sample"),
                    "The evaluator could not classify the interaction response: " +
                    decision.Reason);

                if (decision.Accepted)
                {
                    string statusAfter = acceptedSample.Status;
                    SignCircuitTestSupport.ReadStatusText(out string statusAfterSource);
                    receive?.Invoke(new InteractionObservation
                    {
                        PositionX = x,
                        Attempts = attempts,
                        VisualChanged = decision.NearbyVisualChanged,
                        StatusChanged = decision.StatusChanged,
                        DecisionReason = decision.Reason,
                        MaximumPenaltyDiscontinuity =
                            decision.MaximumPenaltyDiscontinuity,
                        UnstableControlSamples = unstableControlSamples,
                        LocatorSource = locatorSource,
                        StatusBefore = statusBefore,
                        StatusAfter = statusAfter,
                        StatusBeforeSource = statusBeforeSource,
                        StatusAfterSource = statusAfterSource
                    });
                    yield break;
                }

                // Retry E at most once in the same stable published range. If the first
                // native cadence was missed, the second remains ordinary player input;
                // after that, take only a tiny guarded step instead of sweeping across a
                // checkpoint and hiding a discovery defect.
                if (attemptsInsideCurrentLocator < 2)
                {
                    continue;
                }
                yield return MoveRightDuringInteractionDiscovery(
                    expectedProgressBefore, player, 0.04f,
                    "refining_inside_locator");
                attemptsInsideCurrentLocator = 0;
            }
            Assert.Fail("Sweeping the visible route with ordinary movement and nearby E input " +
                        "found no stable causal response inside a published interaction range. " +
                        "The probe was only a locator; no candidate type/name/collider/state " +
                        "was accepted as score proof.");
        }

        IEnumerator MoveRightDuringInteractionDiscovery(
            int expectedProgress,
            SignCircuitPlayer player,
            float seconds,
            string reason)
        {
            InteractionResponseSample before =
                CaptureInteractionResponseSample(player);
            yield return driver.Hold(Key.D, seconds, false);
            InteractionResponseSample after =
                CaptureInteractionResponseSample(player);
            float penalty = InteractionResponseClassifier.TimerDiscontinuity(before, after);
            TraceInteraction(
                $"move reason={reason},from={before.PositionX:F3},to={after.PositionX:F3}," +
                $"progress={before.Progress}->{after.Progress},penalty_jump={penalty:F3}");
            Assert.That(after.Progress, Is.EqualTo(expectedProgress),
                "Interaction discovery crossed a checkpoint before configuration.");
            Assert.That(penalty, Is.LessThan(2.2f),
                "Interaction discovery crossed a rejected checkpoint before " +
                "establishing a real E-caused response.");
        }

        IEnumerator CaptureStableInteractionControl(
            int expectedProgress,
            SignCircuitPlayer player,
            Action<InteractionControlWindow> receive,
            float timeoutSeconds = 1.8f,
            float stableSeconds = 0.30f)
        {
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            while (Time.realtimeSinceStartup < deadline)
            {
                driver.ReleaseKeyboard();
                yield return new WaitForFixedUpdate();
                Assert.That(SignCircuitTestSupport.TryReadInteractionAvailableHint(
                        out bool availableAtStart, out _), Is.True,
                    "The public interaction locator became unavailable while settling.");
                if (!availableAtStart)
                {
                    receive?.Invoke(null);
                    yield break;
                }

                InteractionResponseSample controlStart =
                    CaptureInteractionResponseSample(player);
                bool remainedAvailable = true;
                float stableDeadline = Time.realtimeSinceStartup + stableSeconds;
                while (Time.realtimeSinceStartup < stableDeadline)
                {
                    yield return null;
                    Assert.That(SignCircuitTestSupport.TryReadInteractionAvailableHint(
                            out bool stillAvailable, out _), Is.True,
                        "The public interaction locator became stale while settling.");
                    if (!stillAvailable)
                    {
                        remainedAvailable = false;
                        break;
                    }
                }

                if (!remainedAvailable)
                {
                    receive?.Invoke(null);
                    yield break;
                }

                InteractionResponseSample preInput =
                    CaptureInteractionResponseSample(player);
                float penalty = InteractionResponseClassifier.TimerDiscontinuity(
                    controlStart, preInput);
                TraceInteraction(
                    $"control_window x={controlStart.PositionX:F3}->{preInput.PositionX:F3}," +
                    $"progress={controlStart.Progress}->{preInput.Progress}," +
                    $"penalty_jump={penalty:F3}," +
                    $"stable={InteractionResponseClassifier.IsStableControl(controlStart, preInput)}");
                Assert.That(preInput.Progress, Is.EqualTo(expectedProgress),
                    "Progress changed while the visible interaction baseline was settling.");
                Assert.That(penalty, Is.LessThan(2.2f),
                    "A rejected checkpoint was reached while the interaction baseline settled.");
                if (InteractionResponseClassifier.IsStableControl(
                        controlStart, preInput))
                {
                    receive?.Invoke(new InteractionControlWindow
                    {
                        ControlStart = controlStart,
                        PreInput = preInput
                    });
                    yield break;
                }
            }

            Assert.Fail("The avatar, nearby visible feedback, or status never settled inside " +
                        "the published interaction range before E input.");
        }

        IEnumerator ObservePersistentInteractionResponse(
            InteractionControlWindow control,
            SignCircuitPlayer player,
            Action<InteractionResponseDecision, InteractionResponseSample> receive,
            float timeoutSeconds = 1.0f,
            float confirmationSeconds = 0.14f)
        {
            yield return new WaitForFixedUpdate();
            yield return null;
            InteractionResponseSample postInput =
                CaptureInteractionResponseSample(player);
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            InteractionResponseDecision latest = null;
            while (Time.realtimeSinceStartup < deadline)
            {
                float confirmDeadline =
                    Time.realtimeSinceStartup + confirmationSeconds;
                while (Time.realtimeSinceStartup < confirmDeadline)
                {
                    yield return null;
                }
                InteractionResponseSample confirm =
                    CaptureInteractionResponseSample(player);
                latest = InteractionResponseClassifier.Classify(
                    control.ControlStart, control.PreInput, postInput, confirm);
                TraceInteraction(
                    $"post_window from={postInput.PositionX:F3},to={confirm.PositionX:F3}," +
                    $"progress={postInput.Progress}->{confirm.Progress}," +
                    $"decision={latest.Reason}," +
                    $"penalty_jump={latest.MaximumPenaltyDiscontinuity:F3}");
                if (latest.Accepted || latest.Reason == "progress_changed" ||
                    latest.Reason == "rejected_penalty_detected" ||
                    latest.Reason == "invalid_sample" ||
                    latest.Reason == "invalid_configuration" ||
                    latest.Reason == "missing_sample")
                {
                    receive?.Invoke(latest, confirm);
                    yield break;
                }

                // Never press E again while a first response is still settling.
                // Promote the latest state to the candidate post state and require
                // the following window to confirm it persistently.
                postInput = confirm;
            }

            receive?.Invoke(latest ?? InteractionResponseClassifier.Classify(
                control.ControlStart, control.PreInput, postInput, postInput), postInput);
        }

        static InteractionResponseSample CaptureInteractionResponseSample(
            SignCircuitPlayer player)
        {
            Vector2 position = player.Position;
            return new InteractionResponseSample
            {
                NearbyVisual =
                    SignCircuitTestSupport.NearbyWorldVisualSignature(player),
                Status = SignCircuitTestSupport.ReadStatusText(out _),
                Progress = SignCircuitTestSupport.ReadProgress(out _),
                Timer = SignCircuitTestSupport.ReadTimerSeconds(out _),
                Realtime = Time.realtimeSinceStartup,
                PositionX = position.x,
                PositionY = position.y
            };
        }

        void TraceInteraction(string observation)
        {
            string testId = TestContext.CurrentContext.Test.Name;
            if (string.IsNullOrWhiteSpace(testId)) testId = "interaction-trajectory";
            if (interactionTrace.Count >= 180) interactionTrace.RemoveAt(0);
            interactionTrace.Add(
                $"realtime={Time.realtimeSinceStartup:F3};frame={Time.frameCount};" +
                observation);
            SignCircuitEvidenceWriter.WriteDiagnosticTrace(testId, interactionTrace);
        }

        static void DeleteInteractionTrace(string testId) =>
            SignCircuitEvidenceWriter.DeleteDiagnosticTrace(testId);

        IEnumerator CompleteNextStage(
            string publicStageLabel,
            int expectedProgress,
            SignCircuitPlayer player,
            ICollection<string> observations)
        {
            int previousProgress = expectedProgress - 1;
            InteractionObservation interaction = null;
            yield return ConfigureNextVisibleInteraction(
                previousProgress, player, value => interaction = value);
            Assert.That(interaction, Is.Not.Null);
            Assert.That(SignCircuitTestSupport.ReadProgress(out _), Is.EqualTo(previousProgress),
                $"{publicStageLabel} interaction advanced progress before route crossing.");

            string configuredVisual = SignCircuitTestSupport.WorldVisualSignature(player);
            float previousTimer = SignCircuitTestSupport.ReadTimerSeconds(out _);
            float previousRealtime = Time.realtimeSinceStartup;
            float deadline = Time.realtimeSinceStartup + 7f;
            try
            {
                while (SignCircuitTestSupport.ReadProgress(out _) != expectedProgress &&
                       Time.realtimeSinceStartup < deadline)
                {
                    driver.SetHeldKey(Key.D);
                    yield return null;
                    float timer = SignCircuitTestSupport.ReadTimerSeconds(out _);
                    float now = Time.realtimeSinceStartup;
                    float discontinuity = previousTimer - timer - (now - previousRealtime);
                    Assert.That(discontinuity, Is.LessThan(2.2f),
                        $"{publicStageLabel} configured interaction reached a rejected checkpoint.");
                    previousTimer = timer;
                    previousRealtime = now;
                }
            }
            finally
            {
                driver.ReleaseKeyboard();
            }
            yield return null;
            yield return SignCircuitTestSupport.WaitForProgress(expectedProgress);
            string acceptedVisual = SignCircuitTestSupport.WorldVisualSignature(player);
            Assert.That(acceptedVisual, Is.Not.EqualTo(configuredVisual),
                $"{publicStageLabel} progress advanced without persistent visible checkpoint/route feedback.");
            observations?.Add(
                $"{publicStageLabel}:interaction_x={interaction.PositionX:F2}," +
                $"e_attempts={interaction.Attempts},progress={expectedProgress}/3," +
                "visible_interaction=true,visible_acceptance=true," +
                $"accepted_by={interaction.DecisionReason}," +
                $"status_changed={interaction.StatusChanged.ToString().ToLowerInvariant()}," +
                $"nearby_visual_changed={interaction.VisualChanged.ToString().ToLowerInvariant()}," +
                $"unstable_control_samples={interaction.UnstableControlSamples}," +
                $"max_config_penalty_discontinuity={interaction.MaximumPenaltyDiscontinuity:F3}");
            observations?.Add(publicStageLabel + ":locator=" +
                              interaction.LocatorSource);
            observations?.Add(publicStageLabel + ":status_before_source=" +
                              interaction.StatusBeforeSource);
            observations?.Add(publicStageLabel + ":status_after_source=" +
                              interaction.StatusAfterSource);
        }

        IEnumerator DriveRightUntilPenalty(
            int expectedProgress,
            SignCircuitPlayer player,
            Action<PenaltyObservation> receive,
            float timeoutSeconds = 7f)
        {
            float previousTimer = SignCircuitTestSupport.ReadTimerSeconds(
                out string previousTimerSource);
            float previousRealtime = Time.realtimeSinceStartup;
            string statusBefore = SignCircuitTestSupport.ReadStatusText(
                out string statusBeforeSource);
            string visualBefore = SignCircuitTestSupport.WorldVisualSignature(player);
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            PenaltyObservation result = null;
            try
            {
                while (Time.realtimeSinceStartup < deadline)
                {
                    driver.SetHeldKey(Key.D);
                    yield return null;
                    float timer = SignCircuitTestSupport.ReadTimerSeconds(
                        out string timerSource);
                    float now = Time.realtimeSinceStartup;
                    float natural = now - previousRealtime;
                    float discontinuity = previousTimer - timer - natural;
                    if (discontinuity >= 2.35f)
                    {
                        int progress = SignCircuitTestSupport.ReadProgress(out _);
                        string statusAfter = SignCircuitTestSupport.ReadStatusText(
                            out string statusAfterSource);
                        string visualAfter = SignCircuitTestSupport.WorldVisualSignature(player);
                        result = new PenaltyObservation
                        {
                            PenaltySeconds = discontinuity,
                            PositionX = player.Position.x,
                            ProgressAfter = progress,
                            StatusBefore = statusBefore,
                            StatusAfter = statusAfter,
                            TimerBeforeSource = previousTimerSource,
                            TimerAfterSource = timerSource,
                            StatusBeforeSource = statusBeforeSource,
                            StatusAfterSource = statusAfterSource,
                            VisibleFeedbackChanged =
                                !string.Equals(statusBefore, statusAfter,
                                    StringComparison.Ordinal) ||
                                !string.Equals(visualBefore, visualAfter,
                                    StringComparison.Ordinal)
                        };
                        break;
                    }
                    Assert.That(SignCircuitTestSupport.ReadProgress(out _),
                        Is.EqualTo(expectedProgress),
                        "An invalid checkpoint advanced before its penalty was observable.");
                    previousTimer = timer;
                    previousTimerSource = timerSource;
                    previousRealtime = now;
                }
            }
            finally
            {
                driver.ReleaseKeyboard();
            }
            yield return null;
            Assert.That(result, Is.Not.Null,
                "Ordinary movement did not encounter the expected invalid checkpoint penalty.");
            Assert.That(result.PenaltySeconds, Is.InRange(2.35f, 3.65f),
                $"Invalid checkpoint penalty was not approximately 3.0 seconds: {result.PenaltySeconds:F2}");
            Assert.That(result.ProgressAfter, Is.EqualTo(expectedProgress));
            receive?.Invoke(result);
        }

        IEnumerator ObserveNoRepeatedPenalty(Action<float> receive)
        {
            float maximumDiscontinuity = 0f;
            float previousTimer = SignCircuitTestSupport.ReadTimerSeconds(out _);
            float previousRealtime = Time.realtimeSinceStartup;
            float deadline = Time.realtimeSinceStartup + 0.40f;
            while (Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                float timer = SignCircuitTestSupport.ReadTimerSeconds(out _);
                float now = Time.realtimeSinceStartup;
                maximumDiscontinuity = Mathf.Max(maximumDiscontinuity,
                    previousTimer - timer - (now - previousRealtime));
                previousTimer = timer;
                previousRealtime = now;
            }
            receive?.Invoke(maximumDiscontinuity);
        }

        IEnumerator AttemptUpstreamJump(
            Key key,
            SignCircuitPlayer player,
            JumpAttempt result)
        {
            yield return new WaitForFixedUpdate();
            float startY = player.Position.y;
            float peakY = startY;
            float peakVelocityY = player.Velocity.y;
            yield return driver.Press(key, false);
            float deadline = Time.realtimeSinceStartup + 0.9f;
            while (Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                peakY = Mathf.Max(peakY, player.Position.y);
                peakVelocityY = Mathf.Max(peakVelocityY, player.Velocity.y);
            }
            result.Key = key;
            result.DeviceInputDelivered = true;
            result.StartY = startY;
            result.PeakY = peakY;
            result.PeakVelocityY = peakVelocityY;
            result.PhysicalResponse = peakY > startY + 0.15f || peakVelocityY > 0.5f;
        }

        sealed class InteractionObservation
        {
            public float PositionX;
            public int Attempts;
            public bool VisualChanged;
            public bool StatusChanged;
            public string DecisionReason;
            public float MaximumPenaltyDiscontinuity;
            public int UnstableControlSamples;
            public string LocatorSource;
            public string StatusBefore;
            public string StatusAfter;
            public string StatusBeforeSource;
            public string StatusAfterSource;
        }

        sealed class InteractionControlWindow
        {
            public InteractionResponseSample ControlStart;
            public InteractionResponseSample PreInput;
        }

        sealed class PenaltyObservation
        {
            public float PenaltySeconds;
            public float PositionX;
            public int ProgressAfter;
            public string StatusBefore;
            public string StatusAfter;
            public string TimerBeforeSource;
            public string TimerAfterSource;
            public string StatusBeforeSource;
            public string StatusAfterSource;
            public bool VisibleFeedbackChanged;
        }

        sealed class JumpAttempt
        {
            public Key Key;
            public bool DeviceInputDelivered;
            public bool PhysicalResponse;
            public float StartY;
            public float PeakY;
            public float PeakVelocityY;
            public bool Success => DeviceInputDelivered && PhysicalResponse;
            public string Summary =>
                $"jump_key={Key},device_input={DeviceInputDelivered}," +
                $"visible_response={PhysicalResponse},start_y={StartY:F3}," +
                $"peak_y={PeakY:F3},optional_velocity_y={PeakVelocityY:F3}";
        }
    }
}
