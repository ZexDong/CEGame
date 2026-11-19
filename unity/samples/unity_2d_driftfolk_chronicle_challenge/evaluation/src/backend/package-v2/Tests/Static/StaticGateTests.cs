using System.Collections;
using System.Linq;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
namespace GameCreate.Stormbound.Evaluator
{
 public sealed class StaticGateTests
 {
  [UnityTest] public IEnumerator STATIC01_SceneAndCamera(){var r=new StormboundRun("static");return r.Execute(new[]{"D1_SCENE","D1_CAMERA"},Body(r));}
  IEnumerator Body(StormboundRun r){yield return r.Load();var scene=SceneManager.GetActiveScene();var cameras=Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(c=>c.isActiveAndEnabled).ToArray();r.Facts.frames.Add(new FrameFact{frame=Time.frameCount,realtime=Time.realtimeSinceStartup,label="real-saved-scene-frame",visible_text=StormboundRun.Text(),actors=cameras.Select(c=>new WorldActor{id="camera",instance_id=c.GetInstanceID(),position=c.transform.position,presentation=c.name}).ToList()});r.Check("D1_SCENE",scene.path==StormboundRun.ScenePath,"saved final scene loads",scene.path);r.Check("D1_CAMERA",cameras.Any(c=>c.pixelWidth>0&&c.pixelHeight>0),"at least one active usable rendering camera; multiple-camera equivalents accepted","cameras="+cameras.Length);}
 }
}
