using System;
using System.Collections;
using System.Linq;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace GameCreate.NoirRoombreak.Evaluator
{
 public sealed class FreshLifecycleTests
 {
  const string ScenePath="Assets/NoirChallenge/Scenes/NoirRoombreak.unity";
  [UnityTest]public IEnumerator FRESH01_NewProcessStartsAtCleanMenu()
  {
   LogAssert.ignoreFailingMessages=true;EvidenceStore.Initialize("fresh","New Unity process; normal Input System pointer/Enter starts reopened run");EvidenceStore.BeginTrajectory("FRESH01","FRESH01_NewProcessStartsAtCleanMenu","");EvidenceStore.Check("D4_REOPEN","D4",3f,false,"different PID opens clean menu and clean Room 1","not observed","REOPEN-01");
   if(!Application.CanStreamedLevelBeLoaded(ScenePath)){EvidenceStore.Classify("D4_REOPEN","BLOCKED_BY_PRODUCT","saved-entry","Required saved game entry is absent.");EvidenceStore.EndTrajectory("FRESH01","candidate-entry-missing","");LogAssert.ignoreFailingMessages=false;yield break;}AsyncOperation op=null;try{op=SceneManager.LoadSceneAsync(ScenePath,LoadSceneMode.Single);}catch{EvidenceStore.EndTrajectory("FRESH01","candidate-entry-load-failed","");LogAssert.ignoreFailingMessages=false;yield break;}var until=Time.realtimeSinceStartup+15;while(op!=null&&!op.isDone&&Time.realtimeSinceStartup<until)yield return null;yield return null;yield return null;
   var probes=UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).OfType<INoirRoombreakProbe>().ToArray();var probe=probes.FirstOrDefault();var prior=ReadInt("NOIR_ROOMBREAK_PRIOR_PROCESS_ID");var priorSession=Read("NOIR_ROOMBREAK_PRIOR_SESSION_ID");var dirtyMarker=Read("NOIR_ROOMBREAK_PRIOR_DIRTY_MARKER");var expectedMarker=$"TRAJ10|completed-dirty-close|session={priorSession}|process={prior}";var dirtyChain=prior>0&&!string.IsNullOrWhiteSpace(priorSession)&&dirtyMarker==expectedMarker;EvidenceStore.SetPriorLifecycle(prior,priorSession,dirtyMarker,dirtyChain);var current=System.Diagnostics.Process.GetCurrentProcess().Id;var distinct=prior>0&&current!=prior;
   var cleanMenu=probe!=null&&probe.CurrentScreen==NoirScreen.Menu&&probe.CurrentRoomIndex==-1&&probe.RoomCount==5&&probe.Bonds==3&&probe.MaximumBonds==3&&probe.DashCharges==probe.MaximumDashCharges&&probe.DefeatedEnemyCount==0&&probe.SoftRespawnCount==0&&probe.GlobalRespawnCount==0&&probe.LastRespawnKind==NoirRespawnKind.None;
   var input=new VirtualInputDriver();if(probe!=null){var rect=probe.StartButtonScreenRect;if(rect.width>=20&&rect.height>=20)yield return input.Click(rect.center);until=Time.realtimeSinceStartup+2;while(probe.CurrentScreen==NoirScreen.Menu&&Time.realtimeSinceStartup<until)yield return null;if(probe.CurrentScreen==NoirScreen.Menu&&TrySingleButtonRect(out var actualRect))yield return input.Click(actualRect.center);until=Time.realtimeSinceStartup+2;while(probe.CurrentScreen==NoirScreen.Menu&&Time.realtimeSinceStartup<until)yield return null;if(probe.CurrentScreen==NoirScreen.Menu)yield return input.Press(UnityEngine.InputSystem.Key.Enter);until=Time.realtimeSinceStartup+3;while(probe.CurrentScreen!=NoirScreen.Playing&&Time.realtimeSinceStartup<until)yield return null;}var cleanActive=probe!=null&&probe.CurrentScreen==NoirScreen.Playing&&probe.CurrentRoomIndex==0&&probe.Bonds==3&&probe.DashCharges==3&&probe.PlayerAlive&&probe.DefeatedEnemyCount==0&&probe.SoftRespawnCount==0&&probe.GlobalRespawnCount==0;yield return input.Dispose();
   var passed=dirtyChain&&distinct&&probes.Length>=1&&cleanMenu&&cleanActive;var observed=$"priorPid={prior};priorSession={priorSession};dirtyChain={dirtyChain};currentPid={current};distinct={distinct};probes={probes.Length};cleanMenu={cleanMenu};cleanActive={cleanActive}";EvidenceStore.Check("D4_REOPEN","D4",3f,passed,"validated dirty prior session in a different PID opens clean menu and clean Room 1",observed,"REOPEN-01");EvidenceStore.EndTrajectory("FRESH01",passed?"completed":"failed",priorSession);LogAssert.ignoreFailingMessages=false;
  }
  static int ReadInt(string name)=>int.TryParse(Environment.GetEnvironmentVariable(name),out var value)?value:0;
  static string Read(string name)=>Environment.GetEnvironmentVariable(name)??string.Empty;
  static bool TrySingleButtonRect(out Rect rect){rect=Rect.zero;Canvas.ForceUpdateCanvases();var buttons=UnityEngine.Object.FindObjectsByType<Button>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x&&x.isActiveAndEnabled&&x.interactable&&x.gameObject.activeInHierarchy&&x.GetComponentInParent<Canvas>() is Canvas canvas&&canvas.isActiveAndEnabled).ToArray();if(buttons.Length!=1)return false;var button=buttons[0];var canvas=button.GetComponentInParent<Canvas>();var transform=button.transform as RectTransform;if(transform==null)return false;var corners=new Vector3[4];transform.GetWorldCorners(corners);var camera=canvas.renderMode==RenderMode.ScreenSpaceOverlay?null:(canvas.worldCamera!=null?canvas.worldCamera:Camera.main);var a=RectTransformUtility.WorldToScreenPoint(camera,corners[0]);var b=RectTransformUtility.WorldToScreenPoint(camera,corners[2]);rect=Rect.MinMaxRect(Mathf.Min(a.x,b.x),Mathf.Min(a.y,b.y),Mathf.Max(a.x,b.x),Mathf.Max(a.y,b.y));return rect.width>=8&&rect.height>=8&&rect.center.x>=0&&rect.center.x<=Screen.width&&rect.center.y>=0&&rect.center.y<=Screen.height;}
 }
}

