using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using GameCreate.Session;
using GameCreate.Kitchen;
using GameCreate.Evaluation.Session;
using NUnit.Framework;
using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.InputSystem;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Process = System.Diagnostics.Process;
using Object = UnityEngine.Object;

namespace GameCreate.Undercooked.Evaluator
{
    [Serializable] public sealed class KitchenCheck
    {
        public string id, dimension, status, expected, observed, attribution, acquisition_status, acquisition_route, trajectory, product_block_reason, blocker_kind, failed_capability;
        public bool precondition_reached, oracle_valid;
        public int process_id, frame, setup_writes_after_action;
        public float weight;
        public string[] requirements = Array.Empty<string>();
    }
    [Serializable] public sealed class KitchenEvidence
    {
        public int schema_version=4;
        public string phase, session_id;
        public int process_id;
        public List<KitchenCheck> checks=new List<KitchenCheck>();
    }
    [Serializable] public sealed class WorldActor
    {
        public string id, presentation;
        public int instance_id, renderers;
        public Vector3 position;
    }
    [Serializable] public sealed class FrameFact
    {
        public int frame;
        public float realtime;
        public string label, save_json, visible_text;
        public List<WorldActor> actors=new List<WorldActor>();
    }
    [Serializable] public sealed class ScenarioFacts
    {
        public string test_id, phase;
        public int process_id;
        public string exception;
        public List<string> actions=new List<string>();
        public List<FrameFact> frames=new List<FrameFact>();
        public List<SessionReceipt> service_receipts=new List<SessionReceipt>();
        public List<RuntimeLogFact> runtime_logs=new List<RuntimeLogFact>();
        public int runtime_log_summary_overflow;
        public bool evaluator_logged_error;
    }
    public sealed class NavigationFailure : Exception {public NavigationFailure(string message):base(message){}}

