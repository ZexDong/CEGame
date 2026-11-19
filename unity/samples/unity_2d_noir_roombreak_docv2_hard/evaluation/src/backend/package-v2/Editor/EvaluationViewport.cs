#if UNITY_EDITOR
using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;

namespace GameCreate.NoirRoombreak.Evaluator.Standalone.Editor
{
    [InitializeOnLoad]
    static class EvaluationViewport
    {
        const BindingFlags Any=BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance|BindingFlags.Static|BindingFlags.FlattenHierarchy;
        const string Label="Private Noir evaluation 1280x720";
        static EvaluationViewport()
        {
            if(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("NOIR_ROOMBREAK_EVIDENCE_FILE")))return;
            EditorApplication.delayCall+=Apply;
        }
        static void Apply()
        {
            try
            {
                var assembly=typeof(EditorWindow).Assembly;
                var sizesType=assembly.GetType("UnityEditor.GameViewSizes",true);
                var sizes=sizesType.GetProperty("instance",Any).GetValue(null);
                var groupType=assembly.GetType("UnityEditor.GameViewSizeGroupType",true);
                var group=sizesType.GetMethod("GetGroup",Any).Invoke(sizes,new[]{Enum.Parse(groupType,"Standalone")});
                var groupClass=group.GetType();var count=(int)groupClass.GetMethod("GetBuiltinCount",Any).Invoke(group,null);
                var customCount=(int)groupClass.GetMethod("GetCustomCount",Any).Invoke(group,null);
                var sizeType=assembly.GetType("UnityEditor.GameViewSize",true);var kind=assembly.GetType("UnityEditor.GameViewSizeType",true);
                var size=Activator.CreateInstance(sizeType,Any,null,new object[]{Enum.Parse(kind,"FixedResolution"),1280,720,Label},null);
                var index=count+customCount;groupClass.GetMethod("AddCustomSize",Any).Invoke(group,new[]{size});
                var viewType=assembly.GetType("UnityEditor.GameView",true);var view=EditorWindow.GetWindow(viewType,false,"Game",false);
                var selected=viewType.GetProperty("selectedSizeIndex",Any);var prior=(int)selected.GetValue(view);
                selected.SetValue(view,index);view.Repaint();
                EditorApplication.quitting+=()=>
                {
                    try{if(view!=null)selected.SetValue(view,prior);groupClass.GetMethod("RemoveCustomSize",Any).Invoke(group,new object[]{customCount});}catch{}
                };
            }
            catch(Exception error){Debug.LogError("EVALUATOR_VIEWPORT_SETUP_FAILED: "+error);}
        }
    }
}
#endif
