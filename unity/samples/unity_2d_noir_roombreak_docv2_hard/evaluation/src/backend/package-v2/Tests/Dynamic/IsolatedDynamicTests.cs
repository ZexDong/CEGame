using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Benchmark.NoirRoombreak;
using GameCreate.NoirRoombreak.StateAccess;
using GameCreate.Evaluation.Session;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.NoirRoombreak.Evaluator
{
 public sealed partial class DynamicTrajectoryTests
 {
  sealed class ProductMissing : Exception { public ProductMissing(string text):base(text){} }
  sealed class DeathSample { public bool dead,recovered,feedback; public int beforeBonds,afterBonds,beforeSoft,afterSoft,beforeGlobal,afterGlobal,afterRoom; public float delay; public string details; }
  NoirStateAccess a; VirtualInputDriver input; UiProof ui; string route,sessionId,menuSignature,menuSignatureFailure; bool dirtyClose;
  readonly HashSet<string> finished=new HashSet<string>();
  readonly Dictionary<string,bool> outcomes=new Dictionary<string,bool>();
  Func<Scene,bool> declaredRuntimeScene=scene=>scene.path==ScenePath;
  IEnumerator Run(string id,string name,string[] ids,IEnumerator body)
  {
   route=id;sessionId=Guid.NewGuid().ToString("N");dirtyClose=false;finished.Clear();
   var previousIgnore=LogAssert.ignoreFailingMessages;var runtime=new CandidateRuntimeScope(declaredRuntimeScene,id);
   Exception failure=null,cleanupFailure=null;
   try
   {
    input=new VirtualInputDriver();LogAssert.ignoreFailingMessages=true;
    EvidenceStore.Initialize("dynamic","Unity Input System virtual Keyboard and Mouse through real player-loop frames");
    EvidenceStore.BeginTrajectory(id,name,sessionId);
    foreach(var check in ids){var spec=S[check];EvidenceStore.Check(check,spec.d,spec.w,false,check,"not executed",spec.r);EvidenceStore.Classify(check,"INCONCLUSIVE_EVALUATOR","pending");}
    yield return Pump(body,ex=>failure=ex);
    var failureSetup=a?.SetupId??"entry";
    try{a?.Dispose();}catch(Exception ex){cleanupFailure=ex;}a=null;
    if(input!=null){yield return Pump(input.Dispose(),ex=>cleanupFailure=ex);input=null;}
    if(id=="TRAJ10"&&dirtyClose)runtime.PreserveDirtyClose();
    else yield return Pump(runtime.Cleanup(),ex=>cleanupFailure=ex);
    foreach(var check in ids.Where(x=>!finished.Contains(x)))
    {
     var spec=S[check];EvidenceStore.Check(check,spec.d,spec.w,false,check,failure?.ToString()??"Declared check was not emitted.",spec.r);
     EvidenceStore.Classify(check,(failure is ProductMissing || failure is SessionProductFailure)?"BLOCKED_BY_PRODUCT":"INCONCLUSIVE_EVALUATOR",failureSetup,failure?.Message??"Declared check was not emitted.");outcomes[check]=false;
    }
    runtime.Receipt.cleanup_error=cleanupFailure?.ToString();EvidenceStore.RuntimeIsolation(runtime.Receipt);
    var evaluatorFailure=cleanupFailure!=null||runtime.Receipt.evaluator_logged_error||failure!=null&&!(failure is ProductMissing)&&!(failure is SessionProductFailure);
    EvidenceStore.EndTrajectory(id,evaluatorFailure?"evaluator-error":dirtyClose?"completed-dirty-close":(failure is ProductMissing || failure is SessionProductFailure)?"candidate-entry-missing":failure==null?(id=="TRAJ10"?"dirty-close-failed":"completed"):"evaluator-error",sessionId);
   }
   finally{runtime.Dispose();LogAssert.ignoreFailingMessages=previousIgnore;}
   if(cleanupFailure!=null||runtime.Receipt.evaluator_logged_error||failure!=null&&!(failure is ProductMissing)&&!(failure is SessionProductFailure))
    Assert.Fail("Evaluator unresolved: "+failure+"; cleanup="+cleanupFailure+"; evaluator_logged_error="+runtime.Receipt.evaluator_logged_error);
  }
  static IEnumerator Pump(IEnumerator body,Action<Exception> failed)
  {
   var stack=new Stack<IEnumerator>();stack.Push(body);
   while(stack.Count>0)
   {
    object next=null;bool more=false;Exception failure=null;
    try{more=stack.Peek().MoveNext();if(more)next=stack.Peek().Current;}catch(Exception ex){failure=ex;}
    if(failure!=null){failed(failure);yield break;}
    if(!more){stack.Pop();continue;}if(next is IEnumerator nested)stack.Push(nested);else yield return next;
   }
  }
  [UnityTearDown] public IEnumerator Cleanup(){a?.Dispose();a=null;if(input!=null)yield return input.Dispose();input=null;Time.timeScale=1;}
  IEnumerator Fresh()
  {
   a?.Dispose();a=null;menuSignature=null;menuSignatureFailure=null;Time.timeScale=1;Application.targetFrameRate=60;QualitySettings.vSyncCount=0;
   if(!Application.CanStreamedLevelBeLoaded(ScenePath))throw new ProductMissing("Required saved game Scene is absent; gameplay was not implemented.");
   yield return SceneManager.LoadSceneAsync(ScenePath,LoadSceneMode.Single);yield return null;yield return null;
   if(Screen.width!=1280||Screen.height!=720)throw new InvalidOperationException($"Evaluator viewport is {Screen.width}x{Screen.height}, required 1280x720.");
   a=NoirStateAccess.Find();if(a==null)throw new SessionProductFailure("public-observation", "Required public game observation/session interfaces are absent.");
   yield return input.Ready();yield return input.Frame();a.TryMenuWorldSignature(out menuSignature,out menuSignatureFailure);
  }
  IEnumerator Prepare(int room=0,int bonds=3,int charges=3)
  {
   yield return Fresh();yield return a.BeginRoom(room,bonds,charges);
  }
  IEnumerator Seal(){yield return a.Seal();}
  void SafeOthers(NoirStateAccess.Enemy target)
  {
   var offset=0f;foreach(var e in a.CurrentEnemies().Where(x=>x.Alive&&x.View!=target.View)){a.PlaceEnemy(e,a.TestX(-6.7f+offset),a.FloorY);offset+=.5f;}
  }
  NoirStateAccess.Enemy Target(NoirEnemyKind kind)
  {
   var target=a.First(kind);if(target==null)throw new ProductMissing($"The initialized room {a.Room+1} has no living {kind}; engine entity inventory confirms it.");return target;
  }
  IEnumerator Wait(float seconds){var end=Time.realtimeSinceStartup+seconds;while(Time.realtimeSinceStartup<end)yield return null;}
  IEnumerator Until(Func<bool> condition,float seconds){var end=Time.realtimeSinceStartup+seconds;while(!condition()&&Time.realtimeSinceStartup<end)yield return null;}
  bool Playing=>a!=null&&a.Phase==NoirScreen.Playing;
  bool OnScreen()=>a.Player!=null&&Camera.main!=null&&Camera.main.isActiveAndEnabled&&InViewport(Camera.main.WorldToViewportPoint(a.Position));
  static bool InViewport(Vector3 p)=>p.z>0&&p.x>=0&&p.x<=1&&p.y>=0&&p.y<=1;
  bool Clean()
  {
   if(menuSignature==null)return false;
   try{return a.Phase==NoirScreen.Menu&&a.Room==-1&&a.Bonds==3&&a.Charges==3&&a.Defeated==0&&a.Soft==0&&a.Global==0&&a.LastRespawn==NoirRespawnKind.None&&!a.Dashing&&!a.Invulnerable&&a.WorldSignature()==menuSignature;}
   catch(SessionProductFailure){return false;}
  }
  IEnumerator StartNormally(){yield return input.Press(Key.Enter);if(!Playing&&a.Probe!=null&&a.Probe.StartButtonScreenRect.width>0)yield return input.Click(a.Probe.StartButtonScreenRect.center);yield return Until(()=>Playing,1);}
  void R(string id,bool passed,string observed="")
  {
   var spec=S[id];var fact=observed;if(menuSignatureFailure!=null)fact+=" | initial-menu capture unavailable: "+menuSignatureFailure;
   try{fact+=" | "+(a==null?"no adapter":a.Counters+$";position={a.Position};profile={a.Profile};setup={a.SetupId};writes={string.Join(",",a.SetupWrites)}");}
   catch(Exception diagnosticError){fact+=" | diagnostic unavailable: "+diagnosticError.GetType().Name;}
   EvidenceStore.Check(id,spec.d,spec.w,passed,id,fact,spec.r);
   EvidenceStore.Classify(id,passed?"PASS":"FAIL_OBSERVED",a?.SetupId??"native-ui",lateWrites:a?.LateWrites??0);
   outcomes[id]=passed;finished.Add(id);
  }
  UiProof Ui()=>ui??(ui=UiProof.Load());
  bool HasResult(string id)=>outcomes.TryGetValue(id,out var value)&&value;
  // A product failure in one observation must not discard later observations
  // with an independent public chapter-entry route. Evaluator errors still escape.
  IEnumerator IndependentObservation(string[] ids,IEnumerator body)
  {
   var stack=new Stack<IEnumerator>();stack.Push(body);SessionProductFailure failure=null;
   while(stack.Count>0)
   {
    object next=null;bool more=false;
    try{more=stack.Peek().MoveNext();if(more)next=stack.Peek().Current;}catch(SessionProductFailure ex){failure=ex;}
    if(failure!=null)break;
    if(!more){stack.Pop();continue;}if(next is IEnumerator nested)stack.Push(nested);else yield return next;
   }
   if(failure==null)yield break;
   foreach(var id in ids.Where(x=>!finished.Contains(x)))
   {
    var spec=S[id];EvidenceStore.Check(id,spec.d,spec.w,false,id,failure.ToString(),spec.r);
    EvidenceStore.Classify(id,"BLOCKED_BY_PRODUCT",a?.SetupId??"entry",failure.Message);outcomes[id]=false;finished.Add(id);
   }
  }
  bool VisibleActor(NoirStateAccess.Enemy e)=>e!=null&&e.View!=null&&e.Renderer!=null&&e.Renderer.enabled&&e.Renderer.sprite!=null;
  bool VisibleBeam(NoirStateAccess.Enemy enemy)
  {
   var sprite=enemy.ThreatSprite;
   if(sprite!=null&&sprite.gameObject.activeInHierarchy&&sprite.enabled&&sprite.sprite!=null&&sprite.color.a>.01f&&sprite.bounds.size.x>.1f&&sprite.bounds.size.y>.01f)return true;
   var line=enemy.ThreatBeam;return line!=null&&line.gameObject.activeInHierarchy&&line.enabled&&line.positionCount>=2&&line.startWidth>0&&(line.startColor.a>.01f||line.endColor.a>.01f);
  }
  HashSet<int> ActiveSprites()=>new HashSet<int>(UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x.enabled&&x.sprite!=null&&x.color.a>.05f).Select(x=>x.GetInstanceID()));
  bool NewActionSprite(HashSet<int> before)=>UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude,FindObjectsSortMode.None)
   .Any(x=>x.enabled&&x.sprite!=null&&x.color.a>.05f&&!before.Contains(x.GetInstanceID())&&Vector3.Distance(x.bounds.center,a.Position)<3f);
  string ThreatVisual(NoirStateAccess.Enemy enemy)
  {
   // A warning may change a beam, an enemy sprite, or a visible world label.
   // Do not require every valid implementation to recolor the enemy's body.
   var line=enemy.ThreatBeam;
   var sprite=enemy.ThreatSprite;
   var beam=line!=null?$"{line.enabled}:{line.startWidth:F3}:{line.startColor}:{line.endColor}":sprite!=null?$"sprite:{sprite.gameObject.activeInHierarchy}:{sprite.enabled}:{sprite.color}:{sprite.bounds.size}":"no beam";
   var labels=UnityEngine.Object.FindObjectsByType<TextMesh>(FindObjectsInactive.Exclude,FindObjectsSortMode.None)
    .Where(x=>x.GetComponent<Renderer>().enabled&&Vector3.Distance(x.transform.position,enemy.Position)<3&&System.Text.RegularExpressions.Regex.IsMatch(x.text,@"(?i)LOCK|LASER|ALERT|FIRING"))
    .Select(x=>x.text+":"+x.color).OrderBy(x=>x,StringComparer.Ordinal);
   return enemy.Color+"|"+beam+"|"+string.Join("|",labels);
  }

  [UnityTest,Order(10)] public IEnumerator TRAJ01_MenuStartMovementAndHud()=>Run("TRAJ01",nameof(TRAJ01_MenuStartMovementAndHud),new[]{"D2_MENU","D2_MOVE_JUMP","D2_UI_STATES","D2_AV_ASSEMBLY","D3_INITIAL_STATE","D3_MOVE_COLLISION","D4_START","D5_MENU_CONTROLS","D5_HUD","D5_AUDIO_VISUAL_FEEDBACK"},MenuMovement());
  IEnumerator MenuMovement()
  {
   yield return Fresh();var u=Ui();R("D2_MENU",a.Phase==NoirScreen.Menu&&u.MenuReadable,u.Text("menu"));
   R("D5_MENU_CONTROLS",u.MenuReadable&&u.menu_click,"native OS click at OCR-localized visible Start control="+u.menu_click);
   R("D4_START",u.initial_world_clean,"native entry has a clean playable state="+u.initial_world_clean);
   yield return IndependentObservation(new[]{"D3_INITIAL_STATE"},InitialStateAfterNormalStart());
   R("D2_UI_STATES",u.MenuReadable&&u.HudMatches("gameplay")&&u.PauseReadable&&u.SuccessReadable,"native rendered menu/gameplay/pause/success OCR");
   R("D5_HUD",u.HudMatches("gameplay")&&u.HudMatches("after_dash"),u.Text("gameplay")+" -> "+u.Text("after_dash"));
   yield return Prepare();yield return Seal();var start=a.Position;yield return input.Hold(.15f,Key.D);var moved=a.Position.x>start.x+.05f;
   var audio=RuntimeInspector.PlayingAudioSourceIds();var floor=a.Position.y;yield return input.Press(Key.Space);
   var playback=RuntimeInspector.ActionPlaybackObserved(audio,out var audioDetails);var peak=a.Position.y;var end=Time.realtimeSinceStartup+.7f;
   while(Time.realtimeSinceStartup<end){peak=Mathf.Max(peak,a.Position.y);yield return null;}
   yield return Until(()=>a.Grounded,2f);
   R("D2_MOVE_JUMP",moved&&peak>floor+.08f&&a.Grounded,$"horizontal={moved};jumpHeight={peak-floor};grounded={a.Grounded}");
   var assembly=RuntimeInspector.SuppliedAssembly(playback,"jump",out var suppliedFeedback,out var mediaDetails);
   assembly&=RuntimeInspector.ReadableActor(a.PlayerRenderer==null?null:a.PlayerRenderer.transform,out var readableDetails);mediaDetails+=" | "+readableDetails;
   R("D2_AV_ASSEMBLY",assembly&&playback,mediaDetails+" | "+audioDetails);
   R("D5_AUDIO_VISUAL_FEEDBACK",assembly&&suppliedFeedback&&peak>floor+.08f,mediaDetails);
   yield return input.Hold(1.5f,Key.A);var middle=a.Position;yield return input.Hold(.5f,Key.A);var edge=a.Position;
   yield return Wait(.2f);R("D3_MOVE_COLLISION",moved&&OnScreen()&&Mathf.Abs(middle.x-edge.x)<.07f&&Vector3.Distance(edge,a.Position)<.03f,$"leftBoundary={middle}->{edge};solidColliders={RuntimeInspector.SolidColliderCount()}");
  }

  IEnumerator InitialStateAfterNormalStart()
  {
   yield return StartNormally();var before=a.Counters;var position=a.Position;yield return Wait(.2f);
   R("D3_INITIAL_STATE",Playing&&a.Room==0&&a.Bonds==3&&a.Charges==3&&a.Alive&&a.Soft==0&&a.Global==0&&a.Defeated==0&&before==a.Counters&&Vector3.Distance(position,a.Position)<.02f);
  }

  [UnityTest,Order(20)] public IEnumerator TRAJ02_AndaAndBackstab()=>Run("TRAJ02",nameof(TRAJ02_AndaAndBackstab),new[]{"D2_BACKSTAB","D2_ANDA","D3_BACKSTAB_BOUNDARY","D3_BACKSTAB_CHARGE","D3_ANDA_TRANSITIONS","D5_MOVEMENT_COMBAT"},AndaBackstab());
  IEnumerator AndaBackstab()
  {
   yield return Prepare();var target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(-4.5f),a.FloorY);yield return Seal();
   var patrolStart=target.Position;yield return Wait(.5f);var patrolMoved=Vector3.Distance(patrolStart,target.Position)>.03f;
   // Separate detector entry; no long chase route is a prerequisite for combat.
   yield return Prepare();target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(-2),a.FloorY);a.PlacePlayer(a.SightX(target),a.FloorY);yield return Seal();
   var alert=false;var chased=false;var chaseStart=target.Position;var until=Time.realtimeSinceStartup+8f;
   while(Time.realtimeSinceStartup<until&&a.Alive){alert|=target.State==NoirEnemyState.Alert;chased|=target.State==NoirEnemyState.Chase;if(chased&&Vector3.Distance(chaseStart,target.Position)>.08f)break;yield return null;}
   var chaseMoved=Vector3.Distance(chaseStart,target.Position)>.05f;
   var disengaged=false;
   if(patrolMoved&&alert&&chased&&chaseMoved)
   {
    yield return Prepare();target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(-2),a.FloorY);a.PlacePlayer(a.ExitX-1,a.FloorY);
    if(!a.PrepareChase(target))throw new NotSupportedException("A witnessed chase requires a bound lost-target fixture.");
    yield return Seal();yield return Until(()=>target.State!=NoirEnemyState.Chase,8f);disengaged=a.Alive&&target.State==NoirEnemyState.Patrol;
   }
   R("D2_ANDA",VisibleActor(target)&&patrolMoved&&chased&&chaseMoved,$"patrolMotion={patrolMoved};chaseState={chased};chaseMotion={chaseMoved}");
   R("D3_ANDA_TRANSITIONS",patrolMoved&&alert&&chased&&chaseMoved&&disengaged,$"alert={alert};chase={chased};disengaged={disengaged}");
   var rejects=true;var descriptions=new List<string>();
   foreach(var scenario in new[]{"far","front","occluded"})
   {
    yield return Prepare();target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(0),a.FloorY);
    a.PlacePlayer(a.TestX(scenario=="far"?-4f:scenario=="front"?1.3f:-1.3f),a.FloorY);if(scenario=="occluded")a.OcclusionBetween(target);yield return Seal();
    if(scenario=="front")yield return Wait(.5f);
    var c=a.Charges;var d=a.Defeated;yield return input.Press(Key.C);yield return Wait(.05f);
    var clean=target.Alive&&a.Charges==c&&a.Defeated==d;rejects&=clean;descriptions.Add(scenario+"="+clean);
   }
   yield return Prepare(charges:2);target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(-1.3f),a.FloorY);yield return Seal();
   var before=a.Defeated;var sound=RuntimeInspector.PlayingAudioSourceIds();var text=RuntimeInspector.VisibleTextSnapshot();
   yield return input.Press(Key.C);var played=RuntimeInspector.ActionPlaybackObserved(sound,out var soundDetails);yield return Wait(.08f);
   var killed=!target.Alive&&a.Defeated==before+1;var reward=a.Charges==3;var feedback=(target.View==null||!target.View.gameObject.activeInHierarchy)||text!=RuntimeInspector.VisibleTextSnapshot();
   var after=a.Defeated;var charge=a.Charges;yield return input.Press(Key.C);yield return Wait(.05f);var duplicateClean=a.Defeated==after&&a.Charges==charge;
   R("D2_BACKSTAB",killed,"backstab produced exactly one functional enemy defeat="+killed);
   R("D3_BACKSTAB_CHARGE",killed&&reward&&duplicateClean,$"rewardToCap={reward};repeatClean={duplicateClean}");
   R("D3_BACKSTAB_BOUNDARY",killed&&rejects&&duplicateClean,string.Join(";",descriptions)+";defeatedTargetRejected="+duplicateClean);
   R("D5_MOVEMENT_COMBAT",killed&&played&&feedback,soundDetails+";visibleDefeat="+feedback);
  }

  [UnityTest,Order(30)] public IEnumerator TRAJ03_DashDamageAndBoundaries()=>Run("TRAJ03",nameof(TRAJ03_DashDamageAndBoundaries),new[]{"D2_DASH","D2_LETHAL_DAMAGE","D3_DASH_COST","D3_ZERO_DASH_REJECT","D3_DASH_INVULNERABILITY","D3_ONE_HIT_DEATH","D5_DASH_FEEDBACK"},DashDamage());
  IEnumerator DashDamage()
  {
   yield return Prepare();yield return Seal();var p=a.Position;var charge=a.Charges;var sounds=RuntimeInspector.PlayingAudioSourceIds();var color=a.PlayerRenderer.color;var spriteBefore=ActiveSprites();
   yield return input.Press(Key.Z);var dash=a.Dashing;var inv=a.Invulnerable;var played=RuntimeInspector.ActionPlaybackObserved(sounds,out var soundDetails);var visual=Vector4.Distance(color,a.PlayerRenderer.color)>.08f||NewActionSprite(spriteBefore);
   yield return Until(()=>!a.Dashing,8f);var travelled=Vector3.Distance(p,a.Position);R("D2_DASH",dash&&travelled>.4f,$"dashing={dash};distance={travelled}");
   R("D3_DASH_COST",dash&&inv&&!a.Dashing&&!a.Invulnerable&&a.Charges==charge-1,$"invulnerableDuring={inv};after={a.Invulnerable};charges={charge}->{a.Charges}");
   R("D5_DASH_FEEDBACK",played&&visual&&Ui().HudMatches("after_dash"),soundDetails+";visibleDashChange="+visual);
   yield return Prepare(charges:0);yield return Seal();p=a.Position;var counters=a.Counters;yield return input.Press(Key.Z);yield return Wait(.15f);
   R("D3_ZERO_DASH_REJECT",a.Charges==0&&!a.Dashing&&!a.Invulnerable&&Vector3.Distance(p,a.Position)<.03f&&counters==a.Counters);
   yield return Prepare();var target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(0)-a.ContactReach*.95f,a.FloorY);yield return Seal();
   var death=new DeathSample();yield return DieByInput(death);
   R("D2_LETHAL_DAMAGE",death.dead&&death.recovered,death.details);
   R("D3_ONE_HIT_DEATH",death.dead&&death.recovered&&death.delay<.35f&&death.afterBonds==death.beforeBonds-1&&death.afterSoft+death.afterGlobal==death.beforeSoft+death.beforeGlobal+1,death.details);
   yield return Prepare();target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(0)-a.ContactReach*.95f,a.FloorY);yield return Seal();
   var bonds=a.Bonds;yield return input.Frame(Key.D,Key.Z);var crossed=false;var protectedDuring=true;var invSeen=false;var end=Time.realtimeSinceStartup+1.5f;
   while(Time.realtimeSinceStartup<end&&a.Dashing){invSeen|=a.Invulnerable;protectedDuring&=a.Alive&&a.Bonds==bonds;crossed|=a.Position.x>target.Position.x+.05f;yield return input.Frame(Key.D);}
   yield return input.Frame();R("D3_DASH_INVULNERABILITY",death.dead&&invSeen&&crossed&&protectedDuring&&!a.Invulnerable,$"unprotectedControlDies={death.dead};crossed={crossed};protected={protectedDuring};expired={!a.Invulnerable}");
  }
  IEnumerator DieByInput(DeathSample d)
  {
   d.beforeBonds=a.Bonds;d.beforeSoft=a.Soft;d.beforeGlobal=a.Global;var start=Time.realtimeSinceStartup;var sound=RuntimeInspector.PlayingAudioSourceIds();var text=RuntimeInspector.VisibleTextSnapshot();var color=a.PlayerRenderer.color;
   while(a.Alive&&Time.realtimeSinceStartup<start+1){yield return input.Frame(Key.D);}
   d.dead=!a.Alive;d.delay=Time.realtimeSinceStartup-start;d.feedback=RuntimeInspector.ActionPlaybackObserved(sound,out var soundDetails)&&(text!=RuntimeInspector.VisibleTextSnapshot()||Vector4.Distance(color,a.PlayerRenderer.color)>.08f);
   yield return input.Frame();yield return Until(()=>a.Alive,8f);d.recovered=d.dead&&a.Alive;
   d.afterBonds=a.Bonds;d.afterSoft=a.Soft;d.afterGlobal=a.Global;d.afterRoom=a.Room;
   d.details=$"dead={d.dead};returnedAlive={d.recovered};delay={d.delay:F3};bonds={d.beforeBonds}->{d.afterBonds};soft={d.beforeSoft}->{d.afterSoft};global={d.beforeGlobal}->{d.afterGlobal};room={d.afterRoom};{soundDetails}";
  }

  [UnityTest,Order(40)] public IEnumerator TRAJ04_ObserCameraAndPause()=>Run("TRAJ04",nameof(TRAJ04_ObserCameraAndPause),new[]{"D2_OBSER","D2_ROOM_CAMERA","D2_PAUSE","D3_OBSER_WARNING_ORDER","D3_CAMERA_BOUNDARY","D3_PAUSE_FREEZE","D4_PAUSE_RESUME","D5_ENEMY_WARNINGS"},ObserCameraPause());
  IEnumerator ObserCameraPause()
  {
   yield return Prepare(0);foreach(var other in a.CurrentEnemies())a.PlaceEnemy(other,a.TestX(-6.5f),a.FloorY);a.PlacePlayer(a.CameraTrackingX,a.FloorY);yield return Seal();
   var camera=Camera.main;var cameraBefore=camera.transform.position;yield return input.Hold(.25f,Key.D);var followed=Vector3.Distance(cameraBefore,camera.transform.position)>.02f;
   R("D2_ROOM_CAMERA",followed&&OnScreen(),$"camera={cameraBefore}->{camera.transform.position};player={a.Position}");
   R("D3_CAMERA_BOUNDARY",OnScreen()&&camera.isActiveAndEnabled&&a.CurrentEnemies().Where(x=>x.Alive).All(x=>x.View!=null),"current player and room stay in a single valid camera view");
   yield return input.Press(Key.Escape);var paused=a.Phase==NoirScreen.Paused;var position=a.Position;var counters=a.Counters;var enemies=EnemySnapshot();yield return Wait(.65f);
   var frozen=paused&&a.Counters==counters&&Vector3.Distance(position,a.Position)<.02f&&enemies==EnemySnapshot();yield return input.Press(Key.Escape);
   R("D2_PAUSE",paused&&Playing&&Ui().PauseReadable);R("D3_PAUSE_FREEZE",frozen,$"paused={paused};frozen={frozen}");R("D4_PAUSE_RESUME",paused&&frozen&&Playing);
   yield return Prepare(2);var enemy=Target(NoirEnemyKind.Obser);SafeOthers(enemy);a.PlaceEnemy(enemy,a.TestX(0),a.FloorY);a.PlacePlayer(a.SightX(enemy),a.FloorY);yield return Seal();
   var lockSeen=false;var laserSeen=false;var lockVisual=false;var laserVisual=false;var lockAudio=false;var laserAudio=false;var lockImage=ThreatVisual(enemy);var initialImage=lockImage;var beam=false;
   var sound=RuntimeInspector.PlayingAudioSourceIds();var until=Time.realtimeSinceStartup+8;
   while(Time.realtimeSinceStartup<until&&!laserSeen)
   {
    if(enemy.State==NoirEnemyState.Locking&&!lockSeen){lockSeen=true;lockImage=ThreatVisual(enemy);lockVisual=initialImage!=lockImage;lockAudio=RuntimeInspector.ActionPlaybackObserved(sound,out _);sound=RuntimeInspector.PlayingAudioSourceIds();}
    if(enemy.State==NoirEnemyState.Firing)
    {
     laserSeen=true;laserVisual=ThreatVisual(enemy)!=lockImage;beam=VisibleBeam(enemy);laserAudio=RuntimeInspector.ActionPlaybackObserved(sound,out _);
     for(var frame=0;!beam&&frame<3&&enemy.State==NoirEnemyState.Firing;frame++){yield return null;beam|=VisibleBeam(enemy);}
    }
    // A shared AudioSource can finish its warning and start the laser later.
    // Observe that silent interval instead of requiring a different source ID.
    if(lockSeen&&!laserSeen)sound=sound.Intersect(RuntimeInspector.PlayingAudioSourceIds()).ToArray();
    yield return null;
   }
   R("D2_OBSER",lockSeen&&laserSeen&&lockVisual&&beam,$"lock={lockSeen};laser={laserSeen};visibleLock={lockVisual};visibleBeam={beam}");
   R("D3_OBSER_WARNING_ORDER",lockSeen&&laserSeen&&lockVisual&&laserVisual,$"warningBeforeLaser={lockSeen&&laserSeen};visualStages={lockVisual}/{laserVisual}");
   R("D5_ENEMY_WARNINGS",lockVisual&&laserVisual&&lockAudio&&laserAudio,$"lockAudio={lockAudio};laserAudio={laserAudio};lockVisual={lockVisual};laserVisual={laserVisual}");
  }
  string EnemySnapshot()=>string.Join("|",a.CurrentEnemies().Select(x=>$"{x.Kind}:{x.State}:{x.Alive}:{x.Position:F2}"));

  [UnityTest,Order(50)] public IEnumerator TRAJ05_SoftAndGlobalRespawn()=>Run("TRAJ05",nameof(TRAJ05_SoftAndGlobalRespawn),new[]{"D2_SOFT_RESPAWN","D2_GLOBAL_RESPAWN","D3_SOFT_RESPAWN_RULES","D3_GLOBAL_RESPAWN_RULES","D4_DEATH_RECOVERY","D5_DEATH_RESPAWN"},Respawn());
  IEnumerator Respawn()
  {
   var softOk=true;var softPresent=false;var feedback=true;var description=new List<string>();
   foreach(var bonds in new[]{2,1})
   {
    yield return Prepare(1,bonds);var target=Target(NoirEnemyKind.Anda);SafeOthers(target);a.PlaceEnemy(target,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(0)-a.ContactReach*.95f,a.FloorY);
    var earlier=a.AllEnemies().FirstOrDefault(x=>x.Room==0&&x.Kind==NoirEnemyKind.Anda);if(earlier!=null)a.ClearEnemyAsPrecondition(earlier);yield return Seal();
    var sample=new DeathSample();yield return DieByInput(sample);softPresent|=sample.dead&&sample.recovered&&sample.afterSoft==sample.beforeSoft+1;
    var ok=sample.recovered&&sample.afterBonds==bonds-1&&sample.afterRoom==1&&sample.afterSoft==sample.beforeSoft+1&&sample.afterGlobal==sample.beforeGlobal&&a.CurrentEnemies().All(x=>x.Alive)&&a.Position.x<a.TestX(-4)&&a.Charges==3;
    if(earlier!=null)ok&=!earlier.Alive;softOk&=ok;feedback&=sample.feedback;description.Add(sample.details+";earlierPreserved="+(earlier==null?"not represented":(!earlier.Alive).ToString()));
   }
   R("D2_SOFT_RESPAWN",softPresent,string.Join(" | ",description));R("D3_SOFT_RESPAWN_RULES",softOk,string.Join(" | ",description));
   yield return Prepare(3,0);var enemy=Target(NoirEnemyKind.Anda);SafeOthers(enemy);a.PlaceEnemy(enemy,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(0)-a.ContactReach*.95f,a.FloorY);
   var prior=a.AllEnemies().FirstOrDefault(x=>x.Room==0&&x.Kind==NoirEnemyKind.Anda);if(prior!=null)a.ClearEnemyAsPrecondition(prior);yield return Seal();
   var global=new DeathSample();yield return DieByInput(global);
   var globalOk=global.recovered&&global.afterGlobal==global.beforeGlobal+1&&global.afterSoft==global.beforeSoft&&a.Bonds==3&&a.Room==2&&a.Charges==3&&a.AtGlobalRecoveryPoint&&(prior==null||prior.Alive);
   var globalPresent=global.recovered&&global.afterGlobal==global.beforeGlobal+1&&a.Room==2;
   yield return Prepare(1,0);enemy=Target(NoirEnemyKind.Anda);SafeOthers(enemy);a.PlaceEnemy(enemy,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(0)-a.ContactReach*.95f,a.FloorY);yield return Seal();
   var beforeBench=new DeathSample();yield return DieByInput(beforeBench);
   globalOk&=beforeBench.recovered&&beforeBench.afterRoom==0&&a.Bonds==3&&beforeBench.afterGlobal==beforeBench.beforeGlobal+1;
   var globalDetails=global.details+" | before Room 3 bench activation: "+beforeBench.details;
   R("D2_GLOBAL_RESPAWN",globalPresent,globalDetails);
   R("D3_GLOBAL_RESPAWN_RULES",globalOk,globalDetails);R("D4_DEATH_RECOVERY",softOk&&globalOk,globalDetails);
   R("D5_DEATH_RESPAWN",feedback&&global.feedback&&global.recovered,string.Join(" | ",description)+" | "+globalDetails);
  }

  [UnityTest,Order(60)] public IEnumerator TRAJ06_CompleteJourneyResultRestartAndDirtyClose()=>Run("TRAJ06",nameof(TRAJ06_CompleteJourneyResultRestartAndDirtyClose),new[]{"D2_FIVE_ROOMS","D2_SUCCESS","D3_SUCCESS_CONDITION","D3_RESTART_CLEAN","D4_ROOM_PROGRESSION","D4_COMPLETE_JOURNEY","D4_RESTART_ACTIVE","D4_RESTART_PAUSED_SUCCESS","D5_PAUSE_SUCCESS"},RoomsAndLifecycle());
  IEnumerator RoomsAndLifecycle()
  {
   var signatures=new HashSet<string>();var content=true;var ready=0;var transitions=true;
   for(var room=0;room<5;room++)
   {
    yield return Prepare(room);yield return Seal();yield return input.Frame();ready++;
    signatures.Add(a.WorldSignature());content&=(room==2||a.CurrentEnemies().Any(x=>x.Alive&&x.Kind==NoirEnemyKind.Anda))&&HasResult("D3_MOVE_COLLISION")&&(room<2||a.CurrentEnemies().Any(x=>x.Alive&&x.Kind==NoirEnemyKind.Obser))&&(room!=2||a.HasBench);
   }
   R("D2_FIVE_ROOMS",ready==5&&content&&signatures.Count==5,$"independentRooms={ready};content={content};distinctWorlds={signatures.Count}");
   for(var room=0;room<4;room++)
   {
    yield return Prepare(room,2,2);a.PlacePlayer(a.ExitX-.04f,a.FloorY);yield return Seal();yield return input.Hold(.12f,Key.D);
    transitions&=a.Room==room+1&&a.Alive&&a.Bonds==2&&a.Charges==2&&a.CurrentEnemies().Any(x=>x.Alive)&&OnScreen();
   }
   R("D4_ROOM_PROGRESSION",transitions,"all four adjacent transitions and resource transfer="+transitions);
   yield return Prepare(4);foreach(var enemy in a.CurrentEnemies().Where(x=>x.Alive))a.ClearEnemyAsPrecondition(enemy);a.PlacePlayer(a.ExitX-.04f,a.FloorY);yield return Seal();
   yield return input.Hold(.12f,Key.D);var success=a.Phase==NoirScreen.Success;var p=a.Position;var c=a.Counters;
   yield return input.Hold(.15f,Key.A,Key.Z,Key.C);var terminalFrozen=success&&a.Phase==NoirScreen.Success&&a.Counters==c&&Vector3.Distance(a.Position,p)<.02f&&!a.Dashing&&!a.Invulnerable;
   R("D2_SUCCESS",success&&Ui().SuccessReadable);R("D3_SUCCESS_CONDITION",terminalFrozen&&a.Room==4&&HasResult("D3_MIXED_EXIT_LOCK"),$"success={success};terminalFrozen={terminalFrozen};gate={HasResult("D3_MIXED_EXIT_LOCK")}");
   yield return input.Press(Key.R);yield return Wait(.4f);var successRestart=success&&Clean();
   yield return Prepare();yield return Seal();yield return input.Press(Key.Z);yield return input.Press(Key.R);yield return Wait(.5f);var activeRestart=Clean();
   R("D3_RESTART_CLEAN",activeRestart&&successRestart,$"active={activeRestart};success={successRestart}");R("D4_RESTART_ACTIVE",activeRestart);
   yield return Prepare();yield return Seal();yield return input.Press(Key.Escape);yield return input.Press(Key.R);yield return Wait(.2f);var pausedRestart=Clean();
   R("D4_RESTART_PAUSED_SUCCESS",pausedRestart&&successRestart,$"paused={pausedRestart};success={successRestart}");
   R("D5_PAUSE_SUCCESS",Ui().PauseReadable&&Ui().SuccessReadable&&Ui().pause_resume_click&&Ui().pause_restart_click&&Ui().success_return_click,"native visible pause and success controls");
   R("D4_COMPLETE_JOURNEY",ready==5&&transitions&&HasResult("D2_BACKSTAB")&&HasResult("D2_DASH")&&HasResult("D4_MIXED_SUCCESS_FLOW")&&terminalFrozen&&successRestart,$"rooms={ready};transitions={transitions};backstab={HasResult("D2_BACKSTAB")};dash={HasResult("D2_DASH")};mixed={HasResult("D4_MIXED_SUCCESS_FLOW")};terminal={terminalFrozen};restart={successRestart}");

  }

  [UnityTest,Order(100)] public IEnumerator TRAJ10_IndependentDirtyShutdown()=>Run("TRAJ10",nameof(TRAJ10_IndependentDirtyShutdown),Array.Empty<string>(),DirtyShutdown());
  IEnumerator DirtyShutdown(){
   yield return Fresh();yield return StartNormally();
   var charges=a.Charges;var position=a.Probe==null?Vector2.zero:a.Probe.PlayerScreenPosition;
   yield return input.Press(Key.Z);yield return input.Hold(.15f,Key.D);
   dirtyClose=Playing&&(a.Charges!=charges||a.Probe!=null&&Vector2.Distance(position,a.Probe.PlayerScreenPosition)>2);
  }

  [UnityTest,Order(70)] public IEnumerator TRAJ07_DashboardAndInputEdges()=>Run("TRAJ07",nameof(TRAJ07_DashboardAndInputEdges),new[]{"D2_INPUT_EDGE_MODEL","D3_ONE_PRESS_ONE_INTENT","D3_REJECTED_ACTION_SIDE_EFFECT_FREE","D3_INPUT_REUSABLE_AFTER_RESTARTS","D4_INPUT_LIFECYCLE_STABILITY","D5_INPUT_REJECTION_FEEDBACK","D5_DASHBOARD_VISIBLE_AGREEMENT"},InputEdges());
  IEnumerator InputEdges()
  {
   yield return Prepare();yield return Seal();var before=a.Counters;var p=a.Position;var text=RuntimeInspector.VisibleTextSnapshot();var sound=RuntimeInspector.PlayingAudioSourceIds();
   yield return input.Press(Key.C);yield return Wait(.1f);var invalidClean=a.Counters==before&&Vector3.Distance(p,a.Position)<.03f;var invalidFeedback=RuntimeInspector.ActionPlaybackObserved(sound,out _)||text!=RuntimeInspector.VisibleTextSnapshot();
   var charge=a.Charges;yield return input.Hold(.18f,Key.Z);yield return Until(()=>!a.Dashing,8f);var one=a.Charges==charge-1;
   R("D3_ONE_PRESS_ONE_INTENT",one,$"one physical held press cost={charge-a.Charges}");
   yield return Prepare(charges:0);yield return Seal();before=a.Counters;p=a.Position;text=RuntimeInspector.VisibleTextSnapshot();sound=RuntimeInspector.PlayingAudioSourceIds();
   yield return input.Press(Key.Z);yield return Wait(.12f);var zeroClean=before==a.Counters&&Vector3.Distance(p,a.Position)<.03f&&!a.Dashing&&!a.Invulnerable;var zeroFeedback=RuntimeInspector.ActionPlaybackObserved(sound,out _)||text!=RuntimeInspector.VisibleTextSnapshot();
   R("D3_REJECTED_ACTION_SIDE_EFFECT_FREE",invalidClean&&zeroClean,$"invalidC={invalidClean};zeroDash={zeroClean}");
   R("D5_INPUT_REJECTION_FEEDBACK",invalidClean&&zeroClean&&invalidFeedback&&zeroFeedback,$"invalidFeedback={invalidFeedback};zeroFeedback={zeroFeedback}");
   yield return Prepare();yield return Seal();var resets=true;var starts=true;
   for(var i=0;i<2;i++){yield return input.Press(Key.Z);yield return input.Press(Key.R);yield return Wait(.4f);resets&=Clean();var returned=a.Phase==NoirScreen.Menu;yield return StartNormally();starts&=returned&&Playing;yield return Wait(.9f);}
   charge=a.Charges;yield return input.Press(Key.Z);var reusable=Playing&&a.Charges==charge-1;
   R("D3_INPUT_REUSABLE_AFTER_RESTARTS",starts&&reusable,$"starts={starts};nextAction={reusable}");R("D4_INPUT_LIFECYCLE_STABILITY",resets&&starts,$"cleanRestarts={resets};starts={starts}");
   R("D2_INPUT_EDGE_MODEL",Ui().initial_world_clean&&one&&invalidClean&&zeroClean&&starts&&reusable);
   yield return Prepare();yield return Seal();var dashboard=RuntimeInspector.FindDashboard();var contract=RuntimeInspector.DashboardContractOk(dashboard,out var detail);var matching=RuntimeInspector.DashboardMatchesProbe(dashboard,a.Probe,out var agreement);var sequence=a.Sequence;RuntimeInspector.DashboardMatchesProbe(dashboard,a.Probe,out _);var readsPure=sequence==a.Sequence;yield return Wait(.2f);
   R("D5_DASHBOARD_VISIBLE_AGREEMENT",contract&&matching&&readsPure&&Ui().HudMatches("gameplay"),detail+" | "+agreement+";readOnlySnapshotSequence="+sequence+"->"+a.Sequence);
  }

  [UnityTest,Order(80)] public IEnumerator TRAJ08_TimedPauseDuringLiveThreat()=>Run("TRAJ08",nameof(TRAJ08_TimedPauseDuringLiveThreat),new[]{"D2_TIMED_PAUSE","D3_PAUSE_UNSCALED_FREEZE","D3_PAUSE_NO_BUFFER","D4_TIMED_THREAT_PAUSE_RESUME"},TimedPause());
  IEnumerator TimedPause()
  {
   yield return Prepare(2);var enemy=Target(NoirEnemyKind.Obser);SafeOthers(enemy);a.PlaceEnemy(enemy,a.TestX(0),a.FloorY);a.PlacePlayer(a.SightX(enemy),a.FloorY);yield return Seal();
   yield return Until(()=>enemy.State==NoirEnemyState.Locking,8);var timed=enemy.State==NoirEnemyState.Locking;
   if(!timed){R("D2_TIMED_PAUSE",false,"No locking transition during a complete normal threat cycle");R("D3_PAUSE_UNSCALED_FREEZE",false,"No locking state exists to freeze");R("D3_PAUSE_NO_BUFFER",false,"Missing in-progress threat state");R("D4_TIMED_THREAT_PAUSE_RESUME",false,"No threat transition");yield break;}
   yield return input.Press(Key.Escape);var paused=a.Phase==NoirScreen.Paused;var p=a.Position;var counters=a.Counters;var e=EnemySnapshot();yield return Wait(9f);
   var frozen=paused&&a.Counters==counters&&Vector3.Distance(p,a.Position)<.02f&&e==EnemySnapshot();yield return input.Press(Key.Z);yield return input.Hold(.15f,Key.D);
   var bufferedClean=a.Counters==counters&&Vector3.Distance(p,a.Position)<.02f;yield return input.Frame(Key.Escape);var first=Playing&&enemy.State==NoirEnemyState.Locking;yield return input.Frame();
   yield return Until(()=>enemy.State==NoirEnemyState.Firing,8);var resumed=Playing&&enemy.State==NoirEnemyState.Firing;
   // Independently cover pausing an active dash as well as a warning timer.
   yield return Prepare();yield return Seal();yield return input.Frame(Key.Z);yield return input.Frame(Key.Escape);var dashPaused=a.Phase==NoirScreen.Paused&&a.Dashing;p=a.Position;counters=a.Counters;yield return Wait(9f);
   var dashFrozen=dashPaused&&a.Dashing&&counters==a.Counters&&Vector3.Distance(p,a.Position)<.02f;yield return input.Frame();yield return input.Frame(Key.Escape);var dashResume=Playing&&a.Dashing;yield return input.Frame();yield return Until(()=>!a.Dashing,1.2f);
   R("D2_TIMED_PAUSE",paused&&resumed&&dashPaused&&dashResume);
   R("D3_PAUSE_UNSCALED_FREEZE",frozen&&dashFrozen,$"warningFrozen={frozen};dashFrozen={dashFrozen}");
   R("D3_PAUSE_NO_BUFFER",bufferedClean&&first&&dashResume,$"ignoredPausedInput={bufferedClean};firstWarningFrame={first};firstDashFrame={dashResume}");
   R("D4_TIMED_THREAT_PAUSE_RESUME",resumed&&first&&dashResume&&!a.Dashing&&!a.Invulnerable);
  }

  [UnityTest,Order(55)] public IEnumerator TRAJ09_FinalMixedEncounterGate()=>Run("TRAJ09",nameof(TRAJ09_FinalMixedEncounterGate),new[]{"D2_MIXED_ENCOUNTER","D3_MIXED_CONCURRENT_THREATS","D3_MIXED_EXIT_LOCK","D3_MIXED_CROSS_THREAT_WINDOW","D4_MIXED_SUCCESS_FLOW","D5_MIXED_THREAT_FEEDBACK"},MixedGate());
  IEnumerator MixedGate()
  {
   var mixed=true;var concurrent=true;var cross=true;var feedback=true;
   foreach(var room in new[]{3,4})
   {
    yield return Prepare(room);var anda=Target(NoirEnemyKind.Anda);var obser=Target(NoirEnemyKind.Obser);a.PlaceEnemy(anda,a.TestX(-4),a.FloorY);a.PlaceEnemy(obser,a.TestX(0),a.FloorY);a.PlacePlayer(a.SightX(obser),a.FloorY);yield return Seal();
    mixed&=VisibleActor(anda)&&VisibleActor(obser);concurrent&=anda.Alive&&obser.Alive;
    yield return Until(()=>obser.State==NoirEnemyState.Locking,8);cross&=anda.Alive&&obser.State==NoirEnemyState.Locking;var c=ThreatVisual(obser);yield return Until(()=>obser.State==NoirEnemyState.Firing,8);
    feedback&=c!=ThreatVisual(obser);
   }
   R("D2_MIXED_ENCOUNTER",mixed,"independent fourth and fifth room content");R("D3_MIXED_CONCURRENT_THREATS",concurrent);R("D3_MIXED_CROSS_THREAT_WINDOW",cross);
   var gate=true;var success=false;
   foreach(var mask in new[]{0,1,2,3})
   {
    yield return Prepare(4);foreach(var enemy in a.CurrentEnemies().Where(x=>x.Alive).ToArray())if((enemy.Kind==NoirEnemyKind.Anda&&(mask&1)!=0)||(enemy.Kind==NoirEnemyKind.Obser&&(mask&2)!=0))a.ClearEnemyAsPrecondition(enemy);
    a.PlacePlayer(a.ExitX-.04f,a.FloorY+1.25f,true);yield return Seal();yield return input.Hold(.08f,Key.D);
    if(mask==3)success=a.Phase==NoirScreen.Success;else gate&=a.Phase!=NoirScreen.Success&&a.Room==4;
   }
   R("D3_MIXED_EXIT_LOCK",gate&&success,$"none/Anda-only/Obser-only all blocked={gate};both-cleared opens={success}");
   var independentlyDefeatable=true;
   foreach(var kind in new[]{NoirEnemyKind.Anda,NoirEnemyKind.Obser})
   {
    yield return Prepare(4);var target=Target(kind);SafeOthers(target);a.PlaceEnemy(target,a.TestX(0),a.FloorY);a.PlacePlayer(a.TestX(-1.3f),a.FloorY);yield return Seal();
    yield return input.Press(Key.C);if(target.Alive){yield return input.Frame(Key.D,Key.Z);yield return input.Hold(.3f,Key.D);}
    independentlyDefeatable&=!target.Alive&&a.Alive;
   }
   R("D4_MIXED_SUCCESS_FLOW",gate&&success&&independentlyDefeatable,$"gate={gate};terminal={success};separateRealDefeats={independentlyDefeatable}");
   R("D5_MIXED_THREAT_FEEDBACK",mixed&&cross&&feedback,$"bothRoomPairs={mixed};concurrentWarning={cross};visiblePhaseChange={feedback}");
  }
 }
}
