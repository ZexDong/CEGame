#if UNITY_EDITOR
using System;
using System.Collections;
using System.IO;
using System.Linq;
using System.Reflection;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;
using UnityEngine.UIElements;
using GameCreate.Evaluation.Session;
using Object=UnityEngine.Object;
using UButton=UnityEngine.UIElements.Button;
using Image=UnityEngine.UI.Image;

namespace GameCreate.Stormbound.Evaluator.ImguiQualification
{
 public sealed class RetainedUiRegression
 {
  static GameObject RectObject(string name,Transform parent,float x,float y,float w,float h,params Type[] components)
  {
   var o=new GameObject(name,new[]{typeof(RectTransform)}.Concat(components).ToArray());o.transform.SetParent(parent,false);
   var r=(RectTransform)o.transform;r.anchorMin=r.anchorMax=new Vector2(0,1);r.pivot=new Vector2(0,1);r.anchoredPosition=new Vector2(x,-y);r.sizeDelta=new Vector2(w,h);return o;
  }
  [UnityTest]public IEnumerator I08_RetainedUiGeometryAndToolkitNormalInputSurviveImguiScope()
  {
   yield return EditorGameViewResolution.Ensure1280x720();
   var cameraObject=new GameObject("Owned retained UI render camera");var camera=cameraObject.AddComponent<Camera>();
   camera.depth=999;camera.cullingMask=0;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=new Color(.06f,.10f,.15f);
   var canvasRoot=new GameObject("Owned retained uGUI",typeof(Canvas),typeof(CanvasGroup));var canvas=canvasRoot.GetComponent<Canvas>();canvas.renderMode=RenderMode.ScreenSpaceOverlay;
   var viewport=RectObject("Owned visible scroll",canvasRoot.transform,20,20,360,200,typeof(RectMask2D),typeof(ScrollRect));
   var content=RectObject("Owned content",viewport.transform,0,0,330,1280);
   var label=RectObject("Owned label",content.transform,0,0,320,1200,typeof(UnityEngine.UI.Text)).GetComponent<UnityEngine.UI.Text>();
   label.font=Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");label.fontSize=20;label.color=Color.white;label.text=string.Join("\n",Enumerable.Range(1,40).Select(i=>"Day "+i+" Morning Ada food 3"));
   var bar=RectObject("Owned bar",canvasRoot.transform,382,20,18,200,typeof(Image),typeof(Scrollbar)).GetComponent<Scrollbar>();
   var track=RectObject("Owned track",bar.transform,0,0,18,200);
   var handle=RectObject("Owned thumb",track.transform,0,0,18,35,typeof(Image));bar.handleRect=(RectTransform)handle.transform;bar.targetGraphic=handle.GetComponent<Image>();bar.direction=Scrollbar.Direction.BottomToTop;
   var scroll=viewport.GetComponent<ScrollRect>();scroll.viewport=(RectTransform)viewport.transform;scroll.content=(RectTransform)content.transform;scroll.horizontal=false;scroll.verticalScrollbar=bar;
   var uiRoot=new GameObject("Owned retained UITK");var settings=ScriptableObject.CreateInstance<PanelSettings>();settings.scaleMode=PanelScaleMode.ConstantPixelSize;
   var themeFactory=typeof(PanelSettings).GetField("GetOrCreateDefaultTheme",BindingFlags.Static|BindingFlags.NonPublic)?.GetValue(null) as Delegate;
   if(themeFactory!=null)settings.themeStyleSheet=(ThemeStyleSheet)themeFactory.DynamicInvoke();
   var doc=uiRoot.AddComponent<UIDocument>();doc.panelSettings=settings;
   var root=doc.rootVisualElement;root.style.width=1280;root.style.height=720;
   var button=new UButton{name="owned-normal-pointer",text="TOOLKIT NORMAL POINTER"};button.style.position=Position.Absolute;button.style.left=520;button.style.top=20;button.style.width=340;button.style.height=60;root.Add(button);int clicks=0;button.clicked+=()=>clicks++;
   var history=new ScrollView(ScrollViewMode.Vertical){name="owned-visible-history"};history.style.position=Position.Absolute;history.style.left=520;history.style.top=110;history.style.width=360;history.style.height=200;history.verticalScrollerVisibility=ScrollerVisibility.AlwaysVisible;root.Add(history);
   for(var i=1;i<=40;i++){var row=new Label("Day "+i+" Morning Ada food 3");row.style.height=32;row.style.minHeight=32;row.style.fontSize=18;history.Add(row);}
   var evidence=Path.Combine(Environment.GetEnvironmentVariable("STORMBOUND_IMGUI_PROBE_OUTPUT"),"I08");ImguiObservationScope scope=null;var input=new PlayerInputDriver();
   try
   {
    Canvas.ForceUpdateCanvases();yield return input.Ready();for(var i=0;i<4;i++)yield return null;
    scope=new ImguiObservationScope(evidence);yield return scope.Refresh("retained-before");
    var u=PresentationObservers.Scrolls().Single(x=>x.ugui==scroll);Assert.IsTrue(u.hasVerticalScrollbarGeometry,"uGUI actual track/handle geometry");Assert.Greater(u.verticalScrollbarTrack.height,u.verticalScrollbarThumb.height);
    var t=PresentationObservers.Scrolls().Single(x=>x.toolkit==history);Assert.IsTrue(t.hasVerticalScrollbarGeometry,"UITK actual drag-container/dragger geometry");Assert.Greater(t.verticalScrollbarTrack.height,t.verticalScrollbarThumb.height);
    var observed=PresentationObservers.FindControl("^TOOLKIT NORMAL POINTER$");Assert.IsNotNull(observed);Assert.IsTrue(PresentationObservers.CanHit(observed,out var point));
    yield return input.Click(point);yield return scope.Refresh("toolkit-click");Assert.AreEqual(1,clicks,"Actual retained UI engine pointer processing, no callback invocation by the observer");
    var before=t.Offset;yield return input.Scroll(t.screen.center,new Vector2(0,-120));for(var i=0;i<4;i++)yield return null;
    yield return scope.Refresh("toolkit-wheel");Assert.Greater(t.Offset,before);
    canvasRoot.GetComponent<CanvasGroup>().alpha=0;history.style.opacity=0;button.style.opacity=0;yield return null;yield return scope.Refresh("retained-hidden");
    Assert.IsFalse(PresentationObservers.Scrolls().Any(x=>x.ugui==scroll||x.toolkit==history));Assert.IsNull(PresentationObservers.FindControl("^TOOLKIT NORMAL POINTER$"));
   }
   finally
   {
    var cleanup=input.Dispose();while(cleanup.MoveNext()){};scope?.Dispose();Object.DestroyImmediate(uiRoot);Object.DestroyImmediate(settings);Object.DestroyImmediate(canvasRoot);Object.DestroyImmediate(cameraObject);EditorGameViewResolution.Restore();
   }
   Assert.IsTrue(scope.Restored);
  }
 }
}
#endif

