#if UNITY_EDITOR
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Text.RegularExpressions;
using GameCreate.Session;
using GameCreate.Evaluation.Session;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.TestTools;
using static GameCreate.Stormbound.Evaluator.StormboundRun;

namespace GameCreate.Stormbound.Evaluator
{
    public sealed partial class DynamicTrajectoryTests
    {
        static readonly string[] PresentationLeaves={"D2_START","D5_CONTROLS","D5_HUD","D5_FEEDBACK","D5_CHRONICLE","D5_AUDIO"};

        static void PresentedFrame(StormboundRun run,string label,IEnumerable<PresentedText> texts,SessionSave save=null)
        {
            var scope=ImguiObservationScope.Current;
            if(scope!=null&&scope.HasRuntimeSurface)label+=";imgui_frame="+scope.Frame+";sequence="+scope.Sequence+
                ";native_frame="+scope.ImagePath+";native_sha256="+scope.ImageSha256;
            run.Facts.frames.Add(new FrameFact{label=label+";viewport="+Screen.width+"x"+Screen.height,
                frame=Time.frameCount,realtime=Time.realtimeSinceStartup,visible_text=PresentationObservers.Joined(texts),
                save_json=save==null?null:JsonUtility.ToJson(save)});
        }

        static void PresentationVerdict(StormboundRun run,string id,bool pass,string expected,string observed)
        {
            run.Check(id,pass,expected,observed);
            var check=run.Checks.Last();check.acquisition_route="normal_player_input_and_actual_presentation";
        }

        static void PresentationFailure(StormboundRun run,string id,Exception exception)
        {
            if(run.Checks.Any(x=>x.id==id))return;
            run.Check(id,false,"Published presentation obligation",exception.ToString());
            var check=run.Checks.Last();var product=exception as SessionProductFailure;
            check.status=product==null?"INCONCLUSIVE_EVALUATOR":"BLOCKED_BY_PRODUCT";
            check.attribution=product==null?"presentation_observer_unsupported":"published_service_not_delivered";
            check.acquisition_status=product==null?"UNREACHABLE_EVALUATOR":"PRODUCT_BLOCKED";
            check.precondition_reached=false;check.oracle_valid=product!=null;
            check.failed_capability=product?.Capability;check.product_block_reason=product?.Message;
            check.blocker_kind=product==null?null:"public_session_contract";
        }

        static IEnumerator IsolatedPresentationSegment(IEnumerator body,Action<Exception> failed)
        {
            var stack=new Stack<IEnumerator>();stack.Push(body);
            while(stack.Count>0)
            {
                bool more;object next;
                try{more=stack.Peek().MoveNext();next=more?stack.Peek().Current:null;}
                catch(Exception e){failed(e);yield break;}
                if(!more){stack.Pop();continue;}
                if(next is IEnumerator nested){stack.Push(nested);continue;}
                yield return next;
            }
        }

        static List<PresentedText> ReadPresented()
        {
            var texts=PresentationObservers.Texts();
            if(texts.Count==0&&!PresentationObservers.HasSupportedTextSurface())throw new PresentationUnsupported(
                "No screen-visible text was available through the supported rendering observers. A rendered-frame/OCR observer is required; this is not evidence of an empty product.");
            return texts;
        }

        static PresentedControl FindPresentedControl(string pattern)
        {
            // A real observed control wins over a coincidentally shorter help
            // label. A label-only candidate is still usable if normal input
            // actually establishes the required effect.
            return PresentationObservers.Controls().Where(x=>Regex.IsMatch(x.label,pattern,RegexOptions.IgnoreCase))
                .OrderBy(x=>x.isCandidateOnly).ThenBy(x=>x.label.Length)
                .FirstOrDefault(x=>PresentationObservers.CanHit(x,out _));
        }

        static IEnumerator WithPresentationObservation(StormboundRun run,IEnumerator body)
        {
            // Flatten locally: StormboundRun's outer Pump does not dispose an
            // abandoned nested iterator after a failure. Always release this
            // engine observer even if a deeply nested preparation/action fails.
            yield return EditorGameViewResolution.Ensure1280x720();
            var evidence=Environment.GetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE");
            if(string.IsNullOrEmpty(evidence))throw new PresentationUnsupported("No presentation evidence destination");
            var name=Regex.Replace(run.Name??"presentation",@"[^A-Za-z0-9_.-]","_");
            var scope=new ImguiObservationScope(Path.Combine(Path.GetDirectoryName(evidence),"imgui-observations",name));
            var stack=new Stack<IEnumerator>();stack.Push(body);Exception failed=null;
            try
            {
                while(stack.Count>0)
                {
                    bool more;object next;
                    try{more=stack.Peek().MoveNext();next=more?stack.Peek().Current:null;}
                    catch(Exception error){failed=error;break;}
                    if(!more){(stack.Pop() as IDisposable)?.Dispose();continue;}
                    if(next is IEnumerator nested){stack.Push(nested);continue;}
                    yield return next;
                }
            }
            finally
            {
                while(stack.Count>0)
                {
                    try{(stack.Pop() as IDisposable)?.Dispose();}
                    catch(Exception error){if(failed==null)failed=error;}
                }
                scope.Dispose();
                run.Facts.actions.Add("passive-imgui-observer-disposed;restored="+scope.Restored+";frame="+Time.frameCount);
            }
            if(failed!=null)ExceptionDispatchInfo.Capture(failed).Throw();
            if(!scope.Restored)throw new PresentationUnsupported("Passive IMGUI observer ownership was not restored");
        }

