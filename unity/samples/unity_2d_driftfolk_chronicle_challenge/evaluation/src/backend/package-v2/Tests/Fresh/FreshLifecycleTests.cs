using System;
using System.Collections;
using System.Diagnostics;
using System.IO;
using GameCreate.Session;
using GameCreate.Evaluation.Session;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.TestTools;
using static GameCreate.Stormbound.Evaluator.StormboundRun;
namespace GameCreate.Stormbound.Evaluator
{
 public sealed class FreshLifecycleTests
 {
  [Serializable]sealed class Dirty{public int process_id;public string save_json;}
  [UnityTest]public IEnumerator FRESH01_ReopenAndExplicitLoad(){var r=new StormboundRun("fresh");return r.Execute(new[]{"D4_REOPEN"},Body(r));}
  IEnumerator Body(StormboundRun r){if(!int.TryParse(Environment.GetEnvironmentVariable("STORMBOUND_PRIOR_PROCESS_ID"),out var prior)||prior<=0||prior==Process.GetCurrentProcess().Id)throw new InvalidOperationException("Missing distinct prior process binding");try{var process=Process.GetProcessById(prior);if(!process.HasExited)throw new InvalidOperationException("Prior player still running");}catch(ArgumentException){}
   if(Environment.GetEnvironmentVariable("STORMBOUND_PRIOR_DIRTY_STATUS")!="ready")throw new SessionProductFailure("state_restore","Independent dirty-state save preparation was blocked");
   var dirtyPath=Path.Combine(Path.GetDirectoryName(Environment.GetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE")),"dirty-close.json");var dirty=JsonUtility.FromJson<Dirty>(File.ReadAllText(dirtyPath));if(dirty.process_id!=prior)throw new InvalidOperationException("Dirty receipt PID mismatch");var saved=JsonUtility.FromJson<SessionSave>(dirty.save_json);
   yield return r.Load();r.Find();var initial=r.Read();bool lobby=initial.phase=="menu"&&V(initial,"day")==1&&V(initial,"pressure")==0;r.Observe("new-process-lobby");yield return r.Ready();yield return r.Tap(Key.F9);var loaded=r.Read();bool restored=Same(saved,loaded);r.Observe("explicit-disk-load-new-process");yield return r.Step();var continued=r.Read();bool continuity=V(continued,"day")==2&&V(continued,"period")==1&&V(A(continued,"ferry"),"remaining")==1&&V(A(continued,"resident-1"),"island")==0;yield return r.Tap(Key.R);var clean=r.Read();r.Observe("fresh-normal-restart");r.Check("D4_REOPEN",lobby&&restored&&continuity&&clean.phase=="playing"&&V(clean,"day")==1&&V(clean,"pressure")==0&&V(A(clean,"island-a"),"food")==30,"new process opens lobby, explicitly loads true prior disk slot, continues transit, and resets clean","prior="+prior+";current="+Process.GetCurrentProcess().Id+";restored="+restored+";continued="+JsonUtility.ToJson(continued));}
 }
}
