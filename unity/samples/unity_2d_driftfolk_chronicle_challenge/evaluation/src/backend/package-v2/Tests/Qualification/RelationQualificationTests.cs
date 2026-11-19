using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GameCreate.Session;
using GameCreate.Stormbound.Contract;
using Newtonsoft.Json.Linq;
using NUnit.Framework;
using UnityEngine;

namespace GameCreate.Stormbound.Evaluator.Qualification
{
    [Serializable] public sealed class RelationFact
    {
        public string label,expected,error,before_json,after_json;
        public bool request_unchanged;
    }
    [Serializable] public sealed class RelationReceipt
    {
        public string test_id,diagnostic_nunit_status;
        public int process_id;
        public List<RelationFact> observations=new List<RelationFact>();
    }

    // These are author-only data fixtures, not a game implementation. They use
    // the published model to build complete saves and test the independent
    // public relation validator without importing a reference game's code.
    public sealed class RelationQualificationTests
    {
        JObject document;
        RelationReceipt receipt;
        [SetUp] public void Setup()
        {
            document=JObject.Parse(Resources.Load<TextAsset>("session-model").text);
            receipt=new RelationReceipt{test_id=TestContext.CurrentContext.Test.Name,process_id=System.Diagnostics.Process.GetCurrentProcess().Id};
        }
        [TearDown] public void Evidence()
        {
            var output=Environment.GetEnvironmentVariable("STORMBOUND_QUALIFICATION_OUTPUT");
            if(string.IsNullOrWhiteSpace(output))throw new InvalidOperationException("Explicit qualification evidence directory required.");
            Directory.CreateDirectory(output);receipt.diagnostic_nunit_status=TestContext.CurrentContext.Result.Outcome.Status.ToString();
            var path=Path.Combine(output,receipt.test_id+".json");
            using(var file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read))
            using(var writer=new StreamWriter(file,new System.Text.UTF8Encoding(false)))writer.Write(JsonUtility.ToJson(receipt,true));
        }
        SessionSave Initial(string phase="playing")
        {
            var start=document["rules"]["initial"];
            var save=new SessionSave{contentVersion=(string)document["contentVersion"],entryId="archipelago",phase=phase,
                seed=(int)document["rules"]["seed"],opaqueData="{\"fixture\":\"author-only-not-gameplay\"}"};
            foreach(var rule in document["values"])
            {
                var name=(string)rule["name"];
                double value=start[name]!=null?(double)start[name]:name=="period_seconds"?(double)document["rules"]["period_seconds"]:
                    name=="chronicle_count"?1:name=="next_chronicle_id"?2:0;
                save.values.Add(new NamedNumber{name=name,value=value});
            }
            int ordinal=0;
            foreach(var identity in document["requiredActors"])
            {
                var id=(string)identity["id"];var kind=(string)identity["kind"];
                var actor=new ActorSave{id=id,kind=kind,entryId="archipelago",present=true,position=new Vector3(++ordinal*.1f,2,-3),facing=1,
                    state=kind=="island"?"settled":kind=="resident"?"alive":kind=="building"?"unbuilt":kind=="boat"?"idle_a":"hull"};
                foreach(var field in document["actorValues"][kind])actor.values.Add(new NamedNumber{name=(string)field["name"],value=0});
                save.actors.Add(actor);
                if(kind=="island")foreach(var resource in new[]{"food","timber","ore"})Set(actor,resource,(double)start[id=="island-a"?"island_a":"island_b"][resource]);
                if(kind=="resident")
                {
                    var index=int.Parse(id.Substring("resident-".Length))-1;
                    Set(actor,"island",(int)start["resident_islands"][index]);Set(actor,"job",(int)start["resident_jobs"][index]);
                    foreach(var name in new[]{"health","fatigue","morale"})Set(actor,name,(double)start[name]);
                }
                if(kind=="building")
                {
                    Set(actor,"island",id.StartsWith("a-")?1:2);
                    Set(actor,"type",id.EndsWith("workshop")?0:id.EndsWith("clinic")?1:2);
                }
            }
            return save;
        }
        static ActorSave Actor(SessionSave save,string id)=>save.actors.Single(actor=>actor.id==id);
        static void Set(SessionSave save,string name,double value)=>save.values.Single(item=>item.name==name).value=value;
        static void Set(ActorSave actor,string name,double value)=>actor.values.Single(item=>item.name==name).value=value;
        void Check(SessionSave save,bool accepted,string label)
        {
            var fact=new RelationFact{label=label,expected=accepted?"accept":"reject",before_json=JsonUtility.ToJson(save)};receipt.observations.Add(fact);
            Assert.DoesNotThrow(()=>fact.error=StormboundStateRules.Validate(save),"Validator must return a diagnostic, not throw: "+label);
            fact.after_json=JsonUtility.ToJson(save);fact.request_unchanged=fact.before_json==fact.after_json;
            Assert.That(fact.request_unchanged,Is.True,"Validation mutated caller state: "+label);
            if(accepted)Assert.That(fact.error,Is.Null,label+": "+fact.error);else Assert.That(fact.error,Is.Not.Null.And.Not.Empty,label);
        }
        void Passenger(SessionSave save,int number)
        {
            var resident=Actor(save,"resident-"+number);resident.state="aboard";Set(resident,"island",0);
            var ferry=Actor(save,"ferry");ferry.state="to_b";Set(ferry,"remaining",2);
            Set(ferry,"passengers",(int)StormboundStateRules.Number(ferry.values,"passengers")|(1<<(number-1)));
        }
        static void Dead(ActorSave resident){resident.state="dead";Set(resident,"health",0);Set(resident,"job",0);Set(resident,"morale",0);}
        static void Built(SessionSave save,string id,int work){var building=Actor(save,id);building.state="built";Set(building,"work",work);}
        static void Beacons(SessionSave save){foreach(var prefix in new[]{"a-","b-"}){Built(save,prefix+"workshop",4);Built(save,prefix+"beacon",5);}}