        static IEnumerator RefreshPresented(StormboundRun run,string label,bool saveFrame=true)
        {
            var scope=ImguiObservationScope.Current;
            if(scope==null)throw new PresentationUnsupported("No owned presentation observation scope");
            var start=Time.frameCount;
            yield return scope.Refresh(Regex.Replace(label,@"[^A-Za-z0-9_.-]","_"),saveFrame);
            if(scope.HasRuntimeSurface&&scope.Frame<start)
                throw new PresentationUnsupported("IMGUI observation did not acquire a fresh repaint after the requested action");
            run.Facts.actions.Add("presentation-refresh:"+label+";requested_frame="+start+";observed_frame="+scope.Frame+
                ";sequence="+scope.Sequence+";normal_input_system_only;save_frame="+saveFrame);
        }

        static IEnumerator ClickPresented(StormboundRun run,PresentedControl control)
        {
            if(control==null||!PresentationObservers.CanHit(control,out var point))
                throw new PresentationUnsupported("A selected visible presentation target has no qualified screen coordinate.");
            run.Facts.actions.Add("normal-mouse:"+control.label+":"+point+":"+Time.frameCount);
            yield return run.Input.Click(point);
            yield return RefreshPresented(run,"after-normal-pointer");
        }

        static IEnumerator WaitForPhase(StormboundRun run,string phase,float timeout=3)
        {
            var until=Time.realtimeSinceStartup+timeout;
            do
            {
                if(run.Read().phase==phase)yield break;
                yield return null;
            }while(Time.realtimeSinceStartup<until);
        }

        [UnityTest] public IEnumerator T02_NormalMenu()
        {
            var run=new StormboundRun("dynamic");
            return run.Execute(new[]{"D2_START","D5_CONTROLS"},WithPresentationObservation(run,MenuAndIndependentControls(run)));
        }

        IEnumerator MenuAndIndependentControls(StormboundRun run)
        {
            Exception menuError=null;
            yield return IsolatedPresentationSegment(PointerMenu(run),e=>menuError=e);
            if(menuError!=null)PresentationFailure(run,"D2_START",menuError);
            Exception controlsError=null;
            yield return IsolatedPresentationSegment(PointerControls(run),e=>controlsError=e);
            if(controlsError!=null)PresentationFailure(run,"D5_CONTROLS",controlsError);
        }

        IEnumerator PointerMenu(StormboundRun run)
        {
            yield return run.Load();run.Find();yield return run.Ready();
            yield return RefreshPresented(run,"menu-before-normal-pointer");
            var menu=run.Read();var before=ReadPresented();
            PresentedFrame(run,"normal-menu-before-click",before,menu);
            var start=FindPresentedControl(@"\b(start|begin|play|new game|new voyage|set sail)\b");
            if(start==null)
            {
                PresentationVerdict(run,"D2_START",false,"Visible Start accepts a real pointer click",
                    "A supported visible UI was observed, but no visible hittable Start control was found.");
                yield break;
            }
            yield return ClickPresented(run,start);yield return WaitForPhase(run,"playing");
            yield return RefreshPresented(run,"menu-after-normal-pointer");
            var after=run.Read();var text=ReadPresented();PresentedFrame(run,"normal-menu-after-click",text,after);
            var clean=menu.phase=="menu"&&after.phase=="playing"&&V(after,"day")==1&&V(after,"period")==0&&
                Stock(after,"a","food")==30&&Stock(after,"b","food")==24&&
                after.actors.Count(x=>x.kind=="resident"&&x.state=="alive")==6;
            if(start.isCandidateOnly&&after.phase!="playing")
                throw new PresentationUnsupported("A visible Start label candidate did not establish normal entry, and no actual control role was observed; do not call an instruction label a broken button.");
            PresentationVerdict(run,"D2_START",clean,"Normal visible Start opens the clean game, not a service-only route",
                JsonUtility.ToJson(after));
        }

