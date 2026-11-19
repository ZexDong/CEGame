using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

namespace GameCreate.Evaluation.Session
{
    // Normal Unity player-loop input, independent of game implementation and
    // window focus. Changes affect this Unity process only.
    public sealed class PlayerInputDriver
    {
        Keyboard keyboard, previousKeyboard;
        Mouse mouse, previousMouse;
        readonly List<InputDevice> disabled=new List<InputDevice>();
        InputSettings.BackgroundBehavior previousBackground;
#if UNITY_EDITOR
        InputSettings.EditorInputBehaviorInPlayMode previousEditorBehavior;
#endif
        public IEnumerator Ready()
        {
            if(keyboard!=null)yield break;
            previousBackground=InputSystem.settings.backgroundBehavior;
            InputSystem.settings.backgroundBehavior=InputSettings.BackgroundBehavior.IgnoreFocus;
#if UNITY_EDITOR
            previousEditorBehavior=InputSystem.settings.editorInputBehaviorInPlayMode;
            InputSystem.settings.editorInputBehaviorInPlayMode=InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
#endif
            previousKeyboard=Keyboard.current;previousMouse=Mouse.current;
            foreach(var device in InputSystem.devices.Where(x=>x.enabled&&(x is Keyboard||x is Mouse)).ToArray()){
                disabled.Add(device);InputSystem.DisableDevice(device);
            }
            keyboard=InputSystem.AddDevice<Keyboard>();mouse=InputSystem.AddDevice<Mouse>();keyboard.MakeCurrent();mouse.MakeCurrent();
            yield return null;
        }
        public IEnumerator Frame(params Key[] keys)
        {
            yield return Ready();keyboard.MakeCurrent();InputSystem.QueueStateEvent(keyboard,new KeyboardState(keys));yield return null;keyboard.MakeCurrent();
        }
        public IEnumerator Press(Key key){yield return Frame(key);yield return Frame();}
        public IEnumerator Hold(Key key,float seconds)
        {
            yield return Ready();var end=Time.realtimeSinceStartup+seconds;
            while(Time.realtimeSinceStartup<end){yield return Frame(key);}yield return Frame();
        }
        public IEnumerator Dispose()
        {
            if(keyboard!=null&&keyboard.added)InputSystem.RemoveDevice(keyboard);
            if(mouse!=null&&mouse.added)InputSystem.RemoveDevice(mouse);
            foreach(var device in disabled)if(device.added)InputSystem.EnableDevice(device);disabled.Clear();
            if(previousKeyboard!=null&&previousKeyboard.added)previousKeyboard.MakeCurrent();
            if(previousMouse!=null&&previousMouse.added)previousMouse.MakeCurrent();
            InputSystem.settings.backgroundBehavior=previousBackground;
#if UNITY_EDITOR
            InputSystem.settings.editorInputBehaviorInPlayMode=previousEditorBehavior;
#endif
            keyboard=null;mouse=null;yield return null;
        }
    }
}
