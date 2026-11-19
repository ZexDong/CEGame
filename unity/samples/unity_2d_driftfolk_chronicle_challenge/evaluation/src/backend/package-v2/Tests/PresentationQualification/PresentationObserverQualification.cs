#if UNITY_EDITOR
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object=UnityEngine.Object;

namespace GameCreate.Stormbound.Evaluator.PresentationQualification
{
    public sealed class PresentationObserverQualification
    {
        [Serializable]sealed class NativeAudioQualificationEvidence
        {
            public string unity_version,created_utc;
            public int process_id,screen_width,screen_height,audio_sample_rate,source_id,source_game_object_id,loop_clip_id,cue_clip_id;
            public List<AudioWindowFact> windows;
        }
        static KeyValuePair<double,double>[] Edit=>new[]{new KeyValuePair<double,double>(117,163)};
        static AudioVoiceFact Voice(int source,int asset,int plays)=>new AudioVoiceFact{source=source,asset=asset,plays=plays,audibility=1,volume=1};
        static AudioWindowFact Window(params AudioVoiceFact[] voices)=>new AudioWindowFact{
            frames=new List<AudioFrameFact>{new AudioFrameFact{voices=voices.ToList(),listener_available=true,listener_rms=.1f}}};

        [Test]public void P01_StaticDuplicateNumbersDoNotRejectCorrectHud()
        {
            Assert.IsTrue(PresentationObservers.ReplacedNumbers(new[]{"Food 117","Ship 117","Decoration 163"},
                new[]{"Food 163","Ship 117","Decoration 163"},Edit));
        }
        [Test]public void P02_UnchangedWrongHudIsRejected()
        {
            Assert.IsFalse(PresentationObservers.ReplacedNumbers(new[]{"Food 117"},new[]{"Food 117"},Edit));
        }
        [Test]public void P03_DecimalFormattingIsEquivalent()
        {
            Assert.IsTrue(PresentationObservers.ReplacedNumbers(new[]{"Food 117.00"},new[]{"Food 163.0"},Edit));
        }
        [Test]public void P04_LayoutOrderDoesNotChangeHudResult()
        {
            Assert.IsTrue(PresentationObservers.ReplacedNumbers(new[]{"Food 117","Day 2"},
                new[]{"Day 2","Food 163"},Edit));
        }
        [Test]public void P05_OffScreenRectangleCannotBeVisible()
        {
            Assert.IsFalse(PresentationObservers.Clip(new Rect(2000,40,100,30),new Rect(0,0,1280,720),out _));
        }
        [Test]public void P06_ZeroAreaClipCannotBeVisible()
        {
            Assert.IsFalse(PresentationObservers.Clip(new Rect(40,40,100,30),new Rect(50,50,0,0),out _));
        }
        [Test]public void P07_PartiallyClippedReadableSurfaceIsAccepted()
        {
            Assert.IsTrue(PresentationObservers.Clip(new Rect(20,20,100,30),new Rect(40,10,100,100),out var clip));
            Assert.AreEqual(80,clip.width);
        }
        [Test]public void P08_RichTextAndWhitespaceDoNotChangeHistoryMeaning()
        {
            Assert.AreEqual(PresentationObservers.SemanticText("Day 1  Ada <color=#123456>3 food</color>"),
                PresentationObservers.SemanticText("Day 1\n Ada <b>3 food</b>"));
        }
        [Test]public void P09_TwoDifferentAmbientLayersAreLegal()
        {
            Assert.IsTrue(AudioPresentationScope.NoLoopGrowth(new Dictionary<string,int>{{"sea",1},{"wind",1}},
                new Dictionary<string,int>{{"sea",1},{"wind",1}}));
        }
        [Test]public void P10_RestartStackingIsRejected()
        {
            Assert.IsFalse(AudioPresentationScope.NoLoopGrowth(new Dictionary<string,int>{{"sea",1},{"wind",1}},
                new Dictionary<string,int>{{"sea",2},{"wind",1}}));
        }
        [Test]public void P11_OneShotOnExistingLoopSourceIsRecognized()
        {
            Assert.IsTrue(AudioPresentationScope.DistinctCue(Window(Voice(42,100,1)),
                Window(Voice(42,100,1),Voice(42,200,1))));
        }
        [Test]public void P12_AmbienceWithoutActionVoiceDoesNotPass()
        {
            Assert.IsFalse(AudioPresentationScope.DistinctCue(Window(Voice(42,100,1)),Window(Voice(42,100,1))));
        }

