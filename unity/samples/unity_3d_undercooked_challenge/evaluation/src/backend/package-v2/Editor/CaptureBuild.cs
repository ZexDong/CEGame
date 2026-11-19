using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
namespace GameCreate.Undercooked.Evaluator.Capture
{
 public static class CaptureBuild
 {
  public static void Build(){var root=Environment.GetEnvironmentVariable("KITCHEN_CAPTURE_BUILD_ROOT");if(string.IsNullOrEmpty(root))throw new InvalidOperationException("Capture build directory missing");Directory.CreateDirectory(root);var scene="Assets/UndercookedChallenge/Scenes/UndercookedKitchen.unity";if(!File.Exists(scene))throw new InvalidOperationException("Candidate final scene is absent");var report=BuildPipeline.BuildPlayer(new BuildPlayerOptions{scenes=new[]{scene},locationPathName=Path.Combine(root,"KitchenCapture.exe"),target=BuildTarget.StandaloneWindows64,options=BuildOptions.None});if(report.summary.result!=BuildResult.Succeeded)throw new InvalidOperationException("Capture build failed: "+report.summary.result);}
 }
}
