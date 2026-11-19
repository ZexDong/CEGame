#if UNITY_EDITOR
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using TMPro;
using UnityEditor;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using UnityEngine.UIElements;
using Object = UnityEngine.Object;
using UIButton = UnityEngine.UI.Button;
using UIEButton = UnityEngine.UIElements.Button;

namespace GameCreate.Stormbound.Evaluator
{
    public sealed class PresentationUnsupported : Exception
    {
        public PresentationUnsupported(string message) : base(message) { }
    }

    [Serializable] public sealed class PresentedText
    {
        public string text, framework, owner;
        public Rect screen;
        [NonSerialized] public Component component;
        [NonSerialized] public VisualElement element;
        public string imguiScrollKey;
    }

    public sealed class PresentedControl
    {
        public string label;
        public string framework;
        public Rect screen;
        public Selectable selectable;
        public VisualElement element;
        public bool interactable;
        // True means visible text offers an ordinary pointer attempt only;
        // nonresponse is not evidence that this label was a control.
        public bool isCandidateOnly;
        public Vector2 Point => screen.center;
    }

    public sealed class PresentedScroll
    {
        public string key;
        public Rect screen;
        public ScrollRect ugui;
        public ScrollView toolkit;
        public string imguiKey;
        public bool hasVerticalScrollbarGeometry;
        public Rect verticalScrollbarTrack,verticalScrollbarThumb;
        public float Offset => ugui ? ugui.verticalNormalizedPosition : toolkit!=null?toolkit.scrollOffset.y:ImguiObservationScope.Current.ScrollOffset(imguiKey);
        public float Extent => ugui
            ? Mathf.Max(0, ugui.content.rect.height - (ugui.viewport ? ugui.viewport.rect.height : ((RectTransform)ugui.transform).rect.height))
            : toolkit!=null?Mathf.Max(0, toolkit.contentContainer.layout.height - toolkit.contentViewport.layout.height):ImguiObservationScope.Current.ScrollExtent(imguiKey);
    }

    public static class PresentationObservers
    {
        static readonly PropertyInfo ToolkitWorldClip=typeof(VisualElement).GetProperty("worldClip",BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic);
        public static Rect Viewport => new Rect(0, 0, Screen.width, Screen.height);
        public static bool Clip(Rect a, Rect b, out Rect result)
        {
            var x0 = Mathf.Max(a.xMin, b.xMin); var y0 = Mathf.Max(a.yMin, b.yMin);
            var x1 = Mathf.Min(a.xMax, b.xMax); var y1 = Mathf.Min(a.yMax, b.yMax);
            result = Rect.MinMaxRect(x0, y0, x1, y1);
            return x1 > x0 && y1 > y0;
        }

        public static string SemanticText(string text)
        {
            return Regex.Replace(PlainText(text), @"\s+", " ").Trim();
        }

        static string PlainText(string text) => Regex.Replace(text ?? "", @"</?(?:b|i|u|s|size|color|alpha|font|material|align|style|sprite|link|mark|voffset|space|cspace|mspace|line-height|indent|margin|width|nobr|noparse)(?:[ =][^>]*)?>", "", RegexOptions.IgnoreCase);

        public static bool HasSupportedTextSurface() =>
            Object.FindObjectsByType<UnityEngine.UI.Text>(FindObjectsInactive.Include,FindObjectsSortMode.None).Length>0 ||
            Object.FindObjectsByType<TMP_Text>(FindObjectsInactive.Include,FindObjectsSortMode.None).Length>0 ||
            Object.FindObjectsByType<TextMesh>(FindObjectsInactive.Include,FindObjectsSortMode.None).Length>0 ||
            Object.FindObjectsByType<UIDocument>(FindObjectsInactive.Include,FindObjectsSortMode.None).Length>0 ||
            ImguiObservationScope.Current!=null&&ImguiObservationScope.Current.HasTextMetadata;

        static string VisibleUiText(UnityEngine.UI.Text text,Rect clip)
        {
            var raw=text.text??"";var plain=PlainText(raw);var generator=text.cachedTextGenerator;
            if(generator.lines.Count<=1)return plain;
            var lines=generator.lines;var output=new List<string>();
            var canvas=text.canvas;var camera=canvas.renderMode==RenderMode.ScreenSpaceOverlay?null:canvas.worldCamera;
            var scale=Mathf.Max(.0001f,text.pixelsPerUnit);
            for(var i=0;i<lines.Count;i++)
            {
                // TextGenerator offsets refer to its original input, including rich-text tags.
                // Stripping tags before applying these offsets moves later visible rows incorrectly.
                var start=lines[i].startCharIdx;var end=i+1<lines.Count?lines[i+1].startCharIdx:raw.Length;
                if(start>=raw.Length)continue;end=Mathf.Min(end,raw.Length);
                var local=text.rectTransform.rect;
                var a=RectTransformUtility.WorldToScreenPoint(camera,text.transform.TransformPoint(new Vector3(local.xMin,lines[i].topY/scale,0)));
                var b=RectTransformUtility.WorldToScreenPoint(camera,text.transform.TransformPoint(new Vector3(local.xMax,(lines[i].topY-lines[i].height)/scale,0)));
                var line=Rect.MinMaxRect(Mathf.Min(a.x,b.x),Mathf.Min(a.y,b.y),Mathf.Max(a.x,b.x),Mathf.Max(a.y,b.y));
                if(Clip(line,clip,out _))output.Add(PlainText(raw.Substring(start,Mathf.Max(0,end-start))).Trim());
            }
            return string.Join("\n",output);
        }