        IEnumerator PointerControls(StormboundRun run)
        {
            // This preparation is independent of whether the menu path succeeded.
            run.RequiredActorIds.Clear();run.RequiredLandmarks.Clear();
            yield return Setup(run);
            yield return RefreshPresented(run,"independent-controls-prepared");
            var before=run.Read();var original=ReadPresented();
            var pause=FindPresentedControl(@"\b(pause|resume)\b");
            var hasPause=pause!=null;var hasStep=false;
            var pauseWorks=false;var stepWorks=false;
            if(pause!=null)
            {
                yield return ClickPresented(run,pause);
                pauseWorks=V(run.Read(),"paused")==0;
                if(!pauseWorks&&pause.isCandidateOnly)throw new PresentationUnsupported("Unresponsive text-only pause candidate is not proof of a delivered but broken button.");
                var again=FindPresentedControl(@"\b(pause|resume)\b");
                if(again!=null){yield return ClickPresented(run,again);pauseWorks&=V(run.Read(),"paused")==1;}
                else pauseWorks=false;
            }
            if(V(run.Read(),"paused")==1)
            {
                // A Step control is legally disabled while the preceding Resume action is active.
                // Locate its current enabled surface only after the normal Pause action has completed.
                yield return RefreshPresented(run,"independent-step-enabled");
                var ticks=Ticks(run.Read());var step=FindPresentedControl(@"\b(step|next period|advance period)\b");
                hasStep=step!=null;
                if(step!=null){yield return ClickPresented(run,step);stepWorks=Ticks(run.Read())==ticks+1&&V(run.Read(),"paused")==1;}
                if(step!=null&&step.isCandidateOnly&&!stepWorks)throw new PresentationUnsupported("Unresponsive text-only Step candidate requires further observation rather than a fabricated product failure.");
            }
            yield return RefreshPresented(run,"independent-controls-final");
            var after=ReadPresented();PresentedFrame(run,"independent-visible-controls",after,run.Read());
            var contextual=PresentationObservers.Joined(original)!=PresentationObservers.Joined(after);
            PresentationVerdict(run,"D5_CONTROLS",hasPause&&hasStep&&pauseWorks&&stepWorks&&contextual,
                "Independent playable entry exposes visible pointer-operable pause/resume and exact one-period Step",
                "menu_success_is_not_a_dependency;pause_found="+hasPause+";step_found="+hasStep+
                ";pause_behavior="+pauseWorks+";step_behavior="+stepWorks+";visible_change="+contextual+
                ";visible_controls="+string.Join("|",PresentationObservers.Controls().Select(x=>x.label)));
        }

        [UnityTest] public IEnumerator T21_HUD()
        {
            var run=new StormboundRun("dynamic");
            return run.Execute(new[]{"D5_HUD","D5_FEEDBACK"},WithPresentationObservation(run,HudAndFeedback(run)));
        }

        IEnumerator HudAndFeedback(StormboundRun run)
        {
            Exception hudError=null;
            yield return IsolatedPresentationSegment(DifferentialHud(run),e=>hudError=e);
            if(hudError!=null)PresentationFailure(run,"D5_HUD",hudError);
            Exception feedbackError=null;
            yield return IsolatedPresentationSegment(IndependentFeedback(run),e=>feedbackError=e);
            if(feedbackError!=null)PresentationFailure(run,"D5_FEEDBACK",feedbackError);
        }

        IEnumerator DifferentialHud(StormboundRun run)
        {
            run.RequiredActorIds.Clear();run.RequiredLandmarks.Clear();
            yield return Setup(run,s=>{N(A(s,"island-a"),"food",117);N(A(s,"island-a"),"timber",131);
                N(A(s,"island-b"),"food",149);N(A(s,"resident-1"),"health",63);});
            yield return RefreshPresented(run,"hud-state-one");
            var first=ReadPresented();PresentedFrame(run,"hud-edited-state-one",first,run.Read());
            yield return Setup(run,s=>{N(A(s,"island-a"),"food",163);N(A(s,"island-a"),"timber",179);
                N(A(s,"island-b"),"food",193);N(A(s,"resident-1"),"health",47);});
            yield return RefreshPresented(run,"hud-state-two");
            var second=ReadPresented();PresentedFrame(run,"hud-edited-state-two",second,run.Read());
            var edits=new[]{new KeyValuePair<double,double>(117,163),new KeyValuePair<double,double>(131,179),
                new KeyValuePair<double,double>(149,193),new KeyValuePair<double,double>(63,47)};
            var changes=PresentationObservers.ReplacedNumbers(first.Select(x=>x.text),second.Select(x=>x.text),edits);
            PresentationVerdict(run,"D5_HUD",changes,
                "Actual screen-visible stock and health values respond to legal state edits; static duplicate numbers are neutral",
                "count_difference_matches="+changes+";before="+PresentationObservers.Joined(first)+";after="+PresentationObservers.Joined(second));
        }