    public sealed class KitchenEvidenceStore
    {
        readonly string path, phase; readonly KitchenEvidence doc;
        public KitchenEvidenceStore(string phase){this.phase=phase;path=Environment.GetEnvironmentVariable("KITCHEN_EVIDENCE_FILE");if(string.IsNullOrWhiteSpace(path))throw new InvalidOperationException("KITCHEN_EVIDENCE_FILE is required");doc=new KitchenEvidence{phase=phase,process_id=Process.GetCurrentProcess().Id,session_id=Environment.GetEnvironmentVariable("KITCHEN_RUN_ID")};}
        public void Add(string id,string dim,float weight,bool pass,string expected,string observed){doc.checks.Add(new KitchenCheck{id=id,dimension=dim,weight=weight,status=pass?"PASS":"FAIL_OBSERVED",expected=expected,observed=observed,attribution="observed",acquisition_status="READY",acquisition_route="static_engine_observation",precondition_reached=true,oracle_valid=true,process_id=doc.process_id,frame=Time.frameCount,trajectory=TestContext.CurrentContext.Test.FullName});}
        public void Block(string id,string dim,float weight,string reason){doc.checks.Add(new KitchenCheck{id=id,dimension=dim,weight=weight,status="BLOCKED_BY_PRODUCT",expected="public capability available",observed=reason,attribution="published_service_not_delivered",acquisition_status="PRODUCT_BLOCKED",acquisition_route="public_session",precondition_reached=false,oracle_valid=true,process_id=doc.process_id,frame=Time.frameCount,product_block_reason=reason,blocker_kind="public_session_contract"});}
        public void Write(string sessionId=null){doc.session_id=sessionId??doc.session_id;var dir=Path.GetDirectoryName(path);Directory.CreateDirectory(dir);File.WriteAllText(path,JsonUtility.ToJson(doc,true));}
    }
    public sealed class KitchenRun
    {
        public const string ScenePath="Assets/UndercookedChallenge/Scenes/UndercookedKitchen.unity";
        public readonly ScenarioFacts Facts;
        public readonly List<KitchenCheck> Checks=new List<KitchenCheck>();
        public readonly PlayerInputDriver Input=new PlayerInputDriver();
        public IGameSession Game;
        public SessionDriver Driver;
        public SessionSave Initial;
        public EntryDescription Layout;
        public string Name=>Facts.test_id;
        readonly string phase;
        readonly Func<Scene,bool> candidateScene;
        bool inputReady;
        public KitchenRun(string phase):this(phase,null){}
        internal KitchenRun(string phase,Func<Scene,bool> candidateScene) {this.phase=phase;this.candidateScene=candidateScene??(s=>s.path==ScenePath); Facts=new ScenarioFacts{phase=phase,test_id=TestContext.CurrentContext.Test.Name,process_id=Process.GetCurrentProcess().Id};}
        public static float Weight(string id){var value=id.StartsWith("D2")?2.5f:id.StartsWith("D4")?4f:2f;var def=Resources.Load<TextAsset>("kitchen-private-rules");if(!def)throw new InvalidOperationException("Frozen private rules resource missing");var parsed=JsonUtility.FromJson<FlatRules>(def.text);var match=parsed.checks.SingleOrDefault(c=>c.id==id);if(match==null||Math.Abs(match.weight-value)>.00001f)throw new InvalidOperationException("Frozen rule weight mismatched checked map: "+id);return value;}
        [Serializable] sealed class FlatRules{public FlatCheck[] checks;}
        [Serializable] sealed class FlatCheck{public string id;public float weight;}
        public static string NormalizeCapability(string capability)
        {
            if(capability.StartsWith("entry:")||capability=="entry-catalogue"||capability=="session-interface")return "chapter_entry";
            if(capability.StartsWith("restore:")||capability=="invalid-restore")return "state_restore";
            if(capability.StartsWith("actor:")||capability.StartsWith("layout:")||capability=="capture"||capability=="objects")return "object_query";
            if(capability=="resume-simulation")return "player_input";
            return capability;
        }
        public void Check(string id,bool passed,string expected,string observed)
        {
            if(Checks.Any(x=>x.id==id))throw new InvalidOperationException("Duplicate leaf: "+id);
            Checks.Add(new KitchenCheck{id=id,dimension=id.Substring(0,2),weight=Weight(id),status=passed?"PASS":"FAIL_OBSERVED",expected=expected,observed=observed,
                attribution="observed",acquisition_status="READY",acquisition_route="independent_public_session_and_normal_input",precondition_reached=true,oracle_valid=true,
                process_id=Facts.process_id,frame=Time.frameCount,trajectory=TestContext.CurrentContext.Test.FullName});
        }
        public IEnumerator Execute(string[] ids,IEnumerator body)
        {
            // All log-policy access stays inside the currently executing UnityTest.
            // Runtime product logs are retained, not whitelisted by message/name.
            var previousIgnore=LogAssert.ignoreFailingMessages;
            var scope=new CandidateRuntimeScope(candidateScene,Facts);
            Exception failure=null,cleanupFailure=null;
            try
            {
                LogAssert.ignoreFailingMessages=true;
                yield return Pump(body,ex=>failure=ex);
                if(inputReady){yield return Pump(Input.Dispose(),ex=>cleanupFailure=ex);inputReady=false;}
                if(string.Equals(Name,"T99_DirtyClose",StringComparison.Ordinal))scope.PreserveDirtyClose();
                else yield return Pump(scope.Cleanup(),ex=>cleanupFailure=ex);
                if(failure!=null)Facts.exception=failure.ToString();
                if(cleanupFailure!=null)Facts.exception+=("\nEvaluator runtime cleanup: "+cleanupFailure);
                foreach(var id in ids.Where(id=>Checks.All(x=>x.id!=id))){
                var product=failure as SessionProductFailure;
                var capability=product==null?"":NormalizeCapability(product.Capability);
                // Dependencies are real routes executed by this scenario. The
                // menu is reached through the published saved-scene entry, so
                // a missing/invalid entry blocks its menu leaf too; only the
                // static scene/camera leaves are independent of that route.
                var blocked=product!=null&&!id.StartsWith("D1_SCENE")&&!id.StartsWith("D1_CAMERA");
                Checks.Add(new KitchenCheck{id=id,dimension=id.Substring(0,2),weight=Weight(id),status=blocked?"BLOCKED_BY_PRODUCT":"INCONCLUSIVE_EVALUATOR",
                    expected="complete independently acquired public obligation",observed=failure?.Message??"check was not emitted",attribution=blocked?"published_service_not_delivered":"observer_failure",
                    acquisition_status=blocked?"PRODUCT_BLOCKED":"UNREACHABLE_EVALUATOR",acquisition_route="independent_public_session_and_normal_input",oracle_valid=blocked,precondition_reached=false,
                    trajectory=TestContext.CurrentContext.Test.FullName,process_id=Facts.process_id,frame=Time.frameCount,product_block_reason=blocked?failure.Message:null,blocker_kind=blocked?(capability=="saved-scene"?"saved_entry":"public_session_contract"):null,failed_capability=capability});
                }
                SaveEvidence();
            }
            finally
            {
                // No candidate callbacks remain for ordinary tests when this is
                // restored. T99 intentionally keeps the already-recorded dirty
                // scene until process close, without leaking a global whitelist.
                scope.Dispose();LogAssert.ignoreFailingMessages=previousIgnore;
            }
            if(Checks.Any(x=>x.status=="INCONCLUSIVE_EVALUATOR") || failure!=null&&!(failure is SessionProductFailure)||cleanupFailure!=null||Facts.evaluator_logged_error)Assert.Fail("Evaluator unresolved: "+Facts.exception+";evaluator_logged_error="+Facts.evaluator_logged_error);
        }
        static IEnumerator Pump(IEnumerator body,Action<Exception> failed)
        {
            var stack=new Stack<IEnumerator>();stack.Push(body);
            while(stack.Count>0){object current=null;bool advanced=false;Exception error=null;try{advanced=stack.Peek().MoveNext();if(advanced)current=stack.Peek().Current;}catch(Exception ex){error=ex;}if(error!=null){failed(error);yield break;}
                if(!advanced){stack.Pop();continue;}if(current is IEnumerator nested){stack.Push(nested);continue;}yield return current;}
        }
        void SaveEvidence()
        {
            var path=Environment.GetEnvironmentVariable("KITCHEN_EVIDENCE_FILE");
            if(string.IsNullOrWhiteSpace(path))throw new InvalidOperationException("KITCHEN_EVIDENCE_FILE is required");
            var dir=Path.GetDirectoryName(path);Directory.CreateDirectory(dir);
            KitchenEvidence doc=File.Exists(path)?JsonUtility.FromJson<KitchenEvidence>(File.ReadAllText(path)):new KitchenEvidence{phase=phase,process_id=Facts.process_id,session_id=Environment.GetEnvironmentVariable("KITCHEN_RUN_ID")};
            if(doc.phase!=phase||doc.process_id!=Facts.process_id)throw new InvalidOperationException("Stale phase evidence");
            if(Checks.Any(x=>doc.checks.Any(y=>x.id==y.id)))throw new InvalidOperationException("Duplicate emitted phase check");
            doc.checks.AddRange(Checks);File.WriteAllText(path,JsonUtility.ToJson(doc,true));
            var facts=Path.Combine(dir,"facts");Directory.CreateDirectory(facts);File.WriteAllText(Path.Combine(facts,Name+".json"),JsonUtility.ToJson(Facts,true));
        }
        public IEnumerator Load()
        {
            if(!Application.CanStreamedLevelBeLoaded(ScenePath))throw new SessionProductFailure("saved-scene","Required final scene is absent from Build Settings.");
            var op=SceneManager.LoadSceneAsync(ScenePath,LoadSceneMode.Single);var end=Time.realtimeSinceStartup+15;
            while(op!=null&&!op.isDone&&Time.realtimeSinceStartup<end)yield return null;
            if(op==null||!op.isDone)throw new SessionProductFailure("saved-scene","Required scene did not load.");
            yield return null;yield return null;
        }
        public void Find()
        {
            Game=SessionDriver.Find();var resource=Resources.Load<TextAsset>("session-model");
            if(!resource)throw new InvalidOperationException("Protected public session-model resource missing");
            Driver=new SessionDriver(Game,JsonUtility.FromJson<SessionModel>(resource.text),true,s=>KitchenSessionRules.Validate(s,Game.DescribeCurrentEntry()));
        }
        public IEnumerator Open()
        {
            if(inputReady){yield return Input.Dispose();inputReady=false;Facts.actions.Add("previous action segment closed before independent next setup");}
            yield return Load();Find();yield return Driver.Open("kitchen",173);
            Facts.service_receipts.Add(Driver.LastReceipt);Initial=SessionFormat.Clone(Driver.LastSave);Layout=Game.DescribeCurrentEntry();Observe("entry-committed");
        }
        public SessionSave Clean()
        {
            var s=SessionFormat.Clone(Initial);s.phase="playing";
            N(s,"score",0);N(s,"shift_remaining",120);N(s,"active_chef",1);N(s,"delivered_orders",0);N(s,"expired_orders",0);N(s,"order_spawn_remaining",V(s,"order_interval"));
            for(var i=1;i<=3;i++){N(s,$"order_{i}_id",0);N(s,$"order_{i}_remaining",0);N(s,$"order_{i}_initial",0);}
            foreach(var a in s.actors)foreach(var x in a.values)if(x.name=="held_id"||x.name=="held_kind"||x.name=="item_id"||x.name=="item_kind"||x.name.StartsWith("ingredient_")||x.name=="chop_elapsed"||x.name=="cook_elapsed"||x.name=="burn_elapsed")x.value=0;
            A(s,"chef-1").position=Point("chef-1-spawn");A(s,"chef-2").position=Point("chef-2-spawn");return s;
        }
        public IEnumerator Prepare(SessionSave s)
        {
            // Each scenario opens/captures its own candidate state; opaque data and readonly settings remain intact.
            var invalid=KitchenSessionRules.Validate(s,Layout);if(invalid!=null)throw new InvalidOperationException("Author constructed illegal save: "+invalid);
            yield return Driver.Restore(s);Facts.service_receipts.Add(Driver.LastReceipt);Observe("restored-committed");
        }
        public IEnumerator Ready(){yield return Input.Ready();inputReady=true;}
        public IEnumerator Begin(){Driver.BeginActions();Facts.actions.Add("segment.begin; all setup writes sealed; frame="+Time.frameCount);yield return Ready();}
        public IEnumerator Tap(Key key){Facts.actions.Add("press/real-frame/release/real-frame:"+key+":"+Time.frameCount);yield return Input.Press(key);}
        public IEnumerator Hold(Key key,float seconds){Facts.actions.Add("hold/real-frames/release:"+key+":"+seconds+":"+Time.frameCount);yield return Input.Hold(key,seconds);}
        public IEnumerator Wait(float seconds){var end=Time.realtimeSinceStartup+seconds;while(Time.realtimeSinceStartup<end)yield return null;}
        public IEnumerator Until(Func<bool> cond,float timeout){var end=Time.realtimeSinceStartup+timeout;while(!cond()&&Time.realtimeSinceStartup<end)yield return null;}
        public static double V(SessionSave s,string name)=>V(s.values,name);
        public static double V(ActorSave a,string name)=>V(a.values,name);
        public static double V(IReadOnlyList<NamedNumber> values,string name){if(!SessionFormat.TryNumber(values,name,out var value))throw new SessionProductFailure("capture","Missing/ambiguous public number "+name);return value;}
        public static void N(SessionSave s,string name,double value)=>N(s.values,name,value);
        public static void N(ActorSave a,string name,double value)=>N(a.values,name,value);
        public static void N(List<NamedNumber> numbers,string name,double value){var n=numbers.SingleOrDefault(x=>x.name==name);if(n==null)throw new InvalidOperationException("Author edited missing value "+name);n.value=value;}
        public static ActorSave A(SessionSave s,string id)=>s.actors.Single(x=>x.id==id);
        public static long NewItem(SessionSave s){var id=(long)V(s,"next_item_id");N(s,"next_item_id",id+1);return id;}
        public static void Held(SessionSave s,int chef,int kind){var a=A(s,"chef-"+chef);N(a,"held_id",kind==0?0:NewItem(s));N(a,"held_kind",kind);}
        public static void Container(SessionSave s,string id,int kind){var a=A(s,id);N(a,"item_id",kind==0?0:NewItem(s));N(a,"item_kind",kind);if(id=="chopping-board")N(a,"chop_elapsed",kind==2?V(s,"chop_seconds"):0);}
        public static void Ingredients(SessionSave s,int count){var p=A(s,"pot");for(var i=1;i<=3;i++)N(p,"ingredient_"+i+"_id",i<=count?NewItem(s):0);}
        public static void Soup(SessionSave s,bool burnt=false){Container(s,"pot",burnt?6:5);var p=A(s,"pot");N(p,"cook_elapsed",V(s,"cook_seconds"));N(p,"burn_elapsed",burnt?V(s,"burn_seconds"):0);}
        public static void Order(SessionSave s,double remaining=30){var id=V(s,"next_order_id");N(s,"next_order_id",id+1);N(s,"order_1_id",id);N(s,"order_1_initial",V(s,"order_lifetime"));N(s,"order_1_remaining",Math.Min(remaining,V(s,"order_lifetime")));}
        public Vector3 Point(string name){var matches=Layout?.landmarks?.Where(x=>x!=null&&x.name==name&&x.present).ToArray();if(matches==null||matches.Length!=1)throw new SessionProductFailure("layout:kitchen","Missing/duplicate public approach landmark "+name);return matches[0].position;}
        public void At(SessionSave s,string station,int chef=1){var matches=s.actors.Where(a=>a.id==station).ToArray();if(matches.Length!=1||!Game.ResolveActor(station))throw new SessionProductFailure("actor:"+station,"Missing/duplicate real station "+station);var a=A(s,"chef-"+chef);a.position=Point(station+"-approach");N(a,"heading_degrees",V(matches[0],"approach_heading_degrees"));N(s,"active_chef",chef);}
        public SessionSave Read()
        {
            var s=Driver!=null?Driver.Observe():Game.Capture();var invalid=KitchenSessionRules.Validate(s,Game.DescribeCurrentEntry());
            if(invalid!=null)throw new SessionProductFailure("capture","Invalid captured kitchen state: "+invalid);
            return s;
        }
        public FrameFact Observe(string label)
        {
            var s=Read();var f=new FrameFact{label=label,frame=Time.frameCount,realtime=Time.realtimeSinceStartup,save_json=JsonUtility.ToJson(s),visible_text=Text()};var instanceIds=new HashSet<int>();
            foreach(var a in s.actors.Where(a=>a.present)){
                var go=Game.ResolveActor(a.id);if(!go||!go.activeInHierarchy||!instanceIds.Add(go.GetInstanceID()))throw new SessionProductFailure("objects","Missing, inactive or aliased engine actor "+a.id);
                if(Vector3.Distance(go.transform.position,a.position)>.02f)throw new SessionProductFailure("objects","Reported actor pose differs from actual engine object "+a.id);
                var rr=go.GetComponentsInChildren<Renderer>(false).Where(r=>r.enabled&&r.gameObject.activeInHierarchy).ToArray();
                var bits=new List<string>();foreach(var r in rr){bits.Add(r.GetType().Name+"|"+r.transform.localPosition+"|"+r.transform.localScale+"|"+r.enabled);foreach(var m in r.sharedMaterials)if(m){bits.Add(m.name);if(m.HasProperty("_BaseColor"))bits.Add(m.GetColor("_BaseColor").ToString());if(m.HasProperty("_Color"))bits.Add(m.color.ToString());}}
                f.actors.Add(new WorldActor{id=a.id,instance_id=go.GetInstanceID(),position=go.transform.position,renderers=rr.Length,presentation=string.Join(";",bits)});
            }
            Facts.frames.Add(f);return f;
        }
        public static string Text()
        {
            var rows=new List<string>();
            foreach(var t in Object.FindObjectsByType<TMP_Text>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))if(t.isActiveAndEnabled&&t.color.a>.05&&Visible(t.rectTransform))rows.Add(t.text);
            foreach(var t in Object.FindObjectsByType<Text>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))if(t.isActiveAndEnabled&&t.color.a>.05&&Visible(t.rectTransform))rows.Add(t.text);
            return string.Join("\n",rows);
        }
        // Menu presentation is independently observable before a session
        // provider is accepted. This keeps a broken public session contract
        // attributable to its dependent leaves without turning a readable
        // menu into an evaluator-inconclusive result.
        public void ObserveVisibleMenu(string label="menu-visible")
        {
            Facts.frames.Add(new FrameFact{label=label,frame=Time.frameCount,realtime=Time.realtimeSinceStartup,visible_text=Text()});
        }
        public static bool Visible(RectTransform rect){if(!rect.gameObject.activeInHierarchy)return false;foreach(var g in rect.GetComponentsInParent<CanvasGroup>())if(g.alpha<.05)return false;var canvas=rect.GetComponentInParent<Canvas>();if(!canvas||!canvas.isActiveAndEnabled)return false;var cam=canvas.renderMode==RenderMode.ScreenSpaceOverlay?null:canvas.worldCamera;var corners=new Vector3[4];rect.GetWorldCorners(corners);var points=corners.Select(p=>RectTransformUtility.WorldToScreenPoint(cam,p)).ToArray();var bounds=Rect.MinMaxRect(points.Min(p=>p.x),points.Min(p=>p.y),points.Max(p=>p.x),points.Max(p=>p.y));var screen=new Rect(0,0,Screen.width,Screen.height);if(bounds.width<1||bounds.height<1||!screen.Overlaps(bounds))return false;var center=bounds.center;if(!screen.Contains(center))return false;foreach(var mask in rect.GetComponentsInParent<RectMask2D>())if(mask.isActiveAndEnabled&&!RectTransformUtility.RectangleContainsScreenPoint(mask.rectTransform,center,cam))return false;var graphic=rect.GetComponent<Graphic>();if(graphic){foreach(var image in UnityEngine.Object.FindObjectsByType<Image>(FindObjectsInactive.Exclude,FindObjectsSortMode.None)){if(!image.isActiveAndEnabled||image.sprite!=null||image.color.a<.99f||image.canvas!=graphic.canvas||image.depth<=graphic.depth)continue;if(RectTransformUtility.RectangleContainsScreenPoint(image.rectTransform,center,cam))return false;}}return true;}
        public static bool Label(string text,params string[] words)=>words.Any(w=>Regex.IsMatch(Regex.Replace(text??"","<[^>]*>",""),@"\b"+Regex.Escape(w)+@"\b",RegexOptions.IgnoreCase));
        public static bool NumberVisible(string text,double value)=>Regex.Matches(Regex.Replace(text??"","<[^>]*>",""),@"-?\d+(?:\.\d+)?").Cast<Match>().Any(m=>double.TryParse(m.Value,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var d)&&Math.Abs(d-value)<.51);
        public bool Rendered(params string[] ids){return ids.All(id=>{var go=Game.ResolveActor(id);return go&&go.GetComponentsInChildren<Renderer>(false).Any(r=>r.enabled&&r.gameObject.activeInHierarchy);});}
        public static bool SameState(SessionSave a,SessionSave b,double tolerance=.0001){if(a==null||b==null||a.contract!=b.contract||a.contentVersion!=b.contentVersion||a.entryId!=b.entryId||a.phase!=b.phase||a.seed!=b.seed||a.actors.Count!=b.actors.Count)return false;bool numbers(List<NamedNumber> l,List<NamedNumber> r)=>l.Count==r.Count&&l.All(x=>SessionFormat.TryNumber(r,x.name,out var v)&&Math.Abs(v-x.value)<=tolerance);if(!numbers(a.values,b.values))return false;foreach(var x in a.actors){var ys=b.actors.Where(y=>y.id==x.id).ToArray();if(ys.Length!=1)return false;var y=ys[0];if(x.kind!=y.kind||x.entryId!=y.entryId||x.present!=y.present||x.state!=y.state||x.facing!=y.facing||Vector3.Distance(x.position,y.position)>tolerance||!numbers(x.values,y.values))return false;}return true;}
        public void DetachedCapture(){var a=Read();var expected=SessionFormat.Clone(a);var b=Read();if(ReferenceEquals(a,b)||ReferenceEquals(a.values,b.values)||ReferenceEquals(a.actors,b.actors)||a.values.Any(x=>b.values.Any(y=>ReferenceEquals(x,y)))||a.actors.Any(x=>b.actors.Any(y=>ReferenceEquals(x,y)||ReferenceEquals(x.values,y.values)||x.values.Any(n=>y.values.Any(m=>ReferenceEquals(n,m))))))throw new SessionProductFailure("capture","Capture has shared mutable objects");if(!SameState(expected,b))throw new SessionProductFailure("capture","Capture changes gameplay within one frame");a.values[0].value+=1;if(a.actors.Count>0){a.actors[0].position+=Vector3.one;if(a.actors[0].values.Count>0)a.actors[0].values[0].value+=1;}if(!SameState(expected,Read()))throw new SessionProductFailure("capture","Caller snapshot mutation changed real state");}
        public static int NumericCount(string text,double value,double tolerance=.01){var clean=Regex.Replace(text??"","<[^>]*>","").Replace('−','-');var values=Regex.Matches(clean,@"-?\d+(?:\.\d+)?").Cast<Match>().Select(m=>double.TryParse(m.Value,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var x)?x:double.NaN).ToList();foreach(Match m in Regex.Matches(clean,@"\b(\d{1,2}):([0-5]\d)\b"))values.Add(int.Parse(m.Groups[1].Value)*60+int.Parse(m.Groups[2].Value));return values.Count(x=>Math.Abs(x-value)<=tolerance);}
        public static bool Changed(FrameFact before,FrameFact after,params string[] ids)=>ids.Any(id=>before.actors.Single(x=>x.id==id).presentation!=after.actors.Single(x=>x.id==id).presentation);
        public bool HasDistinctEngineActors(){var ids=new HashSet<int>();foreach(var a in Initial.actors.Where(x=>x.present)){var go=Game.ResolveActor(a.id);if(!go||!ids.Add(go.GetInstanceID()))return false;}return ids.Count==Initial.actors.Count(x=>x.present);}

        public sealed class AudioSample{public int id,clip,samples;public bool playing,loop;public float rms,volume;}
        public AudioSample[] AudioSnapshot(){var buffer=new float[256];return Object.FindObjectsByType<AudioSource>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(a=>a.isActiveAndEnabled).Select(a=>{Array.Clear(buffer,0,buffer.Length);a.GetOutputData(buffer,0);return new AudioSample{id=a.GetInstanceID(),clip=a.clip?a.clip.GetInstanceID():0,samples=a.timeSamples,playing=a.isPlaying,loop=a.loop,volume=a.volume,rms=(float)Math.Sqrt(buffer.Select(v=>(double)v*v).Average())};}).ToArray();}
        public bool AudioPulse(AudioSample[] before){var after=AudioSnapshot();Facts.actions.Add("audio-observation:"+string.Join(";",after.Select(a=>$"id={a.id},playing={a.playing},loop={a.loop},samples={a.samples},rms={a.rms},volume={a.volume}")));return after.Any(a=>a.playing&&a.volume>0&&(!before.Any(b=>b.id==a.id&&b.playing)||before.Any(b=>b.id==a.id&&(a.clip!=b.clip||a.samples+32<b.samples||a.rms>Math.Max(.00005f,b.rms*1.15f)))));}
        public bool AudioActive()=>Object.FindObjectsByType<AudioSource>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Any(x=>x.isActiveAndEnabled&&x.volume>0&&x.isPlaying);

        // Drive toward a real station root using only published movement
        // vectors. This never writes candidate state or invokes gameplay APIs.
        public IEnumerator DriveToward(string station,float seconds,Action sample=null)
        {
            var target=Game.ResolveActor(station);
            if(!target)throw new SessionProductFailure("objects","Missing real station root "+station);
            var end=Time.realtimeSinceStartup+seconds;
            while(Time.realtimeSinceStartup<end)
            {
                var s=Read();
                var chef=Game.ResolveActor("chef-"+(int)V(s,"active_chef"));
                if(!chef)throw new SessionProductFailure("objects","Missing active chef root");
                var delta=target.transform.position-chef.transform.position;
                var right=new Vector3((float)V(s,"move_right_x"),(float)V(s,"move_right_y"),(float)V(s,"move_right_z"));
                var forward=new Vector3((float)V(s,"move_forward_x"),(float)V(s,"move_forward_y"),(float)V(s,"move_forward_z"));
                var keys=new List<Key>();
                var x=Vector3.Dot(delta,right);var z=Vector3.Dot(delta,forward);
                if(Mathf.Abs(x)>.05f)keys.Add(x>0?Key.D:Key.A);
                if(Mathf.Abs(z)>.05f)keys.Add(z>0?Key.W:Key.S);
                yield return Input.Frame(keys.ToArray());
                sample?.Invoke();
            }
            yield return Input.Frame();
            sample?.Invoke();
        }

        public IEnumerator Navigate(string station)
        {
            var target=Point(station=="open-floor"?"open-floor":station+"-approach");var initial=Read();var right=new Vector3((float)V(initial,"move_right_x"),(float)V(initial,"move_right_y"),(float)V(initial,"move_right_z"));var forward=new Vector3((float)V(initial,"move_forward_x"),(float)V(initial,"move_forward_y"),(float)V(initial,"move_forward_z"));
            var end=Time.realtimeSinceStartup+12;var arrived=false;
            while(Time.realtimeSinceStartup<end){var s=Read();var go=Game.ResolveActor("chef-"+(int)V(s,"active_chef"));var delta=target-go.transform.position;if(delta.magnitude<.16f){arrived=true;break;}var keys=new List<Key>();var x=Vector3.Dot(delta,right);var y=Vector3.Dot(delta,forward);if(Mathf.Abs(x)>.09f)keys.Add(x>0?Key.D:Key.A);if(Mathf.Abs(y)>.09f)keys.Add(y>0?Key.W:Key.S);yield return Input.Frame(keys.ToArray());}
            yield return Input.Frame();if(!arrived)throw new NavigationFailure("Bounded normal navigation did not reach "+station+"; not a gameplay verdict.");
            // Face a station using a short normal movement. open-floor is a
            // landmark, not an interactable station, so it has no heading.
            if(station!="open-floor"){
                var heading=(float)V(A(initial,station),"approach_heading_degrees")*Mathf.Deg2Rad;var faceKeys=new List<Key>();if(Mathf.Abs(Mathf.Sin(heading))>.3f)faceKeys.Add(Mathf.Sin(heading)>0?Key.D:Key.A);if(Mathf.Abs(Mathf.Cos(heading))>.3f)faceKeys.Add(Mathf.Cos(heading)>0?Key.W:Key.S);yield return Input.Frame(faceKeys.ToArray());yield return Input.Frame();
            }
            Facts.actions.Add("bounded-normal-navigation:"+station+":"+Time.frameCount);
        }
    }
}
