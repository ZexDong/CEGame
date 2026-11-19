using System;
using System.Collections;
using System.Diagnostics;
using System.Linq;
using GameCreate.Session;
using GameCreate.Evaluation.Session;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.TestTools;
using static GameCreate.Undercooked.Evaluator.KitchenRun;
namespace GameCreate.Undercooked.Evaluator
{
 public sealed class FreshLifecycleTests
 {
  [UnityTest] public IEnumerator FRESH01_NewProcessStartsAtCleanMenu(){var r=new KitchenRun("fresh");return r.Execute(new[]{"D4_REOPEN"},Body(r));}
  IEnumerator Body(KitchenRun r)
  {
   if(!int.TryParse(Environment.GetEnvironmentVariable("KITCHEN_PRIOR_PROCESS_ID"),out var prior)||prior<=0||prior==Process.GetCurrentProcess().Id)throw new InvalidOperationException("New-process host PID binding missing");
   try{var alive=Process.GetProcessById(prior);if(!alive.HasExited)throw new InvalidOperationException("Previous game process is still alive");}catch(ArgumentException){}
   var dirty=Environment.GetEnvironmentVariable("KITCHEN_PRIOR_DIRTY_STATUS");if(dirty!="ready")throw new SessionProductFailure("restore:kitchen",Environment.GetEnvironmentVariable("KITCHEN_PRIOR_DIRTY_REASON")??"Independent dirty-close preparation was blocked");
   yield return r.Load();r.Find();var initial=r.Read();var clean=initial.phase=="menu"&&V(initial,"score")==0&&V(initial,"shift_remaining")==120&&V(initial,"active_chef")==1&&V(initial,"delivered_orders")==0&&V(initial,"expired_orders")==0;
   yield return r.Ready();yield return r.Tap(Key.Enter);yield return r.Wait(.15f);var active=r.Read();r.Observe("fresh-process-normal-start");var started=active.phase=="playing"&&V(active,"score")==0&&V(active,"shift_remaining")>=118&&active.actors.Count==9&&active.actors.Where(a=>a.kind=="chef").All(a=>V(a,"held_id")==0);
   r.Check("D4_REOPEN",clean&&started,"different process opens clean menu and normal start has no prior runtime state",$"old_pid={prior};new_pid={Process.GetCurrentProcess().Id};"+JsonUtility.ToJson(active));
  }
 }
}
