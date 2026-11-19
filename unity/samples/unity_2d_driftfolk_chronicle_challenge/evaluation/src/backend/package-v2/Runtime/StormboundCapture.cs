using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using GameCreate.Session;
using GameCreate.Stormbound.Contract;
using GameCreate.Evaluation.Session;
using GameCreate.Evaluation.Rendering;
using UnityEngine;
using UnityEngine.InputSystem;

namespace GameCreate.Stormbound.Evaluator.Capture
{
    [Serializable] public sealed class CaptureInputFact
    {
        public string action;public int queued_frame,completed_frame,keyboard_device_id;
    }
    [Serializable] public sealed class CaptureImageFact
    {
        public string label,path,sha256;public int frame,width,height,nonblack_rgb_pixels;public long bytes;
        public bool all_black;public NativeFullFrameReport render_report;
    }
    [Serializable] public sealed class CaptureReceipt
    {
        public int schema_version=3;
        public bool valid,render_configuration_restored,splash_finished,all_black;
        public bool session_service_verified,input_ready_before_scene,state_verified,entry_transition_observed;
        public string status,classification,error,state="initial_archipelago",method="standalone-owned-window-native-frame-v2";
        public string run_id,screenshot_path,sha256,save_json,observer_status,acquisition_route,state_verification;
        public string company_name,product_name,persistent_data_path;
        public HostIdentityObservation host_identity;
        public string[] host_identity_presentation=Array.Empty<string>();
        public bool requires_author_purity_review=true,host_identity_presentation_is_pixel_verified=false;
        public string committed_public_state_sha256,captured_public_state_sha256,normal_before_observer_error;
        public int process_id,width,height,post_splash_completed_frames,nonblack_rgb_pixels,input_bootstrap_frame,input_keyboard_device_id;
        public long bytes;
        public NativeFullFrameReport render_report;
        public List<CaptureInputFact> input_actions=new List<CaptureInputFact>();
        public List<CaptureImageFact> images=new List<CaptureImageFact>();
    }

