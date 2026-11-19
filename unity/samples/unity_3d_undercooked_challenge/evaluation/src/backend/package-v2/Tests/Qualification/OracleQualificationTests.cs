using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Evaluation.Session;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.UI;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

namespace GameCreate.Undercooked.Evaluator.Qualification
{
    public sealed class OracleQualificationTests
    {
        readonly List<GameObject> created = new List<GameObject>();
        GameObject New(string name) { var o = new GameObject(name); created.Add(o); return o; }
        [TearDown] public void Cleanup() { foreach (var o in created) if(o) Object.DestroyImmediate(o); created.Clear(); }
        (GameObject chef, GameObject station, Vector3 axis, Vector3 normal, float contact) Geometry(float radius=.32f,float depth=1.55f,float yaw=0,float tilt=0)
        {
            var frame=Quaternion.Euler(tilt,yaw,0);var axis=frame*Vector3.forward;var normal=frame*Vector3.up;
            var station=New("real collision station");station.transform.SetPositionAndRotation(new Vector3(11,4,-7),frame);
            var box=station.AddComponent<BoxCollider>();box.size=new Vector3(1.65f,1.1f,depth);box.center=Vector3.up*.5f;
            var chef=New("real chef collision");chef.transform.rotation=frame;var body=chef.AddComponent<CapsuleCollider>();body.radius=radius;body.height=1.4f;body.center=Vector3.up*.7f;
            var contact=depth/2+radius;chef.transform.position=station.transform.position-axis*(contact+.185f);Physics.SyncTransforms();
            return (chef,station,axis,normal,contact);
        }
        void Position((GameObject chef,GameObject station,Vector3 axis,Vector3 normal,float contact) g,float distance)
        { g.chef.transform.position=g.station.transform.position-g.axis*distance;Physics.SyncTransforms(); }
        [TestCase(.18f,1.1f,0,0)]
        [TestCase(.32f,1.55f,37,0)]
        [TestCase(.51f,2.2f,93,51)]
        public void LegalCollisionUsesActualRadiusRotationAndFloorPlane(float radius,float depth,float yaw,float tilt)
        {
            var g=Geometry(radius,depth,yaw,tilt);var p=new ColliderMotionProbe(g.chef,g.station,g.normal);
            foreach(var gap in new[]{.125f,.065f,.005f}) {Position(g,g.contact+gap);p.Sample();}
            Assert.That(p.Result.Blocked,Is.True,JsonUtility.ToJson(p.Result));
        }
        [Test] public void ShortLegalApproachBelowPointTwoPasses()
        {
            var g=Geometry();Position(g,1.3f);var p=new ColliderMotionProbe(g.chef,g.station,g.normal);
            foreach(var d in new[]{1.238337f,1.176675f,1.115012f}){Position(g,d);p.Sample();}
            Assert.That(p.Result.Blocked,Is.True,JsonUtility.ToJson(p.Result));
        }
        [Test] public void AlreadyAtContactNeedsNoAdditionalTravel()
        { var g=Geometry();Position(g,g.contact+.001f);var p=new ColliderMotionProbe(g.chef,g.station,g.normal);p.Sample();Assert.That(p.Result.Blocked,Is.True); }
        [Test] public void StationaryFarFromObstacleFails()
        { var g=Geometry();Position(g,g.contact+1);var p=new ColliderMotionProbe(g.chef,g.station,g.normal);p.Sample();Assert.That(p.Result.Blocked,Is.False); }
        [Test] public void NoFreeMovementFailsEvenWhenAlreadyAtContact()
        {var g=Geometry();Position(g,g.contact+.001f);var p=new ColliderMotionProbe(g.chef,g.station,g.normal);Assert.That(ColliderMotionProbe.MovementPass(false,true,true,false,true,p.Result),Is.False);}
        [Test] public void NoCollisionResponseEnteringObstacleFails()
        {var g=Geometry();var p=new ColliderMotionProbe(g.chef,g.station,g.normal);Position(g,.4f);p.Sample();Assert.That(p.Result.did_not_penetrate,Is.False);Assert.That(p.Result.Blocked,Is.False);}
        [Test] public void OneFrameTunnelFailsEvenWithSeparatedEndpoint()
        {var g=Geometry();var p=new ColliderMotionProbe(g.chef,g.station,g.normal);Position(g,-g.contact-.3f);p.Sample();Assert.That(p.Result.did_not_cross,Is.False);Assert.That(p.Result.did_not_penetrate,Is.False);Assert.That(p.Result.Blocked,Is.False);}
        [Test] public void ThinOffsetObstacleTunnelFailsBeforeRootPlane()
        {
            var g=Geometry(.08f);var box=g.station.GetComponent<BoxCollider>();box.size=new Vector3(8,1.1f,.02f);box.center=new Vector3(0,.5f,-2);Position(g,2.4f);
            var p=new ColliderMotionProbe(g.chef,g.station,g.normal);Position(g,1.6f);p.Sample();
            Assert.That(p.Result.did_not_cross,Is.True);Assert.That(p.Result.did_not_penetrate,Is.False);Assert.That(p.Result.Blocked,Is.False);
        }
        [Test] public void CharacterControllerAtContactUsesRealGeometry()
        {var g=Geometry();Object.DestroyImmediate(g.chef.GetComponent<Collider>());var cc=g.chef.AddComponent<CharacterController>();cc.radius=.32f;cc.height=1.4f;cc.center=Vector3.up*.7f;Position(g,g.contact+.001f);Assert.That(new ColliderMotionProbe(g.chef,g.station,g.normal).Result.Blocked,Is.True);}
        [Test] public void AsymmetricBoxBodyNearRotatedStationUsesRealGeometry()
        {var g=Geometry(.32f,1.55f,43);Object.DestroyImmediate(g.chef.GetComponent<Collider>());var b=g.chef.AddComponent<BoxCollider>();b.size=new Vector3(.4f,1.4f,.64f);b.center=Vector3.up*.7f;Position(g,g.contact+.001f);Assert.That(new ColliderMotionProbe(g.chef,g.station,g.normal).Result.Blocked,Is.True);}
        [Test] public void RendererPaddingCannotChangeGeometryVerdict()
        {
            var g=Geometry();Position(g,g.contact+.001f);var before=new ColliderMotionProbe(g.chef,g.station,g.normal).Result;
            var decoration=GameObject.CreatePrimitive(PrimitiveType.Cube);created.Add(decoration);Object.DestroyImmediate(decoration.GetComponent<Collider>());
            decoration.transform.SetParent(g.station.transform,false);decoration.transform.localScale=Vector3.one*100;
            var after=new ColliderMotionProbe(g.chef,g.station,g.normal).Result;
            Assert.That(after.Blocked,Is.EqualTo(before.Blocked));Assert.That(after.samples[0].gap,Is.EqualTo(before.samples[0].gap).Within(.0001));
        }
        [Test] public void MissingChefColliderIsObserverUnavailableNotProductVerdict()
        {var g=Geometry();Object.DestroyImmediate(g.chef.GetComponent<Collider>());var p=new ColliderMotionProbe(g.chef,g.station,g.normal);Assert.That(p.Result.geometry_available,Is.False);Assert.That(p.Result.unavailable_reason,Does.Contain("not itself a public product violation"));}
        [Test] public void DegenerateInsideSolidApproachCannotPass()
        {var g=Geometry();Position(g,0);var p=new ColliderMotionProbe(g.chef,g.station,g.normal);Assert.That(p.Result.approach_direction_available,Is.False);Assert.That(p.Result.did_not_penetrate,Is.False);Assert.That(p.Result.Blocked,Is.False);}
        static ResultUiObservation[] Ui(Func<int,string[]> text)
        {return new[]{20,60,90}.Select(points=>new ResultUiObservation{score=points,surfaces=text(points).Select(t=>new VisibleUiSurface{text=t,style="same-font"}).ToList()}).ToArray();}
        static string Grade(int n)=>n<40?"Bronze":n<80?"Silver":"Gold";
        const string Legend="Bronze < 40   Silver 40+   Gold 80+";
        [Test] public void CorrectCurrentGradePlusStaticLegendPasses()
        {var a=Ui(n=>new[]{Grade(n)+" KITCHEN",n+" POINTS",Legend});Assert.That(ResultUiOracle.CurrentValues(a,true).All(x=>x),Is.True);Assert.That(ResultUiOracle.CurrentValues(a,false).All(x=>x),Is.True);}
        [Test] public void CombinedCurrentGradeLegendAndScorePasses()
        {var a=Ui(n=>new[]{Grade(n)+" kitchen "+Legend+" "+n+" points"});Assert.That(ResultUiOracle.CurrentValues(a,true).All(x=>x),Is.True);}
        [Test] public void StaticLegendWithChangingScoreCannotEstablishCurrentGrade()
        {var a=Ui(n=>new[]{Legend+" "+n+" points"});Assert.That(ResultUiOracle.CurrentValues(a,true).Any(x=>x),Is.False);}
        [Test] public void WrongCurrentGradeCannotBeRescuedByAllTierLegend()
        {var a=Ui(n=>new[]{"BRONZE KITCHEN",n+" POINTS",Legend});Assert.That(ResultUiOracle.CurrentValues(a,true).All(x=>x),Is.False);}
        [Test] public void SwappedCurrentGradesFail()
        {var a=Ui(n=>new[]{n==20?"Gold":n==90?"Bronze":"Silver",n+" POINTS",Legend});Assert.That(ResultUiOracle.CurrentValues(a,true).All(x=>x),Is.False);}
        [Test] public void StaticDecorativeNumbersCannotEstablishCurrentScore()
        {var a=Ui(n=>new[]{Grade(n),"20 60 90"});Assert.That(ResultUiOracle.CurrentValues(a,false).Any(x=>x),Is.False);}
        [Test] public void FixedGradeLabelsWithUniqueMovingHighlightPass()
        {
            var a=Ui(n=>new[]{"Bronze","Silver","Gold",n.ToString()});
            foreach(var o in a)foreach(var s in o.surfaces)s.style=s.text.Equals(Grade((int)o.score))?"selected":"ordinary";
            Assert.That(ResultUiOracle.CurrentValues(a,true).All(x=>x),Is.True);
        }
        [Test] public void ChangingEntireLegendColorIsNotCurrentSelection()
        {var a=Ui(n=>new[]{Legend,n.ToString()});foreach(var o in a)foreach(var s in o.surfaces)s.style=o.score.ToString();Assert.That(ResultUiOracle.CurrentValues(a,true).Any(x=>x),Is.False);}
        [Test] public void OneTextRichSpanMovingGradeHighlightPasses()
        {var a=Ui(n=>new[]{string.Join(" ",new[]{"Bronze","Silver","Gold"}.Select(g=>g==Grade(n)?"<color=#FFFF00><b>"+g+"</b></color>":g)),n.ToString()});Assert.That(ResultUiOracle.CurrentValues(a,true).All(x=>x),Is.True);}
        [TestCase("ANOTHER SHIFT / R",true)]
        [TestCase("[r]",true)]
        [TestCase("BRONZE",false)]
        [TestCase("Retry",false)]
        public void PublicKeyAffordanceUsesStandaloneKeyNotVocabulary(string text,bool expected)
        {Assert.That(ResultUiOracle.HasPublicRestartKey(text),Is.EqualTo(expected));}
        [TestCase(true,false,true,true)]
        [TestCase(false,true,true,true)]
        [TestCase(true,true,false,false)]
        [TestCase(false,false,true,false)]
        public void FakeOrMissingRestartFails(bool hint,bool control,bool operates,bool expected)
        {Assert.That(ResultUiOracle.RestartVisibleAndOperable(new ResultUiObservation{restart_hint_visible=hint,restart_control_visible=control,restart_operable=operates}),Is.EqualTo(expected));}
        [TestCase("Press ENTER or SPACE to start",false,true)]
        [TestCase("START",true,true)]
        [TestCase("Welcome",false,false)]
        [TestCase("START",false,false)]
        public void MenuAffordanceAllowsKeyboardWithoutButton(string text,bool button,bool expected)
        {Assert.That(ResultUiOracle.MenuAffordance(text,button),Is.EqualTo(expected));}
        [Test] public void DecorativeStartTextCannotEstablishSuccessfulLifecycle()
        {Assert.That(ResultUiOracle.MenuAffordance("Press ENTER to start",false),Is.True);bool initialMenu=true,afterPlaying=false;Assert.That(initialMenu&&afterPlaying,Is.False,"Readable D5 affordance does not grant D4 lifecycle success.");}
        [UnityTest] public IEnumerator RealNormalMouseClicksVisibleControl()
        {
            var driver=new PlayerInputDriver();yield return driver.Ready();
            var canvas=New("fixture canvas");canvas.AddComponent<Canvas>().renderMode=RenderMode.ScreenSpaceOverlay;canvas.AddComponent<GraphicRaycaster>();
            var system=New("fixture event system");system.AddComponent<EventSystem>();system.AddComponent<InputSystemUIInputModule>();
            var buttonGo=new GameObject("arbitrary visible control",typeof(RectTransform),typeof(Image),typeof(Button));created.Add(buttonGo);buttonGo.transform.SetParent(canvas.transform,false);
            var rect=buttonGo.GetComponent<RectTransform>();rect.sizeDelta=new Vector2(240,80);rect.anchoredPosition=Vector2.zero;
            var labelGo=new GameObject("caption",typeof(RectTransform),typeof(Text));labelGo.transform.SetParent(buttonGo.transform,false);
            var label=labelGo.GetComponent<Text>();label.font=Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");label.text="One more kitchen";label.fontSize=20;label.color=Color.white;label.alignment=TextAnchor.MiddleCenter;label.raycastTarget=false;
            label.rectTransform.sizeDelta=new Vector2(230,70);
            bool activated=false;var button=buttonGo.GetComponent<Button>();button.onClick.AddListener(()=>activated=true);
            yield return null;Canvas.ForceUpdateCanvases();yield return null;
            Assert.That(ResultUiOracle.VisibleButtons().Contains(button),Is.True);
            yield return ResultUiOracle.Click(button);yield return null;
            Assert.That(activated,Is.True,"Normal mouse route must reach Unity UI; no direct callback invocation in observer.");
            yield return driver.Dispose();
        }
        IEnumerator CustomCollisionNormalInput(int mode,bool expected)
        {
            var driver=new PlayerInputDriver();yield return driver.Ready();var chef=New("custom collision body without Collider");chef.transform.position=new Vector3(0,0,-1.3f);var mover=chef.AddComponent<CustomCollisionFixtureMover>();mover.mode=mode;
            BehavioralCollisionObservation observation=null;
            yield return BehavioralCollisionOracle.Acquire(driver,chef.transform,Vector3.zero,Vector3.right,Vector3.forward,x=>observation=x);
            Assert.That(observation.Blocked,Is.EqualTo(expected),JsonUtility.ToJson(observation));yield return driver.Dispose();
        }
        [UnityTest] public IEnumerator RealKeyboardCustomCollisionEquivalentPasses(){yield return CustomCollisionNormalInput(0,true);}
        [UnityTest] public IEnumerator RealKeyboardNoCollisionCrossingFails(){yield return CustomCollisionNormalInput(1,false);}
        [UnityTest] public IEnumerator RealKeyboardLocalFrozenControlFails(){yield return CustomCollisionNormalInput(2,false);}
    }
    public sealed class CustomCollisionFixtureMover:MonoBehaviour
    {
        public int mode;
        void Update(){var k=Keyboard.current;if(k==null||mode==2)return;var d=(k.wKey.isPressed?1:0)-(k.sKey.isPressed?1:0);var p=transform.position;p.z+=d*3.7f*Time.deltaTime;if(mode==0)p.z=Mathf.Min(-1.1f,p.z);transform.position=p;}
    }
}
