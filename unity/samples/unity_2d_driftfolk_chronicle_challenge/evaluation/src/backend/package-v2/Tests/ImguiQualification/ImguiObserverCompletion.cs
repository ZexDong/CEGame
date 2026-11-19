#if UNITY_EDITOR
using System;
using System.Collections;
using System.IO;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using GameCreate.Evaluation.Session;
using Object=UnityEngine.Object;

namespace GameCreate.Stormbound.Evaluator.ImguiQualification
{
 public sealed class OwnedFreshNativeSurface:MonoBehaviour
 {
  int counter;GUIStyle box;
  void OnGUI()
  {
   if(Event.current.type!=EventType.Repaint)return;
   counter++;GUI.Label(new Rect(40,20,500,40),"PAINT TOKEN "+counter);
   if(box==null){box=new GUIStyle(GUI.skin.box);box.normal.background=Texture2D.whiteTexture;}
   var old=GUI.backgroundColor;GUI.backgroundColor=Color.white;
   for(var i=0;i<8;i++){GUI.color=(counter&(1<<i))!=0?Color.white:Color.black;GUI.Box(new Rect(40+30*i,80,20,20),GUIContent.none,box);}
   GUI.color=Color.white;GUI.backgroundColor=old;
  }
 }
 public sealed class OwnedLabelPointerSurface:MonoBehaviour
 {
  public int clicks;public bool bridge=true;public float scale=1;public Vector2 origin;
  void Update()
  {
   if(!bridge||Mouse.current==null||!Mouse.current.leftButton.wasReleasedThisFrame)return;
   var p=Mouse.current.position.ReadValue();p.y=Screen.height-p.y;p=(p-origin)/scale;
   if(new Rect(90,80,300,60).Contains(p))clicks++;
  }
  void OnGUI()
  {
   var old=GUI.matrix;GUI.matrix=Matrix4x4.TRS(origin,Quaternion.identity,new Vector3(scale,scale,1));
   GUI.Label(new Rect(90,80,300,60),"CUSTOM LABEL POINTER",GUI.skin.button);
   GUI.Label(new Rect(90,180,400,40),"LABEL CLICK COUNT "+clicks);
   GUI.matrix=old;
  }
 }
 public sealed class OwnedScrollPointerSurface:MonoBehaviour
 {
  public Vector2 offset;public bool wheelBridge=true,dragBridge=true;bool dragging;
  public float scale=1;public Vector2 origin;
  const float ViewHeight=200,ContentHeight=1280;
  void Update()
  {
   if(Mouse.current==null)return;var mouse=Mouse.current;
   var p=mouse.position.ReadValue();p.y=Screen.height-p.y;p=(p-origin)/scale;
   if(wheelBridge&&new Rect(70,70,380,ViewHeight).Contains(p))offset.y=Mathf.Clamp(offset.y-mouse.scroll.ReadValue().y,0,ContentHeight-ViewHeight);
   if(dragBridge&&mouse.leftButton.wasPressedThisFrame&&new Rect(430,70,22,ViewHeight).Contains(p))dragging=true;
   if(dragging&&mouse.leftButton.isPressed)offset.y=Mathf.Clamp((p.y-80)/(ViewHeight-20),0,1)*(ContentHeight-ViewHeight);
   if(mouse.leftButton.wasReleasedThisFrame)dragging=false;
  }
  void OnGUI()
  {
   var old=GUI.matrix;GUI.matrix=Matrix4x4.TRS(origin,Quaternion.identity,new Vector3(scale,scale,1));
   offset=GUI.BeginScrollView(new Rect(70,70,380,ViewHeight),offset,new Rect(0,0,340,ContentHeight),false,true);
   for(var i=0;i<40;i++)GUI.Label(new Rect(8,32*i,330,30),"Day "+(i+1)+" Morning Ada food 3");
   GUI.EndScrollView();GUI.matrix=old;
  }
 }
 public sealed class ImguiObserverCompletion
 {
  static string DirectoryFor(string name)
  {var result=Path.Combine(Environment.GetEnvironmentVariable("STORMBOUND_IMGUI_PROBE_OUTPUT"),name);Directory.CreateDirectory(result);return result;}
  static GameObject CameraFor(string name)
  {
   var owned=new GameObject(name);var camera=owned.AddComponent<Camera>();camera.depth=999;camera.cullingMask=0;
   camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(.06f,.10f,.15f);return owned;
  }
  static void DisposeInput(PlayerInputDriver input){if(input==null)return;var cleanup=input.Dispose();while(cleanup.MoveNext()){};}
  static IEnumerator Drag(Vector2 a,Vector2 b)
  {
   var mouse=Mouse.current;mouse.MakeCurrent();InputSystem.QueueStateEvent(mouse,new MouseState{position=a});yield return null;
   mouse.MakeCurrent();InputSystem.QueueStateEvent(mouse,new MouseState{position=a}.WithButton(MouseButton.Left,true));yield return null;
   for(var i=1;i<=8;i++){mouse.MakeCurrent();InputSystem.QueueStateEvent(mouse,new MouseState{position=Vector2.Lerp(a,b,i/8f)}.WithButton(MouseButton.Left,true));yield return null;}
   mouse.MakeCurrent();InputSystem.QueueStateEvent(mouse,new MouseState{position=b});yield return null;
  }
  [UnityTest]public IEnumerator I05_RefreshBindsOneFreshNativeRepaintAndClearsEmptySurface()
  {
   yield return EditorGameViewResolution.Ensure1280x720();
   var owned=new GameObject("Owned freshness surface");var surface=owned.AddComponent<OwnedFreshNativeSurface>();
   var camera=CameraFor("Owned freshness camera");ImguiObservationScope scope=null;
   try
   {
    scope=new ImguiObservationScope(DirectoryFor("I05"));
    for(var sample=0;sample<3;sample++)
    {
     var frame=Time.frameCount;var sequence=scope.RepaintSequence;yield return scope.Refresh("fresh-"+sample);
     Assert.GreaterOrEqual(scope.Frame,frame);Assert.Greater(scope.RepaintSequence,sequence);
     Assert.IsTrue(scope.Paints.All(row=>row.frame==scope.Frame&&row.repaint_sequence==scope.RepaintSequence));
     var tokens=scope.Texts().Where(row=>row.text.StartsWith("PAINT TOKEN ")).ToArray();Assert.AreEqual(1,tokens.Length);
     var token=int.Parse(tokens[0].text.Substring("PAINT TOKEN ".Length));
     var image=new Texture2D(2,2);image.LoadImage(File.ReadAllBytes(scope.ImagePath));
     try{for(var bit=0;bit<8;bit++){var pixel=image.GetPixel(50+bit*30,Screen.height-90);Assert.AreEqual((token&(1<<bit))!=0,pixel.r>.5f,"Native pixel token must match this exact draw transaction");}}
     finally{Object.DestroyImmediate(image);}
    }
    var oldPath=scope.ImagePath;surface.enabled=false;yield return scope.Refresh("empty-new-frame");
    Assert.IsFalse(scope.Texts().Any(row=>row.text.StartsWith("PAINT TOKEN ")));Assert.AreNotEqual(oldPath,scope.ImagePath);
    Assert.IsFalse(scope.HasRuntimeSurface,"No old draw record may survive a newly repainted empty native UI");
    var seq=scope.Sequence;yield return scope.Refresh("empty-no-png",false);
    Assert.Greater(scope.Sequence,seq);Assert.IsNull(scope.ImagePath);Assert.IsNull(scope.ImageSha256);
   }
   finally{scope?.Dispose();Object.DestroyImmediate(owned);Object.DestroyImmediate(camera);EditorGameViewResolution.Restore();}
   Assert.IsTrue(scope.Restored);Assert.IsNull(ImguiObservationScope.Current);
  }
  [UnityTest]public IEnumerator I06_LabelOnlyNewInputPointerIsEquivalentAndDeadBridgeStaysDead()
  {
   yield return EditorGameViewResolution.Ensure1280x720();var owned=new GameObject("Owned custom label pointer");
   var surface=owned.AddComponent<OwnedLabelPointerSurface>();var camera=CameraFor("Owned pointer camera");
   ImguiObservationScope scope=null;var input=new PlayerInputDriver();
   try
   {
    yield return input.Ready();scope=new ImguiObservationScope(DirectoryFor("I06"));yield return scope.Refresh("label-before");
    var button=PresentationObservers.FindControl("^CUSTOM LABEL POINTER$");Assert.IsNotNull(button);Assert.IsTrue(PresentationObservers.CanHit(button,out var point));
    yield return input.Click(point);yield return scope.Refresh("label-after");Assert.AreEqual(1,surface.clicks);
    Assert.IsTrue(scope.Texts().Any(row=>row.text=="LABEL CLICK COUNT 1"));
    surface.scale=.75f;surface.origin=new Vector2(160,100);yield return scope.Refresh("transformed-before");
    button=PresentationObservers.FindControl("^CUSTOM LABEL POINTER$");Assert.IsNotNull(button);Assert.AreEqual(225,button.screen.width,.1f);
    Assert.IsTrue(PresentationObservers.CanHit(button,out point));yield return input.Click(point);yield return scope.Refresh("transformed-after");Assert.AreEqual(2,surface.clicks);
    surface.bridge=false;yield return input.Click(point);yield return scope.Refresh("dead-bridge");Assert.AreEqual(2,surface.clicks);
    surface.bridge=true;yield return input.Click(new Vector2(1100,40));yield return scope.Refresh("wrong-point");Assert.AreEqual(2,surface.clicks);
   }
   finally{DisposeInput(input);scope?.Dispose();Object.DestroyImmediate(owned);Object.DestroyImmediate(camera);EditorGameViewResolution.Restore();}
   Assert.IsTrue(scope.Restored);
  }
  [UnityTest]public IEnumerator I07_ReadonlyScrollFactsSupportNormalWheelAndVisibleThumbDrag()
  {
   yield return EditorGameViewResolution.Ensure1280x720();var owned=new GameObject("Owned ordinary scroll surface");
   var surface=owned.AddComponent<OwnedScrollPointerSurface>();var camera=CameraFor("Owned scroll camera");
   ImguiObservationScope scope=null;var input=new PlayerInputDriver();
   try
   {
    yield return input.Ready();scope=new ImguiObservationScope(DirectoryFor("I07"));yield return scope.Refresh("scroll-start");
    var scroll=scope.Scrolls().Single();Assert.AreEqual(0,scroll.Offset,.1f);Assert.AreEqual(1080,scroll.Extent,.1f);
    Assert.IsTrue(scroll.hasVerticalScrollbarGeometry,"Native track/thumb must be bound to the same engine ScrollViewState");
    var upper=string.Join(" ",PresentationObservers.InScroll(scroll,scope.Texts()).Select(row=>row.text));
    Assert.IsTrue(upper.Contains("Day 1 Morning"),upper);Assert.IsFalse(upper.Contains("Day 40 Morning"),upper);
    yield return input.Scroll(scroll.screen.center,new Vector2(0,-200));yield return scope.Refresh("wheel-moved");
    Assert.AreEqual(200,scroll.Offset,.1f);Assert.AreEqual(surface.offset.y,scroll.Offset,.1f);
    surface.wheelBridge=false;var before=scroll.Offset;yield return input.Scroll(scroll.screen.center,new Vector2(0,-200));yield return scope.Refresh("wheel-disabled");
    Assert.AreEqual(before,scroll.Offset,.1f,"Read-only observation must not repair or directly move the game scroll");
    scroll=scope.Scrolls().Single();var track=scroll.verticalScrollbarTrack;var thumb=scroll.verticalScrollbarThumb;
    yield return Drag(thumb.center,new Vector2(thumb.center.x,track.yMin+1));yield return scope.Refresh("drag-moved");
    Assert.Greater(scroll.Offset,before+400);Assert.AreEqual(surface.offset.y,scroll.Offset,.1f);
    var lower=string.Join(" ",PresentationObservers.InScroll(scroll,scope.Texts()).Select(row=>row.text));
    Assert.IsTrue(lower.Contains("Day 40 Morning"),lower);Assert.IsFalse(lower.Contains("Day 1 Morning"),lower);
    surface.dragBridge=false;before=scroll.Offset;scroll=scope.Scrolls().Single();
    yield return Drag(scroll.verticalScrollbarThumb.center,new Vector2(scroll.verticalScrollbarThumb.center.x,scroll.verticalScrollbarTrack.yMax-1));yield return scope.Refresh("dead-drag");
    Assert.AreEqual(before,scroll.Offset,.1f);
   }
   finally{DisposeInput(input);scope?.Dispose();Object.DestroyImmediate(owned);Object.DestroyImmediate(camera);EditorGameViewResolution.Restore();}
   Assert.IsTrue(scope.Restored);
  }
 }
}
#endif
