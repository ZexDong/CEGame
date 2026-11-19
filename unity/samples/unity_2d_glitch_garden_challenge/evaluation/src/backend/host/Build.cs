using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;
namespace GameCreate.OpenEvaluation
{
    public static class Build
    {
        public static void Player()
        {
            var root=Environment.GetEnvironmentVariable("GAMECREATE_EVAL_OUTPUT");
            var identity=Environment.GetEnvironmentVariable("GAMECREATE_EVAL_IDENTITY");
            if(string.IsNullOrEmpty(root)||string.IsNullOrEmpty(identity))throw new Exception("Missing author-side build binding");
            var scene="Assets/Game/Scenes/Game.unity";
            if(!File.Exists(scene))throw new Exception("CANDIDATE_FINAL_SCENE_ABSENT");
            PlayerSettings.companyName="GameCreateEvaluation";
            PlayerSettings.productName=identity;
            PlayerSettings.defaultScreenWidth=1280;PlayerSettings.defaultScreenHeight=720;
            PlayerSettings.resizableWindow=false;PlayerSettings.fullScreenMode=FullScreenMode.Windowed;
            PlayerSettings.runInBackground=true;
            PlayerSettings.SetScriptingBackend(UnityEditor.Build.NamedBuildTarget.Standalone,ScriptingImplementation.Mono2x);
            var result=BuildPipeline.BuildPlayer(new BuildPlayerOptions{
                scenes=new[]{scene},locationPathName=Path.Combine(root,"Game.exe"),
                target=BuildTarget.StandaloneWindows64,options=BuildOptions.Development});
            File.WriteAllText(Path.Combine(root,"build-result.json"),JsonUtility.ToJson(new Receipt{
                result=result.summary.result.ToString(),errors=result.summary.totalErrors,warnings=result.summary.totalWarnings}));
            if(result.summary.result!=BuildResult.Succeeded)throw new Exception("CANDIDATE_PLAYER_BUILD_FAILED");
            Debug.Log("GAMECREATE_EVALUATION_PLAYER_BUILT");
        }
        [Serializable] class Receipt {public string result;public int errors,warnings;}
    }
}
