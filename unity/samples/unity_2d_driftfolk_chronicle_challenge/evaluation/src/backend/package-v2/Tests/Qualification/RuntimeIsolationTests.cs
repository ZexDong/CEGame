using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GameCreate.Evaluation.Session;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using Object=UnityEngine.Object;

namespace GameCreate.Stormbound.Evaluator.Qualification
{
 public sealed class RuntimeIsolationTests
 {
  readonly HashSet<int> owned=new HashSet<int>();
  readonly List<GameObject> roots=new List<GameObject>();
  string previousEvidence,casePath;
  [Serializable] sealed class CaseReceipt{public string test_id,diagnostic_nunit_status;public int process_id,frame;}
  [SetUp] public void Setup()
  {
   previousEvidence=Environment.GetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE");
   var root=Environment.GetEnvironmentVariable("STORMBOUND_QUALIFICATION_OUTPUT");
   if(string.IsNullOrWhiteSpace(root))throw new InvalidOperationException("Explicit isolation qualification evidence directory required.");
   var path=Path.Combine(root,TestContext.CurrentContext.Test.Name,"evidence.json");Directory.CreateDirectory(Path.GetDirectoryName(path));
   Environment.SetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE",path);
   casePath=Path.Combine(Path.GetDirectoryName(path),"qualification-case.json");
  }
  [TearDown] public void Restore()
  {
   foreach(var root in roots)if(root)Object.DestroyImmediate(root);
   roots.Clear();owned.Clear();Time.timeScale=1;
   Environment.SetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE",previousEvidence);
   var fact=new CaseReceipt{test_id=TestContext.CurrentContext.Test.Name,diagnostic_nunit_status=TestContext.CurrentContext.Result.Outcome.Status.ToString(),process_id=System.Diagnostics.Process.GetCurrentProcess().Id,frame=Time.frameCount};
   using(var stream=new FileStream(casePath,FileMode.CreateNew,FileAccess.Write,FileShare.Read))using(var writer=new StreamWriter(stream,new System.Text.UTF8Encoding(false)))writer.Write(JsonUtility.ToJson(fact,true));
  }
  StormboundRun Run()=>new StormboundRun("qualification",s=>owned.Contains(s.handle));
  Scene Scene(){var s=SceneManager.CreateScene("OwnedIsolation_"+Guid.NewGuid().ToString("N"));owned.Add(s.handle);return s;}
  GameObject Root(Scene scene,bool error,bool persistent=false,bool respawn=false)
  {
   var root=new GameObject("synthetic product root");roots.Add(root);SceneManager.MoveGameObjectToScene(root,scene);
   var behavior=root.AddComponent<StormboundQualificationProduct.Callbacks>();behavior.emit=error;behavior.respawn=respawn;
   if(persistent)Object.DontDestroyOnLoad(root);return root;
  }
  static IEnumerator Catch(IEnumerator body,Action<Exception> caught)
  {
   var stack=new Stack<IEnumerator>();stack.Push(body);
   while(stack.Count>0){object current=null;bool more=false;Exception failure=null;try{more=stack.Peek().MoveNext();if(more)current=stack.Peek().Current;}catch(Exception e){failure=e;}
    if(failure!=null){caught(failure);yield break;}if(!more){stack.Pop();continue;}if(current is IEnumerator next){stack.Push(next);continue;}yield return current;}
  }
  IEnumerator ErrorBody(StormboundRun run)
  {
   var scene=Scene();Root(scene,true);Root(scene,true,true,true);SceneManager.SetActiveScene(scene);
   Time.timeScale=0;yield return null;yield return null;yield return null;
   run.Check("D1_SESSION_ENTRY",true,"fixture body completed","candidate runtime error retained separately");
  }
  [UnityTest,Order(1)] public IEnumerator T01_ErrorLoopAndAnimationLikeCallbackAreContained()
  {
   var host=new GameObject("preexisting host DDOL");roots.Add(host);Object.DontDestroyOnLoad(host);
   var policy=LogAssert.ignoreFailingMessages;var run=Run();yield return run.Execute(new[]{"D1_SESSION_ENTRY"},ErrorBody(run));
   Assert.That(run.Facts.runtime_logs.Any(l=>l.message=="fixture candidate Update error"&&l.count>=2),Is.True);
   Assert.That(run.Facts.runtime_logs.Any(l=>l.message=="fixture animation-like callback has no receiver"),Is.True);
   Assert.That(run.Facts.evaluator_logged_error,Is.False);Assert.That(host,Is.Not.Null);Assert.That(host.activeSelf,Is.True);
   Assert.That(run.Facts.actions.Any(a=>a.Contains("runtime-scope.cleaned")),Is.True);Assert.That(Time.timeScale,Is.EqualTo(1));
   Assert.That(LogAssert.ignoreFailingMessages,Is.EqualTo(policy));
   Assert.That(Resources.FindObjectsOfTypeAll<StormboundQualificationProduct.Callbacks>().Length,Is.Zero);
  }
  [UnityTest,Order(2)] public IEnumerator T02_NextNUnitScopeHasNoInheritedCandidateLogs()
  {yield return null;yield return null;Assert.That(Resources.FindObjectsOfTypeAll<StormboundQualificationProduct.Callbacks>().Length,Is.Zero);LogAssert.NoUnexpectedReceived();}
  IEnumerator MissingBeforeLoad(){yield return null;throw new SessionProductFailure("saved-scene","fixture setup failure before load");}
  [UnityTest,Order(3)] public IEnumerator T03_SetupFailureBeforeLoadKeepsHostScene()
  {
   var before=SceneManager.GetActiveScene();var host=new GameObject("host survives early failure");roots.Add(host);
   var run=Run();yield return run.Execute(new[]{"D1_SESSION_ENTRY"},MissingBeforeLoad());
   Assert.That(run.Checks.Single().status,Is.EqualTo("BLOCKED_BY_PRODUCT"));Assert.That(host,Is.Not.Null);Assert.That(before.IsValid()&&before.isLoaded,Is.True);
  }
  IEnumerator ProductFailure(StormboundRun run)
  {var scene=Scene();Root(scene,true);yield return null;run.Check("D3_LOCALITY",true,"independent observed behavior","retained");throw new SessionProductFailure("layout:archipelago","fixture typed product failure");}
  [UnityTest,Order(4)] public IEnumerator T04_TypedProductFailureCleansSceneAndKeepsIndependentCheck()
  {
   var run=Run();yield return run.Execute(new[]{"D3_LOCALITY","D2_PRODUCTION"},ProductFailure(run));
   Assert.That(run.Checks.Single(c=>c.id=="D3_LOCALITY").status,Is.EqualTo("PASS"));
   Assert.That(run.Checks.Single(c=>c.id=="D2_PRODUCTION").status,Is.EqualTo("BLOCKED_BY_PRODUCT"));
   Assert.That(run.Facts.actions.Any(a=>a.Contains("runtime-scope.cleaned")),Is.True);
  }
  IEnumerator EvaluatorFailure(){var scene=Scene();Root(scene,true,true);yield return null;throw new InvalidOperationException("fixture evaluator bug must remain inconclusive");}
  [UnityTest,Order(5)] public IEnumerator T05_OrdinaryEvaluatorExceptionIsNotSuppressed()
  {
   var run=Run();Exception failure=null;yield return Catch(run.Execute(new[]{"D2_PRODUCTION"},EvaluatorFailure()),e=>failure=e);
   Assert.That(failure,Is.TypeOf<AssertionException>());Assert.That(run.Checks.Single().status,Is.EqualTo("INCONCLUSIVE_EVALUATOR"));
   Assert.That(run.Facts.exception,Does.Contain("fixture evaluator bug"));Assert.That(Resources.FindObjectsOfTypeAll<StormboundQualificationProduct.Callbacks>().Length,Is.Zero);
  }
  IEnumerator EvaluatorErrorLog(StormboundRun run){Debug.LogError("fixture evaluator-origin error");run.Check("D1_SESSION_ENTRY",true,"fixture action","complete");yield break;}
  [UnityTest,Order(6)] public IEnumerator T06_EvaluatorOriginLogErrorIsNotWhitelisted()
  {
   var run=Run();Exception failure=null;yield return Catch(run.Execute(new[]{"D1_SESSION_ENTRY"},EvaluatorErrorLog(run)),e=>failure=e);
   Assert.That(run.Facts.evaluator_logged_error,Is.True);Assert.That(failure,Is.TypeOf<AssertionException>());
  }
  GameObject dirty;
  IEnumerator Dirty(StormboundRun run){var scene=Scene();dirty=Root(scene,false,true);dirty.GetComponent<StormboundQualificationProduct.Callbacks>().dirtyDay=2;run.Facts.actions.Add("fixture dirty day=2");yield return null;run.Check("D1_SESSION_ENTRY",true,"dirty receipt written","2");}
  [UnityTest,Order(99)] public IEnumerator T99_DirtyClose()
  {
   var policy=LogAssert.ignoreFailingMessages;var run=Run();yield return run.Execute(new[]{"D1_SESSION_ENTRY"},Dirty(run));
   Assert.That(dirty,Is.Not.Null);Assert.That(dirty.GetComponent<StormboundQualificationProduct.Callbacks>().dirtyDay,Is.EqualTo(2));
   Assert.That(run.Facts.actions.Any(a=>a.Contains("preserve-dirty-close")),Is.True);Assert.That(run.Facts.actions.Any(a=>a.Contains("runtime-scope.cleaned")),Is.False);
   Assert.That(File.Exists(Environment.GetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE")),Is.True);Assert.That(LogAssert.ignoreFailingMessages,Is.EqualTo(policy));
  }
 }
}
namespace StormboundQualificationProduct
{
 public sealed class Callbacks:MonoBehaviour
 {
  public bool emit,respawn;public int dirtyDay;
  void Update(){if(emit)Debug.LogError("fixture candidate Update error");}
  void LateUpdate(){if(emit)Debug.LogError("fixture animation-like callback has no receiver");}
  void OnDestroy(){if(respawn){var next=new GameObject("candidate OnDestroy new DDOL");Object.DontDestroyOnLoad(next);next.AddComponent<Callbacks>();}}
 }
}