        [UnityTest]public IEnumerator P13_RealCanvasAlphaAndClipping()
        {
            var canvasObject=new GameObject("PresentationQualificationCanvas",typeof(Canvas));
            var canvas=canvasObject.GetComponent<Canvas>();canvas.renderMode=RenderMode.ScreenSpaceOverlay;
            var group=canvasObject.AddComponent<CanvasGroup>();
            var textObject=new GameObject("OwnedVisibleLabel",typeof(RectTransform),typeof(Text));
            textObject.transform.SetParent(canvasObject.transform,false);
            var text=textObject.GetComponent<Text>();text.font=Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            text.text="Owned presentation qualification 117";text.color=Color.white;
            var rect=text.rectTransform;rect.anchorMin=rect.anchorMax=new Vector2(0,1);rect.pivot=new Vector2(0,1);
            rect.sizeDelta=new Vector2(400,40);rect.anchoredPosition=new Vector2(20,-20);
            try
            {
                Canvas.ForceUpdateCanvases();yield return null;yield return null;
                Assert.IsTrue(PresentationObservers.GraphicVisible(text,out _),"Positive real UI fixture");
                group.alpha=0;yield return null;
                Assert.IsFalse(PresentationObservers.GraphicVisible(text,out _),"Transparent UI must not count");
                group.alpha=1;rect.anchoredPosition=new Vector2(Screen.width+100,-20);yield return null;
                Assert.IsFalse(PresentationObservers.GraphicVisible(text,out _),"Off-screen UI must not count");
                var viewportObject=new GameObject("OwnedHistoryViewport",typeof(RectTransform),typeof(RectMask2D),typeof(ScrollRect));
                viewportObject.transform.SetParent(canvasObject.transform,false);
                var viewport=(RectTransform)viewportObject.transform;viewport.anchorMin=viewport.anchorMax=new Vector2(0,1);
                viewport.pivot=new Vector2(0,1);viewport.sizeDelta=new Vector2(400,80);viewport.anchoredPosition=new Vector2(20,-20);
                rect.SetParent(viewport,false);rect.anchoredPosition=Vector2.zero;rect.sizeDelta=new Vector2(380,1600);
                text.fontSize=18;text.verticalOverflow=VerticalWrapMode.Overflow;
                text.text=string.Join("\n",Enumerable.Range(1,32).Select(i=>"Day "+i+" Morning Ada food 3"));
                Canvas.ForceUpdateCanvases();rect.sizeDelta=new Vector2(380,text.preferredHeight+4);
                var scroll=viewportObject.GetComponent<ScrollRect>();scroll.viewport=viewport;scroll.content=rect;scroll.horizontal=false;scroll.inertia=false;
                Canvas.ForceUpdateCanvases();yield return null;yield return null;
                var upper=string.Join(" ",PresentationObservers.Texts().Where(x=>x.component==text).Select(x=>x.text));
                Assert.IsTrue(upper.Contains("Day 1 Morning"));Assert.IsFalse(upper.Contains("Day 32 Morning"),"Clipped history rows are not visible text");
                scroll.verticalNormalizedPosition=0;Canvas.ForceUpdateCanvases();yield return null;yield return null;
                var lower=string.Join(" ",PresentationObservers.Texts().Where(x=>x.component==text).Select(x=>x.text));
                Assert.IsTrue(lower.Contains("Day 32 Morning"));Assert.IsFalse(lower.Contains("Day 1 Morning"));
                text.text=string.Join("\n",Enumerable.Range(1,32).Select(i=>"<color=#E8BD73>Day "+i+" Morning</color> Ada food 3"));
                Canvas.ForceUpdateCanvases();rect.sizeDelta=new Vector2(380,text.preferredHeight+4);scroll.verticalNormalizedPosition=1;
                Canvas.ForceUpdateCanvases();yield return null;yield return null;
                var richUpper=string.Join(" ",PresentationObservers.Texts().Where(x=>x.component==text).Select(x=>x.text));
                Assert.IsTrue(richUpper.Contains("Day 1 Morning"));Assert.IsFalse(richUpper.Contains("Day 32 Morning"));
                scroll.verticalNormalizedPosition=0;Canvas.ForceUpdateCanvases();yield return null;yield return null;
                var richLower=string.Join(" ",PresentationObservers.Texts().Where(x=>x.component==text).Select(x=>x.text));
                Assert.IsTrue(richLower.Contains("Day 32 Morning"),"Rich-text offsets must preserve visible bottom history rows");
                Assert.IsFalse(richLower.Contains("Day 1 Morning"));
            }
            finally{Object.DestroyImmediate(canvasObject);}
        }

