#if UNITY_EDITOR
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using Object=UnityEngine.Object;
namespace GameCreate.Stormbound.Evaluator
{
 // Private GameView observation. Only engine draw state is read, never candidate fields.
 public sealed class ImguiObservationScope:IDisposable
 {
  const BindingFlags All=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static;
  public static ImguiObservationScope Current {get;private set;}
  readonly ImguiPaintProbeHook hook;
  readonly EditorWindow view;
  readonly string evidenceRoot;
  readonly List<PresentedText> texts=new List<PresentedText>();
  readonly List<PresentedControl> controls=new List<PresentedControl>();
  readonly Dictionary<string,ImguiPaintProbeHook.PaintFact> scrolls=new Dictionary<string,ImguiPaintProbeHook.PaintFact>();
  readonly Dictionary<string,PresentedScroll> scrollGeometry=new Dictionary<string,PresentedScroll>();
  public IReadOnlyList<ImguiPaintProbeHook.PaintFact> Paints {get;private set;}=Array.Empty<ImguiPaintProbeHook.PaintFact>();
  public int Frame {get;private set;}=-1;
  public int Sequence {get;private set;}
  public int RepaintSequence {get;private set;}
  public string ImagePath {get;private set;}
  public string ImageSha256 {get;private set;}
  public bool HasRuntimeSurface=>Paints.Count>0;
  public bool HasTextMetadata=>Paints.Any(row=>!string.IsNullOrWhiteSpace(row.text));
  public bool Restored {get;private set;}
  public ImguiObservationScope(string evidenceRoot)
  {
   if(Current!=null)throw new PresentationUnsupported("Nested IMGUI observation ownership");
   this.evidenceRoot=evidenceRoot;Directory.CreateDirectory(evidenceRoot);
   var type=typeof(Editor).Assembly.GetType("UnityEditor.GameView",true);
   view=Resources.FindObjectsOfTypeAll(type).OfType<EditorWindow>().FirstOrDefault();
   if(!view)throw new PresentationUnsupported("No owned GameView available for native UI observation");
   hook=new ImguiPaintProbeHook(view){recordEveryPaint=true};Current=this;
  }
  public IEnumerable<PresentedText> Texts()=>texts;
  public IEnumerable<PresentedControl> Controls(bool includeDisabled)=>controls.Where(row=>includeDisabled||row.interactable);
  static string ScrollKey(ImguiPaintProbeHook.PaintFact value)=>"IMGUI-state:"+value.scroll_state_id;
  public float ScrollOffset(string key)=>scrolls.TryGetValue(key,out var row)?row.scroll_position.y:throw new PresentationUnsupported("Native scroll surface changed before observation");
  public float ScrollExtent(string key)=>scrolls.TryGetValue(key,out var row)?row.scroll_extent:throw new PresentationUnsupported("Native scroll surface changed before observation");
  public string ScrollText(string key)=>string.Join("\n",texts.Where(row=>row.imguiScrollKey==key).Select(row=>row.text));
  public IEnumerable<PresentedScroll> Scrolls()=>scrollGeometry.Values;
  static bool Clip(Rect a,Rect b,out Rect result)
  {var x0=Mathf.Max(a.xMin,b.xMin);var y0=Mathf.Max(a.yMin,b.yMin);var x1=Mathf.Min(a.xMax,b.xMax);var y1=Mathf.Min(a.yMax,b.yMax);result=Rect.MinMaxRect(x0,y0,x1,y1);return x1>x0&&y1>y0;}
  static Rect BottomLeft(Rect rectangle)=>new Rect(rectangle.x,Screen.height-rectangle.yMax,rectangle.width,rectangle.height);
  static bool Covers(Rect outer,Rect inner)=>outer.xMin<=inner.xMin&&outer.yMin<=inner.yMin&&outer.xMax>=inner.xMax&&outer.yMax>=inner.yMax;
  public IEnumerator Refresh(string label,bool saveFrame=true)
  {
   var start=Time.frameCount;var startRepaint=hook.NativeRepaintSequence;
   hook.facts.Clear();hook.observer_errors.Clear();
   // A pinned GameView's own background paint marks the beginning of its real
   // RenderView transaction, including frames with zero runtime style draws.
   // Await its completion through the normal Editor loop; never invoke OnGUI.
   var deadline=Time.realtimeSinceStartup+3f;
   do{view.Repaint();yield return null;}
   while((hook.NativeRepaintSequence<=startRepaint||hook.NativeRepaintFrame<start)&&Time.realtimeSinceStartup<deadline);
   if(hook.observer_errors.Count>0)throw new PresentationUnsupported("Passive IMGUI observer fault: "+string.Join(" | ",hook.observer_errors));
   if(hook.NativeRepaintSequence<=startRepaint||hook.NativeRepaintFrame<start)throw new PresentationUnsupported("No fresh owned native GameView repaint completed");
   Frame=hook.NativeRepaintFrame;RepaintSequence=hook.NativeRepaintSequence;
   var rows=hook.facts.Where(row=>row.repaint_sequence==RepaintSequence).ToArray();
   if(rows.Any(row=>row.frame!=Frame))throw new PresentationUnsupported("Native repaint/draw frame mismatch");
   Paints=rows;Sequence++;
   ImagePath=Path.Combine(evidenceRoot,Sequence.ToString("D4")+"-"+label+"-native.png");
   if(saveFrame){SaveNativeFrame(ImagePath);ImageSha256=Hash(File.ReadAllBytes(ImagePath));}
   else {ImagePath=null;ImageSha256=null;}
   texts.Clear();controls.Clear();scrolls.Clear();scrollGeometry.Clear();
   var visible=new Rect(0,0,Screen.width,Screen.height);
   var seen=new HashSet<string>();
   for(var i=0;i<rows.Length;i++)
   {
    var row=rows[i];
    var scrollKey=row.in_scroll_view?ScrollKey(row):null;
    if(scrollKey!=null&&row.kind!="vertical-scrollbar"&&row.scroll_viewport.width>0&&row.scroll_viewport.height>0)scrolls[scrollKey]=row;
    if(row.transparent||!Clip(row.unclipped_rect,visible,out var rect)||
       !Clip(rect,row.unclipped_clip,out rect))continue;
    if(!string.IsNullOrEmpty(row.visibility_uncertainty))throw new PresentationUnsupported(row.visibility_uncertainty);
    if(string.IsNullOrWhiteSpace(row.visible_text))continue;
    // A later fully opaque known GUI background cannot expose the earlier label.
    if(rows.Skip(i+1).Any(later=>later.opaque_background&&Covers(later.opaque_rect,rect)))continue;
    var key=row.visible_text+"|"+rect;
    if(!seen.Add(key))continue;
    var presented=new PresentedText{text=row.visible_text,framework="IMGUI-native-Repaint",owner="native GameView draw",screen=BottomLeft(rect),imguiScrollKey=scrollKey};
    texts.Add(presented);
    // A label may be a completely legal custom New-Input pointer target.
    // Geometry is only an attempted action point, never proof of input wiring.
    controls.Add(new PresentedControl{label=row.visible_text,screen=presented.screen,interactable=row.enabled,framework="IMGUI-native-Repaint",isCandidateOnly=row.kind!="button"});
   }
   foreach(var pair in scrolls)
   {
    var geometry=new PresentedScroll{key=pair.Key,imguiKey=pair.Key,screen=BottomLeft(pair.Value.scroll_viewport)};
    foreach(var group in rows.Where(row=>row.kind=="vertical-scrollbar"&&row.scroll_state_id==pair.Value.scroll_state_id&&row.enabled&&row.gui_color.a*row.background_color.a>.01f).GroupBy(row=>row.control_id))
    {
     var paints=group.ToArray();if(paints.Length!=2)continue;
     // Pinned SliderHandler.OnRepaint draws track then thumb with one ID.
     var track=paints[0].unclipped_rect;var thumb=paints[1].unclipped_rect;
     if(track.height<=track.width||thumb.height>=track.height||!Covers(track,thumb)||
        !Clip(track,visible,out track)||!Clip(track,paints[0].unclipped_clip,out track)||
        !Clip(thumb,visible,out thumb)||!Clip(thumb,paints[1].unclipped_clip,out thumb))continue;
     geometry.hasVerticalScrollbarGeometry=true;geometry.verticalScrollbarTrack=BottomLeft(track);geometry.verticalScrollbarThumb=BottomLeft(thumb);break;
    }
    scrollGeometry[pair.Key]=geometry;
   }
   File.WriteAllText(Path.Combine(evidenceRoot,Sequence.ToString("D4")+"-"+label+"-draws.json"),
    JsonUtility.ToJson(new Snapshot{frame=Frame,sequence=Sequence,repaint_sequence=RepaintSequence,width=Screen.width,height=Screen.height,native_frame=ImagePath,native_frame_sha256=ImageSha256,paints=rows.ToList(),texts=texts.ToList()},true));
  }
  [Serializable]sealed class Snapshot
  {public int frame,sequence,repaint_sequence,width,height;public string native_frame,native_frame_sha256;public List<ImguiPaintProbeHook.PaintFact> paints;public List<PresentedText> texts;}
  static object Member(object value,string name)
  {for(var type=value.GetType();type!=null;type=type.BaseType){var property=type.GetProperty(name,All);if(property!=null)return property.GetValue(value);var field=type.GetField(name,All);if(field!=null)return field.GetValue(value);}return null;}
  void SaveNativeFrame(string path)
  {
   var target=Member(view,"m_RenderTexture") as RenderTexture??Member(view,"m_TargetTexture") as RenderTexture;
   if(!target||target.width!=Screen.width||target.height!=Screen.height)throw new PresentationUnsupported("Native GameView texture not current target size");
   var previous=RenderTexture.active;Texture2D copy=null;
   try
   {
    RenderTexture.active=target;copy=new Texture2D(target.width,target.height,TextureFormat.RGBA32,false);
    copy.ReadPixels(new Rect(0,0,target.width,target.height),0,0);copy.Apply();
    var raw=copy.GetPixels32();var normalized=new Color32[raw.Length];
    for(var y=0;y<target.height;y++)Array.Copy(raw,y*target.width,normalized,(target.height-1-y)*target.width,target.width);
    copy.SetPixels32(normalized);copy.Apply();File.WriteAllBytes(path,copy.EncodeToPNG());
   }
   finally{RenderTexture.active=previous;if(copy)Object.DestroyImmediate(copy);}
  }
  static string Hash(byte[] data){using(var sha=System.Security.Cryptography.SHA256.Create())return BitConverter.ToString(sha.ComputeHash(data)).Replace("-","").ToLowerInvariant();}
  public void Dispose(){hook.Dispose();Restored=hook.restored;if(ReferenceEquals(Current,this))Current=null;}
 }
}
#endif
