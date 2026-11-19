using System;
using System.Collections;
using System.Linq;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.NoirRoombreak.Evaluator
{
 public sealed class FreshLifecycleTests
 {
  const string ScenePath="Assets/NoirChallenge/Scenes/NoirRoombreak.unity";
  [UnityTest]public IEnumerator FRESH01_NewProcessStartsAtCleanMenu()
  {
   LogAssert.ignoreFailingMessages=true;EvidenceStore.Initialize("fresh","New Unity process; normal Input System pointer/Enter starts reopened run");EvidenceStore.BeginTrajectory("FRESH01","FRESH01_NewProcessStartsAtCleanMenu","");EvidenceStore.Check("D4_REOPEN","D4",3.5f,false,"different PID opens clean menu and clean Room 1","not observed","REOPEN-01");
   if(!Application.CanStreamedLevelBeLoaded(ScenePath)){EvidenceStore.EndTrajectory("FRESH01","candidate-entry-missing","");LogAssert.ignoreFailingMessages=false;yield break;}AsyncOperation op=null;try{op=SceneManager.LoadSceneAsync(ScenePath,LoadSceneMode.Single);}catch{EvidenceStore.EndTrajectory("FRESH01","candidate-entry-load-failed","");LogAssert.ignoreFailingMessages=false;yield break;}var until=Time.realtimeSinceStartup+15;while(op!=null&&!op.isDone&&Time.realtimeSinceStartup<until)yield return null;yield return null;yield return null;
   var probes=UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).OfType<INoirRoombreakProbe>().ToArray();var probe=probes.FirstOrDefault();var prior=ReadInt("NOIR_ROOMBREAK_PRIOR_PROCESS_ID");var current=System.Diagnostics.Process.GetCurrentProcess().Id;var distinct=prior>0&&current!=prior;
   var cleanMenu=probe!=null&&probe.CurrentScreen==NoirScreen.Menu&&probe.CurrentRoomIndex==-1&&probe.RoomCount==5&&probe.Bonds==3&&probe.MaximumBonds==3&&probe.DashCharges==probe.MaximumDashCharges&&probe.DefeatedEnemyCount==0&&probe.SoftRespawnCount==0&&probe.GlobalRespawnCount==0&&probe.LastRespawnKind==NoirRespawnKind.None;
   var input=new VirtualInputDriver();if(probe!=null){var rect=probe.StartButtonScreenRect;if(rect.width>=20&&rect.height>=20)yield return input.Click(rect.center);until=Time.realtimeSinceStartup+2;while(probe.CurrentScreen==NoirScreen.Menu&&Time.realtimeSinceStartup<until)yield return null;if(probe.CurrentScreen==NoirScreen.Menu)yield return input.Press(UnityEngine.InputSystem.Key.Enter);until=Time.realtimeSinceStartup+3;while(probe.CurrentScreen!=NoirScreen.Playing&&Time.realtimeSinceStartup<until)yield return null;}var cleanActive=probe!=null&&probe.CurrentScreen==NoirScreen.Playing&&probe.CurrentRoomIndex==0&&probe.Bonds==3&&probe.DashCharges==3&&probe.PlayerAlive&&probe.DefeatedEnemyCount==0&&probe.SoftRespawnCount==0&&probe.GlobalRespawnCount==0;yield return input.Dispose();
   var passed=distinct&&probes.Length>=1&&cleanMenu&&cleanActive;var observed=$"priorPid={prior};currentPid={current};distinct={distinct};probes={probes.Length};cleanMenu={cleanMenu};cleanActive={cleanActive}";EvidenceStore.Check("D4_REOPEN","D4",3.5f,passed,"different PID opens clean menu and clean Room 1",observed,"REOPEN-01");EvidenceStore.EndTrajectory("FRESH01",passed?"completed":"failed",probe==null?"":probe.StateSequence.ToString());LogAssert.ignoreFailingMessages=false;
  }
  static int ReadInt(string name)=>int.TryParse(Environment.GetEnvironmentVariable(name),out var value)?value:0;
 }
}

