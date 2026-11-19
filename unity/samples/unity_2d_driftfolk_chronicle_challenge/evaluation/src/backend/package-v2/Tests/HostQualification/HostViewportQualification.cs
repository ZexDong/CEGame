#if UNITY_EDITOR
using System;
using System.Collections;
using System.IO;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
namespace GameCreate.Stormbound.Evaluator.HostQualification
{
 public sealed class HostViewportQualification
 {
  [Serializable]sealed class Fact{public string test_id;public int process_id,before_width,before_height,width,height,restored_width,restored_height;public bool passed,render_configuration_restored;public string restoration_details;}
  [UnityTest]public IEnumerator H01_ActualGameViewSizeAndRestore(){var f=new Fact{test_id="H01_ActualGameViewSizeAndRestore",process_id=System.Diagnostics.Process.GetCurrentProcess().Id,before_width=Screen.width,before_height=Screen.height};try{yield return EditorGameViewResolution.Ensure1280x720();f.width=Screen.width;f.height=Screen.height;Assert.AreEqual(1280,f.width);Assert.AreEqual(720,f.height);}finally{EditorGameViewResolution.Restore();}for(int i=0;i<5;i++)yield return null;f.restored_width=Screen.width;f.restored_height=Screen.height;f.render_configuration_restored=EditorGameViewResolution.LastRestorationVerified;f.restoration_details=EditorGameViewResolution.LastRestorationDetails;f.passed=f.width==1280&&f.height==720&&f.render_configuration_restored;var root=Environment.GetEnvironmentVariable("STORMBOUND_HOST_QUALIFICATION_OUTPUT");if(!string.IsNullOrEmpty(root)){Directory.CreateDirectory(root);File.WriteAllText(Path.Combine(root,f.test_id+".json"),JsonUtility.ToJson(f,true));}Assert.IsTrue(f.passed,"Host must restore the actual selected-size, window geometry and custom-size-list configuration; a previously uninitialized free-aspect Screen cache is not a saved setting");}
 }
}
#endif