        IEnumerator IndependentFeedback(StormboundRun run)
        {
            // A pointer wiring defect must not block the independently declared
            // keyboard route for invalid-order feedback. This invokes only C
            // through the real Input System, never a candidate business method.
            yield return Setup(run,s=>N(s,"selected_building",1));
            yield return RefreshPresented(run,"unavailable-order-before-keyboard");
            var before=run.Read();var text=ReadPresented();
            var missingWorkshop=V(before,"selected_island")==1&&V(before,"selected_building")==1&&
                A(before,"a-workshop").state!="built";
            PresentedFrame(run,"unavailable-order-before-normal-keyboard",text,before);
            yield return run.Tap(Key.C);
            yield return RefreshPresented(run,"unavailable-order-after-keyboard");
            var after=run.Read();var visible=ReadPresented();var newText=PresentationObservers.Joined(visible);
            var changedReason=ConstructionFeedbackObservation.HasNewWorkshopExplanation(text.Select(x=>x.text),visible.Select(x=>x.text));
            // An explicit, readable prerequisite beside the selected action is
            // a legal equivalent to a toast. It need not change or accompany a
            // disabled button. A bare building name never satisfies this route.
            var persistentReason=ConstructionFeedbackObservation.HasPersistentWorkshopExplanation(text.Select(x=>x.text),visible.Select(x=>x.text));
            var reasons=ConstructionFeedbackObservation.WorkshopExplanations(visible.Select(x=>x.text));
            var feedback=missingWorkshop&&Same(before,after,false)&&(changedReason||persistentReason);
            PresentedFrame(run,"unavailable-order-after-normal-keyboard",visible,after);
            PresentationVerdict(run,"D5_FEEDBACK",feedback,
                "Unavailable local construction is visibly explained and cannot spend resources",
                "independent-normal-keyboard-C;pointer_success_is_not_a_dependency;feedback="+feedback+
                ";missing_local_workshop="+missingWorkshop+";state_unchanged="+Same(before,after,false)+";new_explanation="+changedReason+
                ";persistent_explicit_explanation="+persistentReason+";matched_explanations="+string.Join(" | ",reasons)+";visible="+newText);
        }

        [UnityTest] public IEnumerator T22_Chronicle()
        {
            var run=new StormboundRun("dynamic");
            return run.Execute(new[]{"D5_CHRONICLE"},WithPresentationObservation(run,VisibleChronicle(run)));
        }

        static PresentedScroll CurrentScroll(PresentedScroll previous)
        {
            var current=PresentationObservers.Scrolls().FirstOrDefault(x=>x.key==previous.key);
            return current??PresentationObservers.ChronicleScroll()??
                throw new PresentationUnsupported("The observed chronicle surface disappeared during normal navigation");
        }

        static IEnumerator NormalPointerDrag(StormboundRun run,Vector2 from,Vector2 to)
        {
            // Same owned New Input System device as the ordinary driver. Never
            // send legacy IMGUI events, set a scroll offset, or invoke callbacks.
            yield return run.Input.Move(from);var mouse=Mouse.current;
            if(mouse==null||!mouse.added)throw new PresentationUnsupported("No live normal pointer device for drag");
            run.Facts.actions.Add("normal-pointer-drag;device="+mouse.deviceId+";from="+from+";to="+to+";frame="+Time.frameCount);
            try
            {
                for(var frame=0;frame<=12;frame++)
                {
                    mouse.MakeCurrent();var position=Vector2.Lerp(from,to,frame/12f);
                    InputSystem.QueueStateEvent(mouse,new MouseState{position=position}.WithButton(MouseButton.Left,true));
                    yield return null;
                }
            }
            finally
            {
                if(mouse.added){mouse.MakeCurrent();InputSystem.QueueStateEvent(mouse,new MouseState{position=to});}
            }
            yield return null;
            yield return RefreshPresented(run,"after-normal-scrollbar-drag",false);
        }

