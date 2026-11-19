using System.Collections;
using System.Linq;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

namespace GameCreate.NoirRoombreak.Evaluator
{
    public sealed class VirtualInputDriver
    {
        Keyboard keyboard;
        Keyboard previousKeyboard;
        Mouse mouse;
        Mouse previousMouse;
        InputSettings.BackgroundBehavior previousBackground;
#if UNITY_EDITOR
        InputSettings.EditorInputBehaviorInPlayMode previousEditorBehavior;
#endif

        public IEnumerator Ready()
        {
            if (keyboard != null && mouse != null) yield break;
            previousBackground = InputSystem.settings.backgroundBehavior;
            InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
#if UNITY_EDITOR
            previousEditorBehavior = InputSystem.settings.editorInputBehaviorInPlayMode;
            InputSystem.settings.editorInputBehaviorInPlayMode = InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
#endif
            previousKeyboard = Keyboard.current;
            previousMouse = Mouse.current;
            foreach (var device in InputSystem.devices.OfType<Keyboard>().Where(x => x.enabled).ToArray()) InputSystem.DisableDevice(device);
            foreach (var device in InputSystem.devices.OfType<Mouse>().Where(x => x.enabled).ToArray()) InputSystem.DisableDevice(device);
            keyboard = InputSystem.AddDevice<Keyboard>("NoirRoombreakEvaluatorKeyboard");
            mouse = InputSystem.AddDevice<Mouse>("NoirRoombreakEvaluatorMouse");
            keyboard.MakeCurrent();
            mouse.MakeCurrent();
            yield return null;
        }

        public IEnumerator Press(Key key)
        {
            yield return Ready();
            keyboard.MakeCurrent();
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(key));
            yield return null;
            keyboard.MakeCurrent();
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            yield return null;
        }

        public IEnumerator Frame(params Key[] keys)
        {
            yield return Ready();
            keyboard.MakeCurrent();
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(keys));
            yield return null;
            keyboard.MakeCurrent();
        }

        public IEnumerator Hold(float seconds, params Key[] keys)
        {
            yield return Ready();
            var until = Time.realtimeSinceStartup + Mathf.Max(0f, seconds);
            while (Time.realtimeSinceStartup < until)
            {
                keyboard.MakeCurrent();
                InputSystem.QueueStateEvent(keyboard, new KeyboardState(keys));
                yield return null;
            }
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            yield return null;
        }

        public IEnumerator Click(Vector2 bottomLeftScreenPosition)
        {
            yield return Ready();
            mouse.MakeCurrent();
            InputSystem.QueueStateEvent(mouse, new MouseState { position = bottomLeftScreenPosition, buttons = 1 });
            yield return null;
            mouse.MakeCurrent();
            InputSystem.QueueStateEvent(mouse, new MouseState { position = bottomLeftScreenPosition, buttons = 0 });
            yield return null;
        }

        public IEnumerator Dispose()
        {
            if (keyboard != null && keyboard.added) InputSystem.RemoveDevice(keyboard);
            if (mouse != null && mouse.added) InputSystem.RemoveDevice(mouse);
            if (previousKeyboard != null && previousKeyboard.added)
            {
                InputSystem.EnableDevice(previousKeyboard);
                previousKeyboard.MakeCurrent();
            }
            if (previousMouse != null && previousMouse.added)
            {
                InputSystem.EnableDevice(previousMouse);
                previousMouse.MakeCurrent();
            }
            InputSystem.settings.backgroundBehavior = previousBackground;
#if UNITY_EDITOR
            InputSystem.settings.editorInputBehaviorInPlayMode = previousEditorBehavior;
#endif
            keyboard = null;
            mouse = null;
            yield return null;
        }
    }
}
