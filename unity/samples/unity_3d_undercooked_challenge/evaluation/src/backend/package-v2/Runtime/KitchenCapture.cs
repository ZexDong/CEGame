using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using GameCreate.Session;
using GameCreate.Kitchen;
using GameCreate.Evaluation.Session;
using UnityEngine;

namespace GameCreate.Undercooked.Evaluator.Capture
{
 [Serializable] public sealed class CaptureReceipt{public int schema_version=1;public bool valid;public string status,classification,error,state="initial_kitchen",method="standalone-world-and-ugui-composite",run_id,screenshot_path,sha256,save_json;public bool render_configuration_restored;public int process_id,width,height;public long bytes;}
 public sealed class KitchenCapture:MonoBehaviour
 {
  CaptureReceipt receipt;
  [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)] static void Init(){if(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("KITCHEN_CAPTURE_PNG")))return;var go=new GameObject("PrivateKitchenFrameCapture");DontDestroyOnLoad(go);go.AddComponent<KitchenCapture>();}
  IEnumerator Start()
  {
   Application.runInBackground=true;receipt=new CaptureReceipt{run_id=Environment.GetEnvironmentVariable("KITCHEN_RUN_ID"),process_id=Process.GetCurrentProcess().Id,screenshot_path=Environment.GetEnvironmentVariable("KITCHEN_CAPTURE_PNG")};
   var stack=new Stack<IEnumerator>();stack.Push(Capture());Exception error=null;
   while(stack.Count>0){object current=null;bool moved=false;try{moved=stack.Peek().MoveNext();if(moved)current=stack.Peek().Current;}catch(Exception ex){error=ex;break;}if(!moved){stack.Pop();continue;}if(current is IEnumerator nested){stack.Push(nested);continue;}yield return current;}
   if(error!=null){receipt.valid=false;receipt.status="failed";receipt.classification=error is SessionProductFailure?"candidate_state_unavailable":"infrastructure_or_execution_failure";receipt.error=error.ToString();}
   var path=Environment.GetEnvironmentVariable("KITCHEN_CAPTURE_RECEIPT");Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,JsonUtility.ToJson(receipt,true));Application.Quit(error==null||error is SessionProductFailure?0:3);
  }
  IEnumerator Capture()
  {
   yield return null;yield return null;var game=SessionDriver.Find();var model=Resources.Load<TextAsset>("session-model");if(!model)throw new InvalidOperationException("Protected session model is missing");var driver=new SessionDriver(game,JsonUtility.FromJson<SessionModel>(model.text),true,s=>KitchenSessionRules.Validate(s,game.DescribeCurrentEntry()));yield return driver.Open("kitchen",173);driver.BeginActions();
   var end=Time.realtimeSinceStartup+1;while(Time.realtimeSinceStartup<end)yield return null;var save=game.Capture();if(save.phase!="playing")throw new SessionProductFailure("entry:kitchen","Declared fresh active kitchen state unavailable");receipt.save_json=JsonUtility.ToJson(save);
   var png=receipt.screenshot_path;Directory.CreateDirectory(Path.GetDirectoryName(png));if(File.Exists(png))throw new InvalidOperationException("D6 output already exists");yield return new WaitForEndOfFrame();var texture=CompositeFrame.Capture(1280,720,out var restored);receipt.render_configuration_restored=restored;if(!restored)throw new InvalidOperationException("Capture failed to restore camera/canvas/layer settings");File.WriteAllBytes(png,texture.EncodeToPNG());UnityEngine.Object.Destroy(texture);end=Time.realtimeSinceStartup+15;while(!File.Exists(png)&&Time.realtimeSinceStartup<end)yield return null;yield return null;
   if(!File.Exists(png))throw new InvalidOperationException("ScreenCapture did not write a fresh frame");var bytes=File.ReadAllBytes(png);if(bytes.Length<24)throw new InvalidOperationException("Truncated screenshot");receipt.width=(bytes[16]<<24)|(bytes[17]<<16)|(bytes[18]<<8)|bytes[19];receipt.height=(bytes[20]<<24)|(bytes[21]<<16)|(bytes[22]<<8)|bytes[23];if(receipt.width!=1280||receipt.height!=720)throw new InvalidOperationException("Unexpected screenshot dimensions");receipt.bytes=bytes.LongLength;using(var hash=SHA256.Create())receipt.sha256=BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();receipt.valid=true;receipt.status="captured";receipt.classification="observed";
  }
 }
}
