using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.SceneManagement;
using Object=UnityEngine.Object;

namespace GameCreate.Undercooked.Evaluator
{
    [Serializable] public sealed class RuntimeLogFact
    {
        public string type,message,stack;
        public int count,first_frame,last_frame;
    }
    // Host lifecycle only. The selector is the declared candidate scene path in
    // production, a synthetic scene handle in qualification. No candidate names.
    public sealed class CandidateRuntimeScope:IDisposable
    {
        readonly Func<Scene,bool> declaredScene;
        readonly ScenarioFacts facts;
        readonly HashSet<int> baselinePersistent;
        readonly Dictionary<string,RuntimeLogFact> logs=new Dictionary<string,RuntimeLogFact>();
        readonly float previousTimeScale;
        bool closed;
        public CandidateRuntimeScope(Func<Scene,bool> declaredScene,ScenarioFacts facts)
        {
            this.declaredScene=declaredScene;this.facts=facts;
            baselinePersistent=new HashSet<int>(PersistentRoots().Select(g=>g.GetInstanceID()));
            previousTimeScale=Time.timeScale;
            Application.logMessageReceived+=OnLog;
            facts.actions.Add("runtime-scope.begin; baseline-ddol-roots="+baselinePersistent.Count);
        }
        static GameObject[] PersistentRoots()=>Resources.FindObjectsOfTypeAll<GameObject>().Where(g=>g&&g.scene.IsValid()&&g.scene.name=="DontDestroyOnLoad"&&g.transform.parent==null).ToArray();
        static bool TestFrameworkRoot(GameObject root)=>root.GetComponentsInChildren<MonoBehaviour>(true).Where(c=>c).Any(c=>
        {var a=c.GetType().Assembly.GetName().Name;return a=="UnityEngine.TestRunner"||a=="UnityEditor.TestRunner";});
        GameObject[] NewPersistentRoots()=>PersistentRoots().Where(g=>!baselinePersistent.Contains(g.GetInstanceID())&&!TestFrameworkRoot(g)).ToArray();
        Scene[] CandidateScenes()=>Enumerable.Range(0,SceneManager.sceneCount).Select(SceneManager.GetSceneAt).Where(s=>s.IsValid()&&s.isLoaded&&declaredScene(s)).ToArray();
        void OnLog(string message,string stack,LogType type)
        {
            if(type!=LogType.Error&&type!=LogType.Exception&&type!=LogType.Assert)return;
            var first=(stack??"").Split('\n').Select(s=>s.Trim()).FirstOrDefault(s=>s.Length>0&&!s.StartsWith("UnityEngine.Debug")&&!s.StartsWith("UnityEngine.Logger")&&!s.StartsWith("UnityEngine.DebugLogHandler"));
            if(first!=null&&(first.StartsWith("GameCreate.Undercooked.Evaluator.")||first.StartsWith("GameCreate.Evaluation.Session.")))facts.evaluator_logged_error=true;
            var key=type+"\n"+message+"\n"+stack;
            if(logs.TryGetValue(key,out var item)){item.count++;item.last_frame=Time.frameCount;return;}
            // Raw Unity logs remain authoritative/unbounded. Keep a bounded unique
            // message summary in each fact, explicitly recording any truncation.
            if(logs.Count>=512){facts.runtime_log_summary_overflow++;return;}
            item=new RuntimeLogFact{type=type.ToString(),message=message,stack=stack,count=1,first_frame=Time.frameCount,last_frame=Time.frameCount};
            logs.Add(key,item);facts.runtime_logs.Add(item);
        }
        public IEnumerator Cleanup()
        {
            var scenes=CandidateScenes();
            // Deactivate only after all gameplay assertions/input have finished.
            // This prevents another Update/Animation callback during async unload.
            foreach(var scene in scenes)foreach(var root in scene.GetRootGameObjects())if(root)root.SetActive(false);
            if(scenes.Any(s=>s.handle==SceneManager.GetActiveScene().handle))
            {
                var host=SceneManager.GetSceneByName("__KitchenEvaluatorNeutralHost");
                if(!host.IsValid()||!host.isLoaded)host=SceneManager.CreateScene("__KitchenEvaluatorNeutralHost");
                SceneManager.SetActiveScene(host);
            }
            foreach(var scene in scenes)
            {
                facts.actions.Add("runtime-scope.unload-declared-scene;handle="+scene.handle+";path="+scene.path);
                var operation=SceneManager.UnloadSceneAsync(scene);var end=Time.realtimeSinceStartup+10;
                while(operation!=null&&!operation.isDone&&Time.realtimeSinceStartup<end)yield return null;
                if(operation==null||!operation.isDone)throw new InvalidOperationException("Evaluator candidate-scene teardown did not complete.");
            }
            // Include DDOL objects spawned by OnDisable/OnDestroy; never destroy
            // baseline host roots or Unity's test runner. Bounded respawn defense.
            for(int round=0;round<4;round++)
            {
                var roots=NewPersistentRoots();
                foreach(var root in roots)
                {
                    facts.actions.Add("runtime-scope.destroy-new-ddol;id="+root.GetInstanceID()+";name="+root.name);
                    root.SetActive(false);Object.Destroy(root);
                }
                yield return null;yield return null;
                if(NewPersistentRoots().Length==0)break;
            }
            if(CandidateScenes().Length>0||NewPersistentRoots().Length>0)throw new InvalidOperationException("Evaluator runtime isolation left candidate scene/DDOL roots alive.");
            Time.timeScale=previousTimeScale;
            facts.actions.Add("runtime-scope.cleaned; candidate scenes and new DDOL roots absent");
        }
        public void PreserveDirtyClose(){facts.actions.Add("runtime-scope.preserve-dirty-close; no teardown and no global log-policy leak");}
        public void Dispose(){if(closed)return;closed=true;Application.logMessageReceived-=OnLog;}
    }
}
