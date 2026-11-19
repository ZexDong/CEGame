using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using UnityEngine;
using UnityEngine.Rendering;

namespace GameCreate.Evaluation.Rendering
{
    [Serializable] public sealed class OwnedPlayerWindowObservation
    {
        public bool valid,visible,minimized,foreground;
        public int process_id,matching_window_count,client_width,client_height;
        public long hwnd;
        public string window_class,error;
    }
    [Serializable] public sealed class NativeFullFrameReport
    {
        public string method="standalone-owned-window-native-frame-v2",status="pending",reason,error,request_id;
        public bool valid,batchmode,editor,screen_capture_at_end_of_frame,observer_render_configuration_untouched;
        public int process_id,width,height,start_frame,capture_frame,end_of_frame_count,imgui_repaint_count,last_imgui_repaint_frame;
        public int rendered_frame_start,rendered_frame_capture;
        public int native_camera_post_render_count,srp_end_frame_count,application_before_render_count,nonblack_rgb_pixels;
        public string graphics_device,pipeline;
        public OwnedPlayerWindowObservation window;
    }
    public sealed class NativeFullFrameUnavailableException:InvalidOperationException
    {
        public readonly string reason;
        public NativeFullFrameUnavailableException(string value):base("Native full-frame observer unavailable: "+value){reason=value;}
    }