        static string VisibleTmpText(TMP_Text text,Rect clip)
        {
            var info=text.textInfo;
            if(info==null||info.lineCount<=1)return text.text;
            var canvas=text.canvas;var camera=canvas && canvas.renderMode!=RenderMode.ScreenSpaceOverlay?canvas.worldCamera:null;
            var output=new System.Text.StringBuilder();var previousLine=-1;
            for(var i=0;i<info.characterCount;i++)
            {
                var c=info.characterInfo[i];
                if(!c.isVisible)continue;
                var a=RectTransformUtility.WorldToScreenPoint(camera,text.transform.TransformPoint(c.bottomLeft));
                var b=RectTransformUtility.WorldToScreenPoint(camera,text.transform.TransformPoint(c.topRight));
                if(!Clip(Rect.MinMaxRect(Mathf.Min(a.x,b.x),Mathf.Min(a.y,b.y),Mathf.Max(a.x,b.x),Mathf.Max(a.y,b.y)),clip,out _))continue;
                if(previousLine>=0&&previousLine!=c.lineNumber)output.Append('\n');
                else if(i>0&&char.IsWhiteSpace(info.characterInfo[i-1].character))output.Append(' ');
                output.Append(c.character);previousLine=c.lineNumber;
            }
            return output.ToString();
        }

        static float HierarchyAlpha(Transform transform)
        {
            var alpha = 1f;
            for (var t = transform; t; t = t.parent)
            {
                var stop = false;
                foreach (var group in t.GetComponents<CanvasGroup>())
                {
                    alpha *= group.alpha;
                    stop |= group.ignoreParentGroups;
                }
                if (stop) break;
            }
            return alpha;
        }

        static bool RectOnScreen(RectTransform rect, out Rect screen)
        {
            screen = default;
            var canvas = rect.GetComponentInParent<Canvas>();
            if (!canvas || !canvas.enabled || !canvas.gameObject.activeInHierarchy) return false;
            var camera = canvas.renderMode == RenderMode.ScreenSpaceOverlay ? null : canvas.worldCamera;
            if (canvas.renderMode != RenderMode.ScreenSpaceOverlay && (!camera || !camera.isActiveAndEnabled)) return false;
            var corners = new Vector3[4]; rect.GetWorldCorners(corners);
            var points = corners.Select(x => RectTransformUtility.WorldToScreenPoint(camera, x)).ToArray();
            var raw = Rect.MinMaxRect(points.Min(x => x.x), points.Min(x => x.y), points.Max(x => x.x), points.Max(x => x.y));
            if (!Clip(raw, Viewport, out screen)) return false;
            for (var t = rect.parent; t; t = t.parent)
            {
                var mask = t.GetComponent<RectMask2D>();
                var stencil = t.GetComponent<Mask>();
                if ((mask && mask.enabled) || (stencil && stencil.enabled))
                {
                    var r = t as RectTransform;
                    if (r && !MaskRect(r, camera, ref screen)) return false;
                }
            }
            return screen.width > .5f && screen.height > .5f;
        }

        static bool MaskRect(RectTransform rect, Camera camera, ref Rect clip)
        {
            var c = new Vector3[4]; rect.GetWorldCorners(c);
            var p = c.Select(x => RectTransformUtility.WorldToScreenPoint(camera, x)).ToArray();
            return Clip(clip, Rect.MinMaxRect(p.Min(x => x.x), p.Min(x => x.y), p.Max(x => x.x), p.Max(x => x.y)), out clip);
        }

        public static bool GraphicVisible(Graphic graphic, out Rect screen)
        {
            screen = default;
            return graphic && graphic.enabled && graphic.gameObject.activeInHierarchy &&
                graphic.color.a * graphic.canvasRenderer.GetAlpha() * HierarchyAlpha(graphic.transform) > .01f &&
                !graphic.canvasRenderer.cull && RectOnScreen(graphic.rectTransform, out screen);
        }

        // RuntimePanelUtils supplies the actual panel scaling, including a reference resolution.
        public static Vector2 PanelToScreen(IPanel panel, Vector2 panelPoint)
        {
            var origin = RuntimePanelUtils.ScreenToPanel(panel, Vector2.zero);
            var x = RuntimePanelUtils.ScreenToPanel(panel, new Vector2(Screen.width, 0)) - origin;
            var y = RuntimePanelUtils.ScreenToPanel(panel, new Vector2(0, Screen.height)) - origin;
            var delta = panelPoint - origin;
            var determinant = x.x * y.y - x.y * y.x;
            if (Mathf.Abs(determinant) < .00001f) throw new PresentationUnsupported("Degenerate runtime UI panel transform.");
            var px = (delta.x * y.y - delta.y * y.x) / determinant;
            var py = (x.x * delta.y - x.y * delta.x) / determinant;
            return new Vector2(px * Screen.width, (1 - py) * Screen.height);
        }

        public static bool ElementVisible(VisualElement element, out Rect screen)
        {
            screen = default;
            if (element == null || element.panel == null) return false;
            var alpha = 1f; var clip = element.worldBound;
            for (var e = element; e != null; e = e.parent)
            {
                if (!e.visible || e.resolvedStyle.display == DisplayStyle.None ||
                    e.resolvedStyle.visibility == Visibility.Hidden) return false;
                alpha *= e.resolvedStyle.opacity;
            }
            if (alpha <= .01f) return false;
            if(ToolkitWorldClip==null)throw new PresentationUnsupported("Pinned UI Toolkit world-clip observer unavailable.");
            var worldClip=(Rect)ToolkitWorldClip.GetValue(element);
            if(!Clip(clip,worldClip,out clip))return false;
            var a = PanelToScreen(element.panel, clip.min); var b = PanelToScreen(element.panel, clip.max);
            return Clip(Rect.MinMaxRect(Mathf.Min(a.x,b.x),Mathf.Min(a.y,b.y),Mathf.Max(a.x,b.x),Mathf.Max(a.y,b.y)), Viewport, out screen);
        }