    // The normal-input route must install its process-local devices BEFORE any
    // candidate Awake can cache Keyboard.current. No candidate state is touched.
    public static class CaptureInputBootstrap
    {
        public static PlayerInputDriver Driver {get;private set;}
        public static int Frame {get;private set;}
        public static int KeyboardId {get;private set;}
        public static string Error {get;private set;}
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void BeforeScene()
        {
            Driver=null;Error=null;Frame=-1;KeyboardId=0;
            if(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("STORMBOUND_CAPTURE_PNG"))||
               Environment.GetEnvironmentVariable("STORMBOUND_CAPTURE_ROUTE")!="normal_input")return;
            try
            {
                Driver=new PlayerInputDriver();var ready=Driver.Ready();
                // Ready installs devices before its first yielded player frame.
                ready.MoveNext();Frame=Time.frameCount;KeyboardId=Keyboard.current?.deviceId??0;
                if(KeyboardId<=0)throw new InvalidOperationException("No process-local keyboard after early bootstrap.");
            }
            catch(Exception error){Error=error.ToString();}
        }
    }

    public sealed class StormboundCapture:MonoBehaviour
    {
        sealed class ObserverUnresolved:InvalidOperationException{public ObserverUnresolved(string message):base(message){}}
        // Used only by independently compiled author qualification probes. No
        // probe is copied into a real candidate or supplied in public Input.
        public static event Action<CaptureReceipt> Produced;
        CaptureReceipt receipt;
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Init()
        {
            if(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("STORMBOUND_CAPTURE_PNG")))return;
            var root=new GameObject("PrivateStormboundFrameCapture");DontDestroyOnLoad(root);root.AddComponent<StormboundCapture>();
        }
        IEnumerator Start()
        {
            Application.runInBackground=true;
            var route=Environment.GetEnvironmentVariable("STORMBOUND_CAPTURE_ROUTE")??"service_commit";
            receipt=new CaptureReceipt{run_id=Environment.GetEnvironmentVariable("STORMBOUND_RUN_ID"),process_id=Process.GetCurrentProcess().Id,
                screenshot_path=Environment.GetEnvironmentVariable("STORMBOUND_CAPTURE_PNG"),acquisition_route=route,save_json="",
                state_verification=route=="normal_input"?"manual_review_required":"not_observed",
                company_name=Application.companyName,product_name=Application.productName,persistent_data_path=Application.persistentDataPath};
            Exception failure=null;
            yield return Pump(route=="normal_input"?CaptureNatural():CaptureService(),error=>failure=error);
            if(failure!=null)
            {
                receipt.valid=false;receipt.error=failure.ToString();receipt.state_verified=false;
                if(failure is NativeFullFrameUnavailableException native)
                {receipt.status="observer_unresolved";receipt.classification="infrastructure_or_execution_failure";receipt.observer_status=native.reason;}
                else if(failure is ViewportCaptureUnsupportedException unsupported)
                {receipt.status="observer_unsupported";receipt.classification="infrastructure_or_execution_failure";receipt.observer_status=unsupported.reason;}
                else
                {receipt.status=failure is ObserverUnresolved?"capture_observer_unresolved":"failed";
                 receipt.classification=failure is SessionProductFailure?"candidate_state_unavailable":"infrastructure_or_execution_failure";}
            }
            receipt.host_identity=HostIdentityGuard.Observe();
            if(!receipt.host_identity.valid){receipt.valid=false;receipt.status="observer_identity_mismatch";receipt.classification="infrastructure_or_execution_failure";receipt.observer_status="host-identity-mismatch";}
            try{Produced?.Invoke(receipt);}catch(Exception error){receipt.valid=false;receipt.status="qualification_probe_failed";receipt.classification="infrastructure_or_execution_failure";receipt.error=error.ToString();}
            var path=Environment.GetEnvironmentVariable("STORMBOUND_CAPTURE_RECEIPT");Directory.CreateDirectory(Path.GetDirectoryName(path));
            using(var stream=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read))
            using(var writer=new StreamWriter(stream,new System.Text.UTF8Encoding(false)))writer.Write(JsonUtility.ToJson(receipt,true));
            if(CaptureInputBootstrap.Driver!=null)yield return CaptureInputBootstrap.Driver.Dispose();
            Application.Quit(receipt.valid||receipt.classification=="candidate_state_unavailable"?0:3);
        }
        static IEnumerator Pump(IEnumerator body,Action<Exception> failed)
        {
            var stack=new Stack<IEnumerator>();stack.Push(body);
            while(stack.Count>0){bool more=false;object current=null;Exception error=null;
                try{more=stack.Peek().MoveNext();if(more)current=stack.Peek().Current;}catch(Exception caught){error=caught;}
                if(error!=null){failed(error);yield break;}if(!more){stack.Pop();continue;}
                if(current is IEnumerator nested)stack.Push(nested);else yield return current;}
        }
        static string Hash(byte[] bytes){using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
        static string PublicHash(SessionSave save)
        {
            var copy=SessionFormat.Clone(save);copy.opaqueData=null;copy.values=copy.values.OrderBy(v=>v.name,StringComparer.Ordinal).ToList();
            copy.actors=copy.actors.OrderBy(a=>a.id,StringComparer.Ordinal).ToList();foreach(var actor in copy.actors)actor.values=actor.values.OrderBy(v=>v.name,StringComparer.Ordinal).ToList();
            return Hash(System.Text.Encoding.UTF8.GetBytes(JsonUtility.ToJson(copy)));
        }
        IEnumerator DisplayReady()
        {
            var deadline=Time.realtimeSinceStartup+30;
            while(!UnityEngine.Rendering.SplashScreen.isFinished&&Time.realtimeSinceStartup<deadline)yield return null;
            receipt.splash_finished=UnityEngine.Rendering.SplashScreen.isFinished;
            if(!receipt.splash_finished)throw new ObserverUnresolved("Splash readiness timed out; this is not a product zero.");
            // Complete-frame readiness is measured by the native capture worker,
            // not inferred from Update loops or repeated null yields.
        }
        IEnumerator Image(string label,string path,Action<CaptureImageFact> completed)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));if(File.Exists(path))throw new InvalidOperationException("Capture image already exists.");
            Texture2D texture=null;NativeFullFrameReport report=null;Exception failed=null;
            yield return NativeFullFrame.Capture(1280,720,20,(value,observation,error)=>{texture=value;report=observation;failed=error;});
            try
            {
                if(!texture)throw failed??new ObserverUnresolved("Native frame producer returned no texture.");
                var pixels=texture.GetPixels32();var bytes=texture.EncodeToPNG();
                using(var stream=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read))stream.Write(bytes,0,bytes.Length);
                var fact=new CaptureImageFact{label=label,path=path,sha256=Hash(bytes),bytes=bytes.LongLength,width=texture.width,height=texture.height,
                    frame=report.capture_frame,nonblack_rgb_pixels=pixels.Count(p=>p.r!=0||p.g!=0||p.b!=0),render_report=report};
                fact.all_black=fact.nonblack_rgb_pixels==0;receipt.images.Add(fact);
                if(fact.all_black){receipt.all_black=true;receipt.observer_status="all_black_frame_requires_diagnosis";throw new ObserverUnresolved("All-black image retained; root cause requires diagnosis, not automatic product zero.");}
                if(failed!=null)throw failed;
                if(!report.valid||!report.observer_render_configuration_untouched)throw new ObserverUnresolved("Native observer could not prove a complete unmodified engine frame.");
                receipt.post_splash_completed_frames=report.end_of_frame_count;completed(fact);
            }
            finally{receipt.render_report=report;if(texture)UnityEngine.Object.Destroy(texture);}
        }
        void Complete(CaptureImageFact image)
        {
            receipt.sha256=image.sha256;receipt.bytes=image.bytes;receipt.width=image.width;receipt.height=image.height;
            receipt.all_black=image.all_black;receipt.nonblack_rgb_pixels=image.nonblack_rgb_pixels;receipt.render_report=image.render_report;
            // No render configuration was written, so no restoration operation
            // is required. Kept for the common controller's ownership invariant.
            receipt.render_configuration_restored=image.render_report.observer_render_configuration_untouched;
            receipt.host_identity=HostIdentityGuard.Observe();receipt.host_identity_presentation=HostIdentityGuard.PresentationContamination();
            if(!receipt.host_identity.valid)throw new ObserverUnresolved("Actual company/product/persistence differs from the capture-only identity.");
            // Text objects are only hints: clipping may make them invisible,
            // and standalone IMGUI has no public retained text-object tree.
            // ALL native frames require the same immutable author pixel-purity
            // review before D6, including frames from a verified service.
            receipt.valid=true;receipt.status="captured";receipt.classification="observed";receipt.observer_status="frame_acquired";
        }
        IEnumerator CaptureService()
        {
            if(receipt.acquisition_route!="service_commit")throw new ObserverUnresolved("Unknown frozen acquisition route.");
            yield return null;yield return null;
            var game=SessionDriver.Find();var driver=new SessionDriver(game,StormboundStateRules.Model,true,StormboundStateRules.Validate,actor=>false,landmark=>false);
            yield return driver.Open("archipelago",20260823);var initial=driver.Observe();
            if(initial.phase!="playing")throw new SessionProductFailure("entry:archipelago","Fresh playing archipelago is unavailable.");
            receipt.committed_public_state_sha256=PublicHash(initial);receipt.save_json=JsonUtility.ToJson(initial);
            yield return DisplayReady();var before=driver.Observe();
            if(PublicHash(before)!=receipt.committed_public_state_sha256)throw new SessionProductFailure("entry:archipelago","Committed state advanced before ResumeSimulation.");
            CaptureImageFact image=null;yield return Image("service-committed-initial-world",receipt.screenshot_path,value=>image=value);
            var after=driver.Observe();receipt.captured_public_state_sha256=PublicHash(after);
            if(receipt.captured_public_state_sha256!=receipt.committed_public_state_sha256)throw new ObserverUnresolved("Public state changed across normal engine whole-frame observation; diagnose observer versus GUI/render callback effects before scoring.");
            receipt.save_json=JsonUtility.ToJson(after);receipt.session_service_verified=true;receipt.state_verified=true;receipt.state_verification="complete_public_commit_roundtrip";Complete(image);
        }
        IEnumerator Key(PlayerInputDriver input,UnityEngine.InputSystem.Key key)
        {
            var fact=new CaptureInputFact{action="normal-key:"+key,queued_frame=Time.frameCount,keyboard_device_id=Keyboard.current?.deviceId??0};
            receipt.input_actions.Add(fact);yield return input.Press(key);fact.completed_frame=Time.frameCount;
        }
        IEnumerator CaptureNatural()
        {
            receipt.input_ready_before_scene=CaptureInputBootstrap.Driver!=null&&CaptureInputBootstrap.KeyboardId>0&&CaptureInputBootstrap.Error==null;
            receipt.input_bootstrap_frame=CaptureInputBootstrap.Frame;receipt.input_keyboard_device_id=CaptureInputBootstrap.KeyboardId;
            if(!receipt.input_ready_before_scene)throw new ObserverUnresolved("Before-Awake input bootstrap failed: "+CaptureInputBootstrap.Error);
            yield return DisplayReady();var input=CaptureInputBootstrap.Driver;
            CaptureImageFact before=null;Exception beforeFailure=null;
            yield return Pump(Image("before-normal-entry",Path.Combine(Path.GetDirectoryName(receipt.screenshot_path),"00_before_normal_entry.png"),value=>before=value),error=>beforeFailure=error);
            if(beforeFailure!=null)
            {
                // An unsupported/blank lobby observer must not prevent trying
                // independent normal gameplay. Continue only after the renderer
                // proves it restored every configuration it touched.
                receipt.normal_before_observer_error=beforeFailure.ToString();
                if(receipt.render_report==null||!receipt.render_report.observer_render_configuration_untouched)throw beforeFailure;
            }
            yield return Key(input,UnityEngine.InputSystem.Key.Enter);yield return null;yield return null;
            yield return Key(input,UnityEngine.InputSystem.Key.R);yield return null;yield return null;
            CaptureImageFact after=null;yield return Image("after-normal-enter-and-restart",receipt.screenshot_path,value=>after=value);
            receipt.entry_transition_observed=before!=null&&before.sha256!=after.sha256;
            // A changed picture alone does not prove gameplay rather than menu.
            // No service call, fake save, timeScale write or candidate logic call
            // is used on this route. Uniform author image review remains required.
            receipt.session_service_verified=false;receipt.state_verified=false;receipt.save_json="";
            receipt.state_verification="manual_review_required";Complete(after);
        }
    }
}
