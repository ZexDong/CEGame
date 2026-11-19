#if UNITY_EDITOR
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Linq.Expressions;
using NUnit.Framework;
using UnityEditor;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.InputSystem;
using GameCreate.Evaluation.Session;
using Object=UnityEngine.Object;

namespace GameCreate.Stormbound.Evaluator.ImguiQualification
{
 public sealed class OwnedImguiSurface:MonoBehaviour
 {
  public int clicks,repaints;
  public bool newInputBridge;
  public bool coverVisible;
  public Vector2 origin;
  public float scale=1;
  public readonly List<string> observedEvents=new List<string>();
  void Update()
  {
   if(!newInputBridge||Mouse.current==null||!Mouse.current.leftButton.wasReleasedThisFrame)return;
   var point=Mouse.current.position.ReadValue();point.y=Screen.height-point.y;point=(point-origin)/scale;
   if(new Rect(80,90,180,50).Contains(point))clicks++;
  }
  void OnGUI()
  {
   var matrix=GUI.matrix;GUI.matrix=Matrix4x4.TRS(origin,Quaternion.identity,new Vector3(scale,scale,1));
   observedEvents.Add(Time.frameCount+":"+Event.current.type+":"+Event.current.mousePosition);
   if(Event.current.type==EventType.Repaint)repaints++;
   GUI.color=Color.white;
   GUI.Label(new Rect(40,20,460,40),"VISIBLE IMGUI PROBE 117");
   if(GUI.Button(new Rect(80,90,180,50),"NORMAL POINTER PROBE"))clicks++;
   GUI.Label(new Rect(40,170,460,40),"ACTUAL CLICK COUNT "+clicks);
   GUI.color=new Color(1,1,1,0);GUI.Label(new Rect(40,220,460,40),"TRANSPARENT DECOY 997");GUI.color=Color.white;
   GUI.BeginGroup(new Rect(500,20,200,80));GUI.Label(new Rect(0,120,400,30),"CLIPPED DECOY 998");GUI.EndGroup();
   GUI.Label(new Rect(-9000,20,400,30),"OFFSCREEN DECOY 999");
   if(coverVisible){var cover=new GUIStyle(GUI.skin.box){name="OwnedOpaqueCover"};cover.normal.background=Texture2D.whiteTexture;var old=GUI.backgroundColor;GUI.backgroundColor=Color.black;GUI.Box(new Rect(40,20,460,40),GUIContent.none,cover);GUI.backgroundColor=old;}
   GUI.matrix=matrix;
  }
 }
 public sealed class ImguiObserverProbe
 {
  const BindingFlags All=BindingFlags.Instance|BindingFlags.Static|BindingFlags.Public|BindingFlags.NonPublic;
  [Serializable]public sealed class DrawFact {public string text,label;public Rect rect,visible;public int frame;public Color style_color;public List<string> stack=new List<string>();}
  [Serializable]public sealed class ProbeFacts
  {
   public int process_id,screen_width,screen_height,callbacks,repaints,clicks,draw_count;
   public string game_view,parent_view,error,framebuffer_source;
   public bool runtime_text_recorded,queued_pointer_changed_fixture,legacy_input_suppressed,new_input_pointer_changed_fixture,matrix_pointer_changed_fixture,wrong_point_unchanged;
   public List<DrawFact> draws=new List<DrawFact>();
   public List<string> events=new List<string>();
  }
  static object Member(object value,string name)
  {
   for(var type=value.GetType();type!=null;type=type.BaseType)
   {var property=type.GetProperty(name,All);if(property!=null)return property.GetValue(value);var field=type.GetField(name,All);if(field!=null)return field.GetValue(value);}
   return null;
  }
  static void SaveFrame(EditorWindow view,string file,ProbeFacts facts)
  {
   var texture=Member(view,"m_RenderTexture") as RenderTexture;
   if(!texture)texture=Member(view,"m_TargetTexture") as RenderTexture;
   if(!texture){facts.framebuffer_source="No current engine-owned GameView RenderTexture";return;}
   facts.framebuffer_source="Read existing GameView/PlayModeView RT "+texture.width+"x"+texture.height+" renderIMGUI="+Member(view,"renderIMGUI");
   var previous=RenderTexture.active;Texture2D output=null;
   try{RenderTexture.active=texture;output=new Texture2D(texture.width,texture.height,TextureFormat.RGBA32,false);output.ReadPixels(new Rect(0,0,texture.width,texture.height),0,0);output.Apply();var pixels=output.GetPixels32();var normalized=new Color32[pixels.Length];for(var y=0;y<texture.height;y++)Array.Copy(pixels,y*texture.width,normalized,(texture.height-1-y)*texture.width,texture.width);output.SetPixels32(normalized);output.Apply();facts.framebuffer_source+=";explicit_GameView_RT_vertical_normalization";File.WriteAllBytes(file,output.EncodeToPNG());}
   finally{RenderTexture.active=previous;if(output)Object.DestroyImmediate(output);}
  }
  [UnityTest]public IEnumerator I02_PassiveHookPreservesRealPixelsAndReadsActualTint()
  {
   var directory=Environment.GetEnvironmentVariable("STORMBOUND_IMGUI_PROBE_OUTPUT");Directory.CreateDirectory(directory);
   yield return EditorGameViewResolution.Ensure1280x720();
   var viewType=typeof(Editor).Assembly.GetType("UnityEditor.GameView",true);
   var view=Resources.FindObjectsOfTypeAll(viewType).OfType<EditorWindow>().First();
   var owned=new GameObject("Owned passive-hook picture control");var surface=owned.AddComponent<OwnedImguiSurface>();
   var cameraObject=new GameObject("Owned passive-hook camera");var camera=cameraObject.AddComponent<Camera>();camera.depth=999;camera.cullingMask=0;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(.06f,.10f,.15f);
   ImguiPaintProbeHook hook=null;var facts=new ProbeFacts();
   try
   {
    for(var i=0;i<5;i++){view.Repaint();yield return null;}
    SaveFrame(view,Path.Combine(directory,"I02-before-hook.png"),facts);
    hook=new ImguiPaintProbeHook();
    for(var i=0;i<5;i++){view.Repaint();yield return null;}
    SaveFrame(view,Path.Combine(directory,"I02-during-hook.png"),facts);
    Assert.IsTrue(hook.facts.Any(row=>row.text=="VISIBLE IMGUI PROBE 117"&&!row.transparent));
    Assert.IsTrue(hook.facts.Any(row=>row.text=="TRANSPARENT DECOY 997"&&row.transparent));
    Assert.IsTrue(hook.facts.Where(row=>row.text=="VISIBLE IMGUI PROBE 117").All(row=>row.visibility_uncertainty==null||row.visibility_uncertainty==""));
    Assert.IsTrue(File.ReadAllBytes(Path.Combine(directory,"I02-before-hook.png")).SequenceEqual(File.ReadAllBytes(Path.Combine(directory,"I02-during-hook.png"))),"Passive default-handler interception must not change the original pixels");
    hook.injectObserverFailure=true;
    for(var i=0;i<3;i++){view.Repaint();yield return null;}
    SaveFrame(view,Path.Combine(directory,"I02-observer-failure.png"),facts);
    Assert.IsTrue(hook.observer_errors.Any());
    Assert.IsTrue(File.ReadAllBytes(Path.Combine(directory,"I02-before-hook.png")).SequenceEqual(File.ReadAllBytes(Path.Combine(directory,"I02-observer-failure.png"))),"Observer exceptions must not change/abort original drawing");
    Assert.AreEqual(0,surface.clicks);
   }
   finally
   {
    if(hook!=null){hook.Dispose();File.WriteAllText(Path.Combine(directory,"I02-hook-facts.json"),JsonUtility.ToJson(new HookFacts{paints=hook.facts,errors=hook.observer_errors,original_invocations=hook.original_invocations,restored=hook.restored},true));}
    Object.DestroyImmediate(owned);Object.DestroyImmediate(cameraObject);EditorGameViewResolution.Restore();
   }
   Assert.IsTrue(hook.restored);
  }
  [Serializable]public sealed class HookFacts
  {public List<ImguiPaintProbeHook.PaintFact> paints;public List<string> errors;public int original_invocations;public bool restored;}

