using System.Collections;
using System.Linq;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.SceneManagement;
using GameCreate.Session;
namespace GameCreate.Undercooked.Evaluator
{
 public sealed class StaticGateTests
 {
  [UnityTest] public IEnumerator STATIC01_LoadCompileCameraAndRuntimeEntry()
  {
   LogAssert.ignoreFailingMessages=true;var e=new KitchenEvidenceStore("static");var loadable=Application.CanStreamedLevelBeLoaded(KitchenRun.ScenePath);AsyncOperation load=null;
   if(loadable)load=SceneManager.LoadSceneAsync(KitchenRun.ScenePath,LoadSceneMode.Single);
   if(load!=null){var end=Time.realtimeSinceStartup+15;while(!load.isDone&&Time.realtimeSinceStartup<end)yield return null;}
   yield return null;yield return null;var scene=SceneManager.GetActiveScene();
   e.Add("D1_SCENE","D1",2,load!=null&&load.isDone&&scene.path==KitchenRun.ScenePath,"saved final Scene loads",scene.path);
   var cameras=Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(x=>x.isActiveAndEnabled).ToArray();e.Add("D1_CAMERA","D1",2,cameras.Length==1,"one active usable camera","count="+cameras.Length);
   var sessions=Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).OfType<IGameSession>().ToArray();e.Add("D1_RUNTIME","D1",2,sessions.Length==1,"one active public session provider","count="+sessions.Length);e.Write();LogAssert.ignoreFailingMessages=false;
  }
 }
}
