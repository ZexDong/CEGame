using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Benchmark.NoirRoombreak;
using GameCreate.Session;
using GameCreate.Evaluation.Session;
using UnityEngine;

namespace GameCreate.NoirRoombreak.StateAccess
{
    // The only writable game boundary is the published session service. There
    // are no candidate type names, private fields, or implementation profiles.
    public sealed class NoirStateAccess : IDisposable
    {
        readonly IGameSession game;
        readonly SessionModel model;
        SessionDriver driver;
        SessionSave prepared;
        bool sealedState;
        int requestedRoom,requestedBonds,requestedCharges;
        readonly List<GameObject> stimuli=new List<GameObject>();
        readonly List<string> writes=new List<string>();
        bool requestedOcclusion;string occludedEnemy;
        public INoirRoombreakProbe Probe {get;}
        public string Profile=>"public-game-session/v1";
        public string SetupId=>driver==null?"natural-entry":"room-"+(requestedRoom+1);
        public int LateWrites {get;private set;}
        public IReadOnlyList<string> SetupWrites=>writes;
        public static NoirStateAccess Find()
        {
            var components=UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,FindObjectsSortMode.None);
            var ports=components.OfType<IGameSession>().ToArray();
            if(ports.Length>1)throw new SessionProductFailure("session-interface","Multiple active session providers.");
            var probe=components.OfType<INoirRoombreakProbe>().FirstOrDefault();
            return ports.Length==0&&probe==null?null:new NoirStateAccess(ports.FirstOrDefault(),probe);
        }
        NoirStateAccess(IGameSession port,INoirRoombreakProbe probe)
        {
            game=port;Probe=probe;
            var asset=Resources.Load<TextAsset>("session-model");
            if(asset==null)throw new SessionProductFailure("session-interface","Published session model is missing.");
            model=JsonUtility.FromJson<SessionModel>(asset.text);
        }
        SessionSave Live()
        {
            if(game==null)throw new SessionProductFailure("session-interface","Required public session service is missing.");
            try{var save=game.Capture();var error=model.Validate(save);if(error!=null)throw new SessionProductFailure("capture",error);return save;}
            catch(SessionProductFailure){throw;}catch(Exception ex){throw new SessionProductFailure("capture",ex.ToString());}
        }
        SessionSave State=>prepared!=null&&!sealedState?prepared:Live();
        static double Number(SessionSave save,string name)=>save.values.Single(x=>x.name==name).value;
        void SetNumber(string name,double value){RequireSetup();prepared.values.Single(x=>x.name==name).value=value;}
        ActorSave Actor(string id)=>State.actors.SingleOrDefault(x=>x.id==id);
        ActorSave PlayerState=>State.actors.SingleOrDefault(x=>x.kind=="player")??throw new SessionProductFailure("player","Player identity is absent.");
        GameObject Resolve(string id)
        {
            if(game==null)return null;
            try{return game.ResolveActor(id);}catch(Exception ex){throw new SessionProductFailure("actor:"+id,ex.ToString());}
        }
        public int Room=>Probe!=null?Probe.CurrentRoomIndex:(int)Number(Live(),"room_index");
        public int Bonds=>Probe!=null?Probe.Bonds:(int)Number(Live(),"bonds");
        public int Charges=>Probe!=null?Probe.DashCharges:(int)Number(Live(),"dash_charges");
        public int Soft=>Probe!=null?Probe.SoftRespawnCount:(int)Number(Live(),"soft_respawn_count");
        public int Global=>Probe!=null?Probe.GlobalRespawnCount:(int)Number(Live(),"global_respawn_count");
        public int Defeated=>Probe!=null?Probe.DefeatedEnemyCount:(int)Number(Live(),"defeated_enemy_count");
        public int Sequence=>Probe?.StateSequence??0;
        public NoirRespawnKind LastRespawn=>Probe!=null?Probe.LastRespawnKind:(NoirRespawnKind)(int)Number(Live(),"last_respawn_kind");
        public bool Alive=>Probe!=null?Probe.PlayerAlive:Number(Live(),"player_alive")!=0;
        public bool Grounded=>Probe!=null?Probe.PlayerGrounded:Number(Live(),"player_grounded")!=0;
        public bool Dashing=>Probe!=null?Probe.PlayerDashing:Number(Live(),"player_dashing")!=0;
        public bool Invulnerable=>Probe!=null?Probe.PlayerInvulnerable:Number(Live(),"player_invulnerable")!=0;
        public NoirScreen Phase=>Probe!=null?Probe.CurrentScreen:PhaseOf(Live().phase);
        static NoirScreen PhaseOf(string phase)=>phase=="menu"?NoirScreen.Menu:phase=="paused"?NoirScreen.Paused:phase=="won"?NoirScreen.Success:NoirScreen.Playing;
        public Transform Player=>game==null?null:Resolve(PlayerState.id)?.transform;
        public SpriteRenderer PlayerRenderer=>Player==null?null:Player.GetComponentsInChildren<SpriteRenderer>(true).FirstOrDefault(x=>x.sprite!=null);
        public Vector3 Position=>Player==null?Vector3.zero:Player.position;
        public float BackstabReach=>(float)Number(State,"backstab_reach");
        public float ContactReach=>(float)Number(State,"anda_contact_reach");
        public float Unit=>BackstabReach/1.6f;
        EntryDescription Layout=>game.DescribeCurrentEntry();
        Vector3 Landmark(string name)=>Layout.landmarks.Single(x=>x.name==name&&x.present).position;
        public float FloorY=>Landmark("entry").y;
        public float ExitX=>Landmark("exit").x;
        public float TestX(float x)=>Landmark("arena_center").x+x*Unit;
        public float CameraTrackingX=>Landmark("arena_center").x;
        public float SightX(Enemy enemy){
            var reach=(float)Number(State,enemy.Kind==NoirEnemyKind.Anda?"anda_detection_reach":"obser_detection_reach");
            // Renderer bounds include transparent sprite padding. Use published
            // gameplay distances to reserve space, independently of artwork extents.
            var x=Actor(enemy.id).position.x;var margin=Mathf.Max(Unit,ContactReach);
            var available=Mathf.Min(Layout.worldBounds.max.x,ExitX)-x-margin;
            var distance=Mathf.Min(reach*.6f,BackstabReach*2.5f,available);
            if(distance<=0)throw new InvalidOperationException("No in-bounds sensing pose at the declared arena.");
            return x+distance;
        }
        SpriteRenderer Bench=>State.actors.Where(x=>x.kind=="bench"&&x.present).Select(x=>Resolve(x.id)).Where(x=>x!=null).SelectMany(x=>x.GetComponentsInChildren<SpriteRenderer>()).FirstOrDefault(x=>x.enabled&&x.sprite!=null);
        public bool HasBench=>Room==2&&Bench!=null;
        public bool AtGlobalRecoveryPoint=>Room==2&&Bench!=null&&Mathf.Abs(Position.x-Bench.bounds.center.x)<=Bench.bounds.extents.x+(PlayerRenderer?.bounds.extents.x??0)+.15f*Unit;
        public string Counters=>$"room={Room};bonds={Bonds};charges={Charges};defeated={Defeated};soft={Soft};global={Global};alive={Alive};phase={Phase}";
        // A fresh-menu observation is diagnostic, not a prerequisite for the
        // separately declared OpenEntry capability. Do not repair the capture or
        // relax gameplay validation: an unavailable baseline cannot pass Clean().
        public bool TryMenuWorldSignature(out string signature,out string failure)
        {
            signature=null;failure=null;
            try
            {
                var snapshot=Live();
                if(snapshot.phase!="menu"||Number(snapshot,"room_index")!=-1)
                    throw new SessionProductFailure("menu-capture","Initial capture does not report the clean menu phase and room.");
                signature=WorldSignature();return true;
            }
            catch(SessionProductFailure ex){failure=ex.Capability+": "+ex.Message;return false;}
        }
        public string WorldSignature()
        {
            var actors=new HashSet<Transform>(AllEnemies().SelectMany(x=>x.View==null?Array.Empty<Transform>():x.View.GetComponentsInChildren<Transform>(true)));
            // A malformed menu capture is scored by its contract checks; it must
            // not prevent a separate chapter request from reaching valid gameplay.
            var snapshot=State;var playerRecord=snapshot.actors.SingleOrDefault(x=>x.kind=="player");
            if(playerRecord==null&&snapshot.phase!="menu")throw new SessionProductFailure("player","Player identity is absent.");
            var playerRoot=playerRecord==null?null:Resolve(playerRecord.id);
            if(playerRoot!=null)foreach(var t in playerRoot.GetComponentsInChildren<Transform>(true))actors.Add(t);
            return string.Join("|",UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude,FindObjectsSortMode.None)
                .Where(x=>x.enabled&&x.sprite!=null&&!actors.Contains(x.transform)&&x.gameObject.hideFlags==HideFlags.None)
                .Select(x=>$"{x.bounds.center:F2}:{x.bounds.size:F2}:{x.color:F3}").OrderBy(x=>x,StringComparer.Ordinal))
                +"|enemies="+string.Join(",",CurrentEnemies().Where(x=>x.Alive).Select(x=>x.Kind.ToString()).OrderBy(x=>x));
        }
        public int ActivePlayerViews=>Player==null?0:Player.GetComponentsInChildren<SpriteRenderer>().Count(x=>x.enabled&&x.sprite!=null);
        public sealed class Enemy
        {
            internal NoirStateAccess access;internal string id;
            ActorSave Data=>access.Actor(id)??throw new SessionProductFailure("capture","A stable enemy identity disappeared from the save.");
            public Transform View=>access.Resolve(id)?.transform;
            public SpriteRenderer Renderer=>View==null?null:View.GetComponentsInChildren<SpriteRenderer>(true).FirstOrDefault(x=>x.sprite!=null);
            public int Room=>Array.IndexOf(access.model.entries,Data.entryId);
            public NoirEnemyKind Kind=>Data.kind=="anda"?NoirEnemyKind.Anda:NoirEnemyKind.Obser;
            public bool Alive=>Data.state!="defeated";
            public Vector3 Position=>View==null?Data.position:View.position;
            public NoirEnemyState State=>(NoirEnemyState)Enum.Parse(typeof(NoirEnemyState),Data.state,true);
            public Color Color=>Renderer!=null?Renderer.color:Color.clear;
            public LineRenderer ThreatBeam=>Kind!=NoirEnemyKind.Obser?null:UnityEngine.Object.FindObjectsByType<LineRenderer>(FindObjectsInactive.Exclude,FindObjectsSortMode.None)
                .Where(x=>x.positionCount>=2).OrderBy(x=>Vector3.Distance((x.GetPosition(0)+x.GetPosition(x.positionCount-1))*.5f,Position)).FirstOrDefault();
            public SpriteRenderer ThreatSprite=>Kind!=NoirEnemyKind.Obser?null:UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude,FindObjectsSortMode.None)
                .Where(x=>x.enabled&&x.sprite!=null&&x!=Renderer&&x!=access.PlayerRenderer&&x.bounds.size.x>4*x.bounds.size.y&&x.bounds.size.x>access.BackstabReach&&
                    Mathf.Abs(x.bounds.center.y-Position.y)<.25f*access.Unit&&(x.color.r>x.color.g*1.2f||x.color.g>x.color.b*1.2f))
                .OrderBy(x=>Mathf.Abs(x.bounds.center.x-Position.x)).FirstOrDefault();
        }
        public Enemy[] AllEnemies()=>game==null?Array.Empty<Enemy>():State.actors.Where(x=>x.kind=="anda"||x.kind=="obser").Select(x=>new Enemy{access=this,id=x.id}).ToArray();
        public Enemy[] CurrentEnemies()=>AllEnemies().Where(x=>x.Room==Room).ToArray();
        public Enemy First(NoirEnemyKind kind)=>CurrentEnemies().FirstOrDefault(x=>x.Kind==kind&&x.Alive);
        string Legal(SessionSave save)
        {
            var error=model.Validate(save);if(error!=null)return error;
            var room=Array.IndexOf(model.entries,save.entryId);
            if(Number(save,"room_index")!=(save.phase=="menu"?-1:room))return "room/entry mismatch";
            if(Number(save,"defeated_enemy_count")!=save.actors.Count(x=>(x.kind=="anda"||x.kind=="obser")&&x.state=="defeated"))return "defeated history mismatch";
            var players=save.actors.Where(x=>x.kind=="player").ToArray();if(players.Length!=1)return "one player required";
            var state=Number(save,"player_alive")==0?"dead":Number(save,"player_dashing")!=0?"dashing":Number(save,"player_grounded")!=0?"grounded":"airborne";
            if(players[0].state!=state)return "player flags/state mismatch";
            if(save.actors.Any(x=>x.present&&(x.entryId!=save.entryId||x.state=="defeated")))return "illegal presence";
            if(save.phase=="won"&&(room!=4||save.actors.Any(x=>x.entryId=="room-5"&&(x.kind=="anda"||x.kind=="obser")&&x.state!="defeated")))return "illegal result";
            var bounds=Layout.worldBounds;
            if(save.actors.Where(x=>x.present).Any(x=>x.position.x<bounds.min.x||x.position.x>bounds.max.x||x.position.y<bounds.min.y||x.position.y>bounds.max.y))return "pose outside published world bounds";
            return null;
        }
        public IEnumerator BeginRoom(int room,int bonds=3,int charges=3)
        {
            Dispose();sealedState=false;LateWrites=0;writes.Clear();prepared=null;
            requestedRoom=room;requestedBonds=bonds;requestedCharges=charges;
            driver=new SessionDriver(game,model,true,Legal);yield return driver.Open(model.entries[room]);
            prepared=SessionFormat.Clone(driver.Observe());driver.CheckDetachedCapture();
            SetNumber("bonds",bonds);SetNumber("dash_charges",charges);writes.Add("public chapter entry and legal resource setup");
        }
        void RequireSetup(){if(prepared==null||sealedState){LateWrites++;throw new InvalidOperationException("Preparation is closed.");}}
        public void PlacePlayer(float x,float y,bool airborne=false)
        {
            RequireSetup();var actor=PlayerState;actor.position=new Vector3(x,y,actor.position.z);actor.facing=1;actor.state=airborne?"airborne":"grounded";
            SetNumber("player_grounded",airborne?0:1);SetNumber("player_alive",1);writes.Add("player pose");
        }
        public void PlaceEnemy(Enemy enemy,float x,float y)
        {
            RequireSetup();var actor=prepared.actors.Single(x=>x.id==enemy.id);actor.position=new Vector3(x,y,actor.position.z);actor.facing=1;writes.Add("enemy pose");
        }
        public void ClearEnemyAsPrecondition(Enemy enemy)
        {
            RequireSetup();var actor=prepared.actors.Single(x=>x.id==enemy.id);actor.state="defeated";actor.present=false;
            SetNumber("defeated_enemy_count",prepared.actors.Count(x=>(x.kind=="anda"||x.kind=="obser")&&x.state=="defeated"));writes.Add("completed prerequisite history");
        }
        public bool PrepareChase(Enemy enemy){RequireSetup();prepared.actors.Single(x=>x.id==enemy.id).state="chase";writes.Add("observed chase-state replay");return true;}
        public void OcclusionBetween(Enemy enemy){RequireSetup();requestedOcclusion=true;occludedEnemy=enemy.id;}
        public IEnumerator Seal()
        {
            RequireSetup();yield return driver.Restore(prepared);
            if(requestedOcclusion){
                var p=PlayerState.position;var e=Actor(occludedEnemy).position;
                var obstacle=new GameObject("PrivateTerrainStimulus"){hideFlags=HideFlags.DontSave};stimuli.Add(obstacle);
                obstacle.transform.position=(p+e)*.5f+Vector3.up*.2f*Unit;obstacle.AddComponent<BoxCollider2D>().size=new Vector2(.15f,2)*Unit;
                Physics2D.SyncTransforms();writes.Add("published runtime Collider2D terrain");
            }
            sealedState=true;
            if(Room!=requestedRoom||Bonds!=requestedBonds||Charges!=requestedCharges||!Alive||Phase!=NoirScreen.Playing)
                throw new SessionProductFailure("restore","Public Probe and restored real state disagree.");
            driver.BeginActions();
        }
        public void Dispose(){foreach(var item in stimuli)if(item!=null)UnityEngine.Object.DestroyImmediate(item);stimuli.Clear();requestedOcclusion=false;sealedState=true;}
    }
}
