#if UNITY_EDITOR
using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEngine;
namespace GameCreate.Stormbound.Evaluator
{
 // Host viewport configuration only, established before any candidate Awake.
 // No candidate gameplay fields, camera settings or Canvas layout are written.
 public static class EditorGameViewResolution
 {
  static EditorWindow window;static object group;static PropertyInfo selection;static int oldSelection,customIndex=-1;static bool configured,createdWindow;static Rect oldWindowPosition;
  public static bool LastRestorationVerified {get;private set;}
 public static string LastRestorationDetails {get;private set;}
 static int oldCustomCount;
 const BindingFlags All=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static;
  public static IEnumerator Ensure1280x720()
  {
   // Screen retains its last dimensions after an owned GameView is closed.
   // A later test still needs a live native view, not that stale size alone.
   var viewType=typeof(Editor).Assembly.GetType("UnityEditor.GameView",true);
   if(Screen.width==1280&&Screen.height==720&&Resources.FindObjectsOfTypeAll(viewType).Length>0)yield break;
   if(!configured)Configure();
   for(int i=0;i<60&&(Screen.width!=1280||Screen.height!=720);i++)yield return null;
   if(Screen.width!=1280||Screen.height!=720)throw new InvalidOperationException("Evaluator GameView target resolution unavailable: "+Screen.width+"x"+Screen.height+"; expected1280x720");
  }
  static void Configure()
  {
   var assembly=typeof(Editor).Assembly;var viewType=assembly.GetType("UnityEditor.GameView",true);var sizesType=assembly.GetType("UnityEditor.GameViewSizes",true);var groupType=assembly.GetType("UnityEditor.GameViewSizeGroupType",true);var sizeType=assembly.GetType("UnityEditor.GameViewSize",true);var modeType=assembly.GetType("UnityEditor.GameViewSizeType",true);
   var instance=sizesType.BaseType.GetProperty("instance",All).GetValue(null,null);
   group=sizesType.GetMethod("GetGroup",All).Invoke(instance,new[]{Enum.Parse(groupType,"Standalone")});
   var g=group.GetType();int builtin=(int)g.GetMethod("GetBuiltinCount",All).Invoke(group,null);int custom=(int)g.GetMethod("GetCustomCount",All).Invoke(group,null);int chosen=-1;oldCustomCount=custom;LastRestorationVerified=false;
   for(int i=0;i<builtin+custom;i++){var size=g.GetMethod("GetGameViewSize",All).Invoke(group,new object[]{i});if((int)sizeType.GetProperty("width",All).GetValue(size,null)==1280&&(int)sizeType.GetProperty("height",All).GetValue(size,null)==720){chosen=i;break;}}
   if(chosen<0){var size=Activator.CreateInstance(sizeType,All,null,new object[]{Enum.Parse(modeType,"FixedResolution"),1280,720,"Session evaluation 1280x720"},null);g.GetMethod("AddCustomSize",All).Invoke(group,new[]{size});chosen=builtin+custom;customIndex=chosen;}
   window=Resources.FindObjectsOfTypeAll(viewType).OfType<EditorWindow>().FirstOrDefault();createdWindow=!window;if(!window)window=EditorWindow.GetWindow(viewType,false,"Game",false);oldWindowPosition=window.position;
   selection=viewType.GetProperty("selectedSizeIndex",All);oldSelection=(int)selection.GetValue(window,null);selection.SetValue(window,chosen,null);window.Repaint();configured=true;EditorApplication.quitting+=Restore;
  }
  public static void Restore()
  {
   if(!configured)return;
   try{if(window&&selection!=null)selection.SetValue(window,oldSelection,null);if(window){window.position=oldWindowPosition;if(createdWindow)window.Close();}if(customIndex>=0&&group!=null)group.GetType().GetMethod("RemoveCustomSize",All).Invoke(group,new object[]{customIndex});
 int afterCustom=(int)group.GetType().GetMethod("GetCustomCount",All).Invoke(group,null);bool windowOk=createdWindow?!window:window&&(int)selection.GetValue(window,null)==oldSelection&&window.position==oldWindowPosition;LastRestorationVerified=windowOk&&afterCustom==oldCustomCount;LastRestorationDetails="selection="+oldSelection+";window_ok="+windowOk+";owned_window="+createdWindow+";custom_count="+oldCustomCount+"->"+afterCustom;}
   finally{configured=false;customIndex=-1;EditorApplication.quitting-=Restore;}
  }
 }
}
#endif
