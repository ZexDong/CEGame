using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using GameCreate.Session;
using GameCreate.Stormbound.Contract;
using GameCreate.Evaluation.Session;
using NUnit.Framework;
using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.TestTools;
using UnityEngine.UI;
using UnityEngine.UIElements;
using Object=UnityEngine.Object;
using Process=System.Diagnostics.Process;
namespace GameCreate.Stormbound.Evaluator
{
    [Serializable] public sealed class StormboundCheck
    {
        public string id, dimension, status, expected, observed, attribution, acquisition_status, acquisition_route, trajectory, product_block_reason, blocker_kind, failed_capability;
        public bool precondition_reached, oracle_valid;
        public int process_id, frame, setup_writes_after_action;
        public float weight;
        public string[] requirements = Array.Empty<string>();
    }
    [Serializable] public sealed class StormboundEvidence
    {
        public int schema_version=4;
        public string phase, session_id;
        public int process_id;
        public List<StormboundCheck> checks=new List<StormboundCheck>();
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


public sealed class StormboundRun
{
 public const string ScenePath="Assets/DriftfolkChallenge/Scenes/DriftfolkChronicle.unity";
 public readonly ScenarioFacts Facts;
 public readonly List<StormboundCheck> Checks=new List<StormboundCheck>();
 public readonly PlayerInputDriver Input=new PlayerInputDriver();
 public IGameSession Game;public SessionDriver Driver;public SessionSave Initial;public EntryDescription Layout;
 public readonly HashSet<string> RequiredActorIds=new HashSet<string>();public readonly HashSet<string> RequiredLandmarks=new HashSet<string>();
 public string Name=>Facts.test_id;readonly string phase;readonly Func<Scene,bool> candidateScene;bool inputReady;
 public StormboundRun(string phase,Func<Scene,bool> candidateScene=null){this.phase=phase;this.candidateScene=candidateScene??(s=>s.path==ScenePath);Facts=new ScenarioFacts{phase=phase,test_id=TestContext.CurrentContext.Test.Name,process_id=Process.GetCurrentProcess().Id};SelectObservationDependencies();}
 [Serializable]sealed class Flat{public Row[] checks;}[Serializable]sealed class Row{public string id;public float weight;}
 static float Weight(string id){var text=Resources.Load<TextAsset>("stormbound-private-rules");if(!text)throw new InvalidOperationException("Missing frozen rules");return JsonUtility.FromJson<Flat>(text.text).checks.Single(x=>x.id==id).weight;}
 static string Capability(string s){if(s.StartsWith("entry:")||s=="entry-catalogue"||s=="session-interface")return "chapter_entry";if(s.StartsWith("restore:")||s=="invalid-restore")return "state_restore";if(s.StartsWith("actor:")||s.StartsWith("layout:")||s=="objects")return "object_query";if(s=="capture")return "state_capture";if(s=="resume-simulation")return "player_input";return s;}
 public void Check(string id,bool passed,string expected,string observed){if(Checks.Any(x=>x.id==id))throw new InvalidOperationException("Duplicate leaf "+id);Checks.Add(new StormboundCheck{id=id,dimension=id.Substring(0,2),weight=Weight(id),status=passed?"PASS":"FAIL_OBSERVED",expected=expected,observed=observed,attribution="observed",acquisition_status="READY",acquisition_route="independent_public_session_and_normal_input",precondition_reached=true,oracle_valid=true,process_id=Facts.process_id,frame=Time.frameCount,trajectory=TestContext.CurrentContext.Test.FullName});}
 public IEnumerator Execute(string[] ids,IEnumerator body)
 {
  var previous=LogAssert.ignoreFailingMessages;var scope=new CandidateRuntimeScope(candidateScene,Facts);Exception failure=null,cleanup=null;
  try{
   LogAssert.ignoreFailingMessages=true;yield return Pump(body,e=>failure=e);
   if(inputReady&&Name!="T99_DirtyClose"){yield return Pump(Input.Dispose(),e=>cleanup=e);inputReady=false;}
   if(Name=="T99_DirtyClose")scope.PreserveDirtyClose();else yield return Pump(scope.Cleanup(),e=>cleanup=e);
   if(failure!=null)Facts.exception=failure.ToString();if(cleanup!=null)Facts.exception+="\nCleanup: "+cleanup;
   foreach(var id in ids.Where(x=>Checks.All(c=>c.id!=x)))
   {var product=failure as SessionProductFailure;var cap=product==null?"":Capability(product.Capability);Checks.Add(new StormboundCheck{id=id,dimension=id.Substring(0,2),weight=Weight(id),status=product!=null?"BLOCKED_BY_PRODUCT":"INCONCLUSIVE_EVALUATOR",expected="complete declared obligation",observed=failure?.Message??"missing verdict",attribution=product!=null?"published_service_not_delivered":"observer_failure",acquisition_status=product!=null?"PRODUCT_BLOCKED":"UNREACHABLE_EVALUATOR",acquisition_route="public_session_and_normal_input",oracle_valid=product!=null,precondition_reached=false,process_id=Facts.process_id,frame=Time.frameCount,trajectory=TestContext.CurrentContext.Test.FullName,product_block_reason=product?.Message,blocker_kind=product==null?null:cap=="saved-scene"?"saved_entry":"public_session_contract",failed_capability=cap});}
   Write();
  }finally{scope.Dispose();LogAssert.ignoreFailingMessages=previous;}
  if(Checks.Any(x=>x.status=="INCONCLUSIVE_EVALUATOR")||failure!=null&&!(failure is SessionProductFailure)||cleanup!=null||Facts.evaluator_logged_error)Assert.Fail("Evaluator unresolved: "+Facts.exception);
 }
 static IEnumerator Pump(IEnumerator e,Action<Exception> fail){var stack=new Stack<IEnumerator>();stack.Push(e);while(stack.Count>0){bool more=false;object value=null;Exception error=null;try{more=stack.Peek().MoveNext();if(more)value=stack.Peek().Current;}catch(Exception x){error=x;}if(error!=null){fail(error);yield break;}if(!more){stack.Pop();continue;}if(value is IEnumerator nested){stack.Push(nested);continue;}yield return value;}}
 void Write(){var path=Environment.GetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE");if(string.IsNullOrEmpty(path))throw new InvalidOperationException("No evidence destination");Directory.CreateDirectory(Path.GetDirectoryName(path));var doc=File.Exists(path)?JsonUtility.FromJson<StormboundEvidence>(File.ReadAllText(path)):new StormboundEvidence{phase=phase,process_id=Facts.process_id,session_id=Environment.GetEnvironmentVariable("STORMBOUND_RUN_ID")};if(doc.phase!=phase||doc.process_id!=Facts.process_id||Checks.Any(c=>doc.checks.Any(x=>x.id==c.id)))throw new InvalidOperationException("Stale/duplicate evidence");doc.checks.AddRange(Checks);File.WriteAllText(path,JsonUtility.ToJson(doc,true));var directory=Path.Combine(Path.GetDirectoryName(path),"facts");Directory.CreateDirectory(directory);File.WriteAllText(Path.Combine(directory,Name+".json"),JsonUtility.ToJson(Facts,true));}
 public IEnumerator Load(){
#if UNITY_EDITOR
 yield return EditorGameViewResolution.Ensure1280x720();
#endif
 yield return Ready();if(!Application.CanStreamedLevelBeLoaded(ScenePath))throw new SessionProductFailure("saved-scene","Final scene is not saved in Build Settings");var op=SceneManager.LoadSceneAsync(ScenePath,LoadSceneMode.Single);var end=Time.realtimeSinceStartup+15;while(op!=null&&!op.isDone&&Time.realtimeSinceStartup<end)yield return null;if(op==null||!op.isDone)throw new SessionProductFailure("saved-scene","Final scene could not load");yield return null;yield return null;}
 public void Find(){Game=SessionDriver.Find();Driver=new SessionDriver(Game,StormboundStateRules.Model,true,StormboundStateRules.Validate,a=>RequiredActorIds.Contains(a.id),name=>RequiredLandmarks.Contains(name));}
 public IEnumerator Open(){if(inputReady){yield return Input.Dispose();inputReady=false;Facts.actions.Add("prior independent action segment closed");}yield return Load();Find();yield return Driver.Open("archipelago",20260823);Facts.service_receipts.Add(Driver.LastReceipt);Initial=SessionFormat.Clone(Driver.LastSave);Layout=RequiredLandmarks.Count>0?Call("objects",()=>Game.DescribeCurrentEntry()):null;Observe("chapter-committed");}
 public SessionSave Paused(){var s=SessionFormat.Clone(Initial);s.phase="playing";N(s,"paused",1);N(s,"events_resolved",3);N(s,"event_pending",0);return s;}
 public IEnumerator Prepare(SessionSave s){var invalid=StormboundStateRules.Validate(s);if(invalid!=null)throw new InvalidOperationException("Illegal author preparation: "+invalid);yield return Driver.Restore(s);Facts.service_receipts.Add(Driver.LastReceipt);Observe("restored-committed");}
 public IEnumerator Begin(){Driver.BeginActions();Facts.actions.Add("segment.begin; setup writes sealed; frame="+Time.frameCount);yield return Ready();}
 public IEnumerator Ready(){yield return Input.Ready();inputReady=true;}
 public IEnumerator Tap(Key key){Facts.actions.Add("normal-key:"+key+":"+Time.frameCount);yield return Input.Press(key);yield return null;}
 public IEnumerator Step(int count=1){for(int i=0;i<count;i++)yield return Tap(Key.N);}
 public IEnumerator Wait(float seconds){var until=Time.realtimeSinceStartup+seconds;while(Time.realtimeSinceStartup<until)yield return null;}
 public SessionSave Read(){var s=Driver!=null?Driver.Observe():Call("capture",()=>Game.Capture());var invalid=StormboundStateRules.Validate(s);if(invalid!=null)throw new SessionProductFailure("capture","Invalid public state: "+invalid);return s;}
 public FrameFact Observe(string label){var s=Read();var f=new FrameFact{frame=Time.frameCount,realtime=Time.realtimeSinceStartup,label=label,save_json=JsonUtility.ToJson(s),visible_text=Text()};var ids=new HashSet<int>();foreach(var a in s.actors.Where(x=>x.present&&RequiredActorIds.Contains(x.id))){var go=Call("objects",()=>Game.ResolveActor(a.id));if(!go||!go.activeInHierarchy||!ids.Add(go.GetInstanceID()))throw new SessionProductFailure("objects","Missing, inactive or aliased real object: "+a.id);if(Vector3.Distance(a.position,go.transform.position)>.025f)throw new SessionProductFailure("objects","Reported pose disagrees with actual object: "+a.id);f.actors.Add(new WorldActor{id=a.id,instance_id=go.GetInstanceID(),position=go.transform.position,renderers=go.GetComponentsInChildren<Renderer>().Count(x=>x.enabled),presentation=go.name});}Facts.frames.Add(f);return f;}
 public static double V(SessionSave s,string key)=>V(s.values,key);public static double V(ActorSave a,string key)=>V(a.values,key);public static double V(IReadOnlyList<NamedNumber> values,string key){if(!SessionFormat.TryNumber(values,key,out var v))throw new SessionProductFailure("capture","Missing number: "+key);return v;}
 public static void N(SessionSave s,string key,double value)=>N(s.values,key,value);public static void N(ActorSave a,string key,double value)=>N(a.values,key,value);static void N(List<NamedNumber> values,string key,double value){var n=values.SingleOrDefault(x=>x.name==key);if(n==null)throw new InvalidOperationException("Unknown author field: "+key);n.value=value;}
 public static ActorSave A(SessionSave s,string id)=>s.actors.Single(x=>x.id==id);
 public static void Rest(SessionSave s){foreach(var a in s.actors.Where(x=>x.kind=="resident"))N(a,"job",0);}
 public static void Building(SessionSave s,string id,string state,int work){var a=A(s,id);a.state=state;N(a,"work",work);}
 public static void Beacons(SessionSave s){foreach(var port in new[]{"a","b"}){Building(s,port+"-workshop","built",4);Building(s,port+"-beacon","built",5);}}
 public void MoveResident(SessionSave s,int resident,int island){var a=A(s,"resident-"+resident);N(a,"island",island);a.state=island==0?"aboard":"alive";var mark=Layout.landmarks.Single(x=>x.name==(island==0?"harbor-a":island==1?"island-a":"island-b"));a.position=mark.position+new Vector3(resident*.05f,0,0);}
 public static void Date(SessionSave s,int day,int period){N(s,"day",day);N(s,"period",period);N(s,"weather",new[]{0,1,0,2,0,1}[(day-1)%6]);}
 public static int Ticks(SessionSave s)=>(int)((V(s,"day")-1)*3+V(s,"period"));
 public static bool Same(SessionSave a,SessionSave b,bool history=true){var x=SessionFormat.Clone(a);var y=SessionFormat.Clone(b);N(x,"saved_notice",0);N(y,"saved_notice",0);if(!history){x.opaqueData=y.opaqueData="";N(x,"chronicle_count",1);N(y,"chronicle_count",1);N(x,"next_chronicle_id",2);N(y,"next_chronicle_id",2);}return PublicEqual(x,y);}
 public static bool PublicEqual(SessionSave x,SessionSave y){if(x.contract!=y.contract||x.contentVersion!=y.contentVersion||x.entryId!=y.entryId||x.phase!=y.phase||x.seed!=y.seed||!NumbersEqual(x.values,y.values)||x.actors.Count!=y.actors.Count)return false;foreach(var a in x.actors){var b=y.actors.SingleOrDefault(v=>v.id==a.id);if(b==null||a.kind!=b.kind||a.entryId!=b.entryId||a.state!=b.state||a.present!=b.present||Vector3.Distance(a.position,b.position)>.0001f||a.facing!=b.facing||!NumbersEqual(a.values,b.values))return false;}return true;}
 static bool NumbersEqual(List<NamedNumber> x,List<NamedNumber> y){return x.Count==y.Count&&x.All(a=>y.Count(b=>b.name==a.name&&Math.Abs(b.value-a.value)<.0001)==1);}
 public static string Text(){var parts=new List<string>();parts.AddRange(Object.FindObjectsByType<UnityEngine.UI.Text>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x.enabled&&x.color.a>.01f).Select(x=>x.text));parts.AddRange(Object.FindObjectsByType<TMP_Text>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x.enabled&&x.color.a>.01f).Select(x=>x.text));parts.AddRange(Object.FindObjectsByType<TextMesh>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Select(x=>x.text));foreach(var doc in Object.FindObjectsByType<UIDocument>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))if(doc.rootVisualElement!=null)doc.rootVisualElement.Query<TextElement>().ForEach(e=>{if(e.visible&&e.resolvedStyle.display!=DisplayStyle.None)parts.Add(e.text);});return string.Join("\n",parts);}
 public static int VisibleActors(IGameSession game,SessionSave save)=>save.actors.Where(x=>x.present).Count(a=>{var go=Call("objects",()=>game.ResolveActor(a.id));return go&&(go.GetComponentsInChildren<Renderer>().Any(v=>v.enabled&&v.gameObject.activeInHierarchy)||go.GetComponentsInChildren<Graphic>().Any(v=>v.enabled&&v.color.a>.01f));});
 public static T Call<T>(string capability,Func<T> operation){try{return operation();}catch(SessionProductFailure){throw;}catch(Exception e){throw new SessionProductFailure(capability,"Candidate service exception: "+e.GetType().Name+": "+e.Message);}}
 void SelectObservationDependencies(){string ids="";switch(Name){
 case "T01C_ActualActors":case "T20_Restart": ids="island-a island-b resident-1 resident-2 resident-3 resident-4 resident-5 resident-6 a-workshop a-clinic a-beacon b-workshop b-clinic b-beacon ferry escape-project";break;
 case "T03_ProductionLocality":ids="island-a island-b resident-1 resident-2 resident-3 resident-4 resident-5 a-workshop";break;
 case "T04_FatigueRest":ids="island-a resident-1";break;
 case "T05_NightHealth":ids="island-a island-b resident-1 resident-4";break;
 case "T06_Medic":ids="resident-1 resident-2 resident-3 resident-4 a-clinic";break;
 case "T07_WeatherBoat":ids="ferry";break;
 case "T08_BuildAndGuards":ids="island-a a-workshop a-beacon resident-1 resident-2";break;
 case "T09_BuildCancel":ids="island-a a-workshop";break;
 case "T10_TransportAtomic":case "T99_DirtyClose":case "FRESH01_ReopenAndExplicitLoad":ids="island-a resident-1 ferry";break;
 case "T11_Arrival":ids="island-b resident-1 ferry";break;
 case "T12_Event":ids="island-a";break;
 case "T13_EscapePayment":ids="island-a a-clinic a-beacon b-beacon escape-project resident-1 resident-2";break;
 case "T14_EscapeCancel":ids="island-a escape-project";break;
 case "T15_PauseSpeed":ids="island-a resident-1 resident-2 a-workshop";break;
 case "T16_SaveRestore":ids="island-a a-workshop";break;
 case "T17_Endings":ids="escape-project ferry resident-1 island-a";break;
 case "T18_Adjacent":ids="a-workshop ferry resident-1 island-a island-b";break;
 case "T19_ModalContinuity":ids="ferry resident-1 escape-project island-a";break;
 }foreach(var id in ids.Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries))RequiredActorIds.Add(id);
 if(Name=="T01C_ActualActors")foreach(var id in new[]{"island-a","island-b","harbor-a","harbor-b"})RequiredLandmarks.Add(id);
 if(Name=="T11_Arrival"||Name=="T19_ModalContinuity"||Name=="T99_DirtyClose")RequiredLandmarks.Add("harbor-a");if(Name=="T17_Endings")RequiredLandmarks.Add("island-a");}
 public IEnumerator ClickStart(){yield return Ready();var button=Object.FindObjectsByType<UnityEngine.UI.Button>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).FirstOrDefault(b=>b.interactable&&Regex.IsMatch(string.Join(" ",b.GetComponentsInChildren<UnityEngine.UI.Text>().Select(t=>t.text).Concat(b.GetComponentsInChildren<TMP_Text>().Select(t=>t.text))),@"\b(start|begin|new)\b",RegexOptions.IgnoreCase));Vector2 point;
 if(button){var rect=button.GetComponent<RectTransform>();var canvas=button.GetComponentInParent<Canvas>();point=RectTransformUtility.WorldToScreenPoint(canvas.renderMode==RenderMode.ScreenSpaceOverlay?null:canvas.worldCamera,rect.TransformPoint(rect.rect.center));}
 else {var element=Object.FindObjectsByType<UIDocument>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).SelectMany(d=>d.rootVisualElement.Query<UnityEngine.UIElements.Button>().ToList()).FirstOrDefault(b=>b.enabledInHierarchy&&b.visible&&Regex.IsMatch(b.text??"",@"\b(start|begin|new)\b",RegexOptions.IgnoreCase));if(element==null)throw new InvalidOperationException("No independent visible Start click observation; normal keyboard route remains separate");point=new Vector2(element.worldBound.center.x,Screen.height-element.worldBound.center.y);}
 Facts.actions.Add("normal-mouse-start:"+point);InputSystem.QueueStateEvent(Mouse.current,new MouseState{position=point}.WithButton(UnityEngine.InputSystem.LowLevel.MouseButton.Left,true));yield return null;InputSystem.QueueStateEvent(Mouse.current,new MouseState{position=point});yield return null;yield return null;}
}
}
