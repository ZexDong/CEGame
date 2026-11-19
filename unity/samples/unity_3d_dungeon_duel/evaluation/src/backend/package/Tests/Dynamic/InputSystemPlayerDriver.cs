using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    /// <summary>
    /// Sends scored actions through real virtual Input System Mouse and Keyboard
    /// devices. Candidate InputAction callbacks, Physics hits, Colliders, and
    /// NavMesh samples are retained only as diagnostics. The scored route is the
    /// cross-frame virtual-device cadence; gameplay consequences are checked by
    /// the trajectory immediately after each routed action.
    /// </summary>
    internal sealed class InputSystemPlayerDriver
    {
        const float PointerTolerancePixels = 1.5f;

        Mouse virtualMouse;
        Keyboard virtualKeyboard;
        Mouse previousMouse;
        Keyboard previousKeyboard;
        readonly List<InputDevice> disabledDevices = new List<InputDevice>();
        InputSettings.BackgroundBehavior previousBackgroundBehavior;
        bool changedBackgroundBehavior;
#if UNITY_EDITOR
        InputSettings.EditorInputBehaviorInPlayMode previousEditorInputBehavior;
        bool changedEditorInputBehavior;
#endif

        public IEnumerator ClickWorld(
            Vector3 world,
            MouseButton button,
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId,
            bool allowExpectedOccluder = false)
        {
            TrajectoryStepEvidence step = recorder.Step(stepId);
            float started = Time.realtimeSinceStartup;
            yield return EnsureReady(recorder, stepId, routeCheckId);
            if (recorder.HasBlockingFailure)
            {
                yield break;
            }

            Camera camera = GameplayCamera();
            if (camera == null)
            {
                recorder.Fail(stepId, routeCheckId, "enabled gameplay camera", "missing",
                    "No gameplay camera is available for the world input route.");
                yield break;
            }

            if (!TryProjectVisible(camera, world, out Vector2 screen, out Vector3 projected))
            {
                recorder.Fail(stepId, routeCheckId, "camera-visible gameplay-space target",
                    $"screen=({projected.x:F1},{projected.y:F1},{projected.z:F1})",
                    "The requested world target is outside the gameplay camera.");
                yield break;
            }

            Physics.SyncTransforms();
            Ray ray = camera.ScreenPointToRay(screen);
            bool physicsHit = Physics.Raycast(ray, out RaycastHit hit, 250f, ~0,
                QueryTriggerInteraction.Ignore);
            bool navHit = NavMesh.SamplePosition(world, out NavMeshHit navSample,
                2f, NavMesh.AllAreas);
            string targetObservation =
                $"world={world:F2}; screen=({screen.x:F1},{screen.y:F1}); " +
                (physicsHit
                    ? $"optionalPhysics={hit.collider.name}@{hit.point:F2}"
                    : "optionalPhysics=<none>") + "; " +
                (navHit
                    ? $"optionalNavMesh={navSample.position:F2}"
                    : "optionalNavMesh=<none>") +
                (allowExpectedOccluder ? "; behind-gate route requested" : string.Empty);

            var delivery = new InputDeliveryEvidence();
            yield return InjectMouseClick(screen, button, delivery);
            ApplyDelivery(step, delivery, targetObservation);
            RecordMouseDelivery(recorder, stepId, routeCheckId, button, delivery,
                targetObservation);

            step.elapsed_ms = (Time.realtimeSinceStartup - started) * 1000.0;
            step.frame_end = Time.frameCount;
        }

        public IEnumerator ClickActor(
            GameObject target,
            MouseButton button,
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId)
        {
            TrajectoryStepEvidence step = recorder.Step(stepId);
            float started = Time.realtimeSinceStartup;
            yield return EnsureReady(recorder, stepId, routeCheckId);
            if (recorder.HasBlockingFailure)
            {
                yield break;
            }

            if (target == null || !target.activeInHierarchy)
            {
                recorder.Fail(stepId, routeCheckId, "active visible actor pointer target",
                    target == null ? "null" : "inactive",
                    "Native semantic discovery did not expose a usable actor target.");
                yield break;
            }

            Camera camera = GameplayCamera();
            if (camera == null)
            {
                recorder.Fail(stepId, routeCheckId, "enabled gameplay camera", "missing",
                    "No gameplay camera is available for actor targeting.");
                yield break;
            }

            if (!TryFindActorPoint(target, camera, out Vector2 screen,
                    out string targetObservation))
            {
                recorder.Fail(stepId, routeCheckId,
                    "camera-visible Renderer, Collider surface, or Transform anchor for " +
                    target.name,
                    "no visible projected actor point",
                    "The semantic actor could not be projected into the gameplay camera.");
                yield break;
            }

            var delivery = new InputDeliveryEvidence();
            yield return InjectMouseClick(screen, button, delivery);
            ApplyDelivery(step, delivery, targetObservation);
            RecordMouseDelivery(recorder, stepId, routeCheckId, button, delivery,
                targetObservation);

            step.elapsed_ms = (Time.realtimeSinceStartup - started) * 1000.0;
            step.frame_end = Time.frameCount;
        }

        public IEnumerator ClickScreen(
            Vector2 screen,
            string observedTopHit,
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId)
        {
            TrajectoryStepEvidence step = recorder.Step(stepId);
            float started = Time.realtimeSinceStartup;
            yield return EnsureReady(recorder, stepId, routeCheckId);
            if (recorder.HasBlockingFailure)
            {
                yield break;
            }

            if (!IsOnScreen(screen))
            {
                recorder.Fail(stepId, routeCheckId, "visible on-screen UI target",
                    $"screen=({screen.x:F1},{screen.y:F1})",
                    "The requested visible UI click target is outside the game view.");
                yield break;
            }

            string targetObservation =
                $"target={observedTopHit}; screen=({screen.x:F1},{screen.y:F1})";
            var delivery = new InputDeliveryEvidence();
            yield return InjectMouseClick(screen, MouseButton.Left, delivery);
            ApplyDelivery(step, delivery, targetObservation);
            RecordMouseDelivery(recorder, stepId, routeCheckId, MouseButton.Left,
                delivery, targetObservation);

            step.elapsed_ms = (Time.realtimeSinceStartup - started) * 1000.0;
            step.frame_end = Time.frameCount;
        }

        /// <summary>
        /// Sends normal clicks to a bounded set of implementation-neutral screen
        /// targets and stops when the caller observes the requested behavior. The
        /// final route evidence records the virtual-device delivery; the caller
        /// records the independent state transition.
        /// </summary>
        public IEnumerator ClickScreensUntil(
            IEnumerable<ScreenProbeTarget> targets,
            Func<bool> successPredicate,
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId,
            ScreenProbeResult result)
        {
            if (result == null)
            {
                throw new ArgumentNullException(nameof(result));
            }

            TrajectoryStepEvidence step = recorder.Step(stepId);
            float started = Time.realtimeSinceStartup;
            yield return EnsureReady(recorder, stepId, routeCheckId);
            if (recorder.HasBlockingFailure)
            {
                yield break;
            }

            ScreenProbeTarget[] candidates = (targets ?? Enumerable.Empty<ScreenProbeTarget>())
                .Where(item => item != null && IsOnScreen(item.ScreenPosition))
                .GroupBy(item => new
                {
                    X = Mathf.RoundToInt(item.ScreenPosition.x),
                    Y = Mathf.RoundToInt(item.ScreenPosition.y)
                })
                .Select(group => group.First())
                .ToArray();
            if (candidates.Length == 0)
            {
                recorder.Fail(stepId, routeCheckId,
                    "at least one bounded visible screen probe", "none",
                    "No valid screen target was available for the visible-control probe.");
                yield break;
            }

            InputDeliveryEvidence lastDelivery = null;
            ScreenProbeTarget lastTarget = null;
            foreach (ScreenProbeTarget candidate in candidates)
            {
                var delivery = new InputDeliveryEvidence();
                yield return InjectMouseClick(
                    candidate.ScreenPosition, MouseButton.Left, delivery);
                lastDelivery = delivery;
                lastTarget = candidate;
                result.Attempts++;

                if (!delivery.CompleteMouseRoute)
                {
                    break;
                }

                // Give same-scene reset implementations one complete frame to
                // destroy/rebuild their ordinary runtime objects before probing.
                yield return null;
                bool succeeded = false;
                try
                {
                    succeeded = successPredicate != null && successPredicate();
                }
                catch (Exception exception)
                {
                    result.LastPredicateFailure =
                        exception.GetType().Name + ": " + exception.Message;
                }

                if (succeeded)
                {
                    result.Succeeded = true;
                    result.ScreenPosition = candidate.ScreenPosition;
                    result.Observation = candidate.Observation;
                    ApplyDelivery(step, delivery, candidate.Observation);
                    break;
                }
            }

            if (lastDelivery == null)
            {
                recorder.Fail(stepId, routeCheckId,
                    "normal virtual Mouse click on a bounded screen target", "not sent",
                    "The visible-control probe did not send any input.");
            }
            else
            {
                if (!result.Succeeded)
                {
                    ApplyDelivery(step, lastDelivery,
                        lastTarget?.Observation ?? "last bounded screen probe");
                }
                RecordMouseDelivery(recorder, stepId, routeCheckId,
                    MouseButton.Left, lastDelivery,
                    result.Succeeded
                        ? $"behavioral target={result.Observation}; attempts={result.Attempts}"
                        : $"bounded probes sent={result.Attempts}; behavior not yet observed");
            }

            step.elapsed_ms = (Time.realtimeSinceStartup - started) * 1000.0;
            step.frame_end = Time.frameCount;
        }

        public IEnumerator MovePointerToActor(
            GameObject target,
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId)
        {
            TrajectoryStepEvidence step = recorder.Step(stepId);
            yield return EnsureReady(recorder, stepId, routeCheckId);
            if (recorder.HasBlockingFailure)
            {
                yield break;
            }

            Camera camera = GameplayCamera();
            if (target == null || !target.activeInHierarchy || camera == null)
            {
                recorder.Fail(stepId, routeCheckId, "visible actor pointer target",
                    target == null || !target.activeInHierarchy
                        ? "missing actor"
                        : "missing camera",
                    "Could not position the virtual pointer for the Dash direction.");
                yield break;
            }

            if (!TryFindActorPoint(target, camera, out Vector2 screen,
                    out string targetObservation))
            {
                recorder.Fail(stepId, routeCheckId,
                    "camera-visible Renderer, Collider surface, or Transform anchor for " +
                    target.name,
                    "no visible projected actor point",
                    "The Dash pointer target could not be projected into the gameplay camera.");
                yield break;
            }

            var delivery = new InputDeliveryEvidence();
            yield return InjectPointerMove(screen, delivery);
            ApplyDelivery(step, delivery, targetObservation);
            RecordPointerDelivery(recorder, stepId, routeCheckId, delivery,
                targetObservation);
        }

        public IEnumerator MovePointerToWorld(
            Vector3 world,
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId)
        {
            TrajectoryStepEvidence step = recorder.Step(stepId);
            yield return EnsureReady(recorder, stepId, routeCheckId);
            if (recorder.HasBlockingFailure)
            {
                yield break;
            }

            Camera camera = GameplayCamera();
            if (camera == null)
            {
                recorder.Fail(stepId, routeCheckId, "enabled gameplay camera", "missing",
                    "No gameplay camera is available for pointer positioning.");
                yield break;
            }

            if (!TryProjectVisible(camera, world, out Vector2 screen, out Vector3 projected))
            {
                recorder.Fail(stepId, routeCheckId, "visible world pointer target",
                    $"screen=({projected.x:F1},{projected.y:F1},{projected.z:F1})",
                    "The Dash pointer target is outside the gameplay camera.");
                yield break;
            }

            string targetObservation =
                $"world={world:F2}; screen=({screen.x:F1},{screen.y:F1})";
            var delivery = new InputDeliveryEvidence();
            yield return InjectPointerMove(screen, delivery);
            ApplyDelivery(step, delivery, targetObservation);
            RecordPointerDelivery(recorder, stepId, routeCheckId, delivery,
                targetObservation);
        }

        public IEnumerator PressKey(
            Key key,
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId)
        {
            TrajectoryStepEvidence step = recorder.Step(stepId);
            float started = Time.realtimeSinceStartup;
            yield return EnsureReady(recorder, stepId, routeCheckId);
            if (recorder.HasBlockingFailure)
            {
                yield break;
            }

            InputActionRouteRecorder actionRecorder = StartActionRecorder();
            virtualKeyboard.MakeCurrent();
            InputSystem.QueueStateEvent(virtualKeyboard, new KeyboardState(key));
            yield return null;
            bool currentOnPress = Keyboard.current == virtualKeyboard;
            bool pressed = virtualKeyboard[key].isPressed &&
                           Keyboard.current != null && Keyboard.current[key].isPressed;
            InputSystem.QueueStateEvent(virtualKeyboard, new KeyboardState());
            yield return null;
            bool currentOnRelease = Keyboard.current == virtualKeyboard;
            bool released = !virtualKeyboard[key].isPressed &&
                            Keyboard.current != null && !Keyboard.current[key].isPressed;
            List<InputActionEventEvidence> events = StopActionRecorder(actionRecorder);

            step.screen_width = Screen.width;
            step.screen_height = Screen.height;
            step.mouse_device_id = virtualMouse.deviceId;
            step.keyboard_device_id = virtualKeyboard.deviceId;
            step.input_action_events.Clear();
            step.input_action_events.AddRange(events);
            bool routeDelivered = currentOnPress && currentOnRelease && pressed && released;
            string observed =
                $"currentPress={currentOnPress}, currentRelease={currentOnRelease}, " +
                $"pressed={pressed}, released={released}; " +
                "optional candidate action diagnostics: " + FormatActionEvents(events);
            if (routeDelivered)
            {
                recorder.Pass(stepId, routeCheckId,
                    $"virtual Keyboard {key} press for one player-loop frame then release",
                    observed);
            }
            else
            {
                recorder.Fail(stepId, routeCheckId,
                    $"virtual Keyboard {key} press for one player-loop frame then release",
                    observed,
                    "The virtual Keyboard was not the current readable device across the normal key cadence.");
            }

            step.elapsed_ms = (Time.realtimeSinceStartup - started) * 1000.0;
            step.frame_end = Time.frameCount;
        }

        public IEnumerator Dispose()
        {
            if (virtualMouse != null && virtualMouse.added)
            {
                InputSystem.RemoveDevice(virtualMouse);
            }
            if (virtualKeyboard != null && virtualKeyboard.added)
            {
                InputSystem.RemoveDevice(virtualKeyboard);
            }
            foreach (InputDevice device in disabledDevices)
            {
                if (device != null && device.added)
                {
                    InputSystem.EnableDevice(device);
                }
            }
            disabledDevices.Clear();

            if (previousMouse != null && previousMouse.added && previousMouse.enabled)
            {
                previousMouse.MakeCurrent();
            }
            if (previousKeyboard != null && previousKeyboard.added && previousKeyboard.enabled)
            {
                previousKeyboard.MakeCurrent();
            }
            if (changedBackgroundBehavior)
            {
                InputSystem.settings.backgroundBehavior = previousBackgroundBehavior;
            }
#if UNITY_EDITOR
            if (changedEditorInputBehavior)
            {
                InputSystem.settings.editorInputBehaviorInPlayMode = previousEditorInputBehavior;
            }
#endif
            virtualMouse = null;
            virtualKeyboard = null;
            yield return null;
        }

        IEnumerator EnsureReady(
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId)
        {
            if (virtualMouse == null || virtualKeyboard == null)
            {
                previousBackgroundBehavior = InputSystem.settings.backgroundBehavior;
                InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
                changedBackgroundBehavior = true;
#if UNITY_EDITOR
                previousEditorInputBehavior = InputSystem.settings.editorInputBehaviorInPlayMode;
                InputSystem.settings.editorInputBehaviorInPlayMode =
                    InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
                changedEditorInputBehavior = true;
#endif

                previousMouse = Mouse.current;
                previousKeyboard = Keyboard.current;
                foreach (InputDevice device in InputSystem.devices
                             .Where(item => (item is Mouse || item is Keyboard) && item.enabled)
                             .ToArray())
                {
                    disabledDevices.Add(device);
                    InputSystem.DisableDevice(device);
                }

                virtualMouse = InputSystem.AddDevice<Mouse>("OmniGameDungeonDuelMouse");
                virtualKeyboard = InputSystem.AddDevice<Keyboard>("OmniGameDungeonDuelKeyboard");
                virtualMouse.MakeCurrent();
                virtualKeyboard.MakeCurrent();
                yield return null;
            }

            virtualMouse?.MakeCurrent();
            virtualKeyboard?.MakeCurrent();
            if (virtualMouse == null || virtualKeyboard == null ||
                !virtualMouse.added || !virtualKeyboard.added ||
                !virtualMouse.enabled || !virtualKeyboard.enabled ||
                Mouse.current != virtualMouse || Keyboard.current != virtualKeyboard)
            {
                recorder.Fail(stepId, routeCheckId,
                    "enabled current virtual Mouse and Keyboard", "device setup failed",
                    "Input System virtual player devices could not be installed as the current readable devices.");
            }
        }

        IEnumerator InjectMouseClick(
            Vector2 screen,
            MouseButton button,
            InputDeliveryEvidence delivery)
        {
            InputActionRouteRecorder actionRecorder = StartActionRecorder();
            virtualMouse.MakeCurrent();
            QueueMouse(screen, false, false);
            yield return null;
            delivery.ScreenPosition = screen;
            delivery.MouseCurrentOnMove = Mouse.current == virtualMouse;
            delivery.PositionObserved = PointerAt(screen);

            QueueMouse(screen,
                button == MouseButton.Left,
                button == MouseButton.Right);
            yield return null;
            delivery.MouseCurrentOnPress = Mouse.current == virtualMouse;
            delivery.PressedObserved = button == MouseButton.Left
                ? virtualMouse.leftButton.isPressed && Mouse.current.leftButton.isPressed
                : virtualMouse.rightButton.isPressed && Mouse.current.rightButton.isPressed;

            QueueMouse(screen, false, false);
            yield return null;
            delivery.MouseCurrentOnRelease = Mouse.current == virtualMouse;
            delivery.ReleasedObserved = button == MouseButton.Left
                ? !virtualMouse.leftButton.isPressed && !Mouse.current.leftButton.isPressed
                : !virtualMouse.rightButton.isPressed && !Mouse.current.rightButton.isPressed;
            delivery.ActionEvents.AddRange(StopActionRecorder(actionRecorder));
        }

        IEnumerator InjectPointerMove(
            Vector2 screen,
            InputDeliveryEvidence delivery)
        {
            InputActionRouteRecorder actionRecorder = StartActionRecorder();
            virtualMouse.MakeCurrent();
            QueueMouse(screen, false, false);
            yield return null;
            delivery.ScreenPosition = screen;
            delivery.MouseCurrentOnMove = Mouse.current == virtualMouse;
            delivery.PositionObserved = PointerAt(screen);
            delivery.ReleasedObserved = !virtualMouse.leftButton.isPressed &&
                                        !virtualMouse.rightButton.isPressed;
            delivery.ActionEvents.AddRange(StopActionRecorder(actionRecorder));
        }

        InputActionRouteRecorder StartActionRecorder()
        {
            var recorder = new InputActionRouteRecorder(
                virtualMouse.deviceId, virtualKeyboard.deviceId);
            recorder.Start();
            return recorder;
        }

        static List<InputActionEventEvidence> StopActionRecorder(
            InputActionRouteRecorder recorder)
        {
            recorder.Stop();
            return recorder.Events.ToList();
        }

        void ApplyDelivery(
            TrajectoryStepEvidence step,
            InputDeliveryEvidence delivery,
            string targetObservation)
        {
            step.screen_width = Screen.width;
            step.screen_height = Screen.height;
            step.screen_x = delivery.ScreenPosition.x;
            step.screen_y = delivery.ScreenPosition.y;
            step.top_hit = targetObservation;
            step.mouse_device_id = virtualMouse.deviceId;
            step.keyboard_device_id = virtualKeyboard.deviceId;
            step.input_action_events.Clear();
            step.input_action_events.AddRange(delivery.ActionEvents);
        }

        static void RecordMouseDelivery(
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId,
            MouseButton button,
            InputDeliveryEvidence delivery,
            string targetObservation)
        {
            string observed =
                $"{targetObservation}; current(move/press/release)=" +
                $"{delivery.MouseCurrentOnMove}/{delivery.MouseCurrentOnPress}/" +
                $"{delivery.MouseCurrentOnRelease}; position={delivery.PositionObserved}; " +
                $"pressed={delivery.PressedObserved}; released={delivery.ReleasedObserved}; " +
                "optional candidate action diagnostics: " +
                FormatActionEvents(delivery.ActionEvents);
            if (delivery.CompleteMouseRoute)
            {
                recorder.Pass(stepId, routeCheckId,
                    $"current virtual Mouse move, {button} press, and release across frames",
                    observed);
            }
            else
            {
                recorder.Fail(stepId, routeCheckId,
                    $"current virtual Mouse move, {button} press, and release across frames",
                    observed,
                    "The virtual Mouse state was not readable through the normal cross-frame device route.");
            }
        }

        static void RecordPointerDelivery(
            TrajectoryRecorder recorder,
            string stepId,
            string routeCheckId,
            InputDeliveryEvidence delivery,
            string targetObservation)
        {
            string observed =
                $"{targetObservation}; current={delivery.MouseCurrentOnMove}; " +
                $"position={delivery.PositionObserved}; " +
                "optional candidate action diagnostics: " +
                FormatActionEvents(delivery.ActionEvents);
            if (delivery.MouseCurrentOnMove && delivery.PositionObserved)
            {
                recorder.Pass(stepId, routeCheckId,
                    "current virtual Mouse pointer move across a player-loop frame",
                    observed);
            }
            else
            {
                recorder.Fail(stepId, routeCheckId,
                    "current virtual Mouse pointer move across a player-loop frame",
                    observed,
                    "The virtual pointer position was not readable from the current Mouse device.");
            }
        }

        static string FormatActionEvents(IEnumerable<InputActionEventEvidence> events)
        {
            string formatted = string.Join(" -> ", (events ??
                    Enumerable.Empty<InputActionEventEvidence>()).Select(item =>
                    $"{item.action}:{item.phase}@f{item.frame}/{item.control_path}/d{item.device_id}"));
            return string.IsNullOrWhiteSpace(formatted) ? "<none>" : formatted;
        }

        static bool TryFindActorPoint(
            GameObject target,
            Camera camera,
            out Vector2 screen,
            out string observation)
        {
            screen = default;
            observation = "missing";
            Physics.SyncTransforms();

            // Preserve the strongest optional diagnostic when a Collider exists
            // and a normal camera ray resolves to the semantic actor.
            foreach (Collider collider in target.GetComponentsInChildren<Collider>(true)
                         .Where(item => item.enabled && item.gameObject.activeInHierarchy))
            {
                foreach (Vector3 world in SampleBounds(collider.bounds))
                {
                    if (!TryProjectVisible(camera, world, out Vector2 candidate, out _))
                    {
                        continue;
                    }
                    if (Physics.Raycast(camera.ScreenPointToRay(candidate), out RaycastHit hit,
                            250f, ~0, QueryTriggerInteraction.Ignore) &&
                        IsTargetHit(target, hit.collider))
                    {
                        screen = candidate;
                        observation =
                            $"actor={target.name}; optionalPhysicsTopHit=" +
                            $"{hit.collider.name}->{hit.collider.transform.root.name}; " +
                            $"screen=({screen.x:F1},{screen.y:F1})";
                        return true;
                    }
                }
            }

            // Renderer projection is the implementation-neutral actor route.
            // It supports direct Mouse.current polling and actors with no Collider.
            Plane[] planes = GeometryUtility.CalculateFrustumPlanes(camera);
            foreach (Renderer renderer in target.GetComponentsInChildren<Renderer>(true)
                         .Where(item => item.enabled && !item.forceRenderingOff &&
                                        item.gameObject.activeInHierarchy)
                         // Prefer an actual volumetric actor surface over large,
                         // flat ground shadows.  A shadow center can overlap a
                         // neighboring actor after melee convergence even though
                         // both candidates are otherwise implemented correctly.
                         .OrderByDescending(item => item.bounds.size.y > 0.05f)
                         .ThenByDescending(item => item.bounds.size.y)
                         .ThenByDescending(item => item.bounds.size.sqrMagnitude))
            {
                Bounds bounds = renderer.bounds;
                if (!GeometryUtility.TestPlanesAABB(planes, bounds))
                {
                    continue;
                }
                foreach (Vector3 world in SampleBounds(bounds))
                {
                    if (!TryProjectVisible(camera, world, out Vector2 candidate, out _))
                    {
                        continue;
                    }
                    string optionalTopHit = "<none>";
                    if (Physics.Raycast(camera.ScreenPointToRay(candidate), out RaycastHit hit,
                            250f, ~0, QueryTriggerInteraction.Ignore))
                    {
                        optionalTopHit = hit.collider.name;
                    }
                    screen = candidate;
                    observation =
                        $"actor={target.name}; renderer={renderer.name}; " +
                        $"bounds={bounds.center:F2}/{bounds.size:F2}; " +
                        $"optionalPhysicsTopHit={optionalTopHit}; " +
                        $"screen=({screen.x:F1},{screen.y:F1})";
                    return true;
                }
            }

            foreach (Vector3 anchor in new[]
            {
                target.transform.position + Vector3.up,
                target.transform.position + Vector3.up * 0.5f,
                target.transform.position
            })
            {
                if (!TryProjectVisible(camera, anchor, out Vector2 candidate, out _))
                {
                    continue;
                }
                screen = candidate;
                observation =
                    $"actor={target.name}; transformAnchor={anchor:F2}; " +
                    $"screen=({screen.x:F1},{screen.y:F1})";
                return true;
            }
            return false;
        }

        static IEnumerable<Vector3> SampleBounds(Bounds bounds)
        {
            Vector3 center = bounds.center;
            Vector3 extents = bounds.extents;
            yield return center;
            yield return center + Vector3.left * extents.x * 0.55f;
            yield return center + Vector3.right * extents.x * 0.55f;
            yield return center + Vector3.down * extents.y * 0.45f;
            yield return center + Vector3.up * extents.y * 0.45f;
            yield return center + new Vector3(-extents.x * 0.45f, extents.y * 0.35f, 0f);
            yield return center + new Vector3(extents.x * 0.45f, extents.y * 0.35f, 0f);
        }

        static bool IsTargetHit(GameObject target, Collider hit) =>
            hit != null && (hit.transform == target.transform ||
                            hit.transform.IsChildOf(target.transform) ||
                            target.transform.IsChildOf(hit.transform));

        static bool TryProjectVisible(
            Camera camera,
            Vector3 world,
            out Vector2 screen,
            out Vector3 projected)
        {
            projected = camera.WorldToScreenPoint(world);
            screen = new Vector2(projected.x, projected.y);
            return projected.z > 0f && IsOnScreen(screen);
        }

        static bool IsOnScreen(Vector2 screen) =>
            !float.IsNaN(screen.x) && !float.IsInfinity(screen.x) &&
            !float.IsNaN(screen.y) && !float.IsInfinity(screen.y) &&
            screen.x >= 0f && screen.x <= Screen.width &&
            screen.y >= 0f && screen.y <= Screen.height;

        bool PointerAt(Vector2 expected) =>
            virtualMouse != null && Mouse.current == virtualMouse &&
            Vector2.Distance(virtualMouse.position.ReadValue(), expected) <=
            PointerTolerancePixels &&
            Vector2.Distance(Mouse.current.position.ReadValue(), expected) <=
            PointerTolerancePixels;

        void QueueMouse(Vector2 position, bool left, bool right)
        {
            virtualMouse.MakeCurrent();
            Vector2 previous = virtualMouse.position.ReadValue();
            var state = new MouseState
            {
                position = position,
                delta = position - previous,
                displayIndex = 0
            };
            state = state.WithButton(MouseButton.Left, left);
            state = state.WithButton(MouseButton.Right, right);
            InputSystem.QueueStateEvent(virtualMouse, state);
        }

        static Camera GameplayCamera() => Camera.main ??
            UnityEngine.Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
    }

    internal sealed class InputDeliveryEvidence
    {
        public Vector2 ScreenPosition;
        public bool MouseCurrentOnMove;
        public bool MouseCurrentOnPress;
        public bool MouseCurrentOnRelease;
        public bool PositionObserved;
        public bool PressedObserved;
        public bool ReleasedObserved;
        public List<InputActionEventEvidence> ActionEvents { get; } =
            new List<InputActionEventEvidence>();

        public bool CompleteMouseRoute =>
            MouseCurrentOnMove && MouseCurrentOnPress && MouseCurrentOnRelease &&
            PositionObserved && PressedObserved && ReleasedObserved;
    }

    internal sealed class ScreenProbeTarget
    {
        public Vector2 ScreenPosition;
        public string Observation;
    }

    internal sealed class ScreenProbeResult
    {
        public bool Succeeded;
        public int Attempts;
        public Vector2 ScreenPosition;
        public string Observation;
        public string LastPredicateFailure;
    }

    internal sealed class InputActionRouteRecorder
    {
        readonly HashSet<int> acceptedDeviceIds;
        bool recording;

        public InputActionRouteRecorder(params int[] deviceIds)
        {
            acceptedDeviceIds = new HashSet<int>(deviceIds);
        }

        public List<InputActionEventEvidence> Events { get; } =
            new List<InputActionEventEvidence>();

        public void Start()
        {
            if (recording) return;
            InputSystem.onActionChange += OnActionChange;
            recording = true;
        }

        public void Stop()
        {
            if (!recording) return;
            InputSystem.onActionChange -= OnActionChange;
            recording = false;
        }

        void OnActionChange(object value, InputActionChange change)
        {
            string phase = change switch
            {
                InputActionChange.ActionStarted => "started",
                InputActionChange.ActionPerformed => "performed",
                InputActionChange.ActionCanceled => "canceled",
                _ => null
            };
            if (phase == null || value is not InputAction action ||
                action.activeControl == null ||
                !acceptedDeviceIds.Contains(action.activeControl.device.deviceId))
            {
                return;
            }

            Events.Add(new InputActionEventEvidence
            {
                phase = phase,
                action = action.name,
                control_path = action.activeControl.path,
                device_id = action.activeControl.device.deviceId,
                frame = Time.frameCount
            });
        }
    }
}