        static IEnumerator ScrollPresented(StormboundRun run,PresentedScroll scroll,float direction,Action<bool> reached=null)
        {
            var sign=Mathf.Sign(direction);scroll=CurrentScroll(scroll);
            var quantum=HostWheelQuantum();
            if(!SessionFormat.Finite(quantum)||quantum<=0)throw new PresentationUnsupported("Host reports an invalid normal mouse-wheel quantum.");
            run.Facts.actions.Add("normal-scroll-seek:"+scroll.key+";direction="+sign+";host_delta_per_tick="+quantum+";frame="+Time.frameCount);
            if(AtScrollEdge(scroll,sign)){reached?.Invoke(true);yield break;}
            for(var pulse=0;pulse<96;pulse++)
            {
                var before=scroll.Offset;ScrollDiagnostic(run,scroll,"before-wheel-"+pulse);
                yield return run.Input.Scroll(scroll.screen.center,new Vector2(0,sign*quantum));
                yield return RefreshPresented(run,"wheel-pulse-"+pulse,false);scroll=CurrentScroll(scroll);
                var start=Time.realtimeSinceStartupAsDouble;var last=scroll.Offset;var stable=0;
                while(Time.realtimeSinceStartupAsDouble-start<1.25)
                {
                    yield return RefreshPresented(run,"wheel-settle-"+pulse,false);scroll=CurrentScroll(scroll);
                    var now=scroll.Offset;var tolerance=scroll.ugui?.00005f:.05f;
                    var inside=scroll.ugui?now>=-.001f&&now<=1.001f:now>=-.1f&&now<=scroll.Extent+.1f;
                    var still=Mathf.Abs(now-last)<=tolerance;
                    if(scroll.ugui)still&=scroll.ugui.velocity.sqrMagnitude<.04f;
                    stable=still&&inside?stable+1:0;last=now;
                    if(Time.realtimeSinceStartupAsDouble-start>=.04&&stable>=3)break;
                }
                ScrollDiagnostic(run,scroll,"settled-wheel-"+pulse);
                if(AtScrollEdge(scroll,sign)){reached?.Invoke(true);yield break;}
                if(Mathf.Abs(scroll.Offset-before)<(scroll.ugui?.0001f:.1f))
                {run.Facts.actions.Add("normal-wheel-no-progress;"+scroll.key+";pulse="+pulse);break;}
            }

            // Scrollability is not Wheel-only. Try the observed real scrollbar
            // before deciding a control defect; both orientations are legal.
            var realAlternativeAttempted=false;scroll=CurrentScroll(scroll);
            if(scroll.hasVerticalScrollbarGeometry)
            {
                for(var side=0;side<2;side++)
                {
                    scroll=CurrentScroll(scroll);
                    if(!scroll.hasVerticalScrollbarGeometry)break;
                    var track=scroll.verticalScrollbarTrack;var thumb=scroll.verticalScrollbarThumb;
                    if(track.width<=0||track.height<=0||thumb.width<=0||thumb.height<=0||
                       new[]{track.x,track.y,track.width,track.height,thumb.x,thumb.y,thumb.width,thumb.height}.Any(x=>!SessionFormat.Finite(x)))
                        throw new PresentationUnsupported("Observed scrollbar geometry is invalid");
                    var pad=Mathf.Min(thumb.height*.5f,track.height*.49f);
                    var topFirst=sign>0;var useTop=side==0?topFirst:!topFirst;
                    var target=new Vector2(track.center.x,useTop?track.yMax-pad:track.yMin+pad);
                    var viewport=new Rect(0,0,Screen.width,Screen.height);
                    if(!viewport.Contains(thumb.center)||!viewport.Contains(target))
                        throw new PresentationUnsupported("Observed scrollbar drag points are outside the actual viewport");
                    realAlternativeAttempted=true;
                    yield return NormalPointerDrag(run,thumb.center,target);scroll=CurrentScroll(scroll);
                    ScrollDiagnostic(run,scroll,"after-scrollbar-end-"+side);
                    if(AtScrollEdge(scroll,sign)){reached?.Invoke(true);yield break;}
                }
            }

            // Explicit visible paging controls are another ordinary route. A
            // rendered label-only candidate may establish success, but its lack
            // of response is not proof that a real page control is broken.
            var pagePattern=sign>0?@"\b(older|previous page|page up|first entr(?:y|ies)|oldest)\b":
                @"\b(newer|next page|page down|last entr(?:y|ies)|latest)\b";
            for(var page=0;page<40;page++)
            {
                yield return RefreshPresented(run,"page-navigation-candidates",false);
                var target=PresentationObservers.Controls().Where(x=>Regex.IsMatch(x.label,pagePattern,RegexOptions.IgnoreCase))
                    .OrderBy(x=>x.isCandidateOnly).ThenBy(x=>x.label.Length).FirstOrDefault(x=>PresentationObservers.CanHit(x,out _));
                if(target==null)break;
                var before=run.Read();var offset=scroll.Offset;
                realAlternativeAttempted|=!target.isCandidateOnly;
                yield return ClickPresented(run,target);scroll=CurrentScroll(scroll);
                if(!Same(before,run.Read()))throw new PresentationUnsupported("A page-navigation candidate changed unrelated public game state; this route is not an isolated chronicle observation");
                if(AtScrollEdge(scroll,sign)){reached?.Invoke(true);yield break;}
                if(Mathf.Abs(scroll.Offset-offset)<(scroll.ugui?.0001f:.1f))break;
            }
            if(!realAlternativeAttempted)
                throw new PresentationUnsupported("Wheel navigation did not reach the requested region and no independently observed scrollbar/paging alternative was available; do not impose a Wheel-only product requirement");
            run.Facts.actions.Add("observed-normal-scrollbar-or-page-route-did-not-reach-region;"+scroll.key+";direction="+sign);
            reached?.Invoke(false);
        }

