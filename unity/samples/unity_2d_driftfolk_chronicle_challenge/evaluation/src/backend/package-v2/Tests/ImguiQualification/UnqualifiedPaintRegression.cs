#if UNITY_EDITOR
using System;
using System.Collections;
using System.IO;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using Object=UnityEngine.Object;
namespace GameCreate.Stormbound.Evaluator.ImguiQualification
{
 public sealed class OwnedUnqualifiedPaint:MonoBehaviour
 {
  public int mode;
  void OnGUI()
  {
   var style=new GUIStyle(GUI.skin.label){richText=true};
   if(mode==0)GUI.Label(new Rect(30,30,360,40),"UNKNOWN HANDLER TEXT",style);
   if(mode==1)GUI.Label(new Rect(30,30,360,40),"VISIBLE <color=#FFFFFF00>TRANSPARENT SPAN</color>",style);
   if(mode==2){GUI.BeginGroup(new Rect(30,30,90,40));GUI.Label(new Rect(0,0,360,40),"<b>PARTIALLY CLIPPED RICH TEXT</b>",style);GUI.EndGroup();}
  }
 }
 public sealed class UnqualifiedPaintRegression
 {
  const BindingFlags All=BindingFlags.Static|BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic;
  static Delegate Handler(Type type,Func<bool> operation)
  {var args=type.GetMethod("Invoke").GetParameters().Select(x=>Expression.Parameter(x.ParameterType,x.Name)).ToArray();return Expression.Lambda(type,Expression.Invoke(Expression.Constant(operation)),args).Compile();}
  [Test]public void I09_OriginalThrowStopsMulticastAndRestoresWithoutWrapping()
  {
   var field=typeof(GUIStyle).GetField("onDraw",All);var original=(Delegate)field.GetValue(null);ImguiPaintProbeHook hook=null;var expected=new InvalidOperationException("Owned-original-error");int after=0;
   try
   {
    field.SetValue(null,Delegate.Combine(Handler(field.FieldType,()=>{throw expected;}),Handler(field.FieldType,()=>{after++;return true;})));
    var prior=field.GetValue(null);hook=new ImguiPaintProbeHook();
    var state=Activator.CreateInstance(field.FieldType.GetMethod("Invoke").GetParameters()[3].ParameterType);
    var error=Assert.Throws<TargetInvocationException>(()=>((Delegate)field.GetValue(null)).DynamicInvoke(null,default(Rect),GUIContent.none,state));
    Assert.AreSame(expected,error.InnerException);Assert.AreEqual(0,after);hook.Dispose();Assert.AreSame(prior,field.GetValue(null));Assert.IsTrue(hook.restored);
   }
   finally{hook?.Dispose();field.SetValue(null,original);}
  }
  [Serializable]sealed class UnsupportedFact{public int mode;public string reason,native_frame,native_frame_sha256;public bool restored;}
  [UnityTest]public IEnumerator I10_UnknownHandlerTransparentSpanAndPartialRichTextAreUnsupported()
  {
   yield return EditorGameViewResolution.Ensure1280x720();var owned=new GameObject("Owned unsupported paint forms");var surface=owned.AddComponent<OwnedUnqualifiedPaint>();
   var cameraObject=new GameObject("Owned unsupported camera");var camera=cameraObject.AddComponent<Camera>();camera.depth=999;camera.cullingMask=0;camera.clearFlags=CameraClearFlags.SolidColor;camera.backgroundColor=Color.black;
   var field=typeof(GUIStyle).GetField("onDraw",All);var original=(Delegate)field.GetValue(null);
   var root=Path.Combine(Environment.GetEnvironmentVariable("STORMBOUND_IMGUI_PROBE_OUTPUT"),"I10");Directory.CreateDirectory(root);ImguiObservationScope scope=null;
   try
   {
    for(var mode=0;mode<3;mode++)
    {
     surface.mode=mode;if(mode==0)field.SetValue(null,Handler(field.FieldType,()=>true));else field.SetValue(null,original);
     scope=new ImguiObservationScope(Path.Combine(root,"mode-"+mode));var refresh=scope.Refresh("unsupported");Exception error=null;
     while(true)
     {
      bool more=false;try{more=refresh.MoveNext();}catch(Exception ex){error=ex;}
      if(error!=null||!more)break;yield return refresh.Current;
     }
     scope.Dispose();var fact=new UnsupportedFact{mode=mode,reason=error?.Message,native_frame=scope.ImagePath,native_frame_sha256=scope.ImageSha256,restored=scope.Restored};
     File.WriteAllText(Path.Combine(root,"mode-"+mode+".json"),JsonUtility.ToJson(fact,true));
     Assert.IsInstanceOf<PresentationUnsupported>(error,"Unqualified rendering must not become an absent/product failure or visible/pass result");Assert.IsTrue(scope.Restored);scope=null;
    }
   }
   finally{scope?.Dispose();field.SetValue(null,original);Object.DestroyImmediate(owned);Object.DestroyImmediate(cameraObject);EditorGameViewResolution.Restore();}
  }
 }
}
#endif