        [Test] public void R01_InitialPlayingIsLegal(){Check(Initial(),true,"initial playing");}
        [Test] public void R02_InitialMenuIsLegal(){Check(Initial("menu"),true,"initial menu");}
        [Test] public void R03_MenuMayHidePresentationButPlayingActorsMustBePresent(){var s=Initial("menu");foreach(var a in s.actors)a.present=false;Check(s,true,"menu presentation may be hidden or not instantiated");s=Initial();Actor(s,"resident-1").present=false;Check(s,false,"playing still requires present actors");}
        [Test] public void R04_MenuMustHaveInitialTimeAndInventories(){var s=Initial("menu");Set(Actor(s,"island-a"),"food",29);Check(s,false,"dirty menu stock");s=Initial("menu");Set(s,"paused",1);Check(s,false,"dirty menu pause");}
        [Test] public void R05_EquivalentOrderingAndWorldLayoutAreLegal(){var s=Initial();s.values.Reverse();s.actors.Reverse();foreach(var a in s.actors){a.values.Reverse();a.position+=new Vector3(-500,20,77);a.facing=-1;}Check(s,true,"equivalent list order and arbitrary legal coordinates");}
        [Test] public void R06_TransitCargoAtCapacityIsLegal(){var s=Initial();var f=Actor(s,"ferry");f.state="to_b";Set(f,"remaining",1);Set(f,"food",4);Set(f,"timber",4);Set(f,"ore",4);Check(s,true,"exact cargo capacity");}
        [Test] public void R07_TransitCargoAboveCapacityIsRejected(){var s=Initial();var f=Actor(s,"ferry");f.state="to_b";Set(f,"remaining",1);Set(f,"food",7);Set(f,"timber",6);Check(s,false,"aggregate cargo overflow");}
        [Test] public void R08_TwoExclusivePassengersAreLegal(){var s=Initial();Passenger(s,1);Passenger(s,2);Check(s,true,"two passengers");}
        [Test] public void R09_ThirdPassengerIsRejected(){var s=Initial();Passenger(s,1);Passenger(s,2);Passenger(s,3);Check(s,false,"third passenger");}
        [Test] public void R10_AboardResidentMustHaveItsPassengerBit(){var s=Initial();Passenger(s,1);Set(Actor(s,"ferry"),"passengers",0);Check(s,false,"missing ownership bit");}
        [Test] public void R11_LandResidentCannotAlsoBePassenger(){var s=Initial();var f=Actor(s,"ferry");f.state="to_b";Set(f,"remaining",2);Set(f,"passengers",1);Check(s,false,"land and ferry duplicate ownership");}
        [Test] public void R12_DockedFerryCannotRetainCargo(){var s=Initial();Set(Actor(s,"ferry"),"food",1);Check(s,false,"unloaded cargo on docked vessel");}
        [Test] public void R13_TransitNeedsPositiveRemainingTime(){var s=Initial();Actor(s,"ferry").state="to_b";Check(s,false,"transit without remaining period");}
        [Test] public void R14_DraftMayExceedAvailableStock(){var s=Initial();Set(Actor(s,"island-a"),"ore",0);Set(s,"manifest_ore",12);Check(s,true,"unaffordable draft is a legal situation");}
        [Test] public void R15_DraftCannotExceedCargoOrPassengerCapacity(){var s=Initial();Set(s,"manifest_food",7);Set(s,"manifest_ore",6);Check(s,false,"draft cargo capacity");s=Initial();Set(s,"manifest_passengers",7);Check(s,false,"draft passenger capacity");}
        [Test] public void R16_DraftPassengersMustBeAtSelectedIsland(){var s=Initial();Set(s,"manifest_passengers",8);Check(s,false,"draft remote resident");}
        [Test] public void R17_DeadLandResidentRepresentationIsLegal(){var s=Initial();Dead(Actor(s,"resident-1"));Check(s,true,"dead keeps last island");}
        [Test] public void R18_DeadAboardRepresentationWithoutLiveBitIsLegal(){var s=Initial();var a=Actor(s,"resident-1");Dead(a);Set(a,"island",0);Check(s,true,"dead at sea without passenger ownership");}
        [Test] public void R19_DeadResidentCannotWorkOrKeepMorale(){var s=Initial();var a=Actor(s,"resident-1");Dead(a);Set(a,"job",1);Check(s,false,"dead working");Set(a,"job",0);Set(a,"morale",1);Check(s,false,"dead morale");}
        [Test] public void R20_ExtinctWithNoSurvivorsIsLegal(){var s=Initial();foreach(var a in s.actors.Where(a=>a.kind=="resident"))Dead(a);s.phase="extinct";Check(s,true,"legitimate extinction");}
        [Test] public void R21_ExtinctWithSurvivorIsRejected(){var s=Initial();s.phase="extinct";Check(s,false,"premature extinction");}
        [Test] public void R22_PlayingWithNoSurvivorsIsRejected(){var s=Initial();foreach(var a in s.actors.Where(a=>a.kind=="resident"))Dead(a);Check(s,false,"missing terminal phase");}
        [Test] public void R23_ClinicNeedsLocalWorkshop(){var s=Initial();Actor(s,"a-clinic").state="building";Check(s,false,"clinic without workshop");}
        [Test] public void R24_OneIslandCannotHaveTwoUnfinishedBuildings(){var s=Initial();Built(s,"a-workshop",4);Actor(s,"a-clinic").state="building";Actor(s,"a-beacon").state="building";Check(s,false,"one slot per island");}
        [Test] public void R25_IndependentIslandBuildSlotsAreLegal(){var s=Initial();Actor(s,"a-workshop").state="building";Actor(s,"b-workshop").state="building";Check(s,true,"parallel independent slots");}
        [Test] public void R26_BuildingStateProgressAndIdentityMustAgree(){var s=Initial();Set(Actor(s,"a-workshop"),"work",1);Check(s,false,"unbuilt with work");s=Initial();Built(s,"a-workshop",3);Check(s,false,"built without full work");s=Initial();Set(Actor(s,"a-workshop"),"island",2);Check(s,false,"stable building identity");}
        [Test] public void R27_PaidSuspendedDepartureDuringTravelIsLegal(){var s=Initial();Beacons(s);Set(s,"escape_stage",2);Actor(s,"escape-project").state="departure";Set(s,"escape_paid",1);Set(s,"escape_work",1);Passenger(s,1);Check(s,true,"paid/suspended stage while travel prevents work");}
        [Test] public void R28_UnpaidEscapeCannotHaveWorkOrRun(){var s=Initial();Set(s,"escape_work",1);Check(s,false,"unpaid work");s=Initial();Set(s,"escape_active",1);Check(s,false,"unpaid running");}
        [Test] public void R29_UnfinishedEscapeWorkMustStayBelowStageRequirement(){var s=Initial();Beacons(s);Set(s,"escape_paid",1);Set(s,"escape_work",4);Check(s,false,"completed work represented as unfinished stage");}
        [Test] public void R30_StartedEscapeRequiresBothBeacons(){var s=Initial();Set(s,"escape_paid",1);Check(s,false,"escape prerequisites absent");}
        [Test] public void R31_EditedDayMustHaveItsPublishedWeather(){var s=Initial();Set(s,"day",4);Set(s,"weather",2);Check(s,true,"edited storm day");Set(s,"weather",0);Check(s,false,"day-weather mismatch");}
        [Test] public void R32_FractionalTimerAndSpeedMustBeLegal(){var s=Initial();Set(s,"tick_remainder",3.75);Set(s,"speed",16);Check(s,true,"legal partial period");Set(s,"tick_remainder",4);Check(s,false,"full period is not fractional remainder");s=Initial();Set(s,"speed",2);Check(s,false,"unsupported speed");}
        [Test] public void R33_EarlyUnresolvedPendingEventIsLegal(){var s=Initial();s.phase="event";Set(s,"event_pending",2);Check(s,true,"legal edited early pending event");}
        [Test] public void R34_ResolvedEventCannotAlsoBePending(){var s=Initial();s.phase="event";Set(s,"event_pending",1);Set(s,"events_resolved",1);Check(s,false,"already-resolved pending event");}
        [Test] public void R35_EscapeTerminalMustHaveHomeSurvivorsAndNoActiveWork(){var s=Initial();Beacons(s);Set(s,"escape_stage",3);Actor(s,"escape-project").state="complete";foreach(var a in s.actors.Where(a=>a.kind=="resident"))Set(a,"island",1);s.phase="escaped";Check(s,true,"legal escape terminal");Set(Actor(s,"resident-6"),"island",2);Check(s,false,"survivor left behind");}
        [Test] public void R36_NonfiniteAndDuplicateIdentitiesAreRejectedWithoutMutation(){var s=Initial();Set(s,"tick_remainder",double.NaN);Check(s,false,"NaN timer");s=Initial();s.actors[0].position=new Vector3(float.PositiveInfinity,0,0);Check(s,false,"infinite world position");s=Initial();s.actors[1].id=s.actors[0].id;Check(s,false,"duplicate actor ID");}
        [Test] public void R37_ShapeRejectionIsAtomicAndValidatorIsIdempotent(){var s=Initial();Check(s,true,"first validation");Check(s,true,"repeat same data");s.values.Add(new NamedNumber{name="day",value=1});Check(s,false,"duplicate numeric field");s=Initial();s.actors[0].facing=0;Check(s,false,"invalid facing shape");}
    }
}