        public static List<PresentedText> Texts()
        {
            var output = new List<PresentedText>();
            foreach (var t in Object.FindObjectsByType<UnityEngine.UI.Text>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                if (GraphicVisible(t, out var rect)) Add(output,VisibleUiText(t,rect),"uGUI",rect,t,null);
            foreach (var t in Object.FindObjectsByType<TMP_Text>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (!t.enabled || t.color.a <= .01f) continue;
                var graphic = t as Graphic;
                if (graphic && graphic.canvas)
                {
                    if (GraphicVisible(graphic,out var rect)) Add(output,VisibleTmpText(t,rect),"TMP-uGUI",rect,t,null);
                }
                else if (RendererRect(t.GetComponent<Renderer>(),out var rect)) Add(output,t.text,"TMP-world",rect,t,null);
            }
            foreach (var t in Object.FindObjectsByType<TextMesh>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                if (t.color.a > .01f && RendererRect(t.GetComponent<Renderer>(),out var rect)) Add(output,t.text,"TextMesh",rect,t,null);
            foreach (var doc in Object.FindObjectsByType<UIDocument>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                if (doc.enabled && doc.rootVisualElement != null)
                    doc.rootVisualElement.Query<TextElement>().ForEach(t => {
                        if (t.resolvedStyle.color.a > .01f && ElementVisible(t,out var rect)) Add(output,t.text,"UI Toolkit",rect,doc,t);
                    });
            if(ImguiObservationScope.Current!=null)output.AddRange(ImguiObservationScope.Current.Texts());
            return output;
        }

        static bool RendererRect(Renderer renderer, out Rect screen)
        {
            screen = default;
            if (!renderer || !renderer.enabled || !renderer.gameObject.activeInHierarchy) return false;
            foreach (var camera in Camera.allCameras.Where(x => x.isActiveAndEnabled && !x.targetTexture &&
                         (x.cullingMask & (1 << renderer.gameObject.layer)) != 0))
            {
                var box = renderer.bounds;
                if (!GeometryUtility.TestPlanesAABB(GeometryUtility.CalculateFrustumPlanes(camera),box)) continue;
                var points = new List<Vector3>();
                for (int x = -1; x <= 1; x += 2) for (int y = -1; y <= 1; y += 2) for (int z = -1; z <= 1; z += 2)
                    points.Add(camera.WorldToScreenPoint(box.center + Vector3.Scale(box.extents,new Vector3(x,y,z))));
                if (points.All(x => x.z <= 0)) continue;
                var r = Rect.MinMaxRect(points.Min(x=>x.x),points.Min(x=>x.y),points.Max(x=>x.x),points.Max(x=>x.y));
                if (Clip(r,Viewport,out screen)) return true;
            }
            return false;
        }

        static void Add(List<PresentedText> list, string text, string framework, Rect rect, Component component, VisualElement element)
        {
            text = SemanticText(text);
            if (text.Length > 0) list.Add(new PresentedText { text=text,framework=framework,screen=rect,
                owner=component?component.gameObject.name:"",component=component,element=element });
        }

        public static string Joined(IEnumerable<PresentedText> texts) => string.Join("\n",texts.Select(x=>x.text));

        public static Dictionary<double,int> Numbers(IEnumerable<string> texts)
        {
            var counts=new Dictionary<double,int>();
            foreach(var text in texts)
                foreach(Match match in Regex.Matches(SemanticText(text),@"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"))
                    if(double.TryParse(match.Value,NumberStyles.Float,CultureInfo.InvariantCulture,out var number))
                        counts[number]=Count(counts,number)+1;
            return counts;
        }
        static int Count(Dictionary<double,int> numbers,double key)=>numbers.TryGetValue(key,out var value)?value:0;
        public static bool ReplacedNumbers(IEnumerable<string> before,IEnumerable<string> after,IEnumerable<KeyValuePair<double,double>> edits)
        {
            var a=Numbers(before);var b=Numbers(after);
            return edits.All(x=>Count(a,x.Key)-Count(b,x.Key)>=1 && Count(b,x.Value)-Count(a,x.Value)>=1);
        }

        public static List<PresentedControl> Controls(bool includeDisabled=false)
        {
            var texts=Texts();var result=new List<PresentedControl>();
            foreach(var selectable in Object.FindObjectsByType<Selectable>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))
            {
                if(!selectable.isActiveAndEnabled || (!includeDisabled&&!selectable.IsInteractable()) ||
                   HierarchyAlpha(selectable.transform)<=.01f || !(selectable.transform is RectTransform rect) ||
                   !RectOnScreen(rect,out var screen))continue;
                var labels=texts.Where(t=>t.component && t.component.transform.IsChildOf(selectable.transform)).Select(t=>t.text).ToArray();
                if(labels.Length>0)result.Add(new PresentedControl{label=string.Join(" ",labels),screen=screen,selectable=selectable,interactable=selectable.IsInteractable()});
            }
            foreach(var doc in Object.FindObjectsByType<UIDocument>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))
                if(doc.enabled&&doc.rootVisualElement!=null)doc.rootVisualElement.Query<UIEButton>().ForEach(button=>{
                    if((includeDisabled||button.enabledInHierarchy)&&ElementVisible(button,out var screen))
                    {
                        var label=string.Join(" ",button.Query<TextElement>().ToList().Select(x=>SemanticText(x.text)));
                        if(string.IsNullOrWhiteSpace(label))label=SemanticText(button.text);
                        if(label.Length>0)result.Add(new PresentedControl{label=label,screen=screen,element=button,interactable=button.enabledInHierarchy});
                    }});
            if(ImguiObservationScope.Current!=null)result.AddRange(ImguiObservationScope.Current.Controls(includeDisabled));
            return result;
        }

        public static PresentedControl FindControl(string pattern)
        {
            return Controls().Where(x=>Regex.IsMatch(x.label,pattern,RegexOptions.IgnoreCase))
                .OrderBy(x=>x.label.Length).FirstOrDefault(x=>CanHit(x,out _));
        }

        public static bool CanHit(PresentedControl target,out Vector2 point)
        {
            var r=target.screen;
            foreach(var p in new[]{r.center,new Vector2(r.xMin+r.width*.3f,r.center.y),new Vector2(r.xMin+r.width*.7f,r.center.y)})
            {
                if(target.selectable)
                {
                    if(!EventSystem.current)continue;
                    var hits=new List<RaycastResult>();
                    EventSystem.current.RaycastAll(new PointerEventData(EventSystem.current){position=p},hits);
                    if(hits.Count>0 && hits[0].gameObject &&
                       (hits[0].gameObject.transform==target.selectable.transform ||
                        hits[0].gameObject.transform.IsChildOf(target.selectable.transform)))
                    {point=p;return true;}
                }
                else if(target.element!=null)
                {
                    var panel=target.element.panel;
                    var picked=panel.Pick(RuntimePanelUtils.ScreenToPanel(panel,new Vector2(p.x,Screen.height-p.y)));
                    if(picked!=null&&(picked==target.element||target.element.Contains(picked))){point=p;return true;}
                }
                else if(target.framework=="IMGUI-native-Repaint"&&ImguiObservationScope.Current!=null)
                {
                    // This is a visible normal-pointer attempt location, not a claim
                    // that the candidate wired input. Real action effects are asserted.
                    if(target.interactable&&Viewport.Contains(p)){point=p;return true;}
                }
            }
            point=default;return false;
        }

        public static List<PresentedScroll> Scrolls()
        {
            var result=new List<PresentedScroll>();
            foreach(var view in Object.FindObjectsByType<ScrollRect>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))
                if(view.isActiveAndEnabled&&view.vertical&&view.content&&
                   RectOnScreen(view.viewport?view.viewport:(RectTransform)view.transform,out var rect)&&
                   HierarchyAlpha(view.transform)>.01f)
                {
                    var found=new PresentedScroll{key="uGUI:"+view.GetInstanceID(),ugui=view,screen=rect};
                    var bar=view.verticalScrollbar;
                    if(bar&&bar.isActiveAndEnabled&&bar.IsInteractable()&&bar.handleRect&&
                        bar.handleRect.parent is RectTransform track&&
                        HierarchyAlpha(bar.transform)>.01f&&RectOnScreen(track,out var trackRect)&&RectOnScreen(bar.handleRect,out var thumbRect))
                    {found.hasVerticalScrollbarGeometry=true;found.verticalScrollbarTrack=trackRect;found.verticalScrollbarThumb=thumbRect;}
                    result.Add(found);
                }
            foreach(var doc in Object.FindObjectsByType<UIDocument>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))
                if(doc.enabled&&doc.rootVisualElement!=null)doc.rootVisualElement.Query<ScrollView>().ForEach(view=>{
                    if(ElementVisible(view.contentViewport,out var rect))
                    {
                        var found=new PresentedScroll{key="UITK:"+doc.GetInstanceID()+":"+view.name,toolkit=view,screen=rect};
                        var slider=view.verticalScroller.slider;
                        var track=slider.Q<VisualElement>("unity-drag-container");var thumb=slider.Q<VisualElement>("unity-dragger");
                        if(slider.enabledInHierarchy&&track!=null&&thumb!=null&&ElementVisible(track,out var trackRect)&&ElementVisible(thumb,out var thumbRect))
                        {found.hasVerticalScrollbarGeometry=true;found.verticalScrollbarTrack=trackRect;found.verticalScrollbarThumb=thumbRect;}
                        result.Add(found);
                    }
                });
            if(ImguiObservationScope.Current!=null)result.AddRange(ImguiObservationScope.Current.Scrolls());
            return result;
        }