  static Delegate BoolHandler(Type type,Func<bool> operation)
  {
   var parameters=type.GetMethod("Invoke").GetParameters().Select(value=>Expression.Parameter(value.ParameterType,value.Name)).ToArray();
   return Expression.Lambda(type,Expression.Invoke(Expression.Constant(operation)),parameters).Compile();
  }
  [Test]public void I03_OriginalDelegateReturnCountOrderAndRestoration()
  {
   var field=typeof(GUIStyle).GetField("onDraw",All);var original=(Delegate)field.GetValue(null);
   var stateType=field.FieldType.GetMethod("Invoke").GetParameters()[3].ParameterType;
   var arguments=new object[]{null,default(Rect),GUIContent.none,Activator.CreateInstance(stateType)};
   try
   {
    foreach(var returns in new[]{new[]{false},new[]{true},new[]{false,true},new[]{true,false}})
    {
     var order=new List<int>();var delegates=returns.Select((value,index)=>BoolHandler(field.FieldType,()=>{order.Add(index);return value;})).ToArray();
     var prior=Delegate.Combine(delegates);field.SetValue(null,prior);
     var hook=new ImguiPaintProbeHook();var result=(bool)((Delegate)field.GetValue(null)).DynamicInvoke(arguments);
     Assert.AreEqual(returns.Last(),result);CollectionAssert.AreEqual(Enumerable.Range(0,returns.Length),order);
     Assert.AreEqual(returns.Length,hook.original_invocations);hook.Dispose();Assert.IsTrue(hook.restored);Assert.AreSame(prior,field.GetValue(null));
    }
    field.SetValue(null,null);var empty=new ImguiPaintProbeHook();Assert.IsFalse((bool)((Delegate)field.GetValue(null)).DynamicInvoke(arguments));empty.Dispose();Assert.IsNull(field.GetValue(null));
   }
   finally{field.SetValue(null,original);}
  }
  [UnityTest]public IEnumerator I04_SnapshotRejectsTransparentClippedOffscreenAndCoveredText()
  {
   var directory=Path.Combine(Environment.GetEnvironmentVariable("STORMBOUND_IMGUI_PROBE_OUTPUT"),"I04");Directory.CreateDirectory(directory);
   yield return EditorGameViewResolution.Ensure1280x720();
   var owned=new GameObject("Owned IMGUI visibility controls");var surface=owned.AddComponent<OwnedImguiSurface>();
   var cameraObject=new GameObject("Owned visibility camera");var camera=cameraObject.AddComponent<Camera>();camera.depth=999;camera.cullingMask=0;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(.06f,.10f,.15f);
   ImguiObservationScope scope=null;
   try
   {
    scope=new ImguiObservationScope(directory);yield return scope.Refresh("visible");
    var text=string.Join(" ",scope.Texts().Select(row=>row.text));
    Assert.IsTrue(text.Contains("VISIBLE IMGUI PROBE 117"),text);
    Assert.IsFalse(text.Contains("DECOY"),"Transparent, fully clipped and off-screen native draw intents must not be reported visible: "+text);
    surface.coverVisible=true;yield return scope.Refresh("covered");
    text=string.Join(" ",scope.Texts().Select(row=>row.text));Assert.IsFalse(text.Contains("VISIBLE IMGUI PROBE 117"),"A later opaque GUI background must suppress covered text: "+text);
   }
   finally{if(scope!=null)scope.Dispose();Object.DestroyImmediate(owned);Object.DestroyImmediate(cameraObject);EditorGameViewResolution.Restore();}
   Assert.IsTrue(scope.Restored);
  }