        [UnityTest]public IEnumerator P14_PinnedEngineReportsActualOneShotVoiceAndMute()
        {
            var objectRoot=new GameObject("OwnedPresentationAudioQualification");
            var source=objectRoot.AddComponent<AudioSource>();source.loop=true;source.spatialBlend=0;source.volume=.08f;
            AudioListener listener=null;
            if(!Object.FindObjectsByType<AudioListener>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Any(x=>x.isActiveAndEnabled))
                listener=objectRoot.AddComponent<AudioListener>();
            var loop=Tone("OwnedQualificationLoop",173,1);var cue=Tone("OwnedQualificationCue",947,.4f);
            var oldVolume=AudioListener.volume;var oldPause=AudioListener.pause;
            var windows=new List<AudioWindowFact>();
            try
            {
                AudioListener.volume=1;AudioListener.pause=false;
                source.clip=loop;source.Play();
                using(var observer=new AudioPresentationScope())
                {
                    var baseline=new AudioWindowFact{label="qualification-loop"};
                    windows.Add(baseline);
                    yield return observer.Collect(baseline,.65f);
                    Assert.IsTrue(baseline.frames.Any(x=>x.sources.Any(s=>s.source==source.GetInstanceID()&&s.rms>.00001f)),
                        "Host must produce real source samples before measuring a game.");
                    Assert.IsTrue(AudioPresentationScope.Audible(baseline),"Host must expose real listener output before a candidate can lose audio credit.");
                    Assert.IsTrue(baseline.frames.Any(x=>x.voices.Any(v=>v.owner_game_object==objectRoot.GetInstanceID()&&v.bound_source_components.Contains(source.GetInstanceID())&&v.asset==loop.GetInstanceID())),
                        "Pinned native audio-channel observer must bind a real source and clip.");
                    var action=new AudioWindowFact{label="qualification-same-source-one-shot"};
                    windows.Add(action);
                    source.PlayOneShot(cue);
                    yield return observer.Collect(action,.45f);
                    Assert.IsTrue(action.frames.Any(x=>x.voices.Any(v=>v.owner_game_object==objectRoot.GetInstanceID()&&v.bound_source_components.Contains(source.GetInstanceID())&&v.asset==cue.GetInstanceID())),
                        "PlayOneShot on a looping source must be independently visible as a cue voice.");
                    Assert.IsTrue(AudioPresentationScope.DistinctCue(baseline,action));
                    source.mute=true;yield return null;
                    var muted=new AudioWindowFact{label="qualification-muted-source"};
                    windows.Add(muted);
                    source.PlayOneShot(cue);
                    yield return observer.Collect(muted,.15f);
                    Assert.IsTrue(muted.frames.All(x=>x.sources.Where(s=>s.source==source.GetInstanceID()).All(s=>s.mute)),
                        "Muted source evidence remains explicit instead of being treated as audible.");
                    Assert.IsFalse(AudioPresentationScope.DistinctCue(action,muted),"A muted one-shot cannot pass as audible feedback.");
                }
            }
            finally
            {
                var process=System.Diagnostics.Process.GetCurrentProcess().Id;
                var directory=Environment.GetEnvironmentVariable("STORMBOUND_PRESENTATION_EVIDENCE_DIRECTORY");
                if(string.IsNullOrWhiteSpace(directory))directory=Path.Combine(Path.GetDirectoryName(Application.dataPath),"Logs","PresentationQualification");
                Directory.CreateDirectory(directory);
                var path=Path.Combine(directory,"P14-native-audio-"+process+".json");
                var evidence=new NativeAudioQualificationEvidence{unity_version=Application.unityVersion,created_utc=DateTime.UtcNow.ToString("o"),
                    process_id=process,screen_width=Screen.width,screen_height=Screen.height,audio_sample_rate=AudioSettings.outputSampleRate,
                    source_id=source.GetInstanceID(),source_game_object_id=objectRoot.GetInstanceID(),loop_clip_id=loop.GetInstanceID(),cue_clip_id=cue.GetInstanceID(),windows=windows};
                File.WriteAllText(path,JsonUtility.ToJson(evidence,true));
                TestContext.Out.WriteLine("Native audio raw evidence: "+path+";screen="+Screen.width+"x"+Screen.height);
                source.Stop();Object.DestroyImmediate(objectRoot);Object.DestroyImmediate(loop);Object.DestroyImmediate(cue);AudioListener.volume=oldVolume;AudioListener.pause=oldPause;
            }
        }


