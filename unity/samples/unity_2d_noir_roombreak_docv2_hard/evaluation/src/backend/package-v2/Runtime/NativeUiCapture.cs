using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using GameCreate.NoirRoombreak.StateAccess;
using GameCreate.Evaluation.Session;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;

namespace GameCreate.NoirRoombreak.Evaluator.Standalone
{
    internal sealed class NativeInput : IDisposable
    {
        [StructLayout(LayoutKind.Sequential)] struct Point { public int x, y; }
        [StructLayout(LayoutKind.Sequential)] struct Mouse { public int x,y; public uint data,flags,time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)] struct Keyboard { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Explicit)] struct Union { [FieldOffset(0)] public Mouse mouse; [FieldOffset(0)] public Keyboard keyboard; }
        [StructLayout(LayoutKind.Sequential)] struct Input { public uint type; public Union value; }
        [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, Input[] inputs, int size);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window, ref Point point);
        [DllImport("user32.dll")] static extern bool SetCursorPos(int x,int y);
        [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
        [DllImport("user32.dll",SetLastError=true)] static extern bool PostMessage(IntPtr window,uint message,IntPtr wParam,IntPtr lParam);
        readonly IntPtr window, previousWindow;
        readonly Point previousCursor;
        public NativeInput()
        {
            window=System.Diagnostics.Process.GetCurrentProcess().MainWindowHandle;
            if(window==IntPtr.Zero) throw new InvalidOperationException("Native UI player window is unavailable.");
            previousWindow=GetForegroundWindow(); GetCursorPos(out previousCursor);
        }
        void Send(Input input)
        {
            if(SendInput(1,new[]{input},Marshal.SizeOf(typeof(Input)))!=1)
                throw new InvalidOperationException("OS input injection failed: "+Marshal.GetLastWin32Error());
        }
        public IEnumerator Click(float x,float topY)
        {
            var packed=(Mathf.RoundToInt(topY)<<16)|(Mathf.RoundToInt(x)&0xffff);
            if(!PostMessage(window,0x200,IntPtr.Zero,new IntPtr(packed)))throw new InvalidOperationException("Targeted mouse move could not be queued.");
            yield return new WaitForSecondsRealtime(.08f);
            if(!PostMessage(window,0x201,new IntPtr(1),new IntPtr(packed)))throw new InvalidOperationException("Targeted mouse down could not be queued.");
            yield return new WaitForSecondsRealtime(.08f);
            if(!PostMessage(window,0x202,IntPtr.Zero,new IntPtr(packed)))throw new InvalidOperationException("Targeted mouse up could not be queued.");
            yield return new WaitForSecondsRealtime(.18f);
        }
        public void Dispose(){}
    }
    internal sealed class UiInputSentinel : MonoBehaviour
    {
        public bool clicked;
        void OnGUI(){var old=GUI.depth;GUI.depth=-1000000;if(GUI.Button(new Rect(Screen.width-45,Screen.height-45,35,35),"."))clicked=true;GUI.depth=old;}
    }

    [Serializable] public sealed class UiFrame
    {
        public string id,path,phase; public int room,bonds,charges,frame; public bool alive;
    }
    [Serializable] public sealed class UiRequest { public string id,image,token; }
    [Serializable] public sealed class UiReply { public bool valid,found; public float x,y; public string text,error; }
    [Serializable] public sealed class UiCaptureEvidence
    {
        public bool valid,menu_click,pause_resume_click,pause_restart_click,success_return_click,menu_world_clean,initial_world_clean;
        public int process_id; public string error="",profile="",product_block_reason=""; public List<UiFrame> frames=new List<UiFrame>();
    }
    internal sealed class NativeUiCapture : MonoBehaviour
    {
        string directory; NativeInput input; StandaloneInputDriver engineInput; NoirStateAccess access; bool imgui;
        readonly UiCaptureEvidence evidence=new UiCaptureEvidence(); UiReply reply;
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)] static void Install()
        {
            if(Application.isEditor || Environment.GetEnvironmentVariable("NOIR_UI_CAPTURE")!="1")return;
            var go=new GameObject("PrivateNativeUiCapture"); DontDestroyOnLoad(go); go.AddComponent<NativeUiCapture>();
        }
        IEnumerator Start()
        {
            directory=Environment.GetEnvironmentVariable("NOIR_UI_DIR");
            if(string.IsNullOrWhiteSpace(directory)){Application.Quit(3);yield break;}
            Directory.CreateDirectory(directory); evidence.process_id=System.Diagnostics.Process.GetCurrentProcess().Id;
            var stack=new Stack<IEnumerator>();stack.Push(Work());
            while(stack.Count>0)
            {
                object next=null;bool has=false;Exception error=null;
                try{has=stack.Peek().MoveNext();if(has)next=stack.Peek().Current;}catch(Exception ex){error=ex;}
                if(error!=null){if(error is SessionProductFailure)evidence.product_block_reason=error.ToString();else evidence.error=error.ToString();break;}
                if(!has){stack.Pop();continue;}
                if(next is IEnumerator nested)stack.Push(nested);else yield return next;
            }
            engineInput?.Dispose();input?.Dispose(); access?.Dispose();
            evidence.valid=string.IsNullOrEmpty(evidence.error);
            File.WriteAllText(Path.Combine(directory,"ui-runtime.json"),JsonUtility.ToJson(evidence,true));
            Application.Quit(evidence.valid?0:3);
        }
        IEnumerator Work()
        {
            Application.runInBackground=true; QualitySettings.vSyncCount=0;Application.targetFrameRate=60;
            Screen.SetResolution(1280,720,FullScreenMode.Windowed);
            yield return new WaitForSecondsRealtime(.5f);
            var splashDeadline=Time.realtimeSinceStartup+15;
            while(!UnityEngine.Rendering.SplashScreen.isFinished&&Time.realtimeSinceStartup<splashDeadline)yield return null;
            access=NoirStateAccess.Find();
            if(access==null){evidence.product_block_reason="candidate-entry-missing";yield break;}
            UnityEngine.InputSystem.InputSystem.settings.backgroundBehavior=UnityEngine.InputSystem.InputSettings.BackgroundBehavior.IgnoreFocus;
            evidence.profile=access.Profile;input=new NativeInput();engineInput=new StandaloneInputDriver();yield return engineInput.Ready();
            imgui=FindObjectsByType<MonoBehaviour>(FindObjectsSortMode.None).Any(x=>x.GetType().GetMethod("OnGUI",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.Public|System.Reflection.BindingFlags.NonPublic)!=null);
            #if ENABLE_LEGACY_INPUT_MANAGER
            if(imgui)
            {
                var sentinel=gameObject.AddComponent<UiInputSentinel>();yield return null;
                yield return input.Click(Screen.width-25,Screen.height-25);
                if(!sentinel.clicked)throw new InvalidOperationException("IMGUI input transport self-test failed; do not penalize the candidate.");
                Destroy(sentinel);yield return null;
            }
            #endif
            yield return Capture("menu","START");
            if(reply.found)yield return Click(reply.x,reply.y);
            evidence.menu_click=access.Phase==NoirScreen.Playing;
            if(access.Phase==NoirScreen.Menu)yield return Key(UnityEngine.InputSystem.Key.Enter);
            evidence.initial_world_clean=access.Phase==NoirScreen.Playing&&access.Room==0&&access.Bonds==3&&access.Charges==3&&access.Defeated==0&&access.Soft==0&&access.Global==0;
            if(access.Phase!=NoirScreen.Playing){yield return access.BeginRoom(0);yield return access.Seal();yield return null;}
            yield return Capture("gameplay","");
            // UI synchronization is tested away from encounters. It must not
            // inherit a death from the preceding dash while OCR is running.
            yield return access.BeginRoom(0);
            var safeX=access.TestX(6.5f);
            foreach(var enemy in access.CurrentEnemies()){access.PlaceEnemy(enemy,safeX,access.FloorY);safeX+=.4f;}
            yield return access.Seal();yield return null;
            yield return Key(UnityEngine.InputSystem.Key.Z);yield return new WaitForSecondsRealtime(.8f);
            yield return Capture("after_dash","");
            yield return Key(UnityEngine.InputSystem.Key.Escape);yield return Capture("paused","RESUME");
            var hadPause=access.Phase==NoirScreen.Paused;
            if(reply.found)yield return Click(reply.x,reply.y);
            evidence.pause_resume_click=hadPause&&reply.found&&access.Phase==NoirScreen.Playing;
            if(access.Phase==NoirScreen.Paused)yield return Key(UnityEngine.InputSystem.Key.Escape);
            yield return Key(UnityEngine.InputSystem.Key.Escape);yield return Capture("paused_restart","RESTART");
            hadPause=access.Phase==NoirScreen.Paused;
            if(reply.found)yield return Click(reply.x,reply.y);
            evidence.pause_restart_click=hadPause&&reply.found&&access.Phase==NoirScreen.Menu;
            if(access.Phase!=NoirScreen.Menu)yield return Key(UnityEngine.InputSystem.Key.R);
            // This fixture only prepares the cleared final encounter. Success
            // itself must still be entered by the candidate's normal movement.
            yield return access.BeginRoom(4);
            foreach(var enemy in access.CurrentEnemies().Where(x=>x.Alive))access.ClearEnemyAsPrecondition(enemy);
            access.PlacePlayer(access.ExitX-.04f,access.FloorY);yield return access.Seal();
            yield return Key(UnityEngine.InputSystem.Key.D);yield return Capture("success","RETURN");
            var hadSuccess=access.Phase==NoirScreen.Success;
            if(reply.found)yield return Click(reply.x,reply.y);
            evidence.success_return_click=hadSuccess&&reply.found&&access.Phase==NoirScreen.Menu;
            if(access.Phase!=NoirScreen.Menu)yield return Key(UnityEngine.InputSystem.Key.R);
            yield return Capture("restart_menu","");
            evidence.menu_world_clean=UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).All(x=>!x.enabled||x.sprite==null);
        }
        IEnumerator Key(UnityEngine.InputSystem.Key key){yield return engineInput.Press(key);yield return new WaitForSecondsRealtime(.12f);}
        IEnumerator Click(float x,float y)
        {
            var before=access.Phase;
            yield return engineInput.Click(new Vector2(x,Screen.height-y));
            var deadline=Time.realtimeSinceStartup+1.5f;
            while(access.Phase==before&&Time.realtimeSinceStartup<deadline)yield return null;
            #if ENABLE_LEGACY_INPUT_MANAGER
            if(access.Phase==before&&imgui)yield return input.Click(x,y);
            #endif
        }
        IEnumerator Capture(string id,string token)
        {
            yield return new WaitForEndOfFrame();
            var texture=ScreenCapture.CaptureScreenshotAsTexture();
            if(texture==null||texture.width!=1280||texture.height!=720)throw new InvalidOperationException("Invalid UI screenshot.");
            var path=Path.Combine(directory,id+".png");File.WriteAllBytes(path,texture.EncodeToPNG());Destroy(texture);
            evidence.frames.Add(new UiFrame{id=id,path=Path.GetFileName(path),phase=access.Phase.ToString(),room=access.Room,bonds=access.Bonds,charges=access.Charges,alive=access.Alive,frame=Time.frameCount});
            File.WriteAllText(Path.Combine(directory,id+".request.json"),JsonUtility.ToJson(new UiRequest{id=id,image=path,token=token}));
            var replyPath=Path.Combine(directory,id+".reply.json");var until=Time.realtimeSinceStartup+25;
            while(!File.Exists(replyPath)&&Time.realtimeSinceStartup<until)yield return null;
            if(!File.Exists(replyPath))throw new TimeoutException("UI OCR response missing: "+id);
            reply=JsonUtility.FromJson<UiReply>(File.ReadAllText(replyPath));
            if(!reply.valid)throw new InvalidOperationException("UI OCR failed: "+reply.error);
        }
    }
}
