using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEngine;

namespace GameCreate.Stormbound.Evaluator.Capture
{
    [Serializable] public sealed class HostIdentityObservation
    {
        public bool valid,enabled;
        public string company,product,persistent_path,expected_company,expected_product,expected_company_root;
        public int process_id,frame;
    }
    public static class HostIdentityGuard
    {
        static string previous;
        public static HostIdentityObservation Observe()
        {
            var company=Environment.GetEnvironmentVariable("STORMBOUND_HOST_COMPANY");
            var product=Environment.GetEnvironmentVariable("STORMBOUND_HOST_PRODUCT");
            var root=Environment.GetEnvironmentVariable("STORMBOUND_HOST_COMPANY_ROOT");
            var enabled=!string.IsNullOrEmpty(company);
            var path=Path.GetFullPath(Application.persistentDataPath).TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar);
            bool valid=!enabled||company.StartsWith("GameCreateBenchmarkTemp-",StringComparison.Ordinal)&&Application.companyName==company&&
                Application.productName==product&&!string.IsNullOrEmpty(root)&&path.StartsWith(Path.GetFullPath(root).TrimEnd('\\','/')+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase);
            return new HostIdentityObservation{enabled=enabled,valid=valid,company=Application.companyName,product=Application.productName,persistent_path=path,
                expected_company=company,expected_product=product,expected_company_root=root,process_id=System.Diagnostics.Process.GetCurrentProcess().Id,frame=Time.frameCount};
        }
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Begin()
        {
            previous=null;
            if(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("STORMBOUND_HOST_COMPANY")))return;
            Record();var root=new GameObject("PrivateHostIdentityObserver");UnityEngine.Object.DontDestroyOnLoad(root);root.AddComponent<HostIdentityWatcher>();
        }
        internal static void Record()
        {
            var path=Environment.GetEnvironmentVariable("STORMBOUND_HOST_IDENTITY_RECEIPT");if(string.IsNullOrEmpty(path))return;
            var row=Observe();var key=row.company+"\n"+row.product+"\n"+row.persistent_path+"\n"+row.valid;
            if(key==previous)return;previous=key;Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.AppendAllText(path,JsonUtility.ToJson(row)+"\n",new System.Text.UTF8Encoding(false));
        }
        public static string[] PresentationContamination()
        {
            var expected=Environment.GetEnvironmentVariable("STORMBOUND_HOST_COMPANY");if(string.IsNullOrEmpty(expected))return Array.Empty<string>();
            var found=new List<string>();
            foreach(var behavior in UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))
            {
                if(!behavior.isActiveAndEnabled)continue;
                var type=behavior.GetType();var names=new List<string>();for(var t=type;t!=null;t=t.BaseType)names.Add(t.FullName);
                if(!names.Contains("UnityEngine.UI.Text")&&!names.Contains("TMPro.TMP_Text"))continue;
                var color=type.GetProperty("color")?.GetValue(behavior);if(color is Color c&&c.a<=.001f)continue;
                if(behavior.GetComponentsInParent<CanvasGroup>().Any(g=>g.enabled&&g.alpha<=.001f))continue;
                var text=type.GetProperty("text")?.GetValue(behavior) as string;
                if(text!=null&&(text.Contains(expected)||text.Contains("GameCreateBenchmarkTemp-")))found.Add(type.FullName+":"+text);
            }
            foreach(var text in UnityEngine.Object.FindObjectsByType<TextMesh>(FindObjectsInactive.Exclude,FindObjectsSortMode.None))
                if(text.color.a>.001f&&text.GetComponent<Renderer>()&&text.GetComponent<Renderer>().enabled&&
                   (text.text.Contains(expected)||text.text.Contains("GameCreateBenchmarkTemp-")))found.Add("TextMesh:"+text.text);
            return found.ToArray();
        }
    }
    public sealed class HostIdentityWatcher:MonoBehaviour
    {
        void Update(){HostIdentityGuard.Record();}
        void OnDestroy(){HostIdentityGuard.Record();}
    }
}
