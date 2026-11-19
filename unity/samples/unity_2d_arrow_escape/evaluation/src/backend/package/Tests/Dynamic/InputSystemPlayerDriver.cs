using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    internal enum PointerBoundaryGesture
    {
        PressOnly,
        OutsideDownInsideUp,
        InsideDownOutsideUp
    }

    /// <summary>
    /// Drives the same engine-native player path as a real mouse. It may use EventSystem
    /// raycasts and ExecuteEvents.GetEventHandler for observation, but never executes
    /// handlers through ExecuteEvents.Execute*, Button.onClick, or gameplay methods. The exact cadence is:
    /// move -> frame -> press -> frame -> release -> frame.
    /// </summary>
    internal sealed class InputSystemPlayerDriver
    {
        private InputSystemUIInputModule inputModule;
        private bool eventSystemRouteReady;
        private Mouse virtualMouse;
        private Mouse previousCurrentMouse;
        private readonly List<Mouse> disabledMice = new List<Mouse>();
        private bool boundaryPressNeedsCleanup;
        private Vector2 boundaryCleanupPoint;
        private InputSettings.BackgroundBehavior previousBackgroundBehavior;
        private bool changedBackgroundBehavior;
#if UNITY_EDITOR
        private InputSettings.EditorInputBehaviorInPlayMode previousEditorInputBehavior;
        private bool changedEditorInputBehavior;
#endif

        public IEnumerator Click(
            GameObject target,
            string checkPrefix,
            TrajectoryStepEvidence evidence) =>
            ClickInternal(target, null, checkPrefix, evidence);

        public IEnumerator Click(
            VisibleUiTarget target,
            string checkPrefix,
            TrajectoryStepEvidence evidence) =>
            ClickInternal(
                target != null && target.PointerTarget != null
                    ? target.PointerTarget
                    : null,
                target?.Bounds,
                checkPrefix,
                evidence,
                target?.SemanticId ?? target?.Label);

        public IEnumerator BoundaryGesture(
            GameObject target,
            Rect? preferredBounds,
            string semanticId,
            PointerBoundaryGesture gesture,
            string checkPrefix,
            TrajectoryStepEvidence evidence)
        {
            float started = Time.realtimeSinceStartup;
            string targetLabel = target == null
                ? semanticId ?? "<null>"
                : target.name;
            evidence.frame_start = Time.frameCount;
            evidence.operation = "virtual_mouse_boundary_" + gesture;
            evidence.target = targetLabel;
            evidence.screen_width = Screen.width;
            evidence.screen_height = Screen.height;

            yield return EnsureReady(checkPrefix, evidence);
            if (HasFailure(evidence) || target == null || !target.activeInHierarchy)
            {
                if (target == null || !target.activeInHierarchy)
                {
                    Fail(evidence, checkPrefix + ".target", "active player target",
                        target == null ? "null" : "inactive",
                        "Boundary input target is missing or inactive.");
                }
                Finish(evidence, started);
                yield break;
            }

            GameObject discoveredHandler = target == null ? null :
                ExecuteEvents.GetEventHandler<IPointerClickHandler>(target);
            GameObject expectedHandler = eventSystemRouteReady
                ? discoveredHandler
                : null;
            if (!TryFindClickablePoint(target, expectedHandler, preferredBounds,
                    out Vector2 inside, out string observedHits, out string route))
            {
                Fail(evidence, checkPrefix + ".inside", "visible target point",
                    observedHits, "No valid point was found inside the target.");
                Finish(evidence, started);
                yield break;
            }

            Vector2 outside = FindBlankPoint(
                target, expectedHandler, preferredBounds, inside);
            if (float.IsNaN(outside.x) || float.IsNaN(outside.y))
            {
                Fail(evidence, checkPrefix + ".outside",
                    "an on-screen point outside the selected target",
                    "none", "The target leaves no valid point for cross-boundary input.");
                Finish(evidence, started);
                yield break;
            }
            evidence.input_route = route;
            evidence.screen_x = inside.x;
            evidence.screen_y = inside.y;
            evidence.input_device_id = virtualMouse.deviceId;
            if (gesture == PointerBoundaryGesture.PressOnly)
            {
                QueueMouseState(inside, false);
                yield return null;
                QueueMouseState(inside, true);
                yield return null;
                boundaryPressNeedsCleanup = true;
                boundaryCleanupPoint = outside;
            }
            else if (gesture == PointerBoundaryGesture.OutsideDownInsideUp)
            {
                QueueMouseState(outside, false);
                yield return null;
                QueueMouseState(outside, true);
                yield return null;
                QueueMouseState(inside, true);
                yield return null;
                QueueMouseState(inside, false);
                yield return null;
            }
            else // InsideDownOutsideUp
            {
                QueueMouseState(inside, false);
                yield return null;
                QueueMouseState(inside, true);
                yield return null;
                QueueMouseState(outside, true);
                yield return null;
                QueueMouseState(outside, false);
                yield return null;
            }

            Pass(evidence, checkPrefix + ".dispatched",
                "one bounded Input System pointer boundary gesture",
                gesture + $"; inside=({inside.x:F1},{inside.y:F1}); " +
                $"outside=({outside.x:F1},{outside.y:F1})");
            Finish(evidence, started);
        }

        public IEnumerator CleanupBoundaryGesture()
        {
            if (!boundaryPressNeedsCleanup || virtualMouse == null) yield break;
            QueueMouseState(boundaryCleanupPoint, true);
            yield return null;
            QueueMouseState(boundaryCleanupPoint, false);
            yield return null;
            boundaryPressNeedsCleanup = false;
        }

        private IEnumerator ClickInternal(
            GameObject target,
            Rect? preferredBounds,
            string checkPrefix,
            TrajectoryStepEvidence evidence,
            string semanticId = null)
        {
            float started = Time.realtimeSinceStartup;
            string targetLabel = target == null
                ? semanticId ?? "<null>"
                : target.name;
            evidence.frame_start = Time.frameCount;
            evidence.operation = "virtual_mouse_click";
            evidence.target = targetLabel;
            evidence.screen_width = Screen.width;
            evidence.screen_height = Screen.height;
            evidence.display_index = 0;

            yield return EnsureReady(checkPrefix, evidence);
            if (virtualMouse != null && virtualMouse.added)
            {
                // Preserve the real injected device identity even when a candidate-owned
                // target or top-hit check rejects the click before any input is queued.
                // That is valid candidate-failure evidence, not missing evaluator health.
                evidence.input_device_id = virtualMouse.deviceId;
            }
            if (HasFailure(evidence))
            {
                Block(evidence, checkPrefix + ".target", checkPrefix + ".driver_ready");
                Block(evidence, checkPrefix + ".top_hit", checkPrefix + ".driver_ready");
                Block(evidence, checkPrefix + ".move", checkPrefix + ".driver_ready");
                Block(evidence, checkPrefix + ".press", checkPrefix + ".driver_ready");
                Block(evidence, checkPrefix + ".release", checkPrefix + ".driver_ready");
                Finish(evidence, started);
                yield break;
            }

            if (target == null || !target.activeInHierarchy)
            {
                Fail(evidence, checkPrefix + ".target", "active player target",
                    target == null ? "null" : "inactive", "Player pointer target is missing or inactive.");
                Block(evidence, checkPrefix + ".top_hit", checkPrefix + ".target");
                Block(evidence, checkPrefix + ".move", checkPrefix + ".target");
                Block(evidence, checkPrefix + ".press", checkPrefix + ".target");
                Block(evidence, checkPrefix + ".release", checkPrefix + ".target");
                Finish(evidence, started);
                yield break;
            }

            GameObject discoveredHandler = target == null ? null :
                ExecuteEvents.GetEventHandler<IPointerClickHandler>(target);
            bool usesEventSystemHandler = eventSystemRouteReady &&
                                          discoveredHandler != null;
            GameObject expectedHandler = usesEventSystemHandler
                ? discoveredHandler
                : null;
            if (usesEventSystemHandler && !expectedHandler.activeInHierarchy)
            {
                Fail(evidence, checkPrefix + ".target",
                    "active visible player pointer surface",
                    expectedHandler.name + " (inactive)",
                    "Resolved pointer handler is inactive.");
                Block(evidence, checkPrefix + ".top_hit", checkPrefix + ".target");
                Block(evidence, checkPrefix + ".move", checkPrefix + ".target");
                Block(evidence, checkPrefix + ".press", checkPrefix + ".target");
                Block(evidence, checkPrefix + ".release", checkPrefix + ".target");
                Finish(evidence, started);
                yield break;
            }
            string handlerLabel = usesEventSystemHandler
                ? expectedHandler.name
                : targetLabel;
            Pass(evidence, checkPrefix + ".target",
                "active visible player pointer surface",
                usesEventSystemHandler
                    ? handlerLabel + " (EventSystem handler)"
                    : targetLabel + " (native Mouse + engine top-hit surface)");

            if (!TryFindClickablePoint(target, expectedHandler, preferredBounds,
                    out Vector2 point, out string observedHits, out string inputRoute))
            {
                evidence.top_hit = observedHits;
                evidence.input_route = inputRoute;
                Fail(evidence, checkPrefix + ".top_hit",
                    handlerLabel,
                    observedHits,
                    usesEventSystemHandler
                        ? "No visible sampled point has the expected EventSystem top hit."
                        : "No visible sampled point resolves to the intended native Mouse surface.");
                Block(evidence, checkPrefix + ".move", checkPrefix + ".top_hit");
                Block(evidence, checkPrefix + ".press", checkPrefix + ".top_hit");
                Block(evidence, checkPrefix + ".release", checkPrefix + ".top_hit");
                Finish(evidence, started);
                yield break;
            }
            evidence.input_route = inputRoute;

            evidence.screen_x = point.x;
            evidence.screen_y = point.y;
            evidence.input_device_id = virtualMouse.deviceId;
            QueueMouseState(point, false);
            yield return null; // Move -> frame.

            bool correctTopHit = TryResolveTopHit(target, expectedHandler, point,
                out string movedHit, out string movedRoute);
            evidence.top_hit = movedHit;
            if (!correctTopHit)
            {
                Fail(evidence, checkPrefix + ".top_hit",
                    handlerLabel,
                    evidence.top_hit,
                    "The moved virtual Mouse no longer resolves to the expected top-most " +
                    "EventSystem/Physics surface.");
                Block(evidence, checkPrefix + ".press", checkPrefix + ".top_hit");
                Block(evidence, checkPrefix + ".release", checkPrefix + ".top_hit");
                Finish(evidence, started);
                yield break;
            }
            evidence.input_route = movedRoute;
            Pass(evidence, checkPrefix + ".top_hit",
                handlerLabel,
                evidence.top_hit);
            Pass(evidence, checkPrefix + ".move", $"mouse at ({point.x:F1},{point.y:F1})",
                $"({virtualMouse.position.x.ReadValue():F1},{virtualMouse.position.y.ReadValue():F1})");

            var routeRecorder = new PointerRouteRecorder();
            PointerRouteProbe routeProbe = null;
            if (usesEventSystemHandler)
            {
                routeProbe = expectedHandler.AddComponent<PointerRouteProbe>();
                routeProbe.Initialize(routeRecorder);
            }

            QueueMouseState(point, true);
            yield return null; // Press -> frame.
            bool mousePressed = virtualMouse.leftButton.isPressed;
            PointerRouteEventEvidence down = routeRecorder.Events.FirstOrDefault();
            bool downObserved = usesEventSystemHandler
                ? down != null && down.phase == "down" &&
                  down.button == PointerEventData.InputButton.Left.ToString() &&
                  Vector2.Distance(new Vector2(down.screen_x, down.screen_y), point) <= 2f
                : TryResolveTopHit(target, null, point, out _, out _);
            if (!mousePressed || !downObserved)
            {
                CopyPointerEvents(routeRecorder, evidence);
                Fail(evidence, checkPrefix + ".press",
                    usesEventSystemHandler
                        ? "leftButton pressed and matching PointerDown callback"
                        : "leftButton pressed on the same native top-hit surface",
                    $"mousePressed={mousePressed}; events={FormatPointerEvents(routeRecorder.Events)}",
                    usesEventSystemHandler
                        ? "The virtual Mouse press did not traverse the normal EventSystem PointerDown route."
                        : "The virtual Mouse press was not observable on the intended native surface.");
                Block(evidence, checkPrefix + ".release", checkPrefix + ".press");
                DestroyProbe(routeProbe);
                Finish(evidence, started);
                yield break;
            }
            Pass(evidence, checkPrefix + ".press",
                usesEventSystemHandler
                    ? "leftButton pressed and matching PointerDown callback"
                    : "leftButton pressed on the same native top-hit surface",
                usesEventSystemHandler
                    ? $"Mouse pressed; PointerDown frame={down.frame}, pointerId={down.pointer_id}, " +
                      $"position=({down.screen_x:F1},{down.screen_y:F1})"
                    : $"Mouse pressed on {evidence.top_hit}");

            QueueMouseState(point, false);
            yield return null; // Release -> frame.
            CopyPointerEvents(routeRecorder, evidence);
            bool mouseReleased = !virtualMouse.leftButton.isPressed;
            // A legitimate click is allowed to synchronously rebuild its scene,
            // disable the clicked object, or destroy the handler during
            // PointerClick.  For EventSystem targets the recorder has already
            // captured the authoritative down/up/click route, so do not touch
            // the candidate-owned UnityEngine.Object again after release.
            bool targetDestroyedAfterDirectRelease = !usesEventSystemHandler && target == null;
            bool routeComplete = usesEventSystemHandler
                ? IsCompletePointerRoute(evidence.pointer_events, point)
                : targetDestroyedAfterDirectRelease ||
                  TryResolveTopHit(target, null, point, out _, out _);
            if (!mouseReleased || !routeComplete)
            {
                Fail(evidence, checkPrefix + ".release",
                    usesEventSystemHandler
                        ? "leftButton released and PointerUp -> PointerClick on the same route"
                        : "leftButton released on the same native top-hit surface",
                    $"mouseReleased={mouseReleased}; events={FormatPointerEvents(evidence.pointer_events)}",
                    usesEventSystemHandler
                        ? "The virtual Mouse release did not complete the normal EventSystem click route."
                        : "The virtual Mouse release did not complete on the intended native surface.");
            }
            else
            {
                Pass(evidence, checkPrefix + ".release",
                    usesEventSystemHandler
                        ? "leftButton released and PointerUp -> PointerClick on the same route"
                        : "leftButton released on the same native top-hit surface",
                    usesEventSystemHandler
                        ? "Mouse released; PointerUp -> PointerClick; " +
                          $"pointerId={evidence.pointer_events[0].pointer_id}"
                        : targetDestroyedAfterDirectRelease
                            ? "Mouse released after the candidate rebuilt the target; " +
                              "the trajectory verifies the resulting visible state."
                            : "Mouse released; candidate outcome is verified from visible state.");
            }

            DestroyProbe(routeProbe);
            Finish(evidence, started);
        }

        public IEnumerator Dispose()
        {
            if (virtualMouse != null && virtualMouse.added)
            {
                InputSystem.RemoveDevice(virtualMouse);
            }
            foreach (Mouse mouse in disabledMice)
            {
                if (mouse != null && mouse.added)
                {
                    InputSystem.EnableDevice(mouse);
                }
            }
            disabledMice.Clear();
            if (previousCurrentMouse != null && previousCurrentMouse.added && previousCurrentMouse.enabled)
            {
                previousCurrentMouse.MakeCurrent();
            }
            if (changedBackgroundBehavior)
            {
                InputSystem.settings.backgroundBehavior = previousBackgroundBehavior;
                changedBackgroundBehavior = false;
            }
#if UNITY_EDITOR
            if (changedEditorInputBehavior)
            {
                InputSystem.settings.editorInputBehaviorInPlayMode = previousEditorInputBehavior;
                changedEditorInputBehavior = false;
            }
#endif
            virtualMouse = null;
            inputModule = null;
            eventSystemRouteReady = false;
            previousCurrentMouse = null;
            yield return null;
        }

        private IEnumerator EnsureReady(string checkPrefix, TrajectoryStepEvidence evidence)
        {
            if (virtualMouse == null)
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

                previousCurrentMouse = Mouse.current;
                foreach (Mouse mouse in InputSystem.devices.OfType<Mouse>())
                {
                    if (mouse.enabled)
                    {
                        disabledMice.Add(mouse);
                        InputSystem.DisableDevice(mouse);
                    }
                }

                virtualMouse = InputSystem.AddDevice<Mouse>("OmniGameTrajectoryMouse");
                virtualMouse.MakeCurrent();
                yield return null;
            }

            if (!virtualMouse.added || !virtualMouse.enabled)
            {
                Fail(evidence, checkPrefix + ".driver_ready",
                    "active virtual Mouse still registered with Input System",
                    virtualMouse.added ? "disabled" : "removed",
                    "The injected player Mouse is no longer available.");
                yield break;
            }

            EventSystem eventSystem = EventSystem.current;
            inputModule = eventSystem == null
                ? null
                : eventSystem.currentInputModule as InputSystemUIInputModule;
            bool pointReady = eventSystem != null && eventSystem.isActiveAndEnabled &&
                              inputModule != null && inputModule.isActiveAndEnabled &&
                              inputModule.point?.action != null &&
                              inputModule.point.action.enabled &&
                              inputModule.point.action.controls.Any(control => control.device == virtualMouse);
            bool clickReady = eventSystem != null && eventSystem.isActiveAndEnabled &&
                              inputModule != null && inputModule.isActiveAndEnabled &&
                              inputModule.leftClick?.action != null &&
                              inputModule.leftClick.action.enabled &&
                              inputModule.leftClick.action.controls.Any(control => control.device == virtualMouse);
            eventSystemRouteReady = pointReady && clickReady;
            Pass(evidence, checkPrefix + ".driver_ready",
                "active virtual Mouse delivered through a normal candidate input route",
                eventSystemRouteReady
                    ? virtualMouse.name + "; EventSystem Point/LeftClick ready"
                    : virtualMouse.name + "; direct Input System polling route");
        }

        private void QueueMouseState(Vector2 position, bool pressed)
        {
            Vector2 previous = virtualMouse.position.ReadValue();
            var state = new MouseState
            {
                position = position,
                delta = position - previous,
                displayIndex = 0
            };
            state = state.WithButton(MouseButton.Left, pressed);
            InputSystem.QueueStateEvent(virtualMouse, state);
        }

        private static Vector2 FindBlankPoint(
            GameObject target,
            GameObject expectedHandler,
            Rect? preferredBounds,
            Vector2 inside)
        {
            Vector2[] candidates =
            {
                new Vector2(8f, 8f),
                new Vector2(Screen.width - 8f, 8f),
                new Vector2(8f, Screen.height - 8f),
                new Vector2(Screen.width - 8f, Screen.height - 8f),
                new Vector2(Mathf.Clamp(inside.x + Screen.width * 0.4f, 8f,
                    Screen.width - 8f),
                    Mathf.Clamp(inside.y + Screen.height * 0.4f, 8f,
                        Screen.height - 8f))
            };
            foreach (Vector2 candidate in candidates)
            {
                if (!TryResolveTopHit(target, expectedHandler, candidate, out _, out _))
                    return candidate;
            }
            return new Vector2(float.NaN, float.NaN);
        }

        private static bool TryFindClickablePoint(
            GameObject visualRoot,
            GameObject expectedHandler,
            Rect? preferredBounds,
            out Vector2 point,
            out string observed,
            out string inputRoute)
        {
            point = default;
            observed = "<none>";
            inputRoute = "unresolved";
            if (visualRoot == null)
            {
                observed = "candidate target was destroyed or is missing";
                inputRoute = "candidate_target_unavailable";
                return false;
            }
            Physics2D.SyncTransforms();
            Canvas.ForceUpdateCanvases();
            var candidates = new List<Vector2>();

            if (preferredBounds.HasValue)
            {
                AddScreenRectSamplePoints(preferredBounds.Value, candidates);
            }

            if (visualRoot == null)
            {
                observed = "candidate target was destroyed during layout refresh";
                inputRoute = "candidate_target_unavailable";
                return false;
            }

            foreach (Graphic graphic in visualRoot.GetComponentsInChildren<Graphic>(true)
                         .Where(IsVisibleRaycastGraphic))
            {
                AddRectTransformSamplePoints(graphic.rectTransform, candidates);
            }

            RectTransform rect = visualRoot.GetComponent<RectTransform>();
            if (rect != null)
            {
                AddRectTransformSamplePoints(rect, candidates);
            }

            foreach (Collider2D collider in visualRoot.GetComponentsInChildren<Collider2D>(true)
                         .Where(item => item != null && item.enabled &&
                                        item.gameObject.activeInHierarchy))
            {
                Camera camera = CameraFor(collider.gameObject);
                AddWorldBoundsSamplePoints(collider.bounds, camera, candidates);
            }

            foreach (Renderer renderer in visualRoot.GetComponentsInChildren<Renderer>(true)
                         .Where(item => item != null && item.enabled &&
                                        item.gameObject.activeInHierarchy))
            {
                Camera camera = CameraFor(renderer.gameObject);
                AddWorldBoundsSamplePoints(renderer.bounds, camera, candidates);
            }

            if (candidates.Count == 0)
            {
                Camera camera = CameraFor(visualRoot);
                if (camera == null)
                {
                    observed = "no active camera for the candidate target";
                    inputRoute = "candidate_target_unavailable";
                    return false;
                }
                Vector3 screen = camera.WorldToScreenPoint(visualRoot.transform.position);
                candidates.Add(new Vector2(screen.x, screen.y));
            }

            var observedHits = new List<string>();
            foreach (Vector2 candidate in candidates
                         .Where(item => item.x >= 0f && item.x <= Screen.width &&
                                        item.y >= 0f && item.y <= Screen.height)
                         .GroupBy(item => new Vector2Int(Mathf.RoundToInt(item.x * 2f),
                             Mathf.RoundToInt(item.y * 2f)))
                         .Select(group => group.First()))
            {
                if (TryResolveTopHit(visualRoot, expectedHandler, candidate,
                        out string hit, out string route))
                {
                    point = candidate;
                    observed = hit;
                    inputRoute = route;
                    return true;
                }
                if (observedHits.Count < 8)
                {
                    observedHits.Add($"({candidate.x:F1},{candidate.y:F1})->{hit}");
                }
            }

            observed = string.Join(", ", observedHits);
            return false;
        }

        private static bool TryResolveTopHit(
            GameObject visualRoot,
            GameObject expectedHandler,
            Vector2 point,
            out string observed,
            out string route)
        {
            observed = "<none>";
            route = "unresolved";
            if (visualRoot == null)
            {
                observed = "candidate target was destroyed or rebuilt";
                route = "candidate_target_unavailable";
                return false;
            }
            EventSystem eventSystem = EventSystem.current;
            if (eventSystem != null && eventSystem.isActiveAndEnabled)
            {
                var eventData = new PointerEventData(eventSystem) { position = point };
                var raycasts = new List<RaycastResult>();
                eventSystem.RaycastAll(eventData, raycasts);
                RaycastResult top = raycasts.FirstOrDefault(item => item.gameObject != null);
                if (top.gameObject != null)
                {
                    GameObject handler = ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                        top.gameObject);
                    observed = top.gameObject.name + " -> " +
                               (handler == null ? "<native-surface>" : handler.name);
                    bool matches = expectedHandler != null
                        ? handler == expectedHandler
                        : BelongsToRoot(top.gameObject, visualRoot);
                    if (matches)
                    {
                        route = expectedHandler != null
                            ? "eventsystem_pointer_handler"
                            : "eventsystem_native_surface";
                        return true;
                    }

                    // A different EventSystem top hit is an occluder. Do not
                    // click through it with a lower-level Physics query.
                    return false;
                }
            }

            // A screen-space uGUI surface can be the visible target of candidate-owned
            // Mouse.current polling even when there is no EventSystem, no UI input
            // module, and no camera. Resolve that geometry before world-space queries.
            if (PointFallsInsideVisibleGraphic(visualRoot, point))
            {
                observed = visualRoot.name + " -> visible uGUI bounds";
                route = "visual_bounds_native_mouse";
                return true;
            }

            Camera camera = CameraFor(visualRoot);
            if (camera == null) return false;
            Ray ray = camera.ScreenPointToRay(point);
            RaycastHit2D[] hits2D = Physics2D.GetRayIntersectionAll(ray,
                Mathf.Infinity);
            RaycastHit2D[] ordered2D = hits2D
                .Where(hit => hit.collider != null && hit.collider.enabled &&
                              hit.collider.gameObject.activeInHierarchy)
                .OrderByDescending(hit => SortingLayerValue(hit.collider.gameObject))
                .ThenByDescending(hit => SortingOrder(hit.collider.gameObject))
                .ThenBy(hit => hit.distance)
                .ToArray();
            if (ordered2D.Length > 0)
            {
                RaycastHit2D top2D = ordered2D[0];
                observed = top2D.collider.gameObject.name + " -> Physics2D";
                if (BelongsToRoot(top2D.collider.gameObject, visualRoot))
                {
                    route = "physics2d_native_mouse";
                    return true;
                }
                return false;
            }

            if (PointFallsInsideVisibleRoot(visualRoot, point))
            {
                observed = visualRoot.name + " -> visible bounds";
                route = "visual_bounds_native_mouse";
                return true;
            }

            return false;
        }

        private static bool PointFallsInsideVisibleRoot(GameObject root, Vector2 point)
        {
            if (root == null || !root.activeInHierarchy) return false;

            if (PointFallsInsideVisibleGraphic(root, point)) return true;

            Camera worldCamera = CameraFor(root);
            if (worldCamera == null) return false;
            foreach (Renderer renderer in root.GetComponentsInChildren<Renderer>(true)
                         .Where(item => item != null && item.enabled &&
                                        item.gameObject.activeInHierarchy))
            {
                Bounds bounds = renderer.bounds;
                Vector3 min = worldCamera.WorldToScreenPoint(bounds.min);
                Vector3 max = worldCamera.WorldToScreenPoint(bounds.max);
                if (min.z < 0f && max.z < 0f) continue;
                Rect rect = Rect.MinMaxRect(
                    Mathf.Min(min.x, max.x), Mathf.Min(min.y, max.y),
                    Mathf.Max(min.x, max.x), Mathf.Max(min.y, max.y));
                if (rect.width >= 1f && rect.height >= 1f && rect.Contains(point))
                {
                    return true;
                }
            }
            return false;
        }

        private static bool PointFallsInsideVisibleGraphic(GameObject root, Vector2 point)
        {
            if (root == null || !root.activeInHierarchy) return false;

            foreach (Graphic graphic in root.GetComponentsInChildren<Graphic>(true)
                         .Where(item => item != null && item.isActiveAndEnabled &&
                                        item.gameObject.activeInHierarchy &&
                                        item.canvasRenderer != null &&
                                        !item.canvasRenderer.cull &&
                                        item.canvasRenderer.GetInheritedAlpha() > 0.001f))
            {
                Canvas canvas = graphic.canvas;
                Camera camera = canvas != null &&
                                canvas.renderMode != RenderMode.ScreenSpaceOverlay
                    ? canvas.worldCamera
                    : null;
                if (RectTransformUtility.RectangleContainsScreenPoint(
                        graphic.rectTransform, point, camera))
                {
                    return true;
                }
            }
            return false;
        }

        private static bool BelongsToRoot(GameObject hit, GameObject root)
        {
            if (hit == null || root == null) return false;
            return hit == root || hit.transform.IsChildOf(root.transform) ||
                   root.transform.IsChildOf(hit.transform);
        }

        private static int SortingLayerValue(GameObject target)
        {
            if (target == null) return 0;
            Renderer renderer = target.GetComponentInParent<Renderer>();
            return renderer == null
                ? 0
                : SortingLayer.GetLayerValueFromID(renderer.sortingLayerID);
        }

        private static int SortingOrder(GameObject target)
        {
            if (target == null) return 0;
            Renderer renderer = target.GetComponentInParent<Renderer>();
            return renderer == null ? 0 : renderer.sortingOrder;
        }

        private static void AddScreenRectSamplePoints(
            Rect rect,
            ICollection<Vector2> candidates)
        {
            Vector2[] normalizedPoints =
            {
                new Vector2(0.5f, 0.5f),
                new Vector2(0.25f, 0.5f),
                new Vector2(0.75f, 0.5f),
                new Vector2(0.5f, 0.25f),
                new Vector2(0.5f, 0.75f),
                new Vector2(0.25f, 0.25f),
                new Vector2(0.25f, 0.75f),
                new Vector2(0.75f, 0.25f),
                new Vector2(0.75f, 0.75f)
            };
            foreach (Vector2 normalized in normalizedPoints)
            {
                candidates.Add(new Vector2(
                    Mathf.Lerp(rect.xMin, rect.xMax, normalized.x),
                    Mathf.Lerp(rect.yMin, rect.yMax, normalized.y)));
            }
        }

        private static bool IsVisibleRaycastGraphic(Graphic graphic)
        {
            if (graphic == null || !graphic.enabled || !graphic.raycastTarget ||
                !graphic.gameObject.activeInHierarchy || graphic.rectTransform == null ||
                graphic.rectTransform.rect.width <= 0.5f || graphic.rectTransform.rect.height <= 0.5f)
            {
                return false;
            }

            CanvasRenderer canvasRenderer = graphic.canvasRenderer;
            return canvasRenderer != null && !canvasRenderer.cull &&
                   graphic.color.a * canvasRenderer.GetInheritedAlpha() > 0.001f;
        }

        private static void AddRectTransformSamplePoints(
            RectTransform rect,
            ICollection<Vector2> candidates)
        {
            // Unity's C# null-conditional operator checks only the managed
            // reference and bypasses UnityEngine.Object's destroyed-object
            // equality. Candidate scene rebuilds can therefore leave a
            // managed RectTransform wrapper whose native object is already
            // gone. Treat that as an ordinary missing candidate target rather
            // than allowing a MissingReferenceException to invalidate the
            // evaluator run.
            if (rect == null) return;

            Vector3[] corners = new Vector3[4];
            rect.GetWorldCorners(corners);
            Canvas canvas = rect.GetComponentInParent<Canvas>();
            Camera camera = canvas != null && canvas.renderMode != RenderMode.ScreenSpaceOverlay
                ? canvas.worldCamera
                : null;

            // Sample the center first, followed by inset points that remain comfortably inside
            // the visual rectangle. The final EventSystem.RaycastAll check below is still the
            // authority for clipping, masks, overlap, alpha-hit testing, and handler routing.
            Vector2[] normalizedPoints =
            {
                new Vector2(0.5f, 0.5f),
                new Vector2(0.25f, 0.5f),
                new Vector2(0.75f, 0.5f),
                new Vector2(0.5f, 0.25f),
                new Vector2(0.5f, 0.75f),
                new Vector2(0.25f, 0.25f),
                new Vector2(0.25f, 0.75f),
                new Vector2(0.75f, 0.25f),
                new Vector2(0.75f, 0.75f)
            };

            foreach (Vector2 normalized in normalizedPoints)
            {
                Vector3 left = Vector3.Lerp(corners[0], corners[1], normalized.y);
                Vector3 right = Vector3.Lerp(corners[3], corners[2], normalized.y);
                Vector3 world = Vector3.Lerp(left, right, normalized.x);
                candidates.Add(RectTransformUtility.WorldToScreenPoint(camera, world));
            }
        }

        internal static void AddRectTransformSamplePointsForEvaluatorRegression(
            RectTransform rect,
            ICollection<Vector2> candidates) =>
            AddRectTransformSamplePoints(rect, candidates);

        private static void AddWorldBoundsSamplePoints(
            Bounds bounds,
            Camera camera,
            ICollection<Vector2> candidates)
        {
            if (camera == null) return;

            Vector2[] normalizedPoints =
            {
                new Vector2(0.5f, 0.5f),
                new Vector2(0.2f, 0.5f),
                new Vector2(0.8f, 0.5f),
                new Vector2(0.5f, 0.2f),
                new Vector2(0.5f, 0.8f),
                new Vector2(0.2f, 0.2f),
                new Vector2(0.2f, 0.8f),
                new Vector2(0.8f, 0.2f),
                new Vector2(0.8f, 0.8f)
            };
            foreach (Vector2 normalized in normalizedPoints)
            {
                var world = new Vector3(
                    Mathf.Lerp(bounds.min.x, bounds.max.x, normalized.x),
                    Mathf.Lerp(bounds.min.y, bounds.max.y, normalized.y),
                    bounds.center.z);
                Vector3 screen = camera.WorldToScreenPoint(world);
                if (screen.z >= 0f)
                {
                    candidates.Add(new Vector2(screen.x, screen.y));
                }
            }
        }

        private static void CopyPointerEvents(
            PointerRouteRecorder recorder,
            TrajectoryStepEvidence evidence)
        {
            evidence.pointer_events.Clear();
            evidence.pointer_events.AddRange(recorder.Events.Select(item =>
                new PointerRouteEventEvidence
                {
                    phase = item.phase,
                    frame = item.frame,
                    pointer_id = item.pointer_id,
                    button = item.button,
                    screen_x = item.screen_x,
                    screen_y = item.screen_y
                }));
        }

        private static bool IsCompletePointerRoute(
            IReadOnlyList<PointerRouteEventEvidence> events,
            Vector2 expectedPoint)
        {
            if (events.Count != 3 || events[0].phase != "down" ||
                events[1].phase != "up" || events[2].phase != "click")
            {
                return false;
            }
            int pointerId = events[0].pointer_id;
            return events.All(item =>
                item.pointer_id == pointerId &&
                item.button == PointerEventData.InputButton.Left.ToString() &&
                Vector2.Distance(new Vector2(item.screen_x, item.screen_y), expectedPoint) <= 2f) &&
                events[0].frame <= events[1].frame && events[1].frame <= events[2].frame;
        }

        private static string FormatPointerEvents(
            IEnumerable<PointerRouteEventEvidence> events) =>
            string.Join(" -> ", events.Select(item =>
                $"{item.phase}@f{item.frame}/id{item.pointer_id}/" +
                $"({item.screen_x:F1},{item.screen_y:F1})/{item.button}"));

        private static void DestroyProbe(PointerRouteProbe probe)
        {
            if (probe != null)
            {
                UnityEngine.Object.DestroyImmediate(probe);
            }
        }

        private static Camera CameraFor(GameObject target)
        {
            if (target == null) return null;
            Canvas canvas = target.GetComponentInParent<Canvas>();
            if (canvas != null && canvas.renderMode != RenderMode.ScreenSpaceOverlay && canvas.worldCamera != null)
            {
                return canvas.worldCamera;
            }
            return Camera.main ?? UnityEngine.Object.FindObjectsByType<Camera>(
                FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
        }

        private static bool HasFailure(TrajectoryStepEvidence evidence) =>
            evidence.checks.Any(check => string.Equals(check.status, "fail", StringComparison.Ordinal));

        private static void Pass(TrajectoryStepEvidence evidence, string id, string expected, string observed)
        {
            evidence.checks.Add(new TrajectoryCheckEvidence
            {
                check_id = id,
                expected = expected,
                observed = observed,
                status = "pass"
            });
        }

        private static void Fail(
            TrajectoryStepEvidence evidence,
            string id,
            string expected,
            string observed,
            string message)
        {
            evidence.checks.Add(new TrajectoryCheckEvidence
            {
                check_id = id,
                expected = expected,
                observed = observed,
                status = "fail",
                message = message
            });
        }

        private static void Block(TrajectoryStepEvidence evidence, string id, string blockedBy)
        {
            if (evidence.checks.Any(check => string.Equals(check.check_id, id, StringComparison.Ordinal)))
            {
                return;
            }
            evidence.checks.Add(new TrajectoryCheckEvidence
            {
                check_id = id,
                status = "blocked",
                blocked_by = blockedBy,
                message = "Check could not run because an earlier input prerequisite failed."
            });
        }

        private static void Finish(TrajectoryStepEvidence evidence, float started)
        {
            evidence.frame_end = Time.frameCount;
            evidence.elapsed_ms = (Time.realtimeSinceStartup - started) * 1000.0;
            evidence.status = evidence.checks.Any(check => check.status == "fail")
                ? "fail"
                : evidence.checks.Any(check => check.status == "blocked")
                    ? "blocked"
                    : "pass";
            evidence.message = evidence.checks.FirstOrDefault(check => check.status == "fail")?.message;
        }
    }

    internal sealed class PointerRouteRecorder
    {
        public List<PointerRouteEventEvidence> Events { get; } =
            new List<PointerRouteEventEvidence>();
    }

    internal sealed class PointerRouteProbe : MonoBehaviour,
        IPointerDownHandler, IPointerUpHandler, IPointerClickHandler
    {
        private PointerRouteRecorder recorder;

        public void Initialize(PointerRouteRecorder routeRecorder)
        {
            recorder = routeRecorder;
        }

        public void OnPointerDown(PointerEventData eventData) => Record("down", eventData);
        public void OnPointerUp(PointerEventData eventData) => Record("up", eventData);
        public void OnPointerClick(PointerEventData eventData) => Record("click", eventData);

        private void Record(string phase, PointerEventData eventData)
        {
            if (recorder == null || eventData == null)
            {
                return;
            }
            recorder.Events.Add(new PointerRouteEventEvidence
            {
                phase = phase,
                frame = Time.frameCount,
                pointer_id = eventData.pointerId,
                button = eventData.button.ToString(),
                screen_x = eventData.position.x,
                screen_y = eventData.position.y
            });
        }
    }
}
