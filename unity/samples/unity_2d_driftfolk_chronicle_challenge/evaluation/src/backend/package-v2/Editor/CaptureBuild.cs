using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;

namespace GameCreate.Stormbound.Evaluator.Capture
{
    public static class CaptureBuild
    {
        public static void Build()
        {
            HostIdentityPolicy.Apply();
            var root=Environment.GetEnvironmentVariable("STORMBOUND_CAPTURE_BUILD_ROOT");
            if(string.IsNullOrEmpty(root))throw new InvalidOperationException("Capture build directory missing.");
            Directory.CreateDirectory(root);
            const string scene="Assets/DriftfolkChallenge/Scenes/DriftfolkChronicle.unity";
            if(!File.Exists(scene))throw new InvalidOperationException("Published final scene is absent.");
            var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{scene},
                locationPathName=Path.Combine(root,"StormboundCapture.exe"),target=BuildTarget.StandaloneWindows64,options=BuildOptions.None});
            if(report.summary.result!=BuildResult.Succeeded)throw new InvalidOperationException("Capture build failed: "+report.summary.result);
        }
    }
}
