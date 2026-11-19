using System;
using System.IO;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Session;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace GameCreate.OpenEvaluation
{
    // Read-only engine observations plus the exact published session service.
    // After begin, only normal device events may change gameplay. No reflection
    // into candidate classes, no gameplay callback invocation or source patches.
    public sealed class Host : MonoBehaviour
    {
        [Serializable] public class Request
        {
            public int id, seed;
            public string action, entry, actor, label, key, capture, watch;
            public SessionSave save;
            public float x, y, dx, dy, seconds = .12f;
        }
        [Serializable] public class UiFact
        {
            public string text, name, type, shader; public bool shaderValid;
            public Vector3 position;
            public Rect rect;
            public Color color;
            public bool active;
        }
        [Serializable] public class GraphicFact
        {
            public string type, sprite;
            public Color color;
            public Vector3 position, euler;
            public Rect rect;
        }
        [Serializable] public class ActorFact
        {
            public string id, error;
            public int instanceId;
            public bool active, onScreen;
            public Vector3 position, velocity, screen;
            public Rect rect;
            public UiFact[] labels;
            public GraphicFact[] graphics;
            public int renderers, colliders, sprites; public string[] rendererAssets;
            public Bounds bounds;
            public Vector3 euler, scale;
            public string visualSignature;
            public int particles;
            public SurfaceFact[] surfaces;
        }
        [Serializable] public class SurfaceFact { public Vector3 center, size; public string mesh; }
        [Serializable] public class MotionFact { public int frame; public float time; public Vector3 position,euler,scale;public Bounds bounds;public string signature;public NamedNumber[] values; }
        [Serializable] public class Reply
        {
            public int id, processId, frame, inputEvents;
            public string status, error, serviceError, phase, screenshot;
            public bool writesClosed, inputDelivered;
            public float time, width, height;
            public string[] entries;
            public SessionSave save;
            public EntryDescription description;
            public UiFact[] ui;
            public ActorFact[] actors;
            public float audioPeak,audioRms,dspTime;
            public int audioBlocks,listeners,eventSystems,canvases,buttons,sceneObjects;
            public MotionFact[] motion;
        }
        string root;
        int last;
        bool busy, actions;
        Keyboard keyboard;
        Mouse mouse;
        IGameSession service;
        readonly List<InputDevice> disabled = new List<InputDevice>();
        int inputEvents;
        readonly float[] audioBuffer=new float[512];
        float audioPeak,audioSquares;int audioSamples,audioBlocks;
        string watch; readonly List<MotionFact> motion=new List<MotionFact>();
        void LateUpdate()
        {
            AudioListener.GetOutputData(audioBuffer,0);
            for(int i=0;i<audioBuffer.Length;i++){float v=audioBuffer[i];audioPeak=Mathf.Max(audioPeak,Mathf.Abs(v));audioSquares+=v*v;}
            audioSamples+=audioBuffer.Length;audioBlocks++;
            if(!string.IsNullOrEmpty(watch)&&motion.Count<1200)
            {
                try {var svc=FindService();var g=svc.ResolveActor(watch);if(g){var rs=g.GetComponentsInChildren<Renderer>().Where(x=>x.enabled&&x.gameObject.activeInHierarchy).ToArray();var b=rs.Length>0?rs[0].bounds:new Bounds(g.transform.position,Vector3.zero);foreach(var rr in rs.Skip(1))b.Encapsulate(rr.bounds);motion.Add(new MotionFact{frame=Time.frameCount,time=Time.realtimeSinceStartup,position=g.transform.position,euler=g.transform.eulerAngles,scale=g.transform.lossyScale,bounds=b,signature=Signature(rs),values=svc.Capture().values.ToArray()});}}catch{}
            }
        }
        static string Signature(Renderer[] renderers)
        {return string.Join("|",renderers.SelectMany(r=>r.sharedMaterials.Select(m=>m==null?"null":m.name+(m.HasProperty("_Color")?m.color.ToString("F3"):""))));}
        static string Arg(string name)
        {
            var args = Environment.GetCommandLineArgs();
            for (int i=0;i+1<args.Length;i++) if(args[i]==name) return args[i+1];
            return null;
        }
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Install()
        {
            var path=Arg("--session-eval-root");
            if (string.IsNullOrEmpty(path)) return;
            if (Arg("--session-eval-clear")=="yes") { PlayerPrefs.DeleteAll(); PlayerPrefs.Save(); }
            var go=new GameObject("__GameCreateReadOnlyObservationHost");
            DontDestroyOnLoad(go);
            var h=go.AddComponent<Host>(); h.root=path;
            Directory.CreateDirectory(path);
            Application.runInBackground=true;QualitySettings.vSyncCount=0;Application.targetFrameRate=60;
            InputSystem.settings.backgroundBehavior=InputSettings.BackgroundBehavior.IgnoreFocus;
            foreach(var d in InputSystem.devices.Where(d=>d.enabled&&(d is Mouse || d is Keyboard)).ToArray())
            { h.disabled.Add(d); InputSystem.DisableDevice(d); }
            h.keyboard=InputSystem.AddDevice<Keyboard>();
            h.mouse=InputSystem.AddDevice<Mouse>();
            h.keyboard.MakeCurrent();h.mouse.MakeCurrent();
            InputSystem.onEvent+=(e,d)=> { if(d==h.keyboard||d==h.mouse)h.inputEvents++; };
        }
        void Update()
        {
            if (busy||root==null) return;
            string p=Path.Combine(root,"request-"+(last+1)+".json");
            if (!File.Exists(p)) return;
            Request r;
            try { r=JsonUtility.FromJson<Request>(File.ReadAllText(p)); }
            catch { return; } // Client uses atomic replace; a partial write is not a product result.
            if(r==null||r.id<=last) return;
            last=r.id;busy=true;audioPeak=audioSquares=0;audioSamples=audioBlocks=0;watch=r.watch;motion.Clear();StartCoroutine(Guard(Execute(r),r));
        }
        IEnumerator Guard(IEnumerator routine, Request r)
        {
            var stack=new Stack<IEnumerator>();stack.Push(routine);
            Exception error=null;
            while(stack.Count>0)
            {
                object current=null;bool moved=false;
                try { moved=stack.Peek().MoveNext();if(moved)current=stack.Peek().Current; }
                catch(Exception ex) { error=ex;break; }
                if(!moved) { stack.Pop();continue; }
                if(current is IEnumerator child) stack.Push(child); else yield return current;
            }
            Reply reply;
            try { reply=Observe(r.id); }
            catch(Exception ex) { reply=new Reply{id=r.id,status="HOST_ERROR",error=ex.ToString()}; }
            if(error!=null) { reply.status=error is ProductFault?"PRODUCT_ERROR":"HOST_ERROR";reply.error=error.ToString(); }
            if(r.action=="key"||r.action=="click"||r.action=="drag") reply.inputDelivered=delivered;
            if(r.capture!=null) reply.screenshot=Path.Combine(root,Path.GetFileName(r.capture));
            var dest=Path.Combine(root,"reply-"+r.id+".json");
            File.WriteAllText(dest+".tmp",JsonUtility.ToJson(reply,true));
            File.Copy(dest+".tmp",dest,true);File.Delete(dest+".tmp");
            busy=false;
        }
        sealed class ProductFault : Exception { public ProductFault(string m):base(m){} }
        void Need(bool okay,string message) { if(!okay)throw new ProductFault(message); }
        SessionOperation ProductCall(Func<SessionOperation> body){try{return body();}catch(Exception ex){throw new ProductFault("Public service threw: "+ex);}}
        IGameSession FindService()
        {
            var all=FindObjectsByType<MonoBehaviour>(FindObjectsSortMode.None)
                .Where(x=>x.isActiveAndEnabled).OfType<IGameSession>().ToArray();
            Need(all.Length==1,"Required service count: "+all.Length);
            Need(all[0].ContractVersion=="game-session/v1","Incorrect contract version");
            return all[0];
        }
        IEnumerator Complete(SessionOperation op)
        {
            Need(op!=null,"Public call returned null operation");
            var until=Time.realtimeSinceStartup+10;
            while(op.state==OperationState.Pending&&Time.realtimeSinceStartup<until)yield return null;
            Need(op.state==OperationState.Completed,"Valid public call failed: "+op.state+" "+op.code+" "+op.message);
            yield return null;yield return null;
        }
        bool delivered;
        IEnumerator Execute(Request r)
        {
            delivered=false;
            if(r.action=="set-fps"){QualitySettings.vSyncCount=0;Application.targetFrameRate=r.seed;yield return null;}
            if(r.action=="audio-probe")
            {
                // Calibrate the observation channel independently of game audio.
                // Temporary observation-owned objects are removed before scoring.
                float oldVolume=AudioListener.volume;bool oldPause=AudioListener.pause;
                AudioListener.volume=1;AudioListener.pause=false;
                var probe=new GameObject("__AudioObservationCalibration");
                if(!FindObjectsByType<AudioListener>(FindObjectsSortMode.None).Any(x=>x.isActiveAndEnabled))probe.AddComponent<AudioListener>();
                var source=probe.AddComponent<AudioSource>();source.spatialBlend=0;source.volume=.3f;
                float[] values=new float[22050];for(int i=0;i<values.Length;i++)values[i]=.15f*Mathf.Sin(i*.13f);
                var clip=AudioClip.Create("ObserverCalibration",values.Length,1,44100,false);clip.SetData(values,0);source.clip=clip;source.Play();
                yield return new WaitForSecondsRealtime(.35f);
                source.Stop();Destroy(probe);Destroy(clip);
                AudioListener.volume=oldVolume;AudioListener.pause=oldPause;yield return null;
            }
            if(r.action=="quit") { PlayerPrefs.Save();Application.Quit(0);yield break; }
            if(r.action=="reset")
            {
                Time.timeScale=1;actions=false;service=null;
                InputSystem.QueueStateEvent(keyboard,new KeyboardState());
                InputSystem.QueueStateEvent(mouse,new MouseState());
                yield return SceneManager.LoadSceneAsync("Assets/Game/Scenes/Game.unity");
                for(int i=0;i<5;i++)yield return null;
            }
            if(r.action=="open"||r.action=="restore"||r.action=="invalid")
            {
                if(actions)throw new InvalidOperationException("Evaluator write after scored actions");
                service=FindService();
                if(r.action=="open")yield return Complete(ProductCall(()=>service.OpenEntry(r.entry,r.seed)));
                if(r.action=="restore")yield return Complete(ProductCall(()=>service.Restore(r.save)));
                if(r.action=="invalid")
                {
                    var before=JsonUtility.ToJson(service.Capture());
                    var invalid=SessionFormat.Clone(service.Capture());invalid.contract="invalid-schema";
                    var op=service.Restore(invalid);
                    Need(op!=null&&op.state==OperationState.Rejected,"Invalid save was not atomically rejected");
                    Need(before==JsonUtility.ToJson(service.Capture()),"Rejected restore partially mutated state");
                    op=service.OpenEntry("invalid-unknown-entry",0);
                    Need(op!=null&&op.state==OperationState.Rejected,"Unknown entry not immediately rejected");
                    Need(before==JsonUtility.ToJson(service.Capture()),"Rejected entry partially mutated state");
                }
            }
            if(r.action=="detach")
            {
                service=FindService();var one=service.Capture();var before=JsonUtility.ToJson(one);
                var two=service.Capture();
                Need(!ReferenceEquals(one,two)&&!ReferenceEquals(one.actors,two.actors),"Capture aliases mutable state");
                one.phase="invalid-mutated-copy";
                if(one.values.Count>0)one.values[0].value+=100;
                if(one.actors.Count>0) { one.actors[0].position+=Vector3.one;one.actors[0].state="invalid-mutated-copy"; }
                Need(before==JsonUtility.ToJson(service.Capture()),"Snapshot mutations changed live game");
            }
            if(r.action=="begin")
            {
                if(actions)throw new InvalidOperationException("Preparation already sealed");
                service=FindService();try{service.ResumeSimulation();}catch(Exception ex){throw new ProductFault("ResumeSimulation threw: "+ex);}actions=true;yield return null;
            }
            if(r.action=="release"){InputSystem.QueueStateEvent(keyboard,new KeyboardState());yield return null;yield return null;}
            if(r.action=="key")
            {
                var keys=r.key.Split(',').Select(x=>{if(!Enum.TryParse<Key>(x,true,out var k))throw new InvalidOperationException("Unknown evaluator key");return k;}).ToArray();
                keyboard.MakeCurrent();int old=inputEvents;
                InputSystem.QueueStateEvent(keyboard,new KeyboardState(keys));
                for(int i=0;i<3;i++)yield return null;
                delivered=keys.All(k=>keyboard[k].isPressed)&&inputEvents>old;
                if(r.seconds>0)yield return new WaitForSecondsRealtime(Mathf.Clamp(r.seconds,0,5));
                if(r.label!="hold"){InputSystem.QueueStateEvent(keyboard,new KeyboardState());for(int i=0;i<3;i++)yield return null;}
                if(!delivered)throw new InvalidOperationException("Engine keyboard event not delivered");
            }
            if(r.action=="click")
            {
                var target=Target(r);
                Need(target!=null,"No visible control/cell: "+r.actor+" / "+r.label);
                var rt=target.GetComponent<RectTransform>();
                var point=rt!=null?RectTransformUtility.WorldToScreenPoint(UiCamera(rt),rt.TransformPoint(rt.rect.center)):(Vector2)Camera.main.WorldToScreenPoint(target.transform.position);
                Need(point.x>=0&&point.x<Screen.width&&point.y>=0&&point.y<Screen.height,"Target outside viewport");
                Need(EventSystem.current!=null,"No active EventSystem");
                var ped=new PointerEventData(EventSystem.current){position=point};
                var hits=new List<RaycastResult>();EventSystem.current.RaycastAll(ped,hits);
                Need(rt==null?hits.Count==0:(hits.Count>0&&(hits[0].gameObject==target||hits[0].gameObject.transform.IsChildOf(target.transform))),
                    "Actual UI raycast does not hit target: "+r.actor+" / "+r.label);
                yield return MouseFrame(point,false);
                var old=inputEvents;
                yield return MouseFrame(point,true);yield return null;yield return null;
                delivered=mouse.leftButton.isPressed&&inputEvents>old;
                yield return MouseFrame(point,false);yield return null;yield return null;
                if(!delivered)throw new InvalidOperationException("Engine mouse event not delivered");
            }
            if(r.action=="drag")
            {
                Need(Camera.main!=null,"No gameplay camera");
                service=FindService();var ball=service.ResolveActor("ball");Need(ball!=null,"Missing real ball");
                Vector2 start=Camera.main.WorldToScreenPoint(ball.transform.position);
                Vector2 end=start+new Vector2(r.dx,r.dy);
                int old=inputEvents;
                yield return MouseFrame(start,false);yield return MouseFrame(start,true);
                for(int i=1;i<=12;i++)yield return MouseFrame(Vector2.Lerp(start,end,i/12f),true);
                delivered=mouse.leftButton.isPressed&&inputEvents>old;
                yield return MouseFrame(end,false);yield return null;
                if(!delivered)throw new InvalidOperationException("Engine drag events not delivered");
            }
            if(r.action!="key"&&r.seconds>0)yield return new WaitForSecondsRealtime(Mathf.Clamp(r.seconds,0,5));
            if(!string.IsNullOrEmpty(r.capture))
            {
                // Standalone player: genuine composited frame, including overlay UI.
                yield return new WaitForEndOfFrame();
                var texture=ScreenCapture.CaptureScreenshotAsTexture();
                Need(texture!=null,"Screen capture returned no texture");
                File.WriteAllBytes(Path.Combine(root,Path.GetFileName(r.capture)),texture.EncodeToPNG());
                Destroy(texture);
            }
        }
        IEnumerator MouseFrame(Vector2 point,bool down)
        {
            mouse.MakeCurrent();
            InputSystem.QueueStateEvent(mouse,new MouseState{position=point}.WithButton(MouseButton.Left,down));
            yield return null;
        }
        GameObject Target(Request r)
        {
            if(!string.IsNullOrEmpty(r.actor))return FindService().ResolveActor(r.actor);
            // Natural UI remains testable independently of the session service.
            var needles=(r.label??"").Split('|');
            foreach(var b in FindObjectsByType<Button>(FindObjectsSortMode.None).Where(b=>b.isActiveAndEnabled&&b.interactable))
            {
                var text=string.Join(" ",Labels(b.gameObject).Select(x=>x.text)).Trim();
                if(needles.Any(n=>string.Equals(n,text,StringComparison.OrdinalIgnoreCase)))return b.gameObject;
            }
            return null;
        }
        static Camera UiCamera(RectTransform rt)
        {
            var canvas=rt.GetComponentInParent<Canvas>();
            return canvas!=null&&canvas.renderMode!=RenderMode.ScreenSpaceOverlay?canvas.worldCamera:null;
        }
        static Rect RectOf(RectTransform rt)
        {
            var v=new Vector3[4];rt.GetWorldCorners(v);
            var p=v.Select(x=>RectTransformUtility.WorldToScreenPoint(UiCamera(rt),x)).ToArray();
            return Rect.MinMaxRect(p.Min(x=>x.x),p.Min(x=>x.y),p.Max(x=>x.x),p.Max(x=>x.y));
        }
        static UiFact[] Labels(GameObject go)
        {
            var facts=new List<UiFact>();
            foreach(var c in go.GetComponentsInChildren<Component>(false))
            {
                if(c==null)continue;
                // Public text rendering APIs only: supports uGUI Text and TMP.
                if(!(c is Text)&&c.GetType().FullName!="TMPro.TextMeshProUGUI")continue;
                var prop=c.GetType().GetProperty("text");
                var graphic=c as Graphic;var rt=c.GetComponent<RectTransform>();
                if(prop==null||rt==null||graphic==null)continue;
                facts.Add(new UiFact{type=c.GetType().Name,name=c.name,text=prop.GetValue(c) as string,
                    active=graphic.isActiveAndEnabled,position=c.transform.position,rect=RectOf(rt),color=graphic.color,shader=graphic.materialForRendering!=null&&graphic.materialForRendering.shader!=null?graphic.materialForRendering.shader.name:"",shaderValid=graphic.materialForRendering!=null&&graphic.materialForRendering.shader!=null&&graphic.materialForRendering.shader.isSupported&&!graphic.materialForRendering.shader.name.Contains("InternalError")});
            }
            return facts.ToArray();
        }
        Reply Observe(int id)
        {
            var reply=new Reply{id=id,status="OK",processId=System.Diagnostics.Process.GetCurrentProcess().Id,
                frame=Time.frameCount,time=Time.realtimeSinceStartup,width=Screen.width,height=Screen.height,
                inputEvents=inputEvents,writesClosed=actions,audioPeak=audioPeak,audioRms=audioSamples>0?Mathf.Sqrt(audioSquares/audioSamples):0,audioBlocks=audioBlocks,dspTime=(float)AudioSettings.dspTime,
                listeners=FindObjectsByType<AudioListener>(FindObjectsSortMode.None).Count(x=>x.isActiveAndEnabled),
                eventSystems=FindObjectsByType<EventSystem>(FindObjectsSortMode.None).Count(x=>x.isActiveAndEnabled),
                canvases=FindObjectsByType<Canvas>(FindObjectsSortMode.None).Count(x=>x.isActiveAndEnabled&&x.isRootCanvas),
                buttons=FindObjectsByType<Button>(FindObjectsSortMode.None).Count(x=>x.isActiveAndEnabled),
                sceneObjects=FindObjectsByType<Transform>(FindObjectsSortMode.None).Length,motion=motion.ToArray()};
            reply.ui=FindObjectsByType<Canvas>(FindObjectsSortMode.None).Where(x=>x.isActiveAndEnabled&&x.isRootCanvas)
                .SelectMany(x=>Labels(x.gameObject)).ToArray();
            try
            {
                service=FindService();reply.entries=service.EntryIds.ToArray();reply.save=service.Capture();
                reply.description=service.DescribeCurrentEntry();
                var facts=new List<ActorFact>();
                foreach(var actor in reply.save.actors.Where(x=>x.present))
                {
                    var fact=new ActorFact{id=actor.id};
                    try
                    {
                        var go=service.ResolveActor(actor.id);
                        if(go==null) { fact.error="Reported present actor resolves null";facts.Add(fact);continue; }
                        fact.active=go.activeInHierarchy;fact.instanceId=go.GetInstanceID();fact.position=go.transform.position;fact.euler=go.transform.eulerAngles;fact.scale=go.transform.lossyScale;
                        var rt=go.GetComponent<RectTransform>();
                        if(rt!=null) {fact.rect=RectOf(rt);fact.screen=RectTransformUtility.WorldToScreenPoint(UiCamera(rt),rt.TransformPoint(rt.rect.center));}
                        else if(Camera.main!=null)fact.screen=Camera.main.WorldToScreenPoint(go.transform.position);
                        fact.onScreen=fact.screen.x>=0&&fact.screen.x<Screen.width&&fact.screen.y>=0&&fact.screen.y<Screen.height;
                        fact.labels=Labels(go);
                        fact.graphics=go.GetComponentsInChildren<Graphic>(false).Where(x=>x.isActiveAndEnabled).Select(g=>new GraphicFact{
                            type=g.GetType().Name,color=g.color,rect=RectOf(g.rectTransform),position=g.transform.position,
                            euler=g.transform.eulerAngles,sprite=g is Image image&&image.sprite!=null?image.sprite.name:null}).ToArray();
                        var renderers=go.GetComponentsInChildren<Renderer>().Where(x=>x.enabled&&x.gameObject.activeInHierarchy).ToArray();
                        fact.renderers=renderers.Length;fact.sprites=renderers.OfType<SpriteRenderer>().Count(x=>x.sprite!=null);fact.rendererAssets=renderers.Select(x=>x is SpriteRenderer sr&&sr.sprite!=null?sr.sprite.name:x.sharedMaterial!=null?x.sharedMaterial.name:"").ToArray();fact.colliders=go.GetComponentsInChildren<Collider>().Count(x=>x.enabled);
                         fact.visualSignature=Signature(renderers);
                         fact.particles=go.GetComponentsInChildren<ParticleSystem>().Sum(x=>x.particleCount);
                         fact.surfaces=renderers.Select(x=>new SurfaceFact{center=x.bounds.center,size=x.bounds.size,mesh=x.GetComponent<MeshFilter>()!=null&&x.GetComponent<MeshFilter>().sharedMesh!=null?x.GetComponent<MeshFilter>().sharedMesh.name:x is SpriteRenderer sp&&sp.sprite!=null?sp.sprite.name:""}).ToArray();
                        if(renderers.Length>0){fact.bounds=renderers[0].bounds;foreach(var rr in renderers.Skip(1))fact.bounds.Encapsulate(rr.bounds);}
                        var body=go.GetComponent<Rigidbody>();if(body!=null)fact.velocity=body.linearVelocity;
                    }
                    catch(Exception ex) {fact.error=ex.Message;}
                    facts.Add(fact);
                }
                reply.actors=facts.ToArray();
            }
            catch(Exception ex) {reply.serviceError=ex.ToString();}
            return reply;
        }
    }
}