        [UnityTest]public IEnumerator P15_ReusedAudioWindowDrainsEachNewEndToken()
        {
            var root=new GameObject("OwnedRepeatedAudioWindow");
            var source=root.AddComponent<AudioSource>();source.loop=true;source.spatialBlend=0;source.volume=.08f;
            if(!Object.FindObjectsByType<AudioListener>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Any(x=>x.isActiveAndEnabled))
                root.AddComponent<AudioListener>();
            var clip=Tone("OwnedRepeatedWindowTone",257,1);
            var oldVolume=AudioListener.volume;var oldPause=AudioListener.pause;
            var shared=new AudioWindowFact{label="same-window-two-real-collections"};
            try
            {
                AudioListener.volume=1;AudioListener.pause=false;source.clip=clip;source.Play();
                using(var observer=new AudioPresentationScope())
                {
                    yield return observer.Collect(shared,.2f);
                    var firstFrames=shared.frames.ToArray();var firstEnd=firstFrames.Last(x=>x.end_marker).capture_token;
                    Assert.IsTrue(AudioPresentationScope.NativeWindowComplete(shared,firstEnd));
                    yield return observer.Collect(shared,.2f);
                    var secondEnd=shared.frames.Last(x=>x.end_marker).capture_token;
                    Assert.Greater(secondEnd,firstEnd,"Second real interval must have its own final token");
                    Assert.Greater(shared.frames.Count,firstFrames.Length,"Append rather than discard prior acquired samples");
                    Assert.IsTrue(firstFrames.All(x=>shared.frames.Contains(x)),"Prior samples remain part of the merged evidence");
                    Assert.IsTrue(shared.native_complete&&shared.native_frames_bound==shared.frames.Count);
                    Assert.IsTrue(AudioPresentationScope.NativeWindowComplete(shared,secondEnd),"Drain must bind the new end token and every old/new frame");
                }
            }
            finally
            {
                var directory=Environment.GetEnvironmentVariable("STORMBOUND_PRESENTATION_EVIDENCE_DIRECTORY");
                if(string.IsNullOrWhiteSpace(directory))directory=Path.Combine(Path.GetDirectoryName(Application.dataPath),"Logs","PresentationQualification");
                Directory.CreateDirectory(directory);
                var evidence=new NativeAudioQualificationEvidence{unity_version=Application.unityVersion,created_utc=DateTime.UtcNow.ToString("o"),
                    process_id=System.Diagnostics.Process.GetCurrentProcess().Id,screen_width=Screen.width,screen_height=Screen.height,
                    audio_sample_rate=AudioSettings.outputSampleRate,source_id=source.GetInstanceID(),source_game_object_id=root.GetInstanceID(),
                    loop_clip_id=clip.GetInstanceID(),windows=new List<AudioWindowFact>{shared}};
                File.WriteAllText(Path.Combine(directory,"P15-reused-native-audio-"+evidence.process_id+".json"),JsonUtility.ToJson(evidence,true));
                source.Stop();Object.DestroyImmediate(root);Object.DestroyImmediate(clip);AudioListener.volume=oldVolume;AudioListener.pause=oldPause;
            }
        }

        [Test]public void P16_ReusedWindowRejectsStaleEndAndAnyMissingBinding()
        {
            var previous=new AudioFrameFact{capture_token=1,end_marker=true,native_frame_bound=true};
            var current=new AudioFrameFact{capture_token=2,end_marker=true,native_frame_bound=false};
            var window=new AudioWindowFact{native_end_received=true,frames=new List<AudioFrameFact>{previous,current}};
            Assert.IsFalse(AudioPresentationScope.NativeWindowComplete(window,2),"Old end receipt cannot substitute for the new unbound end frame");
            current.native_frame_bound=true;window.native_end_received=false;
            Assert.IsFalse(AudioPresentationScope.NativeWindowComplete(window,2),"All frame rows still require the current interval end receipt");
            window.native_end_received=true;
            Assert.IsFalse(AudioPresentationScope.NativeWindowComplete(window,3),"An absent requested end token cannot pass");
            Assert.IsTrue(AudioPresentationScope.NativeWindowComplete(window,2));
            previous.native_frame_bound=false;
            Assert.IsFalse(AudioPresentationScope.NativeWindowComplete(window,2),"Merged evidence must not drop an earlier unbound frame");
        }

        static AudioClip Tone(string name,float frequency,float seconds)
        {
            const int rate=48000;var values=new float[(int)(rate*seconds)];
            for(var i=0;i<values.Length;i++)values[i]=Mathf.Sin(2*Mathf.PI*frequency*i/rate)*.2f;
            var clip=AudioClip.Create(name,values.Length,1,rate,false);clip.SetData(values,0);return clip;
        }
    }
}

#endif