        static bool AtScrollEdge(PresentedScroll scroll,float direction)
        {
            if(scroll.Extent<=1)return true;
            return scroll.ugui?(direction>0?scroll.Offset>=.999f:scroll.Offset<=.001f):
                (direction>0?scroll.Offset<=.1f:scroll.Offset>=scroll.Extent-.1f);
        }

        static float HostWheelQuantum()
        {
            // The pinned Input System uses this same internal property/constant in UI normalization.
            // Older engine tracks compile the constant branch (1), newer tracks expose the runtime property.
            var flags=System.Reflection.BindingFlags.Static|System.Reflection.BindingFlags.Public|System.Reflection.BindingFlags.NonPublic;
            var property=typeof(InputSystem).GetProperty("scrollWheelDeltaPerTick",flags);
            if(property!=null)return Convert.ToSingle(property.GetValue(null));
            var field=typeof(InputSystem).GetField("scrollWheelDeltaPerTick",flags);
            if(field!=null)return Convert.ToSingle(field.GetValue(null));
            throw new PresentationUnsupported("Pinned Input System wheel normalization member is unavailable.");
        }

        static void ScrollDiagnostic(StormboundRun run,PresentedScroll scroll,string stage)
        {
            var point=scroll.screen.center;var hits=new List<RaycastResult>();var eventSystem=EventSystem.current;
            if(eventSystem)eventSystem.RaycastAll(new PointerEventData(eventSystem){position=point},hits);
            var first=hits.Count>0?hits[0].gameObject:null;
            var receiver=first?ExecuteEvents.GetEventHandler<IScrollHandler>(first):null;
            var module=eventSystem?eventSystem.currentInputModule as InputSystemUIInputModule:null;
            var action=module?module.scrollWheel?.action:null;
            var mouse=Mouse.current;var actionValue="unavailable";
            if(action!=null){try{actionValue=action.ReadValue<Vector2>().ToString();}catch(Exception e){actionValue=e.GetType().Name+":"+e.Message;}}
            run.Facts.actions.Add("wheel-observation;stage="+stage+";frame="+Time.frameCount+";offset="+scroll.Offset+
                ";extent="+scroll.Extent+";point="+point+";mouse="+(mouse!=null?mouse.position.ReadValue().ToString():"none")+
                ";device_scroll="+(mouse!=null?mouse.scroll.ReadValue().ToString():"none")+
                ";module="+(eventSystem&&eventSystem.currentInputModule?eventSystem.currentInputModule.GetType().FullName:"none")+
                ";scroll_action="+(action==null?"none":action.name+"/enabled="+action.enabled)+";action_value="+actionValue+
                ";top_hit="+(first?first.name+"#"+first.GetInstanceID():"none")+
                ";scroll_receiver="+(receiver?receiver.name+"#"+receiver.GetInstanceID():"none")+
                ";target_scroll="+(scroll.ugui?scroll.ugui.gameObject.name+"#"+scroll.ugui.gameObject.GetInstanceID():scroll.key));
        }

