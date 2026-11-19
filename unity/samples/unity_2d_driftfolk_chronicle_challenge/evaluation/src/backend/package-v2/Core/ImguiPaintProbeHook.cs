#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEngine;

namespace GameCreate.Stormbound.Evaluator
{
 // Pinned-engine passive observer; unsupported draw forms fail closed in the scope.
 // It never calls a candidate OnGUI or business method and never suppresses drawing.
 public sealed class ImguiPaintProbeHook:IDisposable
 {
  const BindingFlags All=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static;
  [Serializable]public sealed class PaintFact
  {
   public string text,visible_text,style,kind,visibility_uncertainty;
   public int frame,control_id,repaint_sequence,scroll_state_id;
   public Rect local_rect,unclipped_rect,local_clip,unclipped_clip;
   public Color gui_color,content_color,background_color,text_color;
   public bool enabled,original_return,known_original,gui_state_unchanged,transparent;
   public Matrix4x4 matrix;
   public bool opaque_background;
   public Rect opaque_rect;
   public bool in_scroll_view;
   public Rect scroll_viewport;
   public Vector2 scroll_position;
   public float scroll_extent;
  }
  struct State
  {
   public Color color,content,background;public bool enabled;public Matrix4x4 matrix;
   public static State Read()=>new State{color=GUI.color,content=GUI.contentColor,background=GUI.backgroundColor,enabled=GUI.enabled,matrix=GUI.matrix};
   public bool Same(State other)=>color==other.color&&content==other.content&&background==other.background&&enabled==other.enabled&&matrix==other.matrix;
  }
  readonly FieldInfo field;readonly Delegate previous,installed;readonly Type clip;
  readonly FieldInfo gameViewBackground;readonly PropertyInfo currentView;readonly object ownedParent;
  public int NativeRepaintSequence {get;private set;}
  public int NativeRepaintFrame {get;private set;}=-1;
  public readonly List<PaintFact> facts=new List<PaintFact>();
  public readonly List<string> observer_errors=new List<string>();
  public int original_invocations,observer_invocations;
  public bool injectObserverFailure,restored;
  public bool recordEveryPaint;
  bool disposed;
  public ImguiPaintProbeHook(EditorWindow ownedView=null)
  {
   field=typeof(GUIStyle).GetField("onDraw",All);if(field==null)throw new PresentationUnsupported("Pinned GUIStyle passive hook unavailable");
   previous=(Delegate)field.GetValue(null);clip=typeof(GUI).Assembly.GetType("UnityEngine.GUIClip",true);
   var gameView=typeof(Editor).Assembly.GetType("UnityEditor.GameView",true);
   gameViewBackground=gameView.GetNestedType("Styles",All)?.GetField("gameViewBackgroundStyle",All);
   currentView=typeof(Editor).Assembly.GetType("UnityEditor.GUIView",true).GetProperty("current",All);
   ownedParent=ownedView==null?null:Member(ownedView,"m_Parent");
   if(gameViewBackground==null||currentView==null||(ownedView!=null&&ownedParent==null))throw new PresentationUnsupported("Pinned native GameView repaint-boundary observer unavailable");
   var invoke=field.FieldType.GetMethod("Invoke");var parameters=invoke.GetParameters().Select(p=>Expression.Parameter(p.ParameterType,p.Name)).ToArray();
   var call=Expression.Call(Expression.Constant(this),GetType().GetMethod("Dispatch",All),parameters[0],parameters[1],parameters[2],Expression.Convert(parameters[3],typeof(object)));
   installed=Expression.Lambda(field.FieldType,call,parameters).Compile();field.SetValue(null,installed);
  }
  static object Member(object instance,string name)
  {for(var type=instance.GetType();type!=null;type=type.BaseType){var f=type.GetField(name,All);if(f!=null)return f.GetValue(instance);var p=type.GetProperty(name,All);if(p!=null)return p.GetValue(instance);}return null;}
  Rect Unclip(Rect rect)=>(Rect)clip.GetMethod("Unclip",All,null,new[]{typeof(Rect)},null).Invoke(null,new object[]{rect});
  static bool Intersect(Rect a,Rect b,out Rect value)
  {var x0=Mathf.Max(a.xMin,b.xMin);var y0=Mathf.Max(a.yMin,b.yMin);var x1=Mathf.Min(a.xMax,b.xMax);var y1=Mathf.Min(a.yMax,b.yMax);value=Rect.MinMaxRect(x0,y0,x1,y1);return x1>x0&&y1>y0;}
  static bool Contains(Rect a,Rect b)=>a.xMin<=b.xMin&&a.yMin<=b.yMin&&a.xMax>=b.xMax&&a.yMax>=b.yMax;
  string VisibleText(GUIStyle style,Rect position,GUIContent content,Rect visible,float alpha)
  {
   if(alpha<=.01f||content==null||string.IsNullOrEmpty(content.text))return "";
   if(!Intersect(position,visible,out var area))return "";
   var raw=content.text;
   if(style.richText&&Regex.Matches(raw,@"<color=#([0-9a-f]{8})>",RegexOptions.IgnoreCase).Cast<Match>().Any(tag=>Convert.ToInt32(tag.Groups[1].Value.Substring(6,2),16)<=2))
    throw new PresentationUnsupported("Per-span transparent rich text requires an independently qualified glyph/pixel observer");
   if(Contains(visible,position))return PresentationObservers.SemanticText(raw);
   if(style.richText&&raw.Contains("<"))throw new PresentationUnsupported("Partially clipped rich text needs qualified raw-index/glyph mapping");
   var result=new StringBuilder();var height=Mathf.Max(1,style.lineHeight);
   for(var index=0;index<raw.Length;index++)
   {
    var a=style.GetCursorPixelPosition(position,content,index);var b=style.GetCursorPixelPosition(position,content,index+1);
    var width=b.y>a.y+.1f?Mathf.Max(1,style.CalcSize(new GUIContent(raw[index].ToString())).x):Mathf.Max(1,b.x-a.x);
    var glyph=new Rect(a.x,a.y,width,height);
    if(Intersect(glyph,area,out var clipped)&&clipped.width*clipped.height>=glyph.width*glyph.height*.7f)result.Append(raw[index]);
    else if(result.Length>0&&!char.IsWhiteSpace(result[result.Length-1]))result.Append(' ');
   }
   return PresentationObservers.SemanticText(result.ToString());
  }
  static bool OpaqueTexture(Texture2D texture)
  {
   if(!texture||!texture.isReadable)return false;
   try{return texture.GetPixels32().All(pixel=>pixel.a>=254);}catch{return false;}
  }
  bool RuntimeRepaint(GUIStyle style,out string kind)
  {
   kind="text";if(Event.current==null||Event.current.type!=EventType.Repaint)return false;
   if(ownedParent!=null&&!ReferenceEquals(currentView.GetValue(null),ownedParent))return false;
   var frames=new StackTrace(false).GetFrames();if(frames==null)return false;
   var methods=frames.Select(frame=>frame.GetMethod()).Where(method=>method!=null).ToArray();
   if(ReferenceEquals(style,gameViewBackground.GetValue(null))&&methods.Any(method=>method.DeclaringType?.FullName=="UnityEditor.GameView"&&method.Name=="OnGUI"))
   {NativeRepaintSequence++;NativeRepaintFrame=Time.frameCount;return false;}
   if(!methods.Any(method=>method.DeclaringType==typeof(EditorGUIUtility)&&method.Name.StartsWith("RenderPlayModeViewCamerasInternal",StringComparison.Ordinal)))return false;
   if(methods.Any(method=>method.DeclaringType==typeof(GUI)&&method.Name=="VerticalScrollbar")&&methods.Any(method=>method.DeclaringType?.FullName=="UnityEngine.SliderHandler"))kind="vertical-scrollbar";
   else if(methods.Any(method=>method.DeclaringType==typeof(GUI)&&method.Name=="Button"))kind="button";
   else if(methods.Any(method=>method.DeclaringType==typeof(GUI)&&method.Name=="Box"))kind="box";
   return true;
  }
  bool Dispatch(GUIStyle style,Rect position,GUIContent content,object states)
  {
   bool observe=false;string kind=null;State before=default;bool beforeValid=false;
   try{observe=RuntimeRepaint(style,out kind);if(observe){before=State.Read();beforeValid=true;}}
   catch(Exception error){observer_errors.Add("before: "+error.GetBaseException().Message);}
   var result=false;var anyTrue=false;var allKnown=true;var handlers=previous?.GetInvocationList()??Array.Empty<Delegate>();
   foreach(var handler in handlers)
   {
    // Preserve exact multicast order/count and stop on the same original exception.
    try{result=(bool)handler.DynamicInvoke(style,position,content,states);original_invocations++;}
    catch(TargetInvocationException error)when(error.InnerException!=null){ExceptionDispatchInfo.Capture(error.InnerException).Throw();throw;}
    anyTrue|=result;
    allKnown&=handler.Method.DeclaringType?.FullName=="UnityEditor.StyleSheets.StylePainter"&&handler.Method.Name=="DrawStyle";
   }
   if(observe)
   {
    try
    {
     observer_invocations++;if(injectObserverFailure)throw new InvalidOperationException("Owned observer-fault control");
     var after=State.Read();var visible=(Rect)clip.GetProperty("visibleRect",All).GetValue(null);
     var fact=new PaintFact{text=content?.text??"",style=style?.name??"",kind=kind,frame=Time.frameCount,repaint_sequence=NativeRepaintSequence,
      local_rect=position,unclipped_rect=Unclip(position),local_clip=visible,unclipped_clip=Unclip(visible),
      gui_color=after.color,content_color=after.content,background_color=after.background,enabled=after.enabled,matrix=after.matrix,
      text_color=style==null?Color.clear:style.normal.textColor,control_id=(int)(Member(states,"controlId")??-1),original_return=result,
      known_original=allKnown,gui_state_unchanged=beforeValid&&before.Same(after)};
     if(anyTrue&&(!allKnown||handlers.Length!=1||!fact.gui_state_unchanged))
      fact.visibility_uncertainty="An original handler painted/suppressed with unqualified state timing; image observation required";
     fact.transparent=fact.gui_color.a*fact.content_color.a*fact.text_color.a<=.01f;
     try{fact.visible_text=VisibleText(style,position,content,visible,fact.gui_color.a*fact.content_color.a*fact.text_color.a);}
     catch(PresentationUnsupported error){fact.visibility_uncertainty=error.Message;fact.visible_text="";}
     fact.opaque_background=style!=null&&fact.gui_color.a*fact.background_color.a>=.99f&&OpaqueTexture(style.normal.background);
     fact.opaque_rect=Intersect(fact.unclipped_rect,fact.unclipped_clip,out var opaqueClip)?opaqueClip:default;
     var scrollStack=typeof(GUI).GetProperty("scrollViewStates",All)?.GetValue(null);
     if(scrollStack!=null&&(int)scrollStack.GetType().GetProperty("Count",All).GetValue(scrollStack)>0)
     {
      var state=scrollStack.GetType().GetMethod("Peek",All,null,Type.EmptyTypes,null).Invoke(scrollStack,null);
      var viewRect=(Rect)Member(state,"viewRect");var viewPort=(Rect)Member(state,"visibleRect");
      fact.in_scroll_view=true;fact.scroll_state_id=RuntimeHelpers.GetHashCode(state);fact.scroll_viewport=fact.unclipped_clip;
      fact.scroll_position=(Vector2)Member(state,"scrollPosition");fact.scroll_extent=Mathf.Max(0,viewRect.height-viewPort.height);
     }
     if(recordEveryPaint||!facts.Any(x=>x.text==fact.text&&x.unclipped_rect==fact.unclipped_rect&&x.gui_color==fact.gui_color&&x.content_color==fact.content_color&&x.enabled==fact.enabled))facts.Add(fact);
    }
    catch(Exception error){observer_errors.Add("after: "+error.GetBaseException().Message);}
   }
   return result;
  }
  public void Dispose()
  {
   if(disposed)return;disposed=true;
   var current=(Delegate)field.GetValue(null);
   if(ReferenceEquals(current,installed)){field.SetValue(null,previous);restored=ReferenceEquals(field.GetValue(null),previous);}
   else
   {
    var calls=current?.GetInvocationList()??Array.Empty<Delegate>();var output=new List<Delegate>();var found=0;
    foreach(var call in calls)
     if(call.Equals(installed)){found++;if(previous!=null)output.AddRange(previous.GetInvocationList());}
     else output.Add(call);
    if(found==1){field.SetValue(null,output.Count==0?null:Delegate.Combine(output.ToArray()));restored=true;}
    else {observer_errors.Add("Engine hook owner changed; do not overwrite another observer");restored=false;}
   }
  }
 }
}
#endif