  [UnityTest]public IEnumerator I01_RealRepaintDrawMetadataAndNormalPointer()
  {
   var directory=Environment.GetEnvironmentVariable("STORMBOUND_IMGUI_PROBE_OUTPUT");
   Assert.IsFalse(string.IsNullOrEmpty(directory));Directory.CreateDirectory(directory);
   var facts=new ProbeFacts{process_id=System.Diagnostics.Process.GetCurrentProcess().Id};
   yield return EditorGameViewResolution.Ensure1280x720();
   var windowType=typeof(Editor).Assembly.GetType("UnityEditor.GameView",true);
   var view=Resources.FindObjectsOfTypeAll(windowType).OfType<EditorWindow>().FirstOrDefault();
   Assert.IsNotNull(view,"Owned test Editor must have a real GameView");
   var parent=Member(view,"m_Parent");Assert.IsNotNull(parent);
   facts.game_view=view.GetType().FullName;facts.parent_view=parent.GetType().FullName;
   var helper=typeof(Editor).Assembly.GetType("UnityEditor.GUIViewDebuggerHelper",true);
   var drawType=typeof(Editor).Assembly.GetType("UnityEditor.IMGUIDrawInstruction",true);
   var getDraws=helper.GetMethod("GetDrawInstructions",All);
   var callbackField=helper.GetField("onViewInstructionsChanged",All);
   var queue=typeof(EditorGUIUtility).GetMethod("QueueGameViewInputEvent",All,null,new[]{typeof(Event)},null);
   Assert.IsNotNull(queue);
   var owned=new GameObject("Owned IMGUI qualification surface");var surface=owned.AddComponent<OwnedImguiSurface>();
   var cameraObject=new GameObject("Owned IMGUI qualification camera");var camera=cameraObject.AddComponent<Camera>();
   camera.depth=999;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(.06f,.10f,.15f);camera.cullingMask=0;
   Action capture=()=>{
    facts.callbacks++;
    try{
     var list=(IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(drawType));getDraws.Invoke(null,new object[]{list,true});
     foreach(var row in list){var content=Member(row,"usedGUIContent") as GUIContent;var text=content?.text??"";
      var rect=(Rect)Member(row,"rect");var visible=(Rect)Member(row,"visibleRect");var style=Member(row,"usedGUIStyle") as GUIStyle;
      if(!facts.draws.Any(x=>x.text==text&&x.rect==rect&&x.visible==visible)){
       var fact=new DrawFact{text=text,label=Member(row,"label") as string,rect=rect,visible=visible,frame=Time.frameCount,style_color=style==null?Color.clear:style.normal.textColor};
       var stack=Member(row,"stackframes") as IEnumerable;if(stack!=null)foreach(var entry in stack)fact.stack.Add(Member(entry,"moduleName")+"|"+Member(entry,"methodName")+"|"+Member(entry,"signature"));facts.draws.Add(fact);
      }
     }
    }catch(Exception error){facts.error=error.ToString();}
   };
   try
   {
    callbackField.SetValue(null,Delegate.Combine((Delegate)callbackField.GetValue(null),capture));
    helper.GetMethod("DebugWindow",All).Invoke(null,new[]{parent});
    var end=Time.realtimeSinceStartup+2f;
    while(Time.realtimeSinceStartup<end){view.Repaint();yield return null;}
    capture();SaveFrame(view,Path.Combine(directory,"before-input.png"),facts);
    foreach(var kind in new[]{EventType.MouseMove,EventType.MouseDown,EventType.MouseUp})
    {queue.Invoke(null,new object[]{new Event{type=kind,mousePosition=new Vector2(170,115),button=0,clickCount=1}});view.Repaint();yield return null;yield return null;}
    end=Time.realtimeSinceStartup+1f;while(Time.realtimeSinceStartup<end){view.Repaint();yield return null;}
    facts.queued_pointer_changed_fixture=surface.clicks==1;facts.legacy_input_suppressed=surface.clicks==0;
    var normalInput=new PlayerInputDriver();yield return normalInput.Ready();surface.newInputBridge=true;
    yield return normalInput.Click(new Vector2(170,Screen.height-115));yield return null;view.Repaint();yield return null;
    facts.new_input_pointer_changed_fixture=surface.clicks==1;SaveFrame(view,Path.Combine(directory,"new-input-positive.png"),facts);
    surface.origin=new Vector2(100,70);surface.scale=.75f;view.Repaint();yield return null;yield return null;
    yield return normalInput.Click(new Vector2(100+170*.75f,Screen.height-(70+115*.75f)));yield return null;view.Repaint();yield return null;
    facts.matrix_pointer_changed_fixture=surface.clicks==2;var clicks=surface.clicks;
    yield return normalInput.Click(new Vector2(1100,Screen.height-650));yield return null;
    yield return normalInput.Dispose();
    foreach(var kind in new[]{EventType.MouseMove,EventType.MouseDown,EventType.MouseUp})
    {queue.Invoke(null,new object[]{new Event{type=kind,mousePosition=new Vector2(1100,650),button=0,clickCount=1}});view.Repaint();yield return null;yield return null;}
    end=Time.realtimeSinceStartup+.3f;while(Time.realtimeSinceStartup<end){view.Repaint();yield return null;}
    facts.wrong_point_unchanged=surface.clicks==clicks;capture();SaveFrame(view,Path.Combine(directory,"after-input.png"),facts);
    facts.runtime_text_recorded=facts.draws.Any(row=>row.text.Contains("VISIBLE IMGUI PROBE 117")&&row.visible.width>0&&row.visible.height>0);
   }
   finally
   {
    facts.screen_width=Screen.width;facts.screen_height=Screen.height;facts.repaints=surface.repaints;facts.clicks=surface.clicks;facts.draw_count=facts.draws.Count;facts.events=surface.observedEvents;
    File.WriteAllText(Path.Combine(directory,"I01-facts.json"),JsonUtility.ToJson(facts,true));
    callbackField.SetValue(null,Delegate.Remove((Delegate)callbackField.GetValue(null),capture));helper.GetMethod("StopDebugging",All).Invoke(null,null);
    Object.DestroyImmediate(owned);Object.DestroyImmediate(cameraObject);EditorGameViewResolution.Restore();
   }
   Assert.IsTrue(facts.runtime_text_recorded,"Pinned GUIView debugger must record actual player OnGUI text, not only Editor toolbar");
   Assert.IsTrue(facts.legacy_input_suppressed,"New Input System only must not be silently repaired by generating legacy OnGUI input");
   Assert.IsTrue(facts.new_input_pointer_changed_fixture,"Ordinary New Input System mouse must activate a correctly bridged IMGUI fixture exactly once");
   Assert.IsTrue(facts.matrix_pointer_changed_fixture,"Equivalent transformed IMGUI layout must receive the same normal pointer action");
   Assert.IsTrue(facts.wrong_point_unchanged,"Off-control normal click must not activate the button");
   Assert.IsTrue(string.IsNullOrEmpty(facts.error),facts.error);
  }
 }
}
#endif
