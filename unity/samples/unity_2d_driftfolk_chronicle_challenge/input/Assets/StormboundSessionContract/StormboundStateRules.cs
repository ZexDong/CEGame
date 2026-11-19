using System;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Session;
using Newtonsoft.Json.Linq;
using UnityEngine;
namespace GameCreate.Stormbound.Contract
{
    // Public save-validation aid only. It never creates actors or runs gameplay.
    public static class StormboundStateRules
    {
        static SessionModel model;
        static JObject document;
        public static SessionModel Model { get { Ensure(); return model; } }
        static void Ensure()
        {
            if(model!=null)return;
            var asset=Resources.Load<TextAsset>("session-model");
            if(asset==null)throw new InvalidOperationException("Missing public session-model resource.");
            model=JsonUtility.FromJson<SessionModel>(asset.text);document=JObject.Parse(asset.text);
        }
        public static double Number(IReadOnlyList<NamedNumber> values,string name)
        {
            if(!SessionFormat.TryNumber(values,name,out var value))throw new ArgumentException("Missing number: "+name);
            return value;
        }
        public static string Validate(SessionSave save)
        {
            Ensure();var shape=model.Validate(save);if(shape!=null)return shape;
            Func<string,double> n=k=>Number(save.values,k);
            if(save.seed!=(int)document["rules"]["seed"])return "wrong_seed";
            if(!new[]{1.0,4.0,16.0}.Contains(n("speed")))return "invalid_speed";
            if(n("tick_remainder")>=n("period_seconds"))return "invalid_tick_remainder";
            var required=(JArray)document["requiredActors"];
            if(save.actors.Count!=required.Count)return "wrong_actor_set";
            var actors=save.actors.ToDictionary(x=>x.id,StringComparer.Ordinal);
            foreach(var identity in required)
            {
                var id=(string)identity["id"];var kind=(string)identity["kind"];
                if(!actors.TryGetValue(id,out var actor)||actor.kind!=kind||actor.entryId!="archipelago"||(save.phase!="menu"&&!actor.present))return "required_actor_identity";
                var fields=(JArray)document["actorValues"][kind];
                if(actor.values.Count!=fields.Count)return "wrong_actor_value_set";
                foreach(var rule in fields)
                {
                    if(!SessionFormat.TryNumber(actor.values,(string)rule["name"],out var v))return "missing_actor_value";
                    if(v<(double)rule["minimum"]||v>(double)rule["maximum"]||(bool)rule["integer"]&&v!=Math.Truncate(v))return "actor_value_out_of_range";
                }
            }
            Func<ActorSave,string,double> a=(actor,k)=>Number(actor.values,k);
            var cycle=(JArray)document["rules"]["weather"]["day_cycle"];
            if(n("weather")!=(int)cycle[((int)n("day")-1)%cycle.Count])return "weather_day_mismatch";
            int living=0,aboard=0;bool allHome=true;
            for(int i=1;i<=6;i++)
            {
                var resident=actors["resident-"+i];var health=a(resident,"health");var island=a(resident,"island");
                if(health==0)
                {if(resident.state!="dead"||a(resident,"job")!=0||a(resident,"morale")!=0)return "dead_resident_state";}
                else
                {
                    living++;if(island!=1)allHome=false;
                    if(island==0){if(resident.state!="aboard")return "resident_location_state";aboard|=1<<(i-1);}
                    else if(resident.state!="alive")return "resident_location_state";
                }
            }
            var boat=actors["ferry"];var cargo=a(boat,"food")+a(boat,"timber")+a(boat,"ore");
            if(cargo>12||a(boat,"passengers")!=aboard||Bits(aboard)>2)return "ferry_ownership_or_capacity";
            if(boat.state=="idle_a"||boat.state=="idle_b")
            {if(a(boat,"remaining")!=0||cargo!=0||aboard!=0)return "docked_ferry_payload";}
            else if(a(boat,"remaining")<1)return "transit_time";
            var draft=(int)n("manifest_passengers");
            if(n("manifest_food")+n("manifest_timber")+n("manifest_ore")>12||Bits(draft)>2)return "draft_capacity";
            for(int i=1;i<=6;i++)if((draft&(1<<(i-1)))!=0)
            {var resident=actors["resident-"+i];if(resident.state!="alive"||a(resident,"island")!=n("selected_island"))return "draft_resident_location";}
            var names=new[]{"workshop","clinic","beacon"};var work=new[]{4,3,5};
            for(int island=1;island<=2;island++)
            {
                var prefix=island==1?"a-":"b-";int active=0;
                for(int t=0;t<3;t++)
                {
                    var b=actors[prefix+names[t]];var progress=a(b,"work");
                    if(a(b,"island")!=island||a(b,"type")!=t)return "building_identity";
                    if(b.state=="unbuilt"&&progress!=0||b.state=="building"&&progress>=work[t]||b.state=="built"&&progress!=work[t])return "building_progress_state";
                    if(b.state=="building")active++;
                    if(t>0&&b.state!="unbuilt"&&actors[prefix+"workshop"].state!="built")return "building_prerequisite";
                }
                if(active>1)return "building_slot_conflict";
            }
            var pending=(int)n("event_pending");var resolved=(int)n("events_resolved");
            if((save.phase=="event")!=(pending!=0)||pending>0&&(resolved&(1<<(pending-1)))!=0)return "event_resolution_state";
            var stage=(int)n("escape_stage");var progress2=n("escape_work");var paid=n("escape_paid");var running=n("escape_active");
            if(actors["escape-project"].state!=new[]{"hull","rigging","departure","complete"}[stage])return "escape_actor_state";
            if(stage<3&&progress2>=new[]{4,4,3}[stage]||stage==3&&progress2!=0)return "escape_progress_state";
            if(paid==0&&(progress2!=0||running!=0)||running==1&&paid!=1)return "escape_payment_state";
            if((stage>0||paid==1)&&(actors["a-beacon"].state!="built"||actors["b-beacon"].state!="built"))return "escape_prerequisite";
            if((save.phase=="extinct")!=(living==0))return "extinction_living_boundary";
            if(save.phase=="escaped")
            {if(stage!=3||living==0||!allHome||boat.state!="idle_a")return "escape_terminal_boundary";}
            else if(stage==3)return "completed_escape_phase";
            if(save.phase=="escaped"||save.phase=="extinct")
            {if(pending!=0||running!=0)return "terminal_activity";}
            if(n("next_chronicle_id")<=n("chronicle_count"))return "chronicle_metadata_order";
            if(save.phase=="menu")
            {
                var initial=document["rules"]["initial"];
                foreach(var value in save.values)
                {
                    double expected=initial[value.name]!=null?(double)initial[value.name]:value.name=="period_seconds"?4:value.name=="chronicle_count"?1:value.name=="next_chronicle_id"?2:0;
                    if(value.value!=expected)return "menu_not_initial";
                }
                for(int i=1;i<=6;i++)
                {
                    var resident=actors["resident-"+i];
                    if(resident.state!="alive"||a(resident,"island")!=(int)initial["resident_islands"][i-1]||a(resident,"job")!=(int)initial["resident_jobs"][i-1]||a(resident,"health")!=100||a(resident,"fatigue")!=0||a(resident,"morale")!=70)return "menu_not_initial";
                }
                foreach(var pair in new[]{new[]{"island-a","island_a"},new[]{"island-b","island_b"}})
                    foreach(var resource in new[]{"food","timber","ore"})if(a(actors[pair[0]],resource)!=(double)initial[pair[1]][resource])return "menu_not_initial";
                if(boat.state!="idle_a"||save.actors.Any(x=>x.kind=="building"&&x.state!="unbuilt"))return "menu_not_initial";
            }
            return null;
        }
        static int Bits(int value){int n=0;while(value!=0){n+=value&1;value>>=1;}return n;}
    }
}
