#if UNITY_EDITOR
using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;

namespace GameCreate.NoirRoombreak.Evaluator.Standalone.Editor
{
    public static class StandaloneCaptureBuild
    {
        public static void BuildPlayer()
        {
            var outputRoot = Environment.GetEnvironmentVariable("NOIR_STANDALONE_BUILD_ROOT");
            if (string.IsNullOrWhiteSpace(outputRoot)) throw new InvalidOperationException("NOIR_STANDALONE_BUILD_ROOT is missing.");
            Directory.CreateDirectory(outputRoot);
            var executable = Path.Combine(outputRoot, "NoirRoombreakCapture.exe");
            var scenes = EditorBuildSettings.scenes.Where(x => x.enabled && !string.IsNullOrWhiteSpace(x.path)).Select(x => x.path).ToArray();
            if (scenes.Length == 0) throw new InvalidOperationException("EditorBuildSettings has no scenes.");
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = executable,
                target = BuildTarget.StandaloneWindows64,
                options = BuildOptions.None
            });
            if (report.summary.result != BuildResult.Succeeded) throw new InvalidOperationException("Standalone capture build failed: " + report.summary.result);
        }
    }
}
#endif
