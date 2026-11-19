using System;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;

namespace GameCreate.Stormbound.Evaluator.Capture
{
    [InitializeOnLoad] public static class HostIdentityPolicy
    {
        static HostIdentityPolicy(){Apply();EditorApplication.playModeStateChanged+=state=>{if(state==PlayModeStateChange.ExitingEditMode)Apply();};}
        public static void Apply()
        {
            var company=Environment.GetEnvironmentVariable("STORMBOUND_HOST_COMPANY");
            if(string.IsNullOrEmpty(company))return;
            if(!company.StartsWith("GameCreateBenchmarkTemp-",StringComparison.Ordinal))throw new InvalidOperationException("Unowned host company identity.");
            PlayerSettings.companyName=company; // Deliberately never modify productName.
        }
    }
    public sealed class HostIdentityBuildPolicy:IPreprocessBuildWithReport
    {
        public int callbackOrder=>int.MaxValue;
        public void OnPreprocessBuild(BuildReport report){HostIdentityPolicy.Apply();}
    }
}