    // Reads only windows owned by this very player PID. This observer never
    // captures a desktop DC, calls PrintWindow, or invokes candidate OnGUI.
    public static class OwnedPlayerWindow
    {
        [StructLayout(LayoutKind.Sequential)] struct Rect {public int left,top,right,bottom;}
        delegate bool EnumWindow(IntPtr hwnd,IntPtr parameter);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback,IntPtr parameter);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint process);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd,StringBuilder value,int length);
        public static OwnedPlayerWindowObservation Observe(int expectedWidth,int expectedHeight)
        {
            var pid=System.Diagnostics.Process.GetCurrentProcess().Id;
            var result=new OwnedPlayerWindowObservation{process_id=pid};
            try
            {
                var windows=new List<OwnedPlayerWindowObservation>();
                EnumWindows((hwnd,unused)=>{
                    GetWindowThreadProcessId(hwnd,out var owner);if(owner!=(uint)pid)return true;
                    var name=new StringBuilder(256);GetClassName(hwnd,name,name.Capacity);
                    // The pinned Windows player uses this engine window class.
                    // Other owned dialogs are not silently selected as the game.
                    if(name.ToString()!="UnityWndClass"||!GetClientRect(hwnd,out var rect))return true;
                    windows.Add(new OwnedPlayerWindowObservation{process_id=pid,hwnd=hwnd.ToInt64(),window_class=name.ToString(),
                        visible=IsWindowVisible(hwnd),minimized=IsIconic(hwnd),foreground=GetForegroundWindow()==hwnd,
                        client_width=rect.right-rect.left,client_height=rect.bottom-rect.top});return true;
                },IntPtr.Zero);
                result.matching_window_count=windows.Count;
                if(windows.Count!=1){result.error="Expected exactly one engine client window for the owned player PID.";return result;}
                result=windows[0];result.matching_window_count=1;
                result.valid=result.visible&&!result.minimized&&result.client_width==expectedWidth&&result.client_height==expectedHeight;
                if(!result.valid)result.error="Owned client is hidden/minimized or does not match the requested physical viewport.";
            }
            catch(Exception error){result.error=error.ToString();}
            return result;
        }
    }

    public static class NativeFullFrame
    {
        // A separate EOF coroutine plus ordinary-frame watchdog avoids hanging
        // forever when a host suppresses rendering. A timeout is an observer
        // failure, never a product-zero or a reason to return camera-only art.
        public static IEnumerator Capture(int width,int height,float timeoutSeconds,Action<Texture2D,NativeFullFrameReport,Exception> completed)
        {
            var owner=new GameObject("Private native whole-frame observation");UnityEngine.Object.DontDestroyOnLoad(owner);
            var worker=owner.AddComponent<NativeFullFrameWorker>();worker.Begin(width,height,timeoutSeconds);
            try
            {
                while(!worker.done)yield return null;
                var texture=worker.texture;worker.texture=null;completed(texture,worker.report,worker.failure);
            }
            finally{UnityEngine.Object.Destroy(owner);}
        }
    }

    public sealed class NativeFullFrameWorker:MonoBehaviour
    {
        public bool done;public Texture2D texture;public NativeFullFrameReport report;public Exception failure;
        double deadline;int guiRepaints,lastGuiFrame=-1,postRender,srpEnd,beforeRender;
        void OnEnable(){Camera.onPostRender+=PostRender;RenderPipelineManager.endFrameRendering+=EndFrame;Application.onBeforeRender+=BeforeRender;}
        void OnDestroy(){Camera.onPostRender-=PostRender;RenderPipelineManager.endFrameRendering-=EndFrame;Application.onBeforeRender-=BeforeRender;if(texture)Destroy(texture);}
        void PostRender(Camera camera){postRender++;}
        void EndFrame(ScriptableRenderContext context,Camera[] cameras){srpEnd++;}
        void BeforeRender(){beforeRender++;}
        // Only observes Unity's own GUI event. No GUI draw, business callback,
        // input injection, Camera.Render, camera/canvas or game-state mutation.
        void OnGUI(){if(Event.current!=null&&Event.current.type==EventType.Repaint&&lastGuiFrame!=Time.frameCount){lastGuiFrame=Time.frameCount;guiRepaints++;}}
        public void Begin(int width,int height,float timeout)
        {
            report=new NativeFullFrameReport{process_id=System.Diagnostics.Process.GetCurrentProcess().Id,width=width,height=height,
                request_id=Guid.NewGuid().ToString("N"),start_frame=Time.frameCount,batchmode=Application.isBatchMode,editor=Application.isEditor,
                rendered_frame_start=Time.renderedFrameCount,
                observer_render_configuration_untouched=true,graphics_device=SystemInfo.graphicsDeviceType.ToString(),
                pipeline=GraphicsSettings.currentRenderPipeline?GraphicsSettings.currentRenderPipeline.GetType().FullName:"Built-in"};
            deadline=Time.realtimeSinceStartupAsDouble+Math.Max(1,timeout);
            if(Application.isEditor||Application.isBatchMode){Fail("standalone_interactive_player_required");return;}
            if(width<1||height<1||width>8192||height>8192){Fail("unsupported_output_dimensions");return;}
            StartCoroutine(AtEndOfFrame());
        }
        void Update(){if(!done&&report!=null&&Time.realtimeSinceStartupAsDouble>=deadline)Fail("no_qualified_native_frame_before_deadline");}
        void FillCounters()
        {
            report.imgui_repaint_count=guiRepaints;report.last_imgui_repaint_frame=lastGuiFrame;
            report.native_camera_post_render_count=postRender;report.srp_end_frame_count=srpEnd;report.application_before_render_count=beforeRender;
        }
        void Fail(string reason,Exception error=null)
        {
            if(done)return;FillCounters();report.valid=false;report.status="observer_unresolved";report.reason=reason;
            failure=error??new NativeFullFrameUnavailableException(reason);report.error=failure.ToString();done=true;
        }
        IEnumerator AtEndOfFrame()
        {
            while(!done)
            {
                yield return new WaitForEndOfFrame();if(done)yield break;
                report.end_of_frame_count++;FillCounters();
                if(!UnityEngine.Rendering.SplashScreen.isFinished||report.end_of_frame_count<3||guiRepaints<3||lastGuiFrame!=Time.frameCount||Time.renderedFrameCount-report.rendered_frame_start<3)continue;
                report.window=OwnedPlayerWindow.Observe(report.width,report.height);
                if(!report.window.valid||Screen.width!=report.width||Screen.height!=report.height)continue;
                try
                {
                    // Engine-owned complete screen readback after every camera
                    // and GUI. This is not a camera render or a desktop crop.
                    texture=ScreenCapture.CaptureScreenshotAsTexture(1);
                    if(!texture||texture.width!=report.width||texture.height!=report.height){Fail("native_frame_dimensions_mismatch");yield break;}
                    report.capture_frame=Time.frameCount;report.rendered_frame_capture=Time.renderedFrameCount;report.screen_capture_at_end_of_frame=true;
                    report.nonblack_rgb_pixels=texture.GetPixels32().Count(p=>p.r!=0||p.g!=0||p.b!=0);
                    if(report.nonblack_rgb_pixels==0){Fail("native_all_black_requires_host_diagnosis");yield break;}
                    report.valid=true;report.status="captured";done=true;
                }
                catch(Exception error){Fail("native_screen_readback_failed",error);}
            }
        }
    }
}