        IEnumerator VisibleChronicle(StormboundRun run)
        {
            yield return Setup(run,s=>{Supplies(s,5000);Job(s,1,1);});
            var initialCount=V(run.Read(),"chronicle_count");
            // Repeated ordinary work/rest days create a genuinely long causal history.
            for(var day=0;day<50 && V(run.Read(),"chronicle_count")<=34;day++)
            {
                yield return run.Step();
                for(var j=0;j<5;j++)yield return run.Tap(Key.J);
                yield return run.Step(2);
                yield return run.Tap(Key.J);
            }
            yield return RefreshPresented(run,"chronicle-long-history");
            var save=run.Read();var all=ReadPresented();
            var scroll=PresentationObservers.ChronicleScroll();
            if(scroll==null)throw new PresentationUnsupported("No supported visible chronicle scrolling surface was locatable; require a rendered-frame observer for custom scrolling.");
            var offset0=scroll.Offset;var olderReached=false;var newerReached=false;
            yield return ScrollPresented(run,scroll,3000,value=>olderReached=value);
            yield return RefreshPresented(run,"chronicle-older-region");
            var upper=PresentationObservers.InScroll(scroll,ReadPresented());
            var offset1=scroll.Offset;
            PresentedFrame(run,"chronicle-older-visible-region",upper,run.Read());
            yield return ScrollPresented(run,scroll,-3000,value=>newerReached=value);
            yield return RefreshPresented(run,"chronicle-newer-region");
            var lower=PresentationObservers.InScroll(scroll,ReadPresented());var offset2=scroll.Offset;
            PresentedFrame(run,"chronicle-newer-visible-region",lower,run.Read());
            var oldText=PresentationObservers.Joined(upper);var newText=PresentationObservers.Joined(lower);
            var scrolling=scroll.Extent<=1 || (olderReached&&newerReached&&Mathf.Abs(offset1-offset2)>.001f&&oldText!=newText);
            var dated=PresentationObservers.LooksLikeHistory(oldText+" "+newText);
            var named=Regex.IsMatch(oldText+" "+newText,@"\b(Ada|Bram|Cleo|Dara|Eli|Finn)\b");
            var causal=Regex.IsMatch(oldText+" "+newText,@"\b(food|forag|work|rest|produ|gather|suppl|consum|weather|rain|storm)",RegexOptions.IgnoreCase);
            yield return run.Tap(Key.F5);
            yield return RefreshPresented(run,"chronicle-after-save");
            var saved=run.Read();
            scroll=PresentationObservers.ChronicleScroll();if(scroll==null)throw new PresentationUnsupported("Chronicle surface disappeared after Save.");
            yield return ScrollPresented(run,scroll,-3000);
            yield return RefreshPresented(run,"chronicle-stored-region");
            var storedVisible=PresentationObservers.Joined(PresentationObservers.InScroll(scroll,ReadPresented()));
            yield return run.Tap(Key.F9);
            yield return RefreshPresented(run,"chronicle-after-load");
            var loaded=run.Read();
            scroll=PresentationObservers.ChronicleScroll();if(scroll==null)throw new PresentationUnsupported("Chronicle surface disappeared after Load.");
            yield return ScrollPresented(run,scroll,-3000);
            yield return RefreshPresented(run,"chronicle-loaded-region");
            var loadedVisible=PresentationObservers.Joined(PresentationObservers.InScroll(scroll,ReadPresented()));
            var persisted=V(saved,"chronicle_count")==V(loaded,"chronicle_count")&&
                V(saved,"next_chronicle_id")==V(loaded,"next_chronicle_id")&&
                PresentationObservers.SemanticText(storedVisible)==PresentationObservers.SemanticText(loadedVisible);
            var pass=V(save,"chronicle_count")>30&&V(save,"chronicle_count")>initialCount&&scrolling&&dated&&named&&causal&&persisted;
            PresentationVerdict(run,"D5_CHRONICLE",pass,
                "More than thirty real entries remain visible, scrollable and causal; normal Save/Load preserves visible history and public metadata",
                "count="+V(save,"chronicle_count")+";scroll="+scrolling+";offsets="+offset0+","+offset1+","+offset2+";extent="+scroll.Extent+";dated="+dated+";named="+named+
                ";causal="+causal+";persisted="+persisted+";older_region_reached="+olderReached+";newer_region_reached="+newerReached+";opaque_representation_not_compared");
        }

        [UnityTest] public IEnumerator T23_Audio()
        {
            var run=new StormboundRun("dynamic");
            return run.Execute(new[]{"D5_AUDIO"},ActualAudioPresentation(run));
        }

