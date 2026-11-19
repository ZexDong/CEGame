using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GameCreate.Session;
using GameCreate.Evaluation.Session;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace GameCreate.Stormbound.Evaluator.Qualification
{
    [Serializable] public sealed class ScopedReceipt
    {
        public string test_id,diagnostic_nunit_status;
        public int process_id;
        public List<string> observations=new List<string>();
        public List<SessionReceipt> service_receipts=new List<SessionReceipt>();
    }
    public sealed class ScopedObservationTests
    {
        ScopedReceipt receipt;
        [SetUp] public void Setup(){receipt=new ScopedReceipt{test_id=TestContext.CurrentContext.Test.Name,process_id=System.Diagnostics.Process.GetCurrentProcess().Id};}
        [TearDown] public void Evidence()
        {
            var root=Environment.GetEnvironmentVariable("STORMBOUND_QUALIFICATION_OUTPUT");
            if(string.IsNullOrWhiteSpace(root))throw new InvalidOperationException("Explicit scoped qualification output required.");
            Directory.CreateDirectory(root);receipt.diagnostic_nunit_status=TestContext.CurrentContext.Result.Outcome.Status.ToString();
            using(var stream=new FileStream(Path.Combine(root,receipt.test_id+".json"),FileMode.CreateNew,FileAccess.Write,FileShare.Read))
            using(var writer=new StreamWriter(stream,new System.Text.UTF8Encoding(false)))writer.Write(JsonUtility.ToJson(receipt,true));
        }
        static SessionModel Definition()=>new SessionModel{contentVersion="scoped-fixture",entries=new[]{"entry"},phases=new[]{"playing"},
            operationTimeoutSeconds=1,requiredLandmarks=new[]{"near","far"},values=new[]{new NumberRule{name="energy",minimum=0,maximum=3,integer=true,editable=true}},
            actorKinds=new[]{new ActorRule{kind="unit",states=new[]{"idle"},poseEditable=true,stateEditable=true}}};
        static string PublicRules(SessionSave save)
        {
            var shape=Definition().Validate(save);if(shape!=null)return shape;
            if(save.actors.Count!=2||!save.actors.Any(a=>a.id=="needed")||!save.actors.Any(a=>a.id=="unrelated"))return "required_fixture_identities";
            foreach(var actor in save.actors)if(!SessionFormat.TryNumber(actor.values,"load",out var load)||load<0)return "invalid_complete_relation";
            return null;
        }
        sealed class Product:IGameSession,IDisposable
        {
            readonly Dictionary<string,GameObject> roots=new Dictionary<string,GameObject>();
            SessionSave save;
            public bool brokenNeeded,brokenUnrelated,missingFar,throwLayout,badShape,badRelation,advanceUnrelated,aliasObjects;
            public int layoutQueries,restoreCalls;
            public readonly List<string> actorQueries=new List<string>();
            public Product(){roots["needed"]=new GameObject("fixture meaningful scene A");roots["unrelated"]=new GameObject("independently named scene B");OpenEntry("entry",0);}
            public string ContractVersion=>"game-session/v1";
            public IReadOnlyList<string> EntryIds=>new[]{"entry"};
            public void ResumeSimulation(){}
            public SessionOperation OpenEntry(string entry,int seed)
            {
                save=new SessionSave{contentVersion="scoped-fixture",entryId=entry,phase="playing",seed=seed,
                    values=new List<NamedNumber>{new NamedNumber{name="energy",value=2}}};
                foreach(var pair in roots){var position=pair.Key=="needed"?Vector3.zero:Vector3.one;pair.Value.transform.position=position;
                    save.actors.Add(new ActorSave{id=pair.Key,kind="unit",entryId=entry,state="idle",present=true,position=position,
                        values=new List<NamedNumber>{new NamedNumber{name="load",value=0}}});}
                return new SessionOperation{state=OperationState.Completed};
            }
            public SessionSave Capture()
            {
                if(advanceUnrelated)save.actors.Single(a=>a.id=="unrelated").position+=Vector3.right;
                var copy=SessionFormat.Clone(save);var unrelated=copy.actors.Single(a=>a.id=="unrelated");
                if(badShape)unrelated.kind="undeclared-kind";
                if(badRelation)unrelated.values[0].value=-1;
                return copy;
            }
            public SessionOperation Restore(SessionSave value)
            {
                restoreCalls++;if(PublicRules(value)!=null)return new SessionOperation{state=OperationState.Rejected};
                save=SessionFormat.Clone(value);foreach(var actor in save.actors)roots[actor.id].transform.position=actor.position;
                return new SessionOperation{state=OperationState.Completed};
            }
            public GameObject ResolveActor(string id)
            {
                actorQueries.Add(id);
                if(id=="needed"&&brokenNeeded||id=="unrelated"&&brokenUnrelated)throw new InvalidOperationException("Synthetic failed actor query: "+id);
                return aliasObjects&&id=="unrelated"?roots["needed"]:roots[id];
            }
            public EntryDescription DescribeCurrentEntry()
            {
                layoutQueries++;if(throwLayout)throw new InvalidOperationException("Synthetic unrelated entry query failure");
                var result=new EntryDescription{id="entry",worldBounds=new Bounds(Vector3.zero,new Vector3(10,10,0)),
                    landmarks=new List<Landmark>{new Landmark{name="near",present=true,position=Vector3.zero}}};
                if(!missingFar)result.landmarks.Add(new Landmark{name="far",present=true,position=Vector3.one});return result;
            }
            public void Dispose(){foreach(var root in roots.Values)UnityEngine.Object.DestroyImmediate(root);}
        }
        static IEnumerator Catch(IEnumerator body,Action<Exception> fail)
        {
            var stack=new Stack<IEnumerator>();stack.Push(body);
            while(stack.Count>0){bool moved=false;object current=null;Exception error=null;
                try{moved=stack.Peek().MoveNext();if(moved)current=stack.Peek().Current;}catch(Exception caught){error=caught;}
                if(error!=null){fail(error);yield break;}if(!moved){stack.Pop();continue;}
                if(current is IEnumerator child)stack.Push(child);else yield return current;}
        }
        void Record(Product product,SessionDriver driver,Exception error=null)
        {
            receipt.observations.Add("actor_queries="+string.Join(",",product.actorQueries)+";layout_queries="+product.layoutQueries+";restore_calls="+product.restoreCalls+";error="+error);
            if(driver.LastReceipt!=null)receipt.service_receipts.Add(driver.LastReceipt);
        }

        [UnityTest] public IEnumerator S01_UnrelatedActorFailureDoesNotBlockSelectedActor()
        {using(var game=new Product{brokenUnrelated=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>a.id=="needed");yield return driver.Open("entry");Record(game,driver);Assert.That(driver.LastReceipt.status,Is.EqualTo("READY"));Assert.That(game.actorQueries.All(id=>id=="needed"),Is.True);}}
        [UnityTest] public IEnumerator S02_SelectedActorFailureMustReject()
        {using(var game=new Product{brokenNeeded=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>a.id=="needed");Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());Assert.That(((SessionProductFailure)error).Capability,Is.EqualTo("actor:needed"));}}
        [UnityTest] public IEnumerator S03_DefaultStillQueriesAllActors()
        {using(var game=new Product{brokenUnrelated=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules);Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());Assert.That(game.actorQueries,Does.Contain("unrelated"));}}
        [UnityTest] public IEnumerator S04_UnselectedMissingLandmarkDoesNotBlockSelectedLandmark()
        {using(var game=new Product{missingFar=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,null,name=>name=="near");yield return driver.Open("entry");Record(game,driver);Assert.That(driver.LastReceipt.status,Is.EqualTo("READY"));}}
        [UnityTest] public IEnumerator S05_SelectedMissingLandmarkMustReject()
        {using(var game=new Product{missingFar=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,null,name=>name=="far");Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());Assert.That(((SessionProductFailure)error).Capability,Is.EqualTo("layout:entry"));}}
        [UnityTest] public IEnumerator S06_DefaultStillRequiresAllLandmarks()
        {using(var game=new Product{missingFar=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules);Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());}}
        [UnityTest] public IEnumerator S07_EmptyLandmarkScopeDoesNotCallUnrelatedLayoutService()
        {using(var game=new Product{throwLayout=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>a.id=="needed",name=>false);yield return driver.Open("entry");Record(game,driver);Assert.That(driver.LastReceipt.status,Is.EqualTo("READY"));Assert.That(game.layoutQueries,Is.Zero);}}
        [UnityTest] public IEnumerator S08_UnselectedSerializedShapeMustStillBeLegal()
        {using(var game=new Product{badShape=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>a.id=="needed",name=>false);Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());Assert.That(((SessionProductFailure)error).Capability,Is.EqualTo("capture"));}}
        [UnityTest] public IEnumerator S09_UnselectedPublicRelationMustStillBeLegal()
        {using(var game=new Product{badRelation=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>a.id=="needed",name=>false);Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());Assert.That(((SessionProductFailure)error).Capability,Is.EqualTo("capture"));}}
        [UnityTest] public IEnumerator S10_ScopedPreparationStillRejectsWritesAfterActions()
        {using(var game=new Product{brokenUnrelated=true,throwLayout=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>a.id=="needed",name=>false);yield return driver.Open("entry");driver.BeginActions();Exception error=null;yield return Catch(driver.Restore(driver.Observe()),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<InvalidOperationException>());Assert.That(game.restoreCalls,Is.Zero);}}
        [UnityTest] public IEnumerator S11_AuthorFilterExceptionIsNotAProductFailure()
        {using(var game=new Product()){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>throw new InvalidOperationException("broken author filter"),name=>false);Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<InvalidOperationException>());Assert.That(error,Is.Not.TypeOf<SessionProductFailure>());}}
        [UnityTest] public IEnumerator S12_UnselectedPublicStateCannotAdvanceBehindCommitFreeze()
        {using(var game=new Product{advanceUnrelated=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>a.id=="needed",name=>false);Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());Assert.That(error.Message,Does.Contain("advanced"));}}
        [UnityTest] public IEnumerator S13_SelectedActorsCannotAliasOneEngineObject()
        {using(var game=new Product{aliasObjects=true}){var driver=new SessionDriver(game,Definition(),true,PublicRules,a=>true,name=>false);Exception error=null;yield return Catch(driver.Open("entry"),e=>error=e);Record(game,driver,error);Assert.That(error,Is.TypeOf<SessionProductFailure>());Assert.That(error.Message,Does.Contain("alias"));}}
    }
}
