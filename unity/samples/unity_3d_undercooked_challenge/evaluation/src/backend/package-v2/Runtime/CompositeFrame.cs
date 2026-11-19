using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;
namespace GameCreate.Undercooked.Evaluator.Capture
{
 // General Unity render capture, not kitchen state access. Includes world and every live uGUI canvas.
 // Based on the established separate-overlay path; never uses mesh extents for interaction/collision.
 public static class CompositeFrame
 {
  sealed class CanvasState{public Canvas canvas;public bool enabled;public RenderMode mode;public Camera camera;public float distance;}
  public static Texture2D Capture(int width,int height,out bool restored)
  {
   var main=UnityEngine.Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).SingleOrDefault(c=>c.isActiveAndEnabled);if(!main)throw new InvalidOperationException("One active camera is required for composite capture");
   var states=UnityEngine.Object.FindObjectsByType<Canvas>(FindObjectsInactive.Exclude,FindObjectsSortMode.None).Where(c=>c.isActiveAndEnabled&&c.renderMode!=RenderMode.WorldSpace).Select(c=>new CanvasState{canvas=c,enabled=c.enabled,mode=c.renderMode,camera=c.worldCamera,distance=c.planeDistance}).ToArray();
   var layers=new Dictionary<GameObject,int>();var foreign=new Dictionary<GameObject,int>();var oldTarget=main.targetTexture;var oldAspect=main.aspect;var oldActive=RenderTexture.active;GameObject uiGo=null;Texture2D bottom=null,top=null;restored=false;
   try{
    foreach(var state in states)state.canvas.enabled=false;Canvas.ForceUpdateCanvases();bottom=Render(main,width,height);
    foreach(var state in states)foreach(var t in state.canvas.GetComponentsInChildren<Transform>(true))if(!layers.ContainsKey(t.gameObject)){layers[t.gameObject]=t.gameObject.layer;t.gameObject.layer=31;}
    foreach(var t in UnityEngine.Object.FindObjectsByType<Transform>(FindObjectsInactive.Include,FindObjectsSortMode.None))if(t.gameObject.layer==31&&!layers.ContainsKey(t.gameObject)){foreign[t.gameObject]=31;t.gameObject.layer=0;}
    uiGo=new GameObject("PrivateUiCaptureCamera");var ui=uiGo.AddComponent<Camera>();ui.enabled=false;ui.clearFlags=CameraClearFlags.SolidColor;ui.backgroundColor=Color.clear;ui.cullingMask=unchecked(1<<31);ui.orthographic=true;ui.orthographicSize=5;ui.nearClipPlane=.01f;ui.farClipPlane=100;ui.allowHDR=false;ui.allowMSAA=false;ui.aspect=(float)width/height;ui.transform.position=new Vector3(0,0,-10);
    foreach(var state in states){state.canvas.enabled=true;state.canvas.renderMode=RenderMode.ScreenSpaceCamera;state.canvas.worldCamera=ui;state.canvas.planeDistance=1;}Canvas.ForceUpdateCanvases();top=Render(ui,width,height);
    var a=bottom.GetPixels32();var b=top.GetPixels32();for(var i=0;i<a.Length;i++){var alpha=b[i].a;var inv=255-alpha;a[i]=new Color32((byte)((b[i].r*alpha+a[i].r*inv+127)/255),(byte)((b[i].g*alpha+a[i].g*inv+127)/255),(byte)((b[i].b*alpha+a[i].b*inv+127)/255),255);}var result=new Texture2D(width,height,TextureFormat.RGB24,false);result.SetPixels32(a);result.Apply();if(a.Count(c=>c.r+c.g+c.b>20)<100)throw new InvalidOperationException("Blank composite frame: capture observation unavailable");return result;
   }finally{
    main.targetTexture=oldTarget;main.aspect=oldAspect;RenderTexture.active=oldActive;foreach(var state in states){state.canvas.enabled=state.enabled;state.canvas.renderMode=state.mode;state.canvas.worldCamera=state.camera;state.canvas.planeDistance=state.distance;}foreach(var pair in layers)if(pair.Key)pair.Key.layer=pair.Value;foreach(var pair in foreign)if(pair.Key)pair.Key.layer=pair.Value;Canvas.ForceUpdateCanvases();restored=main.targetTexture==oldTarget&&states.All(s=>s.canvas&&s.canvas.enabled==s.enabled&&s.canvas.renderMode==s.mode&&s.canvas.worldCamera==s.camera)&&layers.All(p=>!p.Key||p.Key.layer==p.Value);if(uiGo)UnityEngine.Object.Destroy(uiGo);if(bottom)UnityEngine.Object.Destroy(bottom);if(top)UnityEngine.Object.Destroy(top);
   }
  }
  static Texture2D Render(Camera camera,int width,int height){var oldTarget=camera.targetTexture;var oldAspect=camera.aspect;var oldActive=RenderTexture.active;var rt=new RenderTexture(width,height,24,RenderTextureFormat.ARGB32){antiAliasing=1};rt.Create();try{camera.targetTexture=rt;camera.aspect=(float)width/height;if(RenderPipelineManager.currentPipeline!=null){var request=new RenderPipeline.StandardRequest{destination=rt};if(!RenderPipeline.SupportsRenderRequest(camera,request))throw new InvalidOperationException("Render pipeline does not support standard capture request");RenderPipeline.SubmitRenderRequest(camera,request);}else camera.Render();RenderTexture.active=rt;var texture=new Texture2D(width,height,TextureFormat.RGBA32,false);texture.ReadPixels(new Rect(0,0,width,height),0,0);texture.Apply();return texture;}finally{camera.targetTexture=oldTarget;camera.aspect=oldAspect;RenderTexture.active=oldActive;rt.Release();UnityEngine.Object.Destroy(rt);}}
 }
}
