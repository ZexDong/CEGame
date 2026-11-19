using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.InputSystem.UI;
using UnityEngine.InputSystem.Users;
using UnityEngine.UIElements;
using UguiButton = UnityEngine.UI.Button;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    /// <summary>
    /// Sends player actions through virtual Input System devices. Candidate code may
    /// consume Keyboard.current/Mouse.current directly, through InputAction/PlayerInput,
    /// or through a UI event backend. Observations never invoke gameplay handlers.
    /// </summary>
    internal sealed class NativeInputDriver
    {
        // Unity Input System 1.19 can rebuild all enabled action maps when a
        // device is added or removed. Repeating AddDevice/RemoveDevice after
        // candidate scenes have created different InputAction layouts can trip
        // Input System's own old/new action-count assertions. Keep exactly one
        // evaluator-owned device pair for the lifetime of this Unity process;
        // per-test leases only neutralize state and restore host devices.
        static Mouse processMouse;
        static Keyboard processKeyboard;
        static NativeInputDriver activeOwner;
        static int processDevicePairCreationCount;
        static int processLeaseCount;

        readonly List<InputDevice> disabledDevices = new List<InputDevice>();
        readonly List<NativeActionEvent> actionEvents = new List<NativeActionEvent>();

        Mouse virtualMouse;
        Keyboard virtualKeyboard;
        Mouse previousMouse;
        Keyboard previousKeyboard;
        InputSettings.BackgroundBehavior previousBackgroundBehavior;
        bool changedBackgroundBehavior;
        bool recording;
#if UNITY_EDITOR
        InputSettings.EditorInputBehaviorInPlayMode previousEditorInputBehavior;
        bool changedEditorInputBehavior;
#endif

        public bool Ready => ReferenceEquals(activeOwner, this) &&
                             virtualMouse != null && virtualMouse.added &&
                             virtualMouse.enabled && virtualKeyboard != null &&
                             virtualKeyboard.added && virtualKeyboard.enabled;

        public string LastUiRoute { get; private set; } = string.Empty;
        public Vector2 LastUiPoint { get; private set; }

        internal static int ProcessDevicePairCreationCount =>
            processDevicePairCreationCount;
        internal static int ProcessLeaseCount => processLeaseCount;
        internal static int ProcessMouseDeviceId =>
            processMouse != null && processMouse.added ? processMouse.deviceId : 0;
        internal static int ProcessKeyboardDeviceId =>
            processKeyboard != null && processKeyboard.added
                ? processKeyboard.deviceId
                : 0;
        internal static bool ProcessDevicesNeutral =>
            processMouse != null && processMouse.added &&
            !processMouse.leftButton.isPressed &&
            processKeyboard != null && processKeyboard.added &&
            processKeyboard.allKeys.All(key => !key.isPressed);

        public IEnumerator Initialize()
        {
            if (Ready)
            {
                RefreshPlayerInputPairings();
                yield break;
            }

            Assert.That(activeOwner == null, Is.True,
                "[OMNIGAME_EVALUATOR_INFRASTRUCTURE] NativeInputDriver received " +
                "overlapping process-device leases.");

            previousBackgroundBehavior = InputSystem.settings.backgroundBehavior;
            InputSystem.settings.backgroundBehavior =
                InputSettings.BackgroundBehavior.IgnoreFocus;
            changedBackgroundBehavior = true;
#if UNITY_EDITOR
            previousEditorInputBehavior =
                InputSystem.settings.editorInputBehaviorInPlayMode;
            InputSystem.settings.editorInputBehaviorInPlayMode =
                InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
            changedEditorInputBehavior = true;
#endif

            previousMouse = Mouse.current;
            previousKeyboard = Keyboard.current;
            try
            {
                EnsureProcessDevices();
            }
            catch (Exception exception)
            {
                Assert.Fail("[OMNIGAME_EVALUATOR_INFRASTRUCTURE] The evaluator " +
                    "could not create its process-scoped Input System devices: " +
                    exception);
                yield break;
            }

            virtualMouse = processMouse;
            virtualKeyboard = processKeyboard;
            foreach (InputDevice device in InputSystem.devices
                         .Where(item => (item is Mouse || item is Keyboard) &&
                                        item.enabled &&
                                        !ReferenceEquals(item, processMouse) &&
                                        !ReferenceEquals(item, processKeyboard))
                         .ToArray())
            {
                disabledDevices.Add(device);
                InputSystem.DisableDevice(device);
            }

            if (!virtualMouse.enabled) InputSystem.EnableDevice(virtualMouse);
            if (!virtualKeyboard.enabled) InputSystem.EnableDevice(virtualKeyboard);
            activeOwner = this;
            processLeaseCount++;
            actionEvents.Clear();
            LastUiRoute = string.Empty;
            LastUiPoint = default;
            QueueKeyboard(new KeyboardState());
            QueueMouse(Vector2.zero, false);
            virtualMouse.MakeCurrent();
            virtualKeyboard.MakeCurrent();
            InputSystem.onActionChange += OnActionChange;
            recording = true;
            yield return null;
            RefreshPlayerInputPairings();

            Assert.That(Ready, Is.True,
                "Virtual Input System Keyboard and Mouse could not be installed.");
        }

        static void EnsureProcessDevices()
        {
            if (processMouse == null && processKeyboard == null)
            {
                processMouse = InputSystem.AddDevice<Mouse>(
                    "OmniGameSignCircuitProcessMouse");
                processKeyboard = InputSystem.AddDevice<Keyboard>(
                    "OmniGameSignCircuitProcessKeyboard");
                processDevicePairCreationCount++;
                return;
            }

            Assert.That(processMouse, Is.Not.Null,
                "[OMNIGAME_EVALUATOR_INFRASTRUCTURE] Process Mouse lease was lost.");
            Assert.That(processKeyboard, Is.Not.Null,
                "[OMNIGAME_EVALUATOR_INFRASTRUCTURE] Process Keyboard lease was lost.");
            Assert.That(processMouse.added && processKeyboard.added, Is.True,
                "[OMNIGAME_EVALUATOR_INFRASTRUCTURE] A process-scoped evaluator " +
                "device was removed while the Dynamic phase was still running.");
        }

        public int CurrentFrame => Time.frameCount;

        public bool HasPerformedKeyboardActionSince(int frame) =>
            actionEvents.Any(item => item.frame >= frame && item.phase == "performed" &&
                                     item.device_id == virtualKeyboard.deviceId);

        public bool HasPerformedMouseActionSince(int frame) =>
            actionEvents.Any(item => item.frame >= frame && item.phase == "performed" &&
                                     item.device_id == virtualMouse.deviceId);

        public string ActionSummarySince(int frame) => string.Join(" -> ", actionEvents
            .Where(item => item.frame >= frame)
            .Select(item => $"{item.action}:{item.phase}@f{item.frame}/{item.control_path}"));

        public IEnumerator Press(Key key, bool requireInputAction = false)
        {
            yield return Initialize();
            int startedFrame = Time.frameCount;
            QueueKeyboard(new KeyboardState(key));
            yield return null;
            bool pressed = virtualKeyboard[key].isPressed;
            QueueKeyboard(new KeyboardState());
            yield return null;
            bool released = !virtualKeyboard[key].isPressed;

            Assert.That(pressed && released, Is.True,
                $"Virtual key {key} did not complete a press/release cadence.");
            if (requireInputAction)
            {
                Assert.That(HasPerformedKeyboardActionSince(startedFrame), Is.True,
                    $"Virtual key {key} did not perform any candidate InputAction. " +
                    ActionSummarySince(startedFrame));
            }
        }

        public IEnumerator Hold(Key key, float realtimeSeconds, bool requireInputAction = false)
        {
            yield return Initialize();
            int startedFrame = Time.frameCount;
            QueueKeyboard(new KeyboardState(key));
            yield return null;

            float deadline = Time.realtimeSinceStartup + Mathf.Max(0.05f, realtimeSeconds);
            while (Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }

            QueueKeyboard(new KeyboardState());
            yield return null;
            Assert.That(!virtualKeyboard[key].isPressed, Is.True,
                $"Virtual key {key} remained pressed after release.");
            if (requireInputAction)
            {
                Assert.That(HasPerformedKeyboardActionSince(startedFrame), Is.True,
                    $"Holding virtual key {key} did not perform any candidate InputAction. " +
                    ActionSummarySince(startedFrame));
            }
        }

        public IEnumerator HoldChord(
            float realtimeSeconds,
            bool requireInputAction,
            params Key[] keys)
        {
            yield return Initialize();
            Assert.That(keys, Is.Not.Null.And.Not.Empty,
                "A virtual keyboard chord must contain at least one key.");
            int startedFrame = Time.frameCount;
            QueueKeyboard(new KeyboardState(keys));
            yield return null;
            Assert.That(keys.All(key => virtualKeyboard[key].isPressed), Is.True,
                $"Virtual chord {string.Join("+", keys)} did not enter the pressed state.");

            float deadline = Time.realtimeSinceStartup + Mathf.Max(0.05f, realtimeSeconds);
            while (Time.realtimeSinceStartup < deadline)
            {
                yield return null;
            }

            QueueKeyboard(new KeyboardState());
            yield return null;
            Assert.That(keys.All(key => !virtualKeyboard[key].isPressed), Is.True,
                $"Virtual chord {string.Join("+", keys)} remained pressed after release.");
            if (requireInputAction)
            {
                Assert.That(HasPerformedKeyboardActionSince(startedFrame), Is.True,
                    $"Virtual chord {string.Join("+", keys)} did not perform any candidate " +
                    "InputAction. " + ActionSummarySince(startedFrame));
            }
        }

        public void SetHeldKey(Key key)
        {
            Assert.That(Ready, Is.True, "NativeInputDriver must be initialized first.");
            RefreshPlayerInputPairings();
            QueueKeyboard(new KeyboardState(key));
        }

        public void ReleaseKeyboard()
        {
            if (Ready)
            {
                QueueKeyboard(new KeyboardState());
            }
        }

        public void ReleasePointer()
        {
            if (Ready)
            {
                QueueMouse(virtualMouse.position.ReadValue(), false);
            }
        }

        public IEnumerator ClickButton(UiClickTarget target)
        {
            yield return Initialize();
            Assert.That(target, Is.Not.Null, "The requested UI click target is missing.");
            if (target.Backend == UiClickBackend.Ugui)
            {
                yield return ClickUguiButton(target);
                yield break;
            }
            if (target.Backend == UiClickBackend.UiToolkit)
            {
                yield return ClickToolkitButton(target);
                yield break;
            }
            if (target.Backend == UiClickBackend.ScreenPoint)
            {
                if (target.ExpectedPointerHandler != null)
                {
                    EventSystem eventSystem = EventSystem.current;
                    Assert.That(eventSystem, Is.Not.Null,
                        "The visible custom uGUI target has no active EventSystem.");
                    var pointer = new PointerEventData(eventSystem)
                    {
                        position = target.ScreenPoint
                    };
                    var hits = new List<RaycastResult>();
                    eventSystem.RaycastAll(pointer, hits);
                    RaycastResult topHit = hits.FirstOrDefault(item =>
                        item.gameObject != null);
                    GameObject actualHandler = topHit.gameObject == null
                        ? null
                        : ExecuteEvents.GetEventHandler<IPointerClickHandler>(
                            topHit.gameObject);
                    Assert.That(actualHandler, Is.EqualTo(target.ExpectedPointerHandler),
                        "The custom uGUI click point is no longer routed to the visible " +
                        "top-hit handler selected during discovery.");
                }
                if (target.ExpectedToolkitHit != null)
                {
                    IPanel panel = target.ExpectedToolkitHit.panel;
                    Assert.That(panel, Is.Not.Null,
                        "The visible custom UI Toolkit target lost its runtime panel.");
                    Vector2 panelPoint = RuntimePanelUtils.ScreenToPanel(panel,
                        new Vector2(target.ScreenPoint.x,
                            Screen.height - target.ScreenPoint.y));
                    VisualElement actual = panel.Pick(panelPoint);
                    Assert.That(IsElementOrDescendant(actual,
                            target.ExpectedToolkitHit), Is.True,
                        "The custom UI Toolkit click point is no longer a real panel top hit.");
                }
                yield return ClickScreenPoint(target.ScreenPoint, target.RouteDescription);
                yield break;
            }
            Assert.Fail($"Unsupported UI click backend: {target.Backend}");
        }

        public IEnumerator ClickScreenPoint(Vector2 point, string routeDescription = "screen point")
        {
            yield return Initialize();
            Assert.That(point.x, Is.InRange(0f, (float)Screen.width));
            Assert.That(point.y, Is.InRange(0f, (float)Screen.height));
            LastUiPoint = point;
            LastUiRoute = string.IsNullOrWhiteSpace(routeDescription)
                ? "screen point"
                : routeDescription;
            QueueMouse(point, false);
            yield return null;
            QueueMouse(point, true);
            yield return null;
            Assert.That(virtualMouse.leftButton.isPressed, Is.True,
                "Virtual Mouse left button did not enter the pressed state.");
            QueueMouse(point, false);
            yield return null;
            Assert.That(!virtualMouse.leftButton.isPressed, Is.True,
                "Virtual Mouse left button did not release.");
        }

        public IEnumerator PressTargetReleaseOutside(Vector2 point)
        {
            yield return Initialize();
            Vector2 outside = new Vector2(
                point.x < Screen.width * 0.5f ? Screen.width - 2f : 2f,
                point.y < Screen.height * 0.5f ? Screen.height - 2f : 2f);
            QueueMouse(point, false);
            yield return null;
            QueueMouse(point, true);
            yield return null;
            Assert.That(virtualMouse.leftButton.isPressed, Is.True);
            QueueMouse(outside, true);
            yield return null;
            QueueMouse(outside, false);
            yield return null;
            Assert.That(!virtualMouse.leftButton.isPressed, Is.True);
        }

        public IEnumerator PressOutsideReleaseTarget(Vector2 point)
        {
            yield return Initialize();
            Assert.That(point.x, Is.InRange(0f, (float)Screen.width));
            Assert.That(point.y, Is.InRange(0f, (float)Screen.height));
            Vector2 outside = new Vector2(
                point.x < Screen.width * 0.5f ? Screen.width - 2f : 2f,
                point.y < Screen.height * 0.5f ? Screen.height - 2f : 2f);
            QueueMouse(outside, false);
            yield return null;
            QueueMouse(outside, true);
            yield return null;
            Assert.That(virtualMouse.leftButton.isPressed, Is.True);
            QueueMouse(point, true);
            yield return null;
            QueueMouse(point, false);
            yield return null;
            Assert.That(!virtualMouse.leftButton.isPressed, Is.True);
        }

        IEnumerator ClickUguiButton(UiClickTarget target)
        {
            UguiButton button = target.UguiButton;
            Assert.That(button, Is.Not.Null, "The requested uGUI Button is missing.");
            Assert.That(button.isActiveAndEnabled && button.interactable, Is.True,
                $"Button {button.name} is not active and interactable.");

            EventSystem eventSystem = EventSystem.current;
            Assert.That(eventSystem, Is.Not.Null,
                "The active scene has no EventSystem for player UI input.");
            GameObject expectedHandler =
                ExecuteEvents.GetEventHandler<IPointerClickHandler>(button.gameObject);
            Assert.That(expectedHandler, Is.Not.Null,
                $"Button {button.name} does not resolve to a normal pointer click handler.");

            Vector2 point = target.ScreenPoint;
            Assert.That(point.x, Is.InRange(0f, (float)Screen.width));
            Assert.That(point.y, Is.InRange(0f, (float)Screen.height));
            if (target.HasProbeRect)
            {
                Assert.That(target.ProbeRect.Contains(point), Is.True,
                    "The saved uGUI click point escaped the published semantic locator.");
            }

            int startedFrame = Time.frameCount;
            QueueMouse(point, false);
            yield return null;
            var pointer = new PointerEventData(eventSystem) { position = point };
            var hits = new List<RaycastResult>();
            eventSystem.RaycastAll(pointer, hits);
            RaycastResult topHit = hits.FirstOrDefault(item => item.gameObject != null);
            GameObject actualHandler = topHit.gameObject == null
                ? null
                : ExecuteEvents.GetEventHandler<IPointerClickHandler>(topHit.gameObject);
            LastUiRoute = topHit.gameObject == null
                ? "<none>"
                : topHit.gameObject.name + " -> " +
                  (actualHandler == null ? "<no-handler>" : actualHandler.name);
            LastUiPoint = point;
            Assert.That(actualHandler == expectedHandler, Is.True,
                $"The current EventSystem top hit was not the requested control: {LastUiRoute}");

            QueueMouse(point, true);
            yield return null;
            Assert.That(virtualMouse.leftButton.isPressed, Is.True,
                "Virtual Mouse left button did not enter the pressed state.");
            QueueMouse(point, false);
            yield return null;
            Assert.That(!virtualMouse.leftButton.isPressed, Is.True,
                "Virtual Mouse left button did not release.");
            LastUiRoute += HasPerformedMouseActionSince(startedFrame)
                ? " [InputAction observed]"
                : " [device event observed]";
        }

        IEnumerator ClickToolkitButton(UiClickTarget target)
        {
            UIDocument document = target.Document;
            UnityEngine.UIElements.Button button = target.ToolkitButton;
            Assert.That(document, Is.Not.Null,
                "The requested UI Toolkit target has no UIDocument.");
            Assert.That(button, Is.Not.Null,
                "The requested UI Toolkit Button is missing.");
            Assert.That(document.isActiveAndEnabled &&
                        document.gameObject.activeInHierarchy, Is.True,
                "The UI Toolkit UIDocument is not active and enabled.");
            Assert.That(button.enabledInHierarchy && button.clickable != null, Is.True,
                "The UI Toolkit Button is not enabled and clickable.");
            Assert.That(SignCircuitTestSupport.IsToolkitElementVisible(button), Is.True,
                "The UI Toolkit Button is not visibly laid out in its panel.");

            IPanel panel = button.panel;
            Assert.That(panel, Is.Not.Null,
                "The UI Toolkit Button is not attached to a runtime panel.");
            Vector2 point = target.ScreenPoint;
            Assert.That(point.x, Is.InRange(0f, (float)Screen.width));
            Assert.That(point.y, Is.InRange(0f, (float)Screen.height));
            if (target.HasProbeRect)
            {
                Assert.That(target.ProbeRect.Contains(point), Is.True,
                    "The saved UI Toolkit click point escaped the published semantic locator.");
            }

            int startedFrame = Time.frameCount;
            QueueMouse(point, false);
            yield return null;
            Vector2 panelPoint = RuntimePanelUtils.ScreenToPanel(panel,
                new Vector2(point.x, Screen.height - point.y));
            VisualElement actual = panel.Pick(panelPoint);
            LastUiRoute = "UI Toolkit: " + DescribeElement(actual) + " -> " +
                          DescribeElement(button);
            LastUiPoint = point;
            Assert.That(IsElementOrDescendant(actual, button), Is.True,
                $"UI Toolkit top pick was not the requested Button: {LastUiRoute}");

            QueueMouse(point, true);
            yield return null;
            Assert.That(virtualMouse.leftButton.isPressed, Is.True,
                "Virtual Mouse left button did not enter the pressed state.");
            QueueMouse(point, false);
            yield return null;
            Assert.That(!virtualMouse.leftButton.isPressed, Is.True,
                "Virtual Mouse left button did not release.");
            LastUiRoute += HasPerformedMouseActionSince(startedFrame)
                ? " [InputAction observed]"
                : " [device event observed]";
        }

        public IEnumerator Dispose()
        {
            Exception cleanupFailure = null;
            try
            {
                try { ReleaseKeyboard(); }
                catch (Exception exception) { cleanupFailure = exception; }
                try { ReleasePointer(); }
                catch (Exception exception)
                {
                    if (cleanupFailure == null) cleanupFailure = exception;
                }
                if (recording)
                {
                    try { InputSystem.onActionChange -= OnActionChange; }
                    catch (Exception exception)
                    {
                        if (cleanupFailure == null) cleanupFailure = exception;
                    }
                    recording = false;
                }
                foreach (InputDevice device in disabledDevices)
                {
                    if (device == null || !device.added) continue;
                    try { InputSystem.EnableDevice(device); }
                    catch (Exception exception)
                    {
                        if (cleanupFailure == null) cleanupFailure = exception;
                    }
                }
                disabledDevices.Clear();

                if (previousMouse != null && previousMouse.added &&
                    previousMouse.enabled)
                {
                    try { previousMouse.MakeCurrent(); }
                    catch (Exception exception)
                    {
                        if (cleanupFailure == null) cleanupFailure = exception;
                    }
                }
                if (previousKeyboard != null && previousKeyboard.added &&
                    previousKeyboard.enabled)
                {
                    try { previousKeyboard.MakeCurrent(); }
                    catch (Exception exception)
                    {
                        if (cleanupFailure == null) cleanupFailure = exception;
                    }
                }
                if (changedBackgroundBehavior)
                {
                    try
                    {
                        InputSystem.settings.backgroundBehavior =
                            previousBackgroundBehavior;
                    }
                    catch (Exception exception)
                    {
                        if (cleanupFailure == null) cleanupFailure = exception;
                    }
                }
#if UNITY_EDITOR
                if (changedEditorInputBehavior)
                {
                    try
                    {
                        InputSystem.settings.editorInputBehaviorInPlayMode =
                            previousEditorInputBehavior;
                    }
                    catch (Exception exception)
                    {
                        if (cleanupFailure == null) cleanupFailure = exception;
                    }
                }
#endif
            }
            finally
            {
                if (recording)
                {
                    InputSystem.onActionChange -= OnActionChange;
                    recording = false;
                }
                disabledDevices.Clear();
                if (ReferenceEquals(activeOwner, this))
                {
                    activeOwner = null;
                }
                actionEvents.Clear();
                LastUiRoute = string.Empty;
                LastUiPoint = default;
                virtualMouse = null;
                virtualKeyboard = null;
            }
            if (cleanupFailure != null)
            {
                Assert.Fail("[OMNIGAME_EVALUATOR_INFRASTRUCTURE] Native input " +
                    "lease cleanup failed after all restoration paths were " +
                    "attempted: " + cleanupFailure);
            }
            yield return null;
        }

        void QueueMouse(Vector2 position, bool leftPressed)
        {
            Vector2 previous = virtualMouse.position.ReadValue();
            var state = new MouseState
            {
                position = position,
                delta = position - previous,
                displayIndex = 0
            };
            state = state.WithButton(
                UnityEngine.InputSystem.LowLevel.MouseButton.Left, leftPressed);
            InputSystem.QueueStateEvent(virtualMouse, state);
            InputSystem.Update();
            virtualMouse.MakeCurrent();
        }

        void QueueKeyboard(KeyboardState state)
        {
            InputSystem.QueueStateEvent(virtualKeyboard, state);
            InputSystem.Update();
            virtualKeyboard.MakeCurrent();
        }

        void RefreshPlayerInputPairings()
        {
            if (virtualKeyboard == null || !virtualKeyboard.added) return;

            // Keep the direct Keyboard.current route intact while also using the normal
            // InputUser device-pairing path for optional PlayerInput backends created by
            // the latest scene load. No candidate handler or callback is invoked here.
            virtualKeyboard.MakeCurrent();
            foreach (PlayerInput playerInput in PlayerInput.all.ToArray())
            {
                if (playerInput == null || !playerInput.isActiveAndEnabled ||
                    !playerInput.gameObject.activeInHierarchy)
                {
                    continue;
                }
                InputUser user = playerInput.user;
                if (!user.valid) continue;
                if (!user.pairedDevices.Contains(virtualKeyboard))
                {
                    InputUser.PerformPairingWithDevice(virtualKeyboard, user: user);
                }
                if (virtualMouse != null && virtualMouse.added &&
                    !user.pairedDevices.Contains(virtualMouse))
                {
                    InputUser.PerformPairingWithDevice(virtualMouse, user: user);
                }
            }
        }

        internal static bool TryFindTopHitPoint(
            RectTransform rect,
            GameObject expectedHandler,
            EventSystem eventSystem,
            Rect allowedScreenRect,
            out Vector2 selected,
            out string sampledHits)
        {
            selected = default;
            var candidates = new List<Vector2>();
            if (rect == null)
            {
                sampledHits = "The visible control has no RectTransform.";
                return false;
            }

            var corners = new Vector3[4];
            rect.GetWorldCorners(corners);
            Canvas canvas = rect.GetComponentInParent<Canvas>();
            Camera camera = canvas != null &&
                            canvas.rootCanvas.renderMode != RenderMode.ScreenSpaceOverlay
                ? canvas.rootCanvas.worldCamera ?? Camera.main
                : null;
            Vector2 bottomLeft = RectTransformUtility.WorldToScreenPoint(camera, corners[0]);
            Vector2 topRight = RectTransformUtility.WorldToScreenPoint(camera, corners[2]);
            if (allowedScreenRect.width >= 1f && allowedScreenRect.height >= 1f)
            {
                bottomLeft = allowedScreenRect.min;
                topRight = allowedScreenRect.max;
            }
            foreach (float xRatio in new[] {0.25f, 0.5f, 0.75f})
            foreach (float yRatio in new[] {0.25f, 0.5f, 0.75f})
            {
                candidates.Add(new Vector2(
                    Mathf.Lerp(bottomLeft.x, topRight.x, xRatio),
                    Mathf.Lerp(bottomLeft.y, topRight.y, yRatio)));
            }

            var observed = new List<string>();
            Canvas.ForceUpdateCanvases();
            foreach (Vector2 point in candidates.Where(point =>
                         point.x >= 0f && point.x <= Screen.width &&
                         point.y >= 0f && point.y <= Screen.height))
            {
                var data = new PointerEventData(eventSystem) { position = point };
                var hits = new List<RaycastResult>();
                eventSystem.RaycastAll(data, hits);
                RaycastResult top = hits.FirstOrDefault(item => item.gameObject != null);
                GameObject handler = top.gameObject == null
                    ? null
                    : ExecuteEvents.GetEventHandler<IPointerClickHandler>(top.gameObject);
                observed.Add($"({point.x:F1},{point.y:F1})=" +
                             (top.gameObject == null ? "<none>" : top.gameObject.name) +
                             "->" + (handler == null ? "<none>" : handler.name));
                if (handler == expectedHandler)
                {
                    selected = point;
                    sampledHits = string.Join(" | ", observed);
                    return true;
                }
            }

            sampledHits = string.Join(" | ", observed);
            return false;
        }

        internal static bool TryFindToolkitTopHitPoint(
            VisualElement button,
            IPanel panel,
            Rect allowedScreenRect,
            out Vector2 selected,
            out string sampledHits)
        {
            selected = default;
            Rect target = button.worldBound;
            Rect root = panel.visualTree.worldBound;
            if (target.width < 1f || target.height < 1f ||
                root.width < 1f || root.height < 1f)
            {
                sampledHits = $"Invalid panel geometry: target={target}, root={root}.";
                return false;
            }

            var observed = new List<string>();
            foreach (float xRatio in new[] {0.25f, 0.5f, 0.75f})
            foreach (float yRatio in new[] {0.25f, 0.5f, 0.75f})
            {
                Vector2 screen;
                if (allowedScreenRect.width >= 1f && allowedScreenRect.height >= 1f)
                {
                    screen = new Vector2(
                        Mathf.Lerp(allowedScreenRect.xMin, allowedScreenRect.xMax, xRatio),
                        Mathf.Lerp(allowedScreenRect.yMin, allowedScreenRect.yMax, yRatio));
                }
                else
                {
                    Vector2 desiredPanel = new Vector2(
                        Mathf.Lerp(target.xMin, target.xMax, xRatio),
                        Mathf.Lerp(target.yMin, target.yMax, yRatio));
                    float normalizedX = Mathf.InverseLerp(root.xMin, root.xMax,
                        desiredPanel.x);
                    float normalizedY = Mathf.InverseLerp(root.yMin, root.yMax,
                        desiredPanel.y);
                    screen = new Vector2(normalizedX * Screen.width,
                        Screen.height - normalizedY * Screen.height);
                }
                Vector2 roundTrip = RuntimePanelUtils.ScreenToPanel(panel,
                    new Vector2(screen.x, Screen.height - screen.y));
                VisualElement hit = panel.Pick(roundTrip);
                observed.Add($"({screen.x:F1},{screen.y:F1})=" +
                             DescribeElement(hit));
                if (screen.x < 0f || screen.x > Screen.width ||
                    screen.y < 0f || screen.y > Screen.height ||
                    !IsElementOrDescendant(hit, button))
                {
                    continue;
                }
                selected = screen;
                sampledHits = string.Join(" | ", observed);
                return true;
            }

            sampledHits = string.Join(" | ", observed);
            return false;
        }

        static bool IsElementOrDescendant(VisualElement element,
            VisualElement expectedAncestor)
        {
            for (VisualElement current = element; current != null;
                 current = current.parent)
            {
                if (current == expectedAncestor) return true;
            }
            return false;
        }

        static string DescribeElement(VisualElement element)
        {
            if (element == null) return "<none>";
            return string.IsNullOrWhiteSpace(element.name)
                ? element.GetType().Name
                : element.name;
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
                (action.activeControl.device != virtualKeyboard &&
                 action.activeControl.device != virtualMouse))
            {
                return;
            }

            actionEvents.Add(new NativeActionEvent
            {
                phase = phase,
                action = action.name,
                control_path = action.activeControl.path,
                device_id = action.activeControl.device.deviceId,
                frame = Time.frameCount
            });
        }
    }

    [Serializable]
    internal sealed class NativeActionEvent
    {
        public string phase;
        public string action;
        public string control_path;
        public int device_id;
        public int frame;
    }
}
