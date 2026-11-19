using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.SceneManagement;
using Object=UnityEngine.Object;

namespace GameCreate.NoirRoombreak.Evaluator
{
    [Serializable] public sealed class RuntimeLogFact
    {
        public string type,message,stack;
        public int count,first_frame,last_frame;
    }
    [Serializable] public sealed class RuntimeIsolationReceipt
    {
        public string trajectory,cleanup_error;
        public bool evaluator_logged_error,cleaned,preserved_dirty_close;
        public int summary_overflow;
        public List<RuntimeLogFact> runtime_logs=new List<RuntimeLogFact>();
        public List<string> actions=new List<string>();
    }
    // Host lifecycle only, after scored actions. No candidate class, tag, message,
    // object name, or gameplay field is selected or modified by this scope.
    public sealed class CandidateRuntimeScope:IDisposable
    {
        readonly Func<Scene,bool> declaredScene;
        readonly HashSet<int> baselinePersistent;
        readonly Dictionary<string,RuntimeLogFact> logs=new Dictionary<string,RuntimeLogFact>();
        readonly float previousTimeScale;
        bool closed;
        public RuntimeIsolationReceipt Receipt {get;}
        public CandidateRuntimeScope(Func<Scene,bool> declaredScene,string trajectory)
        {
            this.declaredScene=declaredScene;Receipt=new RuntimeIsolationReceipt{trajectory=trajectory};
            baselinePersistent=new HashSet<int>(PersistentRoots().Select(g=>g.GetInstanceID()));
            previousTimeScale=Time.timeScale;Application.logMessageReceived+=OnLog;
            Receipt.actions.Add("begin; baseline-ddol-roots="+baselinePersistent.Count);
        }
        static GameObject[] PersistentRoots()=>Resources.FindObjectsOfTypeAll<GameObject>().Where(g=>g&&g.scene.IsValid()&&g.scene.name=="DontDestroyOnLoad"&&g.transform.parent==null).ToArray();
        static bool TestFrameworkRoot(GameObject root)=>root.GetComponentsInChildren<MonoBehaviour>(true).Where(c=>c).Any(c=>
        {var name=c.GetType().Assembly.GetName().Name;return name=="UnityEngine.TestRunner"||name=="UnityEditor.TestRunner";});
        GameObject[] NewPersistentRoots()=>PersistentRoots().Where(g=>!baselinePersistent.Contains(g.GetInstanceID())&&!TestFrameworkRoot(g)).ToArray();
        Scene[] CandidateScenes()=>Enumerable.Range(0,SceneManager.sceneCount).Select(SceneManager.GetSceneAt).Where(s=>s.IsValid()&&s.isLoaded&&declaredScene(s)).ToArray();
        void OnLog(string message,string stack,LogType type)
        {
            if(type!=LogType.Error&&type!=LogType.Exception&&type!=LogType.Assert)return;
            var first=(stack??"").Split('\n').Select(s=>s.Trim()).FirstOrDefault(s=>s.Length>0&&
                !s.StartsWith("UnityEngine.")&&!s.StartsWith("UnityEditor.")&&!s.StartsWith("System.")&&!s.StartsWith("Unity."));
            if(first!=null&&(first.StartsWith("GameCreate.NoirRoombreak.Evaluator.")||first.StartsWith("GameCreate.NoirRoombreak.StateAccess.")||first.StartsWith("GameCreate.Evaluation.Session.")))
                Receipt.evaluator_logged_error=true;
            var key=type+"\n"+message+"\n"+stack;
            if(logs.TryGetValue(key,out var item)){item.count++;item.last_frame=Time.frameCount;return;}
            // The raw Unity log is retained in full. Only this per-trajectory
            // unique-message summary is bounded, with explicit overflow counts.
            if(logs.Count>=512){Receipt.summary_overflow++;return;}
            item=new RuntimeLogFact{type=type.ToString(),message=message,stack=stack,count=1,first_frame=Time.frameCount,last_frame=Time.frameCount};
            logs.Add(key,item);Receipt.runtime_logs.Add(item);
        }
        public IEnumerator Cleanup()
        {
            var scenes=CandidateScenes();
            foreach(var scene in scenes)foreach(var root in scene.GetRootGameObjects())if(root)root.SetActive(false);
            if(scenes.Any(s=>s.handle==SceneManager.GetActiveScene().handle))
            {
                var host=SceneManager.GetSceneByName("__NoirEvaluatorNeutralHost");
                if(!host.IsValid()||!host.isLoaded)host=SceneManager.CreateScene("__NoirEvaluatorNeutralHost");
                SceneManager.SetActiveScene(host);
            }
            foreach(var scene in scenes)
            {
                Receipt.actions.Add("unload-declared-scene;handle="+scene.handle+";path="+scene.path);
                var operation=SceneManager.UnloadSceneAsync(scene);var end=Time.realtimeSinceStartup+10;
                while(operation!=null&&!operation.isDone&&Time.realtimeSinceStartup<end)yield return null;
                if(operation==null||!operation.isDone)throw new InvalidOperationException("Evaluator candidate-scene teardown did not complete.");
            }
            for(int round=0;round<4;round++)
            {
                foreach(var root in NewPersistentRoots())
                {
                    Receipt.actions.Add("destroy-new-ddol;id="+root.GetInstanceID());
                    root.SetActive(false);Object.Destroy(root);
                }
                yield return null;yield return null;
                if(NewPersistentRoots().Length==0)break;
            }
            if(CandidateScenes().Length>0||NewPersistentRoots().Length>0)throw new InvalidOperationException("Evaluator runtime isolation left candidate scene/DDOL roots alive.");
            Time.timeScale=previousTimeScale;Receipt.cleaned=true;Receipt.actions.Add("cleaned; candidate scenes and new DDOL roots absent");
        }
        public void PreserveDirtyClose(){Receipt.preserved_dirty_close=true;Receipt.actions.Add("preserve-dirty-close; no teardown or global log-policy leak");}
        public void Dispose(){if(closed)return;closed=true;Application.logMessageReceived-=OnLog;}
    }
}
