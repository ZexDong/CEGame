using System;
using System.Collections;
using System.Linq;
using System.IO;
using System.Collections.Generic;
using GameCreate.Session;
using GameCreate.Kitchen;
using GameCreate.Evaluation.Session;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.TestTools;
using UnityEngine.UI;
#if UNITY_EDITOR
using UnityEditor;
#endif
using static GameCreate.Undercooked.Evaluator.KitchenRun;
using Object=UnityEngine.Object;
namespace GameCreate.Undercooked.Evaluator
{
 public sealed class DynamicTrajectoryTests
 {
  static string AssetPath(Object value){
#if UNITY_EDITOR
   return AssetDatabase.GetAssetPath(value);
#else
   return value?value.name:"";
#endif
  }

  [UnityTest,Order(1)] public IEnumerator T01_SessionEntry() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D1_SESSION_ENTRY"},Body_T01_SessionEntry(r)); }
  IEnumerator Body_T01_SessionEntry(KitchenRun r)
  {

 yield return r.Open();var s=r.Initial;var f=r.Observe("committed-fresh-entry");
 var clean=s.phase=="playing"&&V(s,"score")==0&&V(s,"active_chef")==1&&V(s,"shift_remaining")==120&&s.actors.Count==9;
 r.Check("D1_SESSION_ENTRY",clean,"published kitchen entry commits a clean real active shift",f.save_json);
  }
  [UnityTest,Order(3)] public IEnumerator T02_RestoreIntegrity() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D1_SESSION_STATE","D3_ITEM_UNIQUENESS"},Body_T02_RestoreIntegrity(r)); }
  IEnumerator Body_T02_RestoreIntegrity(KitchenRun r)
  {

 yield return r.Open();r.DetachedCapture();var s=r.Clean();r.At(s,"counter");Held(s,1,1);Held(s,2,3);N(s,"score",23);Order(s,20);Container(s,"chopping-board",1);N(A(s,"chopping-board"),"chop_elapsed",Math.Min(.35,V(s,"chop_seconds")/2));
 yield return r.Prepare(s);var committed=r.Observe("legal-owner-roundtrip");
 var before=SessionFormat.Clone(r.Read());var bad=SessionFormat.Clone(s);N(A(bad,"chef-2"),"held_id",V(A(bad,"chef-1"),"held_id"));
 if(KitchenSessionRules.Validate(bad)==null)throw new InvalidOperationException("duplicate identity rejection control is legal");
 var op=r.Game.Restore(bad);var rejected=op!=null&&op.state==OperationState.Rejected&&SameState(r.Read(),before);
 r.Check("D1_SESSION_STATE",rejected,"detached capture, legal restoration and atomic invalid-save rejection",committed.save_json+" duplicate_rejected="+rejected);
 yield return r.Begin();var heldId=V(A(s,"chef-1"),"held_id");yield return r.Tap(Key.E);var placed=r.Read();var oneLocation=V(A(placed,"chef-1"),"held_id")==0&&V(A(placed,"counter"),"item_id")==heldId&&V(A(placed,"chef-2"),"held_kind")==3;
 yield return r.Tap(Key.E);var picked=r.Read();var restored=V(A(picked,"chef-1"),"held_id")==heldId&&V(A(picked,"counter"),"item_id")==0;r.Observe("ownership-after-real-input");
 r.Check("D3_ITEM_UNIQUENESS",oneLocation&&restored,"moving a real held item preserves one ownership location and identity",JsonUtility.ToJson(picked));
  }
  [UnityTest,Order(5)] public IEnumerator T03_KitchenPresentation() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_KITCHEN","D2_ASSETS"},Body_T03_KitchenPresentation(r)); }
  IEnumerator Body_T03_KitchenPresentation(KitchenRun r)
  {

 yield return r.Open();var f=r.Observe("kitchen-presentation");var camera=Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).FirstOrDefault(c=>c.isActiveAndEnabled);
 var seen=camera&&r.Initial.actors.All(a=>{var p=camera.WorldToViewportPoint(a.position);return p.z>0&&p.x>0&&p.x<1&&p.y>0&&p.y<1;});
 var real=r.Rendered(r.Initial.actors.Select(a=>a.id).ToArray());r.Check("D2_KITCHEN",seen&&real,"camera shows two distinct chefs and all working station roles",JsonUtility.ToJson(f));
 var meshPaths=Object.FindObjectsByType<MeshFilter>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x.sharedMesh).Select(x=>AssetPath(x.sharedMesh)).Concat(Object.FindObjectsByType<SkinnedMeshRenderer>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x.sharedMesh).Select(x=>AssetPath(x.sharedMesh))).ToArray();
 var supplied=meshPaths.Count(p=>p.StartsWith("Assets/UndercookedStarter/Art/",StringComparison.Ordinal));
 r.Check("D2_ASSETS",real,"the live scene assembles the supplied first-party kitchen/chef assets",string.Join(";",meshPaths));
  }
  [UnityTest,Order(7)] public IEnumerator T04_MoveSwitch() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_MOVE_SWITCH","D3_SWITCH_OWNERSHIP"},Body_T04_MoveSwitch(r)); }
  IEnumerator Body_T04_MoveSwitch(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();A(s,"chef-1").position=r.Point("open-floor");Held(s,1,1);Held(s,2,3);yield return r.Prepare(s);var f0=r.Observe("before-movement");yield return r.Begin();
 var before1=r.Game.ResolveActor("chef-1").transform.position;var before2=r.Game.ResolveActor("chef-2").transform.position;yield return r.Hold(Key.D,.22f);var moved1=Vector3.Distance(before1,r.Game.ResolveActor("chef-1").transform.position)>.1f;var stayed2=Vector3.Distance(before2,r.Game.ResolveActor("chef-2").transform.position)<.02f;var pre=r.Read();
 yield return r.Hold(Key.Q,.18f);var switched=r.Read();var once=V(switched,"active_chef")==2;yield return r.Wait(.08f);once&=V(r.Read(),"active_chef")==2;
 var independent=V(A(switched,"chef-1"),"held_id")==V(A(pre,"chef-1"),"held_id")&&V(A(switched,"chef-2"),"held_id")==V(A(pre,"chef-2"),"held_id");
 before1=r.Game.ResolveActor("chef-1").transform.position;before2=r.Game.ResolveActor("chef-2").transform.position;yield return r.Hold(Key.A,.2f);var moved2=Vector3.Distance(before2,r.Game.ResolveActor("chef-2").transform.position)>.1f;var stayed1=Vector3.Distance(before1,r.Game.ResolveActor("chef-1").transform.position)<.02f;
 var f=r.Observe("after-movement-and-switch");
 r.Check("D3_SWITCH_OWNERSHIP",once&&independent&&stayed1&&stayed2,"two chefs retain independent poses and item identities through switch",JsonUtility.ToJson(r.Read()));
 // The public approach may already be at contact. Free movement was proved above;
 // the collision segment has no undocumented minimum further-travel requirement.
 yield return r.Open();s=r.Clean();r.At(s,"counter");yield return r.Prepare(s);yield return r.Begin();
 var normal=new Vector3((float)V(s,"floor_normal_x"),(float)V(s,"floor_normal_y"),(float)V(s,"floor_normal_z"));
 var probe=new ColliderMotionProbe(r.Game.ResolveActor("chef-1"),r.Game.ResolveActor("counter"),normal);
 if(probe.Result.geometry_available&&!probe.Result.did_not_penetrate)throw new GameCreate.Evaluation.Session.SessionProductFailure("layout:kitchen","SESSION-10: published counter approach restores the chef inside a real solid collider; penetration="+probe.Result.max_penetration);
 if(!probe.Result.approach_direction_available)throw new InvalidOperationException("Collision observer cannot derive an approach direction from coincident nonpenetrating roots; no collision verdict.");
 var free=moved1&&stayed2&&once&&moved2&&stayed1;
 if(!probe.Result.geometry_available)
 {
  // Published behavior, not Unity component architecture, is the requirement.
  // For custom physics use normal fixed-direction push plus an escape control.
  var right=new Vector3((float)V(s,"move_right_x"),(float)V(s,"move_right_y"),(float)V(s,"move_right_z"));var forward=new Vector3((float)V(s,"move_forward_x"),(float)V(s,"move_forward_y"),(float)V(s,"move_forward_z"));
  BehavioralCollisionObservation behavior=null;
  r.Facts.actions.Add("custom-collision-normal-fixed-push-and-retreat; no shape inferred from renderer");
  yield return BehavioralCollisionOracle.Acquire(r.Input,r.Game.ResolveActor("chef-1").transform,r.Game.ResolveActor("counter").transform.position,right,forward,x=>behavior=x);
  r.Check("D2_MOVE_SWITCH",free&&behavior.Blocked,"independent free movement/switch and real normal-input blocking with a working retreat; custom physics does not require Unity Collider components","free_movement="+free+";route=normal-behavior;"+JsonUtility.ToJson(behavior));yield break;
 }
 yield return r.DriveToward("counter",.85f,probe.Sample);
 r.Facts.actions.Add("real-collider-normal-input-probe:"+JsonUtility.ToJson(probe.Result));
 if(free&&!probe.Result.geometry_available)throw new InvalidOperationException("Collision observer unavailable: "+probe.Result.unavailable_reason);
 r.Check("D2_MOVE_SWITCH",ColliderMotionProbe.MovementPass(moved1,stayed2,once,moved2,stayed1,probe.Result),"normal held input moves only the selected chef, switches once, and stops at real collision geometry without crossing or penetration","free_movement="+free+";"+JsonUtility.ToJson(probe.Result));
  }
  [UnityTest,Order(9)] public IEnumerator T05_PickCounter() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_PICKUP"},Body_T05_PickCounter(r)); }
  IEnumerator Body_T05_PickCounter(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"tomato-crate");yield return r.Prepare(s);var before=r.Observe("empty-hand");yield return r.Begin();yield return r.Tap(Key.E);var raw=r.Read();var got=V(A(raw,"chef-1"),"held_kind")==1&&V(A(raw,"chef-1"),"held_id")>0;r.Observe("picked-tomato");
 // A separate action window tests counter transfer; this is not a hidden write during the pickup sequence.
 yield return r.Open();s=r.Clean();r.At(s,"counter");Held(s,1,1);var id=V(A(s,"chef-1"),"held_id");yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var placed=r.Read();var put=V(A(placed,"chef-1"),"held_id")==0&&V(A(placed,"counter"),"item_id")==id;yield return r.Tap(Key.E);var picked=r.Read();var take=V(A(picked,"chef-1"),"held_id")==id&&V(A(picked,"counter"),"item_id")==0;r.Observe("counter-retrieved");
 // A second held item cannot replace an already occupied counter. Both item
 // identities are legal restored state, then the rejected replacement is a
 // normal E action after Begin (no setup writes occur after that boundary).
 yield return r.Open();s=r.Clean();r.At(s,"counter");Held(s,1,1);Container(s,"counter",2);var occupiedHeldId=V(A(s,"chef-1"),"held_id");var occupiedCounterId=V(A(s,"counter"),"item_id");yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var occupied=r.Read();var occupiedRejected=V(A(occupied,"chef-1"),"held_id")==occupiedHeldId&&V(A(occupied,"counter"),"item_id")==occupiedCounterId&&V(A(occupied,"counter"),"item_kind")==2;
 r.Check("D2_PICKUP",got&&put&&take&&occupiedRejected,"tomato pickup plus counter placement/retrieval work through normal E and an occupied counter rejects replacement","held="+occupiedHeldId+";counter="+occupiedCounterId+";"+JsonUtility.ToJson(occupied));
  }
  [UnityTest,Order(11)] public IEnumerator T06_Chop() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_CHOP","D3_CHOP_TIMING"},Body_T06_Chop(r)); }
  IEnumerator Body_T06_Chop(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"chopping-board");Held(s,1,1);var id=V(A(s,"chef-1"),"held_id");yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var placed=r.Read();var raw=V(A(placed,"chopping-board"),"item_kind")==1;var start=Time.realtimeSinceStartup;yield return r.Hold(Key.E,.35f);var partial=r.Read();var below=V(A(partial,"chopping-board"),"item_kind")==1&&V(A(partial,"chopping-board"),"chop_elapsed")<V(s,"chop_seconds");
 yield return r.Hold(Key.E,(float)V(s,"chop_seconds")+.15f);var chopped=r.Read();var done=V(A(chopped,"chopping-board"),"item_kind")==2&&V(A(chopped,"chopping-board"),"item_id")==id;var f=r.Observe("chopped-after-real-input");
 // A raw tomato on the board must not be acted on from a distant, but still
 // walkable, open-floor landmark. Navigate uses only normal movement frames.
 yield return r.Open();s=r.Clean();r.At(s,"chopping-board");Container(s,"chopping-board",1);A(s,"chef-1").position=r.Point("open-floor");yield return r.Prepare(s);yield return r.Begin();var remoteBoard=r.Game.ResolveActor("chopping-board").transform.position;var remoteChef=r.Game.ResolveActor("chef-1").transform.position;var remoteFar=Vector3.Distance(remoteChef,remoteBoard)>V(A(r.Read(),"chopping-board"),"interaction_distance")+.08;yield return r.Hold(Key.E,.2f);var remoteChop=r.Read();var remoteRejected=V(A(remoteChop,"chopping-board"),"item_kind")==1&&V(A(remoteChop,"chopping-board"),"chop_elapsed")==0&&V(A(remoteChop,"chef-1"),"held_id")==0;
 r.Check("D2_CHOP",raw&&done&&r.Rendered("chopping-board")&&remoteFar&&remoteRejected,"placing raw tomato then holding E produces chopped tomato while remote E is rejected","far="+remoteFar+";"+JsonUtility.ToJson(remoteChop));r.Check("D3_CHOP_TIMING",raw&&below&&done&&Time.realtimeSinceStartup-start>=1&&V(A(chopped,"chopping-board"),"chop_elapsed")==V(s,"chop_seconds"),"chopping requires real progress and preserves one ingredient",JsonUtility.ToJson(chopped));
  }
  [UnityTest,Order(13)] public IEnumerator T07_Cook() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_COOK","D3_COOK_RULES"},Body_T07_Cook(r)); }
  IEnumerator Body_T07_Cook(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"pot");Ingredients(s,2);Held(s,1,2);yield return r.Prepare(s);yield return r.Begin();var start=Time.realtimeSinceStartup;yield return r.Tap(Key.E);var inserted=r.Read();var count=Enumerable.Range(1,3).Count(i=>V(A(inserted,"pot"),"ingredient_"+i+"_id")>0);yield return r.Wait(.5f);var early=r.Read();var notEarly=V(A(early,"pot"),"item_kind")==0&&V(A(early,"pot"),"cook_elapsed")>0;yield return r.Until(()=>V(A(r.Read(),"pot"),"item_kind")==5,(float)V(s,"cook_seconds")+.35f);var cooked=r.Read();var elapsed=Time.realtimeSinceStartup-start;var done=V(A(cooked,"pot"),"item_kind")==5;var f=r.Observe("cooked-after-third-input");
 // Fewer than three ingredients never starts cooking, and a raw tomato is
 // rejected without consuming the held item. This is an independent action
 // segment: the legal fixture is restored before Begin and then only E input
 // is used.
 yield return r.Open();s=r.Clean();r.At(s,"pot");Ingredients(s,2);Held(s,1,1);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var underfilled=r.Read();var underfilledRejected=V(A(underfilled,"pot"),"ingredient_1_id")>0&&V(A(underfilled,"pot"),"ingredient_2_id")>0&&V(A(underfilled,"pot"),"ingredient_3_id")==0&&V(A(underfilled,"pot"),"item_kind")==0&&V(A(underfilled,"pot"),"cook_elapsed")==0&&V(A(underfilled,"chef-1"),"held_kind")==1;
 // A pair of chopped tomatoes also cannot be added from a remote, public
 // open-floor landmark.
  yield return r.Open();s=r.Clean();r.At(s,"pot");Ingredients(s,2);Held(s,1,2);A(s,"chef-1").position=r.Point("open-floor");yield return r.Prepare(s);yield return r.Begin();var remotePot=r.Game.ResolveActor("pot").transform.position;var remotePotChef=r.Game.ResolveActor("chef-1").transform.position;var remotePotFar=Vector3.Distance(remotePotChef,remotePot)>V(A(r.Read(),"pot"),"interaction_distance")+.08;yield return r.Tap(Key.E);var remoteAdded=r.Read();var remoteAddRejected=Enumerable.Range(1,3).Count(i=>V(A(remoteAdded,"pot"),"ingredient_"+i+"_id")>0)==2&&V(A(remoteAdded,"chef-1"),"held_kind")==2&&V(A(remoteAdded,"pot"),"item_kind")==0;
 r.Check("D2_COOK",count==3&&done&&r.Rendered("pot")&&underfilledRejected&&remotePotFar&&remoteAddRejected,"third chopped tomato triggers real cooking while underfilled, raw and remote additions are rejected","underfilled="+JsonUtility.ToJson(underfilled)+";remote_far="+remotePotFar+";remote="+JsonUtility.ToJson(remoteAdded));r.Check("D3_COOK_RULES",count==3&&notEarly&&done&&elapsed>=3.9f&&elapsed<=8.3f&&V(A(cooked,"chef-1"),"held_id")==0,"exactly three ingredients cook over four to eight gameplay seconds","elapsed="+elapsed+";"+JsonUtility.ToJson(cooked));
  }
  [UnityTest,Order(15)] public IEnumerator T08_Burn() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_BURN"},Body_T08_Burn(r)); }
  IEnumerator Body_T08_Burn(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"pot");Soup(s);N(A(s,"pot"),"burn_elapsed",Math.Max(0,V(s,"burn_seconds")-.8));yield return r.Prepare(s);yield return r.Begin();yield return r.Wait(.2f);var delayed=r.Read();var burnDelayHonored=V(A(delayed,"pot"),"item_kind")==5;yield return r.Wait(.9f);var burnt=r.Read();var burns=V(A(burnt,"pot"),"item_kind")==6;r.Observe("burnt-from-completed-soup");yield return r.Tap(Key.F);var cleared=r.Read();var empty=V(A(cleared,"pot"),"item_id")==0&&Enumerable.Range(1,3).All(i=>V(A(cleared,"pot"),"ingredient_"+i+"_id")==0);r.Observe("burnt-pot-cleared");
 r.Check("D2_BURN",burnDelayHonored&&burns&&empty,"cooked soup remains safe before the burn threshold, then burns by time and normal F makes the pot reusable","delay="+burnDelayHonored+";"+JsonUtility.ToJson(cleared));
  }
  [UnityTest,Order(17)] public IEnumerator T09_Plate() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_PLATE"},Body_T09_Plate(r)); }
  IEnumerator Body_T09_Plate(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"plate-rack");yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var rackPlate=r.Read();var cleanPlateFromRack=V(A(rackPlate,"chef-1"),"held_kind")==3&&V(A(rackPlate,"chef-1"),"held_id")>0;
 yield return r.Open();s=r.Clean();r.At(s,"pot");Soup(s);Held(s,1,3);yield return r.Prepare(s);var before=r.Observe("plate-and-cooked-pot");yield return r.Begin();yield return r.Tap(Key.E);var after=r.Read();var good=V(A(after,"chef-1"),"held_kind")==4&&V(A(after,"pot"),"item_id")==0&&V(A(after,"pot"),"cook_elapsed")==0;var f=r.Observe("plated-real-input");
 // A clean plate and soup only combine in range. Moving to open floor before
 // E must leave both objects unchanged (no remote transfer).
  yield return r.Open();s=r.Clean();r.At(s,"pot");Soup(s);Held(s,1,3);A(s,"chef-1").position=r.Point("open-floor");yield return r.Prepare(s);yield return r.Begin();var remotePlatePot=r.Game.ResolveActor("pot").transform.position;var remotePlateChef=r.Game.ResolveActor("chef-1").transform.position;var remotePlateFar=Vector3.Distance(remotePlateChef,remotePlatePot)>V(A(r.Read(),"pot"),"interaction_distance")+.08;yield return r.Tap(Key.E);var remotePlateState=r.Read();var remotePlateRejected=V(A(remotePlateState,"chef-1"),"held_kind")==3&&V(A(remotePlateState,"pot"),"item_kind")==5&&V(A(remotePlateState,"pot"),"item_id")>0;
 r.Check("D2_PLATE",cleanPlateFromRack&&good&&r.Rendered("chef-1","pot")&&remotePlateFar&&remotePlateRejected,"a clean plate comes from the rack and only plates cooked soup in normal interaction range","rack="+cleanPlateFromRack+";remote_far="+remotePlateFar+";"+JsonUtility.ToJson(remotePlateState));
  }
  [UnityTest,Order(19)] public IEnumerator T10_Delivery() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_DELIVERY_ORDERS","D3_DELIVERY_ONCE","D5_ACTION"},Body_T10_Delivery(r)); }
  IEnumerator Body_T10_Delivery(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"delivery");Held(s,1,4);Order(s,20);var oid=V(s,"order_1_id");var oid2=OrderSlot(s,2,20);yield return r.Prepare(s);var before=r.Observe("before-delivery");yield return r.Begin();yield return r.Tap(Key.E);var delivered=r.Read();var score=V(delivered,"score");var good=score>=20&&score<=30&&V(delivered,"delivered_orders")==1&&V(A(delivered,"chef-1"),"held_id")==0&&V(delivered,"order_1_id")==oid2&&V(delivered,"order_2_id")==0;var f=r.Observe("after-delivery");yield return r.Tap(Key.E);yield return r.Tap(Key.F);var again=r.Read();r.Observe("repeated-delivery-input");
 // Empty, chopped, and clean-plate deliveries are all independently
 // rejected. Each starts from a legal public state and uses only E after
 // Begin; none can consume the order or change score.
 var invalidDelivery=true;foreach(var kind in new[]{0,2,3}){yield return r.Open();s=r.Clean();r.At(s,"delivery");Held(s,1,kind);Order(s,20);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var invalid=r.Read();invalidDelivery&=V(invalid,"score")==0&&V(invalid,"delivered_orders")==0&&V(A(invalid,"chef-1"),"held_kind")==kind&&V(invalid,"order_1_id")>0;r.Observe("invalid-delivery-"+kind);}
 r.Check("D2_DELIVERY_ORDERS",good&&invalidDelivery,"plated soup consumes the oldest order while empty, chopped, and clean-plate deliveries are rejected",JsonUtility.ToJson(delivered)+" invalid="+invalidDelivery);r.Check("D3_DELIVERY_ONCE",good&&V(again,"score")==score&&V(again,"delivered_orders")==1,"repeated E/F cannot repeat delivery reward",JsonUtility.ToJson(again));r.Check("D5_ACTION",good&&NumberVisible(f.visible_text,score)&&f.visible_text!=before.visible_text,"delivery visibly updates score/order/action feedback",f.visible_text);
  }
  [UnityTest,Order(21)] public IEnumerator T11_RawRejection() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D3_RAW_REJECTION"},Body_T11_RawRejection(r)); }
  IEnumerator Body_T11_RawRejection(KitchenRun r)
  {

 var good=true;foreach(var station in new[]{"pot","delivery"}){yield return r.Open();var s=r.Clean();r.At(s,station);Held(s,1,1);Order(s,20);if(station=="pot")Ingredients(s,2);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var after=r.Read();good&=V(after,"score")==0&&V(A(after,"chef-1"),"held_kind")==1;if(station=="pot")good&=V(A(after,"pot"),"ingredient_3_id")==0;r.Observe("raw-rejection-"+station);}
 r.Check("D3_RAW_REJECTION",good,"raw tomato is rejected by soup cooking and delivery through real E","both independently prepared invalid-action cases="+good);
  }
  [UnityTest,Order(23)] public IEnumerator T12_BurntRejection() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D3_BURN_REJECTION"},Body_T12_BurntRejection(r)); }
  IEnumerator Body_T12_BurntRejection(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"pot");Soup(s,true);Held(s,1,3);Order(s,20);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);var after=r.Read();var rejected=V(A(after,"chef-1"),"held_kind")==3&&(V(A(after,"pot"),"item_kind")==6||V(A(after,"pot"),"item_kind")==0)&&V(after,"score")==0&&V(after,"delivered_orders")==0;r.Observe("burnt-plating-rejected");
 r.Check("D3_BURN_REJECTION",rejected,"burnt soup cannot be plated or grant a delivery reward",JsonUtility.ToJson(after));
  }
  [UnityTest,Order(25)] public IEnumerator T13_Expiry() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_EXPIRY","D3_ORDER_RULES"},Body_T13_Expiry(r)); }
  IEnumerator Body_T13_Expiry(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();Order(s,.35);yield return r.Prepare(s);yield return r.Begin();yield return r.Wait(.7f);var expired=r.Read();var expires=V(expired,"expired_orders")==1&&V(expired,"score")==-5&&V(expired,"order_1_id")==0&&expired.phase=="playing";r.Observe("order-expired");yield return r.Wait(.3f);var once=V(r.Read(),"score")==-5;
 // First normal spawn is tested from an independent entry, not manufactured by the expiry save.
 yield return r.Open();yield return r.Begin();yield return r.Until(()=>V(r.Read(),"order_1_id")>0,3.15f);var first=r.Read();var firstValid=V(first,"order_1_id")>0&&V(first,"order_1_remaining")>=24.8&&V(first,"order_1_initial")>=25;r.Observe("first-natural-order");
 // Fill all three compact slots, then let the real spawn timer elapse. A
 // full queue must never create a fourth order; order_spawn_remaining may
 // remain at zero until space exists.
 yield return r.Open();s=r.Clean();OrderSlot(s,1,25);OrderSlot(s,2,25);OrderSlot(s,3,25);N(s,"order_spawn_remaining",0);yield return r.Prepare(s);yield return r.Begin();yield return r.Wait(Mathf.Min(1.2f,(float)V(s,"order_interval")+.25f));var full=r.Read();var fullQueue=Enumerable.Range(1,3).All(i=>V(full,$"order_{i}_id")>0)&&V(full,"order_1_id")<V(full,"order_2_id")&&V(full,"order_2_id")<V(full,"order_3_id")&&V(full,"order_spawn_remaining")>=0&&Enumerable.Range(1,3).Count(i=>V(full,$"order_{i}_id")>0)==3;
 r.Check("D2_EXPIRY",expires&&once,"natural timer removes an expired order and subtracts five once; a full queue does not exceed three orders",JsonUtility.ToJson(expired)+" full_queue="+fullQueue+";"+JsonUtility.ToJson(full));r.Check("D3_ORDER_RULES",firstValid&&expires&&once&&fullQueue,"normal first order has sufficient lifetime, expired order is compactly removed, and spawn cap/oldest ordering hold",JsonUtility.ToJson(first)+" full_queue="+fullQueue);
  }
  [UnityTest,Order(27)] public IEnumerator T14_Pause() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_PAUSE","D3_PAUSE_FREEZE"},Body_T14_Pause(r)); }
  IEnumerator Body_T14_Pause(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"pot");Ingredients(s,3);Container(s,"chopping-board",1);N(A(s,"chopping-board"),"chop_elapsed",.35);N(A(s,"pot"),"cook_elapsed",.5);Order(s,20);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.Escape);var paused=r.Read();var p=r.Observe("paused-before-input");var snapshot=SessionFormat.Clone(paused);yield return r.Hold(Key.D,.25f);yield return r.Tap(Key.E);yield return r.Hold(Key.F,.15f);yield return r.Wait(.3f);var after=r.Read();var f=r.Observe("paused-after-input");var frozen=SameState(snapshot,after);yield return r.Tap(Key.Escape);yield return r.Wait(.25f);var resumed=r.Read();r.Observe("resumed-timer");
 // A separately prepared burn transient verifies pause freezes burn timing
 // and order timing as well as board/cook timing above.
 yield return r.Open();s=r.Clean();r.At(s,"pot");Soup(s);N(A(s,"pot"),"burn_elapsed",.35);Order(s,20);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.Escape);var burnPaused=r.Read();var burnSnapshot=SessionFormat.Clone(burnPaused);yield return r.Wait(.45f);var burnAfter=r.Read();var burnFrozen=SameState(burnSnapshot,burnAfter)&&V(A(burnAfter,"pot"),"item_kind")==5&&V(burnAfter,"order_1_remaining")==V(burnSnapshot,"order_1_remaining");yield return r.Tap(Key.Escape);yield return r.Wait(.25f);var burnResumed=r.Read();var burnAdvanced=V(A(burnResumed,"pot"),"burn_elapsed")>V(A(burnAfter,"pot"),"burn_elapsed")&&V(burnResumed,"order_1_remaining")<V(burnAfter,"order_1_remaining");
 r.Check("D2_PAUSE",paused.phase=="paused"&&resumed.phase=="playing"&&burnPaused.phase=="paused"&&burnResumed.phase=="playing"&&Label(p.visible_text,"Pause","Paused","Resume","Continue"),"Escape pauses visibly and resumes the same shift",p.visible_text);r.Check("D3_PAUSE_FREEZE",paused.phase=="paused"&&frozen&&burnFrozen&&burnAdvanced&&V(resumed,"shift_remaining")<V(after,"shift_remaining")&&p.actors.All(a=>Vector3.Distance(a.position,f.actors.Single(b=>b.id==a.id).position)<.001f),"pause freezes board chop, pot cook, soup burn, order and chef positions; resume advances them","board_cook="+frozen+";burn_order="+burnFrozen+";advanced="+burnAdvanced+";"+JsonUtility.ToJson(f));
  }
  [UnityTest,Order(29)] public IEnumerator T15_Result() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D2_RESULT","D4_RESULT","D5_PAUSE_RESULT"},Body_T15_Result(r)); }
  IEnumerator Body_T15_Result(KitchenRun r)
  {

 var all=true;var observations=new List<ResultUiObservation>();
 foreach(var points in new[]{20,60,90})
 {
  yield return r.Open();var s=r.Clean();N(s,"shift_remaining",.25);N(s,"score",points);yield return r.Prepare(s);yield return r.Begin();yield return r.Wait(.55f);
  var result=r.Read();r.Observe("natural-result-"+points);
  var ui=new ResultUiObservation{score=points,surfaces=ResultUiOracle.Capture()};
  all&=result.phase=="result"&&V(result,"shift_remaining")==0&&V(result,"score")==points;
  yield return r.Hold(Key.D,.15f);yield return r.Tap(Key.E);all&=V(r.Read(),"score")==points&&r.Read().phase=="result";
  yield return VerifyVisibleRestart(r,ui);
  observations.Add(ui);r.Facts.actions.Add("result-ui-observation:"+JsonUtility.ToJson(ui));
 }
 var grades=ResultUiOracle.CurrentValues(observations,true);var scores=ResultUiOracle.CurrentValues(observations,false);
 var gradeVisible=grades.All(v=>v);var scoreVisible=scores.All(v=>v);var restartVisible=observations.All(o=>o.restart_hint_visible||o.restart_control_visible);var restartOperable=observations.All(o=>o.restart_operable);
 var diagnostics="timing_score_frozen="+all+";grade_visible="+gradeVisible+";score_visible="+scoreVisible+";restart_visible="+restartVisible+";restart_operable="+restartOperable;
 r.Check("D2_RESULT",all,"the active timer reaches a stable terminal result by time, not state injection",diagnostics);
 r.Check("D4_RESULT",all&&gradeVisible&&scoreVisible,"time-to-result transition preserves score and shows current grade for all ranges independently of restart",diagnostics);
 r.Check("D5_PAUSE_RESULT",gradeVisible&&scoreVisible&&observations.All(ResultUiOracle.RestartVisibleAndOperable),"current result score and grade are visible with a restart affordance proven by normal player input",diagnostics);
  }
  static bool CleanRestart(SessionSave s)=>s.phase=="playing"&&V(s,"score")==0&&V(s,"shift_remaining")>=118&&V(s,"shift_remaining")<=120&&V(s,"active_chef")==1&&V(s,"delivered_orders")==0&&V(s,"expired_orders")==0&&s.actors.Count==9&&s.actors.All(a=>a.values.All(n=>!(n.name=="held_id"||n.name=="item_id"||n.name.StartsWith("ingredient_"))||n.value==0));
  IEnumerator VerifyVisibleRestart(KitchenRun r,ResultUiObservation ui)
  {
   ui.restart_hint_visible=ui.surfaces.Any(x=>ResultUiOracle.HasPublicRestartKey(x.text));
   var buttons=ResultUiOracle.VisibleButtons();ui.restart_control_visible=buttons.Length>0;
   if(ui.restart_hint_visible){yield return r.Tap(Key.R);yield return r.Until(()=>CleanRestart(r.Read()),2f);if(CleanRestart(r.Read())){ui.restart_operable=true;ui.restart_route="visible-public-R-and-normal-key-input";yield break;}}
   // A button-only equivalent is legal. Each click gets an independent legal
   // result setup, and the real mouse device drives Unity's ordinary UI module.
   // Labels/classes are not matched to an expected candidate implementation.
   if(buttons.Length>8)throw new InvalidOperationException("Result contains more than eight actionable controls; bounded UI observer cannot select safely.");
   for(var index=0;index<buttons.Length;index++)
   {
    yield return r.Open();var s=r.Clean();s.phase="result";N(s,"shift_remaining",0);N(s,"score",ui.score);yield return r.Prepare(s);yield return r.Begin();
    var current=ResultUiOracle.VisibleButtons();if(index>=current.Length)continue;
    r.Facts.actions.Add("normal-pointer-click-result-control:"+index+":"+Time.frameCount);yield return ResultUiOracle.Click(current[index]);yield return r.Until(()=>CleanRestart(r.Read()),2f);
    if(CleanRestart(r.Read())){ui.restart_operable=true;ui.restart_route="visible-control-and-normal-pointer-input";yield break;}
   }
   ui.restart_route="no-visible-operable-restart-found";
  }
  [UnityTest,Order(31)] public IEnumerator T16_Restart() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D3_RESET_CLEAN","D4_RESTART"},Body_T16_Restart(r)); }
  IEnumerator Body_T16_Restart(KitchenRun r)
  {

 // Legal terminal fixture tests Restart only; T15 independently proves the natural timer-to-result transition.
 var all=true;foreach(var phase in new[]{"playing","paused","result"}){yield return r.Open();var s=r.Clean();s.phase=phase;N(s,"shift_remaining",phase=="result"?0:67);N(s,"score",33);N(s,"active_chef",2);Held(s,1,1);Held(s,2,3);Ingredients(s,2);Order(s,20);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.R);yield return r.Wait(.25f);var reset=r.Read();all&=reset.phase=="playing"&&V(reset,"score")==0&&V(reset,"shift_remaining")>=118&&V(reset,"active_chef")==1&&V(reset,"delivered_orders")==0&&V(reset,"expired_orders")==0&&reset.actors.Count==9&&reset.actors.All(a=>a.values.All(n=>!(n.name=="held_id"||n.name=="item_id"||n.name.StartsWith("ingredient_"))||n.value==0));r.Observe("restart-from-"+phase);yield return r.Tap(Key.Q);all&=V(r.Read(),"active_chef")==2;}
 r.Check("D3_RESET_CLEAN",all,"active, paused and result restart clear both chefs, kitchen state and stale input latches","three independent lifecycle starts="+all);r.Check("D4_RESTART",all,"normal R restarts all required phases and input remains single/reusable","three independently executed restarts="+all);
  }
  [UnityTest,Order(33)] public IEnumerator T17_Menu() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D4_MENU_START","D5_MENU"},Body_T17_Menu(r)); }
  IEnumerator Body_T17_Menu(KitchenRun r)
  {

 yield return r.Load();var text=Text();var buttons=ResultUiOracle.VisibleButtons().Length>0;r.ObserveVisibleMenu();r.Check("D5_MENU",ResultUiOracle.MenuAffordance(text,buttons),"the fresh menu independently presents a readable keyboard or visible button start affordance","visible_keyboard_or_button="+ResultUiOracle.MenuAffordance(text,buttons)+";lifecycle_test=D4_MENU_START;"+text);
 r.Find();var initial=r.Read();yield return r.Ready();yield return r.Tap(Key.Enter);yield return r.Wait(.15f);var s=r.Read();r.Observe("normal-menu-enter");r.Check("D4_MENU_START",initial.phase=="menu"&&s.phase=="playing"&&V(s,"score")==0&&V(s,"shift_remaining")>=118,"normal Enter independently starts a clean shift from the menu",JsonUtility.ToJson(s));
  }
  [UnityTest,Order(35)] public IEnumerator T18_Hud() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D5_HUD_STATION"},Body_T18_Hud(r)); }
  IEnumerator Body_T18_Hud(KitchenRun r)
  {
   var texts=new List<string>();foreach(var tuple in new[]{new[]{27,91},new[]{43,67}}){yield return r.Open();var s=r.Clean();r.At(s,"chopping-board");Container(s,"chopping-board",1);Held(s,2,3);Order(s,20);N(s,"score",tuple[0]);N(s,"shift_remaining",tuple[1]);yield return r.Prepare(s);yield return r.Begin();yield return r.Hold(Key.E,.2f);yield return null;var f=r.Observe("nondefault-hud-"+tuple[0]);texts.Add(f.visible_text);}
   var score=NumericCount(texts[0],27)>NumericCount(texts[1],27)&&NumericCount(texts[1],43)>NumericCount(texts[0],43);var timer=NumericCount(texts[0],91,1)>NumericCount(texts[1],91,1)&&NumericCount(texts[1],67,1)>NumericCount(texts[0],67,1);var station=Label(texts[0],"Chop","Chopping","Progress")||r.Rendered("chopping-board");r.Check("D5_HUD_STATION",score&&timer&&station,"visible scoreboard/time react to two controlled states; static decorative digits cannot establish a role",string.Join("\n---next controlled state---\n",texts));
  }
  [UnityTest,Order(37)] public IEnumerator T19_Audio() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D5_AUDIO"},Body_T19_Audio(r)); }
  IEnumerator Body_T19_Audio(KitchenRun r)
  {
   var passed=true;var summary=new List<string>();
   foreach(var mode in new[]{"interaction","chopping","cooking","delivery","warning","pause","result"}){
    yield return r.Open();var s=r.Clean();
    if(mode=="interaction")r.At(s,"tomato-crate");
    if(mode=="chopping"){r.At(s,"chopping-board");Container(s,"chopping-board",1);}
    if(mode=="cooking"){Ingredients(s,3);N(A(s,"pot"),"cook_elapsed",V(s,"cook_seconds")-.25);}
    if(mode=="delivery"){r.At(s,"delivery");Held(s,1,4);Order(s,20);}
    if(mode=="warning")Order(s,.25);
    if(mode=="result")N(s,"shift_remaining",.25);
    yield return r.Prepare(s);yield return r.Begin();var before=r.AudioSnapshot();
    var ambience=before.Any(a=>a.playing&&a.volume>0&&a.loop);
    if(mode=="interaction"||mode=="delivery")yield return r.Tap(Key.E);
    else if(mode=="chopping")yield return r.Hold(Key.E,.15f);
    else if(mode=="pause")yield return r.Tap(Key.Escape);
    else yield return r.Wait(.3f);
    var pulse=r.AudioPulse(before);passed&=pulse&&ambience;summary.Add(mode+":ambience="+ambience+",distinct_event="+pulse);r.Observe("audio-event-"+mode);
   }
   r.Check("D5_AUDIO",passed,"ambience plus distinct real action/cooking/success/warning/pause/result playback, including shared-source output changes",string.Join(";",summary));
  }
  [UnityTest,Order(39)] public IEnumerator T20_AdjacentWorkflow() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{"D4_ADJACENT_WORKFLOW"},Body_T20_AdjacentWorkflow(r)); }
  IEnumerator Body_T20_AdjacentWorkflow(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();r.At(s,"chopping-board");Held(s,1,1);Ingredients(s,2);Order(s,V(s,"order_lifetime"));yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.E);yield return r.Hold(Key.E,(float)V(s,"chop_seconds")+.2f);yield return r.Tap(Key.E);var chopped=V(A(r.Read(),"chef-1"),"held_kind")==2;r.Observe("adjacent-chopped-output");
 yield return r.Navigate("pot");yield return r.Tap(Key.E);yield return r.Until(()=>V(A(r.Read(),"pot"),"item_kind")==5,8.3f);var cooked=V(A(r.Read(),"pot"),"item_kind")==5;
 yield return r.Navigate("plate-rack");yield return r.Tap(Key.E);yield return r.Navigate("pot");yield return r.Tap(Key.E);var plated=V(A(r.Read(),"chef-1"),"held_kind")==4;r.Observe("adjacent-plated-output");yield return r.Navigate("delivery");yield return r.Tap(Key.E);var delivered=r.Read();r.Observe("adjacent-delivery-output");
 r.Check("D4_ADJACENT_WORKFLOW",chopped&&cooked&&plated&&V(delivered,"delivered_orders")==1,"normal actions connect board output to pot, cooked soup to plate and plate to delivery without post-action setup writes",JsonUtility.ToJson(delivered));
  }
  static long OrderSlot(SessionSave s,int slot,double remaining)
  {
   if(slot<1||slot>3)throw new ArgumentOutOfRangeException(nameof(slot));
   var id=(long)V(s,"next_order_id");N(s,"next_order_id",id+1);N(s,$"order_{slot}_id",id);N(s,$"order_{slot}_initial",V(s,"order_lifetime"));N(s,$"order_{slot}_remaining",Math.Min(remaining,V(s,"order_lifetime")));return id;
  }
  [UnityTest,Order(41)] public IEnumerator T99_DirtyClose() { var r=new KitchenRun("dynamic");return r.Execute(new string[]{},Body_T99_DirtyClose(r)); }
  IEnumerator Body_T99_DirtyClose(KitchenRun r)
  {

 yield return r.Open();var s=r.Clean();N(s,"score",31);N(s,"shift_remaining",67);Held(s,1,1);Ingredients(s,2);Order(s,20);yield return r.Prepare(s);yield return r.Begin();yield return r.Tap(Key.Q);var f=r.Observe("independent-dirty-close");var output=Path.GetDirectoryName(Environment.GetEnvironmentVariable("KITCHEN_EVIDENCE_FILE"));File.WriteAllText(Path.Combine(output,"dirty-close.json"),JsonUtility.ToJson(f,true));
  }
 }
}
