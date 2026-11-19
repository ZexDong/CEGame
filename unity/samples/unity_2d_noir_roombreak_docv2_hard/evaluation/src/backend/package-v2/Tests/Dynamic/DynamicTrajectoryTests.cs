using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using GameCreate.Benchmark.NoirRoombreak;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.NoirRoombreak.Evaluator
{
 public sealed partial class DynamicTrajectoryTests
 {
  const string ScenePath="Assets/NoirChallenge/Scenes/NoirRoombreak.unity";
  sealed class Spec{public string d;public float w;public string[] r;public Spec(string d,float w,params string[] r){this.d=d;this.w=w;this.r=r;}}
  sealed class DeathObservation
  {
   public bool threatSeen,contactSeen,deadSeen,deadBeforeRespawn,respawnSeen,deathFeedback,respawnFeedback;
   public float contactToDeath=float.PositiveInfinity;
   public string observed="";
  }
  static readonly Dictionary<string,Spec> S=new Dictionary<string,Spec>();
  static DynamicTrajectoryTests()
  {
   Add("D2",0,new[]{"D2_MENU:1.5:FLOW-01","D2_FIVE_ROOMS:2:WORLD-01,SESSION-01","D2_MOVE_JUMP:1.5:MOVE-01","D2_BACKSTAB:1.75:COMBAT-01","D2_DASH:1.75:DASH-01","D2_ANDA:1.75:ANDA-01","D2_OBSER:1.75:OBSER-01","D2_LETHAL_DAMAGE:1.5:DAMAGE-01","D2_SOFT_RESPAWN:1.5:RESPAWN-01","D2_GLOBAL_RESPAWN:1.5:RESPAWN-01","D2_ROOM_CAMERA:1.5:CAMERA-01","D2_PAUSE:1.5:PAUSE-01","D2_SUCCESS:1.75:SUCCESS-01","D2_UI_STATES:1.5:UI-01","D2_AV_ASSEMBLY:1.75:AV-01","D2_MIXED_ENCOUNTER:2:MIXED-01","D2_TIMED_PAUSE:1.5:PAUSE-TIME-01","D2_INPUT_EDGE_MODEL:2:INPUT-EDGE-01"});
   Add("D3",0,new[]{"D3_INITIAL_STATE:.75:FLOW-01","D3_MOVE_COLLISION:.75:MOVE-01","D3_BACKSTAB_BOUNDARY:.75:COMBAT-01","D3_BACKSTAB_CHARGE:.75:COMBAT-01,DASH-01","D3_DASH_COST:.75:DASH-01","D3_ZERO_DASH_REJECT:.75:DASH-01","D3_DASH_INVULNERABILITY:.75:DASH-01,DAMAGE-01","D3_ANDA_TRANSITIONS:.75:ANDA-01","D3_OBSER_WARNING_ORDER:.75:OBSER-01","D3_ONE_HIT_DEATH:.75:DAMAGE-01","D3_SOFT_RESPAWN_RULES:.75:RESPAWN-01","D3_GLOBAL_RESPAWN_RULES:.75:RESPAWN-01","D3_CAMERA_BOUNDARY:.75:CAMERA-01","D3_PAUSE_FREEZE:.75:PAUSE-01","D3_SUCCESS_CONDITION:.75:SUCCESS-01","D3_RESTART_CLEAN:.75:RESTART-01","D3_MIXED_CONCURRENT_THREATS:1:MIXED-01","D3_MIXED_EXIT_LOCK:1:MIXED-01,SUCCESS-01","D3_MIXED_CROSS_THREAT_WINDOW:1:MIXED-01,ANDA-01,OBSER-01","D3_PAUSE_UNSCALED_FREEZE:1:PAUSE-TIME-01","D3_PAUSE_NO_BUFFER:1:PAUSE-TIME-01,INPUT-EDGE-01","D3_ONE_PRESS_ONE_INTENT:1:INPUT-EDGE-01","D3_REJECTED_ACTION_SIDE_EFFECT_FREE:1:INPUT-EDGE-01","D3_INPUT_REUSABLE_AFTER_RESTARTS:1:INPUT-EDGE-01,DASH-01,MOVE-01"});
   Add("D4",0,new[]{"D4_START:1.5:FLOW-01","D4_ROOM_PROGRESSION:2.5:WORLD-01,CAMERA-01","D4_COMPLETE_JOURNEY:3:FLOW-01,WORLD-01,COMBAT-01,DASH-01,SUCCESS-01","D4_DEATH_RECOVERY:2:DAMAGE-01,RESPAWN-01","D4_PAUSE_RESUME:1:PAUSE-01","D4_RESTART_ACTIVE:1:RESTART-01","D4_RESTART_PAUSED_SUCCESS:1:RESTART-01,PAUSE-01,SUCCESS-01","D4_MIXED_SUCCESS_FLOW:2.5:MIXED-01,SUCCESS-01","D4_TIMED_THREAT_PAUSE_RESUME:1:PAUSE-TIME-01,PAUSE-01","D4_INPUT_LIFECYCLE_STABILITY:1.5:INPUT-EDGE-01,FLOW-01,PAUSE-01,SUCCESS-01"});
   Add("D5",0,new[]{"D5_MENU_CONTROLS:.75:FLOW-01,UI-01","D5_HUD:1.25:UI-01,DASH-01,RESPAWN-01","D5_MOVEMENT_COMBAT:.75:MOVE-01,COMBAT-01","D5_DASH_FEEDBACK:.75:DASH-01","D5_ENEMY_WARNINGS:1:ANDA-01,OBSER-01","D5_DEATH_RESPAWN:1:DAMAGE-01,RESPAWN-01","D5_PAUSE_SUCCESS:.75:PAUSE-01,SUCCESS-01,RESTART-01","D5_AUDIO_VISUAL_FEEDBACK:1.25:AV-01,UI-01","D5_MIXED_THREAT_FEEDBACK:1:MIXED-01,UI-01","D5_INPUT_REJECTION_FEEDBACK:.75:INPUT-EDGE-01,UI-01","D5_DASHBOARD_VISIBLE_AGREEMENT:.75:UI-01"});
  }
  static void Add(string d,float defaultWeight,string[] rows){foreach(var row in rows){var p=row.Split(':');var w=defaultWeight;var reqIndex=1;if(p.Length>2&&float.TryParse(p[1],System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out var explicitWeight)){w=explicitWeight;reqIndex=2;}S[p[0]]=new Spec(d,w,p[reqIndex].Split(','));}}

 }
}