        public static List<PresentedText> InScroll(PresentedScroll scroll,IEnumerable<PresentedText> texts)
        {
            return texts.Where(x=>scroll.ugui
                ? x.component && x.component.transform.IsChildOf(scroll.ugui.content)
                : scroll.toolkit!=null?x.element!=null&&scroll.toolkit.contentContainer.Contains(x.element):x.imguiScrollKey==scroll.imguiKey)
                .OrderByDescending(x=>x.screen.yMax).ThenBy(x=>x.screen.xMin).ToList();
        }

        public static bool LooksLikeHistory(string text)
        {
            return Regex.IsMatch(text,@"\b(day\s*\d+|morning|night|chronicle|journal|history)\b",RegexOptions.IgnoreCase);
        }

        public static PresentedScroll ChronicleScroll()
        {
            // Raw child strings only locate the semantic scrolling surface. They never prove
            // visibility or readability; the verdict uses clipped rendered text after real wheel input.
            return Scrolls().Select(x=>new{scroll=x,text=RawScrollText(x)})
                .Where(x=>LooksLikeHistory(x.text)).OrderByDescending(x=>x.text.Length).Select(x=>x.scroll).FirstOrDefault();
        }

        static string RawScrollText(PresentedScroll scroll)
        {
            if(scroll.ugui)return string.Join("\n",scroll.ugui.content.GetComponentsInChildren<UnityEngine.UI.Text>(true).Select(x=>x.text)
                .Concat(scroll.ugui.content.GetComponentsInChildren<TMP_Text>(true).Select(x=>x.text)));
            if(scroll.imguiKey!=null)return ImguiObservationScope.Current.ScrollText(scroll.imguiKey);
            return string.Join("\n",scroll.toolkit.contentContainer.Query<TextElement>().ToList().Select(x=>x.text));
        }
    }

    [Serializable] public sealed class AudioVoiceFact
    {
        public int source,asset,voice,plays;
        public int native_owner,owner_game_object;
        public List<int> bound_source_components=new List<int>();
        public float audibility,volume;
        public string clip;
    }
    [Serializable] public sealed class AudioSourceFact
    {
        public int source,game_object;
        public string signature,owner_name;
        public bool playing,loop,mute;
        public float volume,rms;
    }
    [Serializable] public sealed class AudioFrameFact
    {
        public int frame,profiler_frame;
        public int capture_token;
        public int native_audio_owner_token;
        public bool native_frame_coalesced;
        public bool native_frame_bound,end_marker;
        public double realtime_ms,native_start_ms,dsp_time;
        public string game_phase;
        public int audio_capture_flags;
        public bool profiler_enabled,audio_area_enabled;
        public string raw_profiler_array_type;
        public List<AudioRawProfilerRow> raw_profiler_rows=new List<AudioRawProfilerRow>();
        public string raw_clip_profiler_array_type;
        public List<AudioRawProfilerRow> raw_clip_profiler_rows=new List<AudioRawProfilerRow>();
        public float listener_rms;
        public bool listener_available;
        public List<AudioVoiceFact> voices=new List<AudioVoiceFact>();
        public List<AudioSourceFact> sources=new List<AudioSourceFact>();
    }
    [Serializable] public sealed class AudioRawProfilerField
    {
        public string name,type,value;
    }
    [Serializable] public sealed class AudioRawProfilerRow
    {
        public string type,owner_type,owner_name,asset_type,asset_name;
        public int native_owner,native_asset;
        public List<AudioRawProfilerField> fields=new List<AudioRawProfilerField>();
    }
    [Serializable] public sealed class AudioWindowFact
    {
        public string label;
        public int capture_window,native_frames_bound;
        public bool native_complete,native_end_received;
        public List<AudioFrameFact> frames=new List<AudioFrameFact>();
    }

    // Reads the pinned Editor's actual audio channels, including PlayOneShot voices.
    // No candidate member is inspected and no AudioSource state is written.
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct AudioProfilerFrameToken
    {
        public int token,window,unity_frame,end;
    }

    [DefaultExecutionOrder(int.MaxValue)]
    public sealed class AudioProfilerFrameTap : MonoBehaviour
    {
        public Action callback;
        void LateUpdate(){callback?.Invoke();}
    }

    public sealed class AudioPresentationScope : IDisposable
    {
        readonly Type driver,propertyType;
        readonly PropertyInfo enabled,lastFrame,firstFrame,captureFlags;
        readonly MethodInfo setArea,isArea,setRoot,groups,clips,dispose,setCaptureFlags,getRawFrame,getMeta,getMetaCount,setHistoryLength;
        readonly object audioArea;
        readonly bool oldEnabled,oldArea;
        readonly int oldCaptureFlags,oldHistoryLength;
        readonly float[] samples=new float[256];
        readonly Guid metadataId=Guid.NewGuid();
        readonly Dictionary<int,AudioFrameFact> pendingFrames=new Dictionary<int,AudioFrameFact>();
        readonly Dictionary<int,AudioWindowFact> windows=new Dictionary<int,AudioWindowFact>();
        readonly GameObject tapObject;
        readonly AudioProfilerFrameTap tap;
        AudioWindowFact collecting;
        Func<string> phaseReader;
        Exception captureFailure;
        bool endRequested,disposed;
        int sequence,windowSequence,finalToken,nextNativeFrame;
        double nextSampleTime;

        public AudioPresentationScope()
        {
            var assembly=typeof(UnityEditor.Editor).Assembly;
            driver=assembly.GetType("UnityEditorInternal.ProfilerDriver");
            propertyType=assembly.GetType("UnityEditorInternal.ProfilerProperty");
            var rawType=assembly.GetType("UnityEditor.Profiling.RawFrameDataView");
            var settingsType=assembly.GetType("UnityEditor.Profiling.ProfilerUserSettings");
            if(driver==null||propertyType==null||rawType==null)throw new PresentationUnsupported("Pinned Editor audio observer types unavailable.");
            var flags=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Static|BindingFlags.Instance;
            enabled=driver.GetProperty("enabled",flags);lastFrame=driver.GetProperty("lastFrameIndex",flags);
            firstFrame=driver.GetProperty("firstFrameIndex",flags);
            setArea=driver.GetMethod("SetAreaEnabled",flags);isArea=driver.GetMethod("IsAreaEnabled",flags);
            setCaptureFlags=driver.GetMethod("SetAudioCaptureFlags",flags);
            captureFlags=typeof(AudioSettings).GetProperty("profilerCaptureFlags",flags);
            setRoot=propertyType.GetMethod("SetRoot",flags,null,new[]{typeof(int),typeof(int),typeof(int)},null);
            groups=propertyType.GetMethod("GetAudioProfilerGroupInfo",flags);
            clips=propertyType.GetMethod("GetAudioProfilerClipInfo",flags);dispose=propertyType.GetMethod("Dispose",flags);
            getRawFrame=driver.GetMethod("GetRawFrameDataView",flags,null,new[]{typeof(int),typeof(int)},null);
            setHistoryLength=driver.GetMethod("SetMaxFrameHistoryLength",flags);
            oldHistoryLength=(int)settingsType.GetProperty("frameCount",flags).GetValue(null);
            getMeta=rawType.GetMethods(flags).Single(x=>x.Name=="GetFrameMetaData"&&x.IsGenericMethodDefinition&&
                x.GetParameters().Length==3&&x.GetParameters()[0].ParameterType==typeof(Guid))
                .MakeGenericMethod(typeof(AudioProfilerFrameToken));
            getMetaCount=rawType.GetMethods(flags).Single(x=>x.Name=="GetFrameMetaDataCount"&&
                x.GetParameters().Length==2&&x.GetParameters()[0].ParameterType==typeof(Guid));
            if(enabled==null||lastFrame==null||firstFrame==null||setArea==null||isArea==null||setRoot==null||
                groups==null||clips==null||dispose==null||setCaptureFlags==null||captureFlags==null||getRawFrame==null)
                throw new PresentationUnsupported("Pinned Editor audio observer signature changed.");
            audioArea=Enum.Parse(setArea.GetParameters()[0].ParameterType,"Audio");
            oldEnabled=(bool)enabled.GetValue(null);oldArea=(bool)isArea.Invoke(null,new[]{audioArea});
            oldCaptureFlags=(int)captureFlags.GetValue(null);
            nextNativeFrame=(int)lastFrame.GetValue(null)+1;
            try
            {
                enabled.SetValue(null,false);
                // An uncapped empty batch-mode scene can produce thousands of frames per second.
                // The default 300-frame viewer ring otherwise evicts delayed tagged audio frames.
                // This changes only this owned Editor process, not persistent Profiler preferences.
                setHistoryLength.Invoke(null,new object[]{Math.Max(oldHistoryLength,32768)});
                setArea.Invoke(null,new[]{audioArea,(object)true});
                // Pinned Editor detailed audio UI uses channels bit 1 and full-details bits 1|6.
                setCaptureFlags.Invoke(null,new object[]{oldCaptureFlags|7});
                tapObject=new GameObject("__StormboundAudioFrameObserver"){hideFlags=HideFlags.HideAndDontSave};
                Object.DontDestroyOnLoad(tapObject);
                tap=tapObject.AddComponent<AudioProfilerFrameTap>();tap.callback=CaptureTaggedFrame;
            }
            catch(Exception e)
            {
                setCaptureFlags.Invoke(null,new object[]{oldCaptureFlags});setArea.Invoke(null,new[]{audioArea,(object)oldArea});
                setHistoryLength.Invoke(null,new object[]{oldHistoryLength});
                enabled.SetValue(null,oldEnabled);
                throw new PresentationUnsupported("Audio profiler activation failed: "+e.GetBaseException().Message);
            }
        }

        public void Dispose()
        {
            if(disposed)return;disposed=true;collecting=null;
            if(tap)tap.callback=null;
            if(tapObject)Object.DestroyImmediate(tapObject);
            setCaptureFlags.Invoke(null,new object[]{oldCaptureFlags});
            setHistoryLength.Invoke(null,new object[]{oldHistoryLength});
            setArea.Invoke(null,new[]{audioArea,(object)oldArea});enabled.SetValue(null,oldEnabled);
        }

        static T Field<T>(object row,string name)=>(T)row.GetType().GetField(name,BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic).GetValue(row);
        float Rms(){double sum=0;foreach(var x in samples)sum+=(double)x*x;return (float)Math.Sqrt(sum/samples.Length);}

        AudioFrameFact CaptureLive()
        {
            var result=new AudioFrameFact{frame=Time.frameCount,profiler_frame=-1,realtime_ms=Time.realtimeSinceStartupAsDouble*1000,
                dsp_time=AudioSettings.dspTime,audio_capture_flags=(int)captureFlags.GetValue(null),
                profiler_enabled=(bool)enabled.GetValue(null),audio_area_enabled=(bool)isArea.Invoke(null,new[]{audioArea})};
            result.listener_available=Object.FindObjectsByType<AudioListener>(FindObjectsInactive.Exclude,FindObjectsSortMode.None)
                .Any(x=>x.isActiveAndEnabled)&&AudioListener.volume>.01f;
            Array.Clear(samples,0,samples.Length);AudioListener.GetOutputData(samples,0);result.listener_rms=Rms();
            foreach(var source in Object.FindObjectsByType<AudioSource>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x.isActiveAndEnabled))
            {
                Array.Clear(samples,0,samples.Length);source.GetOutputData(samples,0);
                var clip=source.clip;var signature=clip?clip.name+"|"+clip.samples+"|"+clip.frequency:"unassigned";
                result.sources.Add(new AudioSourceFact{source=source.GetInstanceID(),game_object=source.gameObject.GetInstanceID(),
                    owner_name=source.gameObject.name,signature=signature,playing=source.isPlaying,loop=source.loop,
                    mute=source.mute,volume=source.volume,rms=Rms()});
            }
            return result;
        }

        void CaptureTaggedFrame()
        {
            if(collecting==null||(!endRequested&&Time.realtimeSinceStartupAsDouble<nextSampleTime))return;
            try
            {
                var result=CaptureLive();result.game_phase=phaseReader?.Invoke();
                var token=new AudioProfilerFrameToken{token=++sequence,window=collecting.capture_window,
                    unity_frame=Time.frameCount,end=endRequested?1:0};
                result.capture_token=token.token;result.end_marker=endRequested;
                collecting.frames.Add(result);pendingFrames.Add(token.token,result);
                UnityEngine.Profiling.Profiler.EmitFrameMetaData(metadataId,0,new[]{token});
                nextSampleTime=Time.realtimeSinceStartupAsDouble+.01;
                if(endRequested){finalToken=token.token;collecting=null;}
            }
            catch(Exception e){captureFailure=e;collecting=null;}
        }

        static AudioRawProfilerRow RawRow(object row,int asset,int owner=0)
        {
            var assetObject=EditorUtility.InstanceIDToObject(asset);var ownerObject=EditorUtility.InstanceIDToObject(owner);
            var raw=new AudioRawProfilerRow{type=row.GetType().FullName,native_asset=asset,native_owner=owner,
                asset_type=assetObject?assetObject.GetType().FullName:null,asset_name=assetObject?assetObject.name:null,
                owner_type=ownerObject?ownerObject.GetType().FullName:null,owner_name=ownerObject?ownerObject.name:null};
            foreach(var field in row.GetType().GetFields(BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic))
            {
                var value=field.GetValue(row);
                raw.fields.Add(new AudioRawProfilerField{name=field.Name,type=field.FieldType.FullName,
                    value=value is IFormattable formatted?formatted.ToString(null,CultureInfo.InvariantCulture):value?.ToString()});
            }
            return raw;
        }

        void ReadNativeAudio(int frame,AudioFrameFact result)
        {
            object property=null;
            try
            {
                property=Activator.CreateInstance(propertyType);setRoot.Invoke(property,new object[]{frame,0,0});
                var array=groups.Invoke(property,null) as Array;result.raw_profiler_array_type=array?.GetType().FullName;
                if(array!=null)foreach(var row in array)
                {
                    var asset=Field<int>(row,"assetInstanceId");var owner=Field<int>(row,"objectInstanceId");
                    var raw=RawRow(row,asset,owner);result.raw_profiler_rows.Add(raw);
                    // Bind using the live engine-source snapshot from THIS recorded frame, not a later scene.
                    var bound=result.sources.Where(x=>x.game_object==owner||x.source==owner).ToArray();
                    if(asset==0||bound.Length==0)continue;
                    var gameObject=bound[0].game_object;var clip=EditorUtility.InstanceIDToObject(asset) as AudioClip;
                    if(string.IsNullOrEmpty(raw.owner_type)){raw.owner_type="recorded UnityEngine.GameObject";raw.owner_name=bound[0].owner_name;}
                    result.voices.Add(new AudioVoiceFact{source=gameObject,native_owner=owner,owner_game_object=gameObject,
                        bound_source_components=bound.Select(x=>x.source).ToList(),asset=asset,voice=Field<int>(row,"uniqueId"),
                        plays=Field<int>(row,"playCount"),audibility=bound.All(x=>x.mute)?0:Field<float>(row,"audibility"),
                        volume=Field<float>(row,"volume"),clip=clip?clip.name:"asset:"+asset});
                }
                var clipRows=clips.Invoke(property,null) as Array;result.raw_clip_profiler_array_type=clipRows?.GetType().FullName;
                if(clipRows!=null)foreach(var row in clipRows)
                    result.raw_clip_profiler_rows.Add(RawRow(row,Field<int>(row,"assetInstanceId")));
                result.profiler_frame=frame;result.native_frame_bound=true;
            }
            catch(Exception e){throw new PresentationUnsupported("Pinned audio channel read failed: "+e.GetBaseException().Message);}
            finally{if(property!=null)dispose.Invoke(property,null);}
        }

        void ReceiveNativeFrames()
        {
            var first=(int)firstFrame.GetValue(null);var last=(int)lastFrame.GetValue(null);
            if(first<0||last<0)return;
            nextNativeFrame=Math.Max(nextNativeFrame,first);
            for(var frame=nextNativeFrame;frame<=last;frame++)
            {
                object view=null;
                try
                {
                    view=getRawFrame.Invoke(null,new object[]{frame,0});
                    if(view==null||!(bool)view.GetType().GetProperty("valid").GetValue(view))
                    {if(frame==last)return;nextNativeFrame=frame+1;continue;}
                    // Several player-loop LateUpdates can share one Editor profiler frame.
                    // The two-argument GetFrameMetaData returns only block zero: read EVERY block.
                    var tags=new List<AudioProfilerFrameToken>();
                    var blockCount=(int)getMetaCount.Invoke(view,new object[]{metadataId,0});
                    for(var block=0;block<blockCount;block++)
                    {
                        var native=getMeta.Invoke(view,new object[]{metadataId,0,block});
                        var nativeType=native.GetType();var count=(int)nativeType.GetProperty("Length").GetValue(native);
                        var item=nativeType.GetProperty("Item");
                        for(var i=0;i<count;i++)tags.Add((AudioProfilerFrameToken)item.GetValue(native,new object[]{i}));
                    }
                    var ownerToken=tags.Count==0?0:tags.OrderBy(x=>x.unity_frame).ThenBy(x=>x.token).Last().token;
                    foreach(var tag in tags)
                    {
                        if(!windows.TryGetValue(tag.window,out var window)||!pendingFrames.TryGetValue(tag.token,out var result)||result.native_frame_bound)continue;
                        if(result.frame!=tag.unity_frame)throw new PresentationUnsupported("Audio frame metadata identity mismatch.");
                        result.native_start_ms=(double)view.GetType().GetProperty("frameStartTimeMs").GetValue(view);
                        result.native_audio_owner_token=ownerToken;
                        if(tag.token==ownerToken)ReadNativeAudio(frame,result);
                        else{result.profiler_frame=frame;result.native_frame_bound=true;result.native_frame_coalesced=true;}
                        if(tag.end==1)window.native_end_received=true;
                    }
                    nextNativeFrame=frame+1;
                }
                catch(PresentationUnsupported){throw;}
                catch(Exception e){throw new PresentationUnsupported("Audio frame metadata receive failed: "+e.GetBaseException().Message);}
                finally{(view as IDisposable)?.Dispose();}
            }
        }

        public IEnumerator Collect(AudioWindowFact window,float seconds,IEnumerator action=null,Func<string> phase=null)
        {
            if(disposed)throw new ObjectDisposedException(nameof(AudioPresentationScope));
            if(collecting!=null)throw new PresentationUnsupported("Overlapping audio observation windows.");
            bool completed=false;
            try
            {
                captureFailure=null;endRequested=false;finalToken=0;phaseReader=phase;
                // A caller may append multiple real observation intervals to the same window.
                // Preserve every frame, but never reuse a previous interval's end/drain receipt.
                window.native_end_received=false;window.native_complete=false;window.native_frames_bound=0;
                window.capture_window=++windowSequence;windows.Add(window.capture_window,window);
                enabled.SetValue(null,true);
                // Let the recorder start before emitting tagged game frames.
                yield return null;yield return null;
                collecting=window;nextSampleTime=0;
                if(action!=null)
                {
                    var stack=new Stack<IEnumerator>();stack.Push(action);
                    while(stack.Count>0)
                    {
                        if(!stack.Peek().MoveNext()){stack.Pop();continue;}
                        var next=stack.Peek().Current;
                        if(next is IEnumerator nested){stack.Push(nested);continue;}
                        ReceiveNativeFrames();if(captureFailure!=null)throw captureFailure;yield return next;
                    }
                }
                var end=Time.realtimeSinceStartupAsDouble+seconds;
                do
                {
                    ReceiveNativeFrames();if(captureFailure!=null)throw captureFailure;
                    yield return new WaitForSecondsRealtime(.005f);
                }while(Time.realtimeSinceStartupAsDouble<end);
                endRequested=true;
                var emissionDeadline=Time.realtimeSinceStartupAsDouble+3;
                while(finalToken==0)
                {
                    if(captureFailure!=null)throw captureFailure;
                    if(Time.realtimeSinceStartupAsDouble>=emissionDeadline)
                        throw new PresentationUnsupported("The audio observer LateUpdate did not commit its end-frame token.");
                    ReceiveNativeFrames();yield return null;
                }
                // The final token was emitted by LateUpdate of a completed real game frame.
                enabled.SetValue(null,false);collecting=null;
                var deadline=Time.realtimeSinceStartupAsDouble+8;
                while(!NativeWindowComplete(window,finalToken)&&Time.realtimeSinceStartupAsDouble<deadline)
                {ReceiveNativeFrames();yield return new WaitForSecondsRealtime(.01f);}
                ReceiveNativeFrames();
                window.native_frames_bound=window.frames.Count(x=>x.native_frame_bound);
                window.native_complete=NativeWindowComplete(window,finalToken);
                if(!window.native_complete)throw new PresentationUnsupported(
                    "Native audio recording did not drain all tagged real frames: "+window.native_frames_bound+"/"+window.frames.Count+
                    ";end="+window.native_end_received+". This is an observer/host fault, not missing product audio.");
                completed=true;
            }
            finally
            {
                collecting=null;phaseReader=null;
                if(!disposed)enabled.SetValue(null,false);
                if(!completed){WriteFailureDiagnostics();Dispose();}
            }
        }

        public static bool NativeWindowComplete(AudioWindowFact window,int finalToken)
        {
            return finalToken>0&&window.native_end_received&&window.frames.Count>0&&
                window.frames.All(x=>x.native_frame_bound)&&
                window.frames.Any(x=>x.capture_token==finalToken&&x.end_marker&&x.native_frame_bound);
        }

        [Serializable]sealed class FailedAudioWindows
        {
            public string schema="native-audio-frame-observer-failure/v1",created_utc;
            public int process_id,screen_width,screen_height;
            public List<AudioWindowFact> windows;
        }
        void WriteFailureDiagnostics()
        {
            var root=Environment.GetEnvironmentVariable("STORMBOUND_PRESENTATION_EVIDENCE_DIRECTORY");
            if(string.IsNullOrWhiteSpace(root))
            {
                var file=Environment.GetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE");
                root=string.IsNullOrWhiteSpace(file)?System.IO.Path.Combine(System.IO.Path.GetDirectoryName(Application.dataPath),"Logs","PresentationQualification"):System.IO.Path.GetDirectoryName(file);
            }
            System.IO.Directory.CreateDirectory(root);
            var pid=System.Diagnostics.Process.GetCurrentProcess().Id;
            System.IO.File.WriteAllText(System.IO.Path.Combine(root,"AudioObserverFailure-"+pid+"-"+metadataId.ToString("N")+".json"),
                JsonUtility.ToJson(new FailedAudioWindows{created_utc=DateTime.UtcNow.ToString("o"),process_id=pid,
                    screen_width=Screen.width,screen_height=Screen.height,windows=windows.Values.ToList()},true));
        }
        public static bool Audible(AudioWindowFact window)=>window.frames.Any(x=>x.listener_available&&x.listener_rms>.00001f);
        public static bool HasVoiceEvidence(AudioWindowFact window)=>window.frames.Any(x=>x.voices.Count>0);
        public static bool DistinctCue(AudioWindowFact before,AudioWindowFact after)
        {
            var seen=before.frames.SelectMany(x=>x.voices).GroupBy(x=>x.source+":"+x.asset)
                .ToDictionary(x=>x.Key,x=>x.Max(y=>y.plays));
            return after.frames.SelectMany(x=>x.voices).Any(x=>x.audibility>.00001f&&x.volume>.00001f&&
                (!seen.TryGetValue(x.source+":"+x.asset,out var plays)||x.plays>plays));
        }
        public static Dictionary<string,int> LoopCounts(AudioWindowFact window)
        {
            // Long-lived ambience can be looped natively or replayed by normal game code.
            // A short transient cue in one frame does not become an ambience stream.
            var minimum=Math.Max(1,(int)Math.Ceiling(window.frames.Count*.75));
            return window.frames.SelectMany(x=>x.sources.Where(s=>s.playing&&!s.mute&&s.volume>.00001f))
                .GroupBy(x=>x.source+"|"+x.signature).Where(x=>x.Count()>=minimum)
                .Select(x=>x.First()).GroupBy(x=>x.signature).ToDictionary(x=>x.Key,x=>x.Count());
        }
        public static bool NoLoopGrowth(Dictionary<string,int> before,Dictionary<string,int> after)
        {
            // Different legitimate tracks may occupy the same stable number of ambience layers.
            return after.Values.Sum()<=before.Values.Sum();
        }
    }
}

#endif