        static void SaveAudioFacts(StormboundRun run,List<AudioWindowFact> windows)
        {
            var root=Path.GetDirectoryName(Environment.GetEnvironmentVariable("STORMBOUND_EVIDENCE_FILE"));
            var dir=Path.Combine(root,"facts");Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir,run.Name+"-audio.json"),JsonUtility.ToJson(new AudioEvidence{windows=windows},true));
        }
        [Serializable]sealed class AudioEvidence{public List<AudioWindowFact> windows;}

        IEnumerator ActualAudioPresentation(StormboundRun run)
        {
            // Audio is entered through ordinary input, not Restore or real-object lookup.
            yield return run.Load();yield return run.Ready();yield return run.Tap(Key.Enter);
            yield return run.Wait(.5f);
            // A menu defect is not a common prerequisite for the audio mechanics.
            SessionSave normal=null;
            try{run.Find();normal=run.Read();}catch(SessionProductFailure){/* Normal audio may still be independently observable. */}
            if(normal!=null&&normal.phase=="menu")
            {yield return run.Open();yield return run.Begin();yield return run.Wait(.2f);}
            var windows=new List<AudioWindowFact>();
            using(var audio=new AudioPresentationScope())
            {
                var baseline=new AudioWindowFact{label="initial-ambience"};
                windows.Add(baseline);yield return audio.Collect(baseline,.65f);
                var action=new AudioWindowFact{label="normal-order-feedback"};
                windows.Add(action);yield return audio.Collect(action,.35f,run.Tap(Key.C));
                var saveCue=new AudioWindowFact{label="normal-save-feedback"};
                windows.Add(saveCue);yield return audio.Collect(saveCue,.35f,run.Tap(Key.F5));
                var beforeRestart=AudioPresentationScope.LoopCounts(baseline);
                var restart=new AudioWindowFact{label="normal-double-restart"};
                windows.Add(restart);
                yield return audio.Collect(restart,.25f,run.Tap(Key.R));
                yield return run.Wait(2.1f);
                yield return audio.Collect(restart,.25f,run.Tap(Key.R));
                yield return run.Wait(2.1f);
                var after=new AudioWindowFact{label="restored-ambience-after-two-restarts"};
                windows.Add(after);yield return audio.Collect(after,.65f);
                SaveAudioFacts(run,windows);
                var audible=AudioPresentationScope.Audible(baseline)&&AudioPresentationScope.Audible(after);
                if(audible&&!AudioPresentationScope.HasVoiceEvidence(baseline))
                    throw new PresentationUnsupported("Actual output exists but pinned audio-channel capture produced no voices. Audio observer qualification is required.");
                var orderFeedback=AudioPresentationScope.DistinctCue(baseline,action);
                var saveFeedback=AudioPresentationScope.DistinctCue(action,saveCue);
                var noGrowth=AudioPresentationScope.NoLoopGrowth(beforeRestart,AudioPresentationScope.LoopCounts(after));
                var escapedCue=false;var extinctCue=false;
                yield return EndingAudioTrial(run,audio,windows,true,result=>escapedCue=result);
                yield return EndingAudioTrial(run,audio,windows,false,result=>extinctCue=result);
                SaveAudioFacts(run,windows);
                PresentationVerdict(run,"D5_AUDIO",audible&&orderFeedback&&saveFeedback&&noGrowth&&escapedCue&&extinctCue,
                    "Real output contains ambience, action/save voices and both normal endings, including PlayOneShot; repeated Restart does not stack streams",
                    "audible="+audible+";order_cue="+orderFeedback+";save_cue="+saveFeedback+
                    ";no_loop_growth="+noGrowth+";escape_cue="+escapedCue+";extinction_cue="+extinctCue+
                    ";multiple_distinct_ambient_layers_allowed;voice_and_waveform_facts_saved");
            }
        }

        IEnumerator EndingAudioTrial(StormboundRun run,AudioPresentationScope audio,List<AudioWindowFact> windows,bool success,Action<bool> result)
        {
            run.RequiredLandmarks.Add("island-a");
            yield return Setup(run,s=>{
                N(s,"tick_remainder",3.875);
                if(success)
                {
                    Beacons(s);Supplies(s,500);
                    for(var i=1;i<=6;i++)run.MoveResident(s,i,1);
                    Job(s,1,4);Esc(s,2,2);
                }
                else
                {
                    Date(s,1,2);for(var i=2;i<=6;i++)Kill(s,i);
                    N(A(s,"resident-1"),"health",10);N(A(s,"island-a"),"food",0);
                }
            });
            var phase=success?"escaped":"extinct";
            var before=new AudioWindowFact{label="before-"+phase};windows.Add(before);
            yield return audio.Collect(before,.25f,null,()=>run.Read().phase);
            var transition=new AudioWindowFact{label="normal-clock-"+phase};windows.Add(transition);
            // Normal resume commits the last real work/night tick; no terminal state is injected.
            yield return audio.Collect(transition,.8f,run.Tap(Key.Escape),()=>run.Read().phase);
            var prior=new AudioWindowFact{label="pre-terminal-audio",frames=before.frames.Concat(
                transition.frames.Where(x=>x.game_phase!=phase)).ToList()};
            var terminal=new AudioWindowFact{label="terminal-audio",frames=transition.frames.Where(x=>x.game_phase==phase).ToList()};
            result(run.Read().phase==phase&&AudioPresentationScope.Audible(terminal)&&
                AudioPresentationScope.DistinctCue(prior,terminal));
        }
    }
}

#endif
