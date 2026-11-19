using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEngine;

namespace GameCreate.NoirRoombreak.Evaluator
{
    [Serializable]
    public sealed class CheckEvidence
    {
        public string id;
        public string dimension;
        public float weight;
        public bool passed;
        public string expected;
        public string observed;
        public string requirement_ids;
        public string trajectory;
        public int process_id;
        public int frame;
        public string utc;
    }

    [Serializable]
    public sealed class TrajectoryEvidence
    {
        public string id;
        public string test_name;
        public string session_id;
        public int process_id;
        public int started_frame;
        public int completed_frame;
        public string status;
        public string input_route;
    }

    [Serializable]
    public sealed class ScreenshotEvidence
    {
        public string name;
        public string state;
        public int width;
        public int height;
        public long bytes;
        public string sha256;
        public string status;
        public string runtime_snapshot;
        public int process_id;
        public int frame;
        public string utc;
    }

    [Serializable]
    public sealed class EvidenceDocument
    {
        public int schema_version=3;
        public string phase="dynamic";
        public int process_id;
        public string input_route="Unity Input System virtual Keyboard, press/hold/release across real player-loop frames";
        public List<CheckEvidence> checks=new();
        public List<TrajectoryEvidence> trajectories=new();
        public List<string> screenshots=new();
        public List<ScreenshotEvidence> screenshot_receipts=new();
    }

    public static class EvidenceStore
    {
        static EvidenceDocument document;
        static string currentTrajectory="";
        static string PathValue=>Environment.GetEnvironmentVariable("NOIR_ROOMBREAK_EVIDENCE_FILE");

        public static void Initialize(string phase,string inputRoute=null)
        {
            LoadOrCreate();
            document.phase=phase;
            if(!string.IsNullOrWhiteSpace(inputRoute))document.input_route=inputRoute;
            document.process_id=System.Diagnostics.Process.GetCurrentProcess().Id;
            Save();
        }

        public static void BeginTrajectory(string id,string testName,string sessionId)
        {
            LoadOrCreate();
            currentTrajectory=id;
            document.trajectories.RemoveAll(x=>x.id==id);
            document.trajectories.Add(new TrajectoryEvidence
            {
                id=id,test_name=testName,session_id=sessionId??"",process_id=System.Diagnostics.Process.GetCurrentProcess().Id,
                started_frame=Time.frameCount,completed_frame=0,status="running",input_route=document.input_route
            });
            Save();
        }

        public static void EndTrajectory(string id,string status,string sessionId)
        {
            LoadOrCreate();
            var trajectory=document.trajectories.FirstOrDefault(x=>x.id==id);
            if(trajectory==null)
            {
                trajectory=new TrajectoryEvidence{id=id,test_name=id,started_frame=Time.frameCount,process_id=System.Diagnostics.Process.GetCurrentProcess().Id,input_route=document.input_route};
                document.trajectories.Add(trajectory);
            }
            trajectory.completed_frame=Time.frameCount;
            trajectory.status=status;
            trajectory.session_id=sessionId??trajectory.session_id;
            currentTrajectory="";
            Save();
        }

        public static void Check(string id,string dimension,float weight,bool passed,string expected,string observed,params string[] requirementIds)
        {
            LoadOrCreate();
            document.checks.RemoveAll(x=>x.id==id);
            document.checks.Add(new CheckEvidence
            {
                id=id,dimension=dimension,weight=weight,passed=passed,expected=expected,observed=observed,
                requirement_ids=string.Join(",",requirementIds??Array.Empty<string>()),trajectory=currentTrajectory,
                process_id=System.Diagnostics.Process.GetCurrentProcess().Id,frame=Time.frameCount,utc=DateTime.UtcNow.ToString("o")
            });
            Save();
        }

        public static void Screenshot(string name)
        {
            LoadOrCreate();
            if(!document.screenshots.Contains(name))document.screenshots.Add(name);
            Save();
        }

        public static void Screenshot(string name,string state,int width,int height,long bytes,string sha256,string status,string runtimeSnapshot)
        {
            LoadOrCreate();
            if(string.Equals(status,"captured",StringComparison.OrdinalIgnoreCase))
            {
                if(!document.screenshots.Contains(name))document.screenshots.Add(name);
            }
            else document.screenshots.RemoveAll(x=>x==name);
            document.screenshot_receipts.RemoveAll(x=>x.name==name);
            document.screenshot_receipts.Add(new ScreenshotEvidence
            {
                name=name,state=state??"",width=width,height=height,bytes=bytes,sha256=sha256??"",status=status??"",
                runtime_snapshot=runtimeSnapshot??"",process_id=System.Diagnostics.Process.GetCurrentProcess().Id,
                frame=Time.frameCount,utc=DateTime.UtcNow.ToString("o")
            });
            Save();
        }

        static void LoadOrCreate()
        {
            if(document!=null)return;
            if(!string.IsNullOrWhiteSpace(PathValue)&&File.Exists(PathValue))
            {
                try{document=JsonUtility.FromJson<EvidenceDocument>(File.ReadAllText(PathValue));}catch{document=null;}
            }
            document??=new EvidenceDocument();
            document.checks??=new List<CheckEvidence>();
            document.trajectories??=new List<TrajectoryEvidence>();
            document.screenshots??=new List<string>();
            document.screenshot_receipts??=new List<ScreenshotEvidence>();
        }

        static void Save()
        {
            if(string.IsNullOrWhiteSpace(PathValue))return;
            var parent=Path.GetDirectoryName(PathValue);
            if(!string.IsNullOrWhiteSpace(parent))Directory.CreateDirectory(parent);
            File.WriteAllText(PathValue,JsonUtility.ToJson(document,true));
        }
    }
}


