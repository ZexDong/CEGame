using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Session;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace GameCreate.Evaluation.Session.Tests
{
    public sealed class SessionDriverTests
    {
        enum Fault { None, AcknowledgementOnly, FalsePose, AliasCapture, AcceptInvalid, Pending, MissingPlayer, NoOperationId, NullOperation }
        sealed class Sample : IGameSession, IDisposable
        {
            readonly GameObject actor=new GameObject("unrelated-internal-name");
            readonly SessionModel definition;
            readonly Fault fault;
            SessionSave state;
            // A second implementation stores resource values in a dictionary and
            // creates its transport rows on each capture, without sharing fields.
            readonly bool dictionaryStorage;
            Dictionary<string,double> resourceStore=new Dictionary<string,double>();
            public string ContractVersion=>"game-session/v1";
            public void ResumeSimulation(){}
            public IReadOnlyList<string> EntryIds=>new[]{"chapter-a","chapter-b"};
            public Sample(SessionModel model,Fault fault=Fault.None,bool dictionary=false){definition=model;this.fault=fault;dictionaryStorage=dictionary;OpenEntry("chapter-a",0);}
            SessionOperation Result(OperationState status,string code=null)=>fault==Fault.NullOperation?null:new SessionOperation{id=fault==Fault.NoOperationId?null:Guid.NewGuid().ToString("N"),state=status,code=code};
            public SessionOperation OpenEntry(string entry,int seed)
            {
                if(!EntryIds.Contains(entry))return Result(OperationState.Rejected,"unknown_entry");
                state=new SessionSave{contentVersion="sample-1",entryId=entry,phase="playing",seed=seed,
                    values=new List<NamedNumber>{new NamedNumber{name="energy",value=3}},
                    actors=new List<ActorSave>{new ActorSave{id="hero",kind="player",entryId=entry,state="idle",present=true,position=Vector3.zero}}};
                resourceStore["energy"]=3;actor.transform.position=Vector3.zero;
                return Result(fault==Fault.Pending?OperationState.Pending:OperationState.Completed);
            }
            public SessionSave Capture()
            {
                if(dictionaryStorage)state.values=resourceStore.Select(x=>new NamedNumber{name=x.Key,value=x.Value}).ToList();
                var result=fault==Fault.AliasCapture?state:SessionFormat.Clone(state);
                if(fault==Fault.FalsePose)result.actors[0].position=Vector3.one*9;
                if(fault==Fault.MissingPlayer)result.actors.Clear();
                return result;
            }
            public SessionOperation Restore(SessionSave save)
            {
                if(definition.Validate(save)!=null)return Result(fault==Fault.AcceptInvalid?OperationState.Completed:OperationState.Rejected,"invalid");
                if(fault!=Fault.AcknowledgementOnly){state=SessionFormat.Clone(save);actor.transform.position=state.actors[0].position;resourceStore=state.values.ToDictionary(x=>x.name,x=>x.value);}
                return Result(OperationState.Completed);
            }
            public EntryDescription DescribeCurrentEntry()=>new EntryDescription{id=state.entryId,worldBounds=new Bounds(Vector3.zero,new Vector3(30,20,0)),landmarks=new List<Landmark>{new Landmark{name="entry",present=true,position=Vector3.zero}}};
            public GameObject ResolveActor(string id)=>id=="hero"?actor:null;
            public void Dispose(){UnityEngine.Object.DestroyImmediate(actor);}
        }
        static SessionModel Model()=>new SessionModel{contentVersion="sample-1",entries=new[]{"chapter-a","chapter-b"},phases=new[]{"playing"},requiredLandmarks=new[]{"entry"},operationTimeoutSeconds=.05f,
            values=new[]{new NumberRule{name="energy",minimum=0,maximum=3,integer=true,editable=true}},actorKinds=new[]{new ActorRule{kind="player",states=new[]{"idle"},poseEditable=true}}};
        static IEnumerator Catch(IEnumerator routine,Action<Exception> error)
        {
            var stack=new Stack<IEnumerator>();stack.Push(routine);
            while(stack.Count>0)
            {
                bool more=false;object next=null;Exception fault=null;
                try{more=stack.Peek().MoveNext();if(more)next=stack.Peek().Current;}catch(Exception ex){fault=ex;}
                if(fault!=null){error(fault);yield break;}
                if(!more){stack.Pop();continue;}
                if(next is IEnumerator child)stack.Push(child);else yield return next;
            }
        }
        [UnityTest] public IEnumerator TwoStorageArchitecturesUseIdenticalClient()
        {
            foreach(var dictionary in new[]{false,true})using(var game=new Sample(Model(),dictionary:dictionary))
            {
                var driver=new SessionDriver(game,Model(),true,Model().Validate);yield return driver.Open("chapter-b",17);
                var save=driver.Observe();save.values[0].value=1;save.actors[0].position=new Vector3(2,1,0);
                yield return driver.Restore(save);driver.CheckDetachedCapture();
                Assert.AreEqual("READY",driver.LastReceipt.status);Assert.AreEqual(1,driver.LastSave.values[0].value);
                Assert.AreEqual(new Vector3(2,1,0),driver.LastReceipt.actors[0].enginePosition);
            }
        }
        [UnityTest] public IEnumerator AcknowledgementWithoutRestoreIsProductFailure()
        {
            using(var game=new Sample(Model(),Fault.AcknowledgementOnly)){
                var driver=new SessionDriver(game,Model(),true,Model().Validate);yield return driver.Open("chapter-a");
                var save=driver.Observe();save.values[0].value=0;Exception caught=null;
                yield return Catch(driver.Restore(save),ex=>caught=ex);
                Assert.IsInstanceOf<SessionProductFailure>(caught);Assert.AreEqual("PRODUCT_CONTRACT_FAILURE",driver.LastReceipt.status);
            }
        }
        [UnityTest] public IEnumerator LyingPoseIsComparedToRealEngineObject()
        {
            using(var game=new Sample(Model(),Fault.FalsePose)){
                var driver=new SessionDriver(game,Model(),true);Exception caught=null;
                yield return Catch(driver.Open("chapter-a"),ex=>caught=ex);Assert.IsInstanceOf<SessionProductFailure>(caught);
            }
        }
        [UnityTest] public IEnumerator MutableCaptureAliasIsProductFailure()
        {
            using(var game=new Sample(Model(),Fault.AliasCapture)){
                var driver=new SessionDriver(game,Model(),true);yield return driver.Open("chapter-a");
                Assert.Throws<SessionProductFailure>(()=>driver.CheckDetachedCapture());
            }
        }
        [UnityTest] public IEnumerator InvalidRestoreMustRejectWithoutPartialWrites()
        {
            foreach(var fault in new[]{Fault.None,Fault.AcceptInvalid})using(var game=new Sample(Model(),fault)){
                var driver=new SessionDriver(game,Model(),true);yield return driver.Open("chapter-a");
                var save=driver.Observe();save.values[0].value=99;
                if(fault==Fault.None)Assert.DoesNotThrow(()=>driver.CheckInvalidRestore(save));
                else Assert.Throws<SessionProductFailure>(()=>driver.CheckInvalidRestore(save));
            }
        }
        [UnityTest] public IEnumerator LateWritesAreEvaluatorFailure()
        {
            using(var game=new Sample(Model())){
                var driver=new SessionDriver(game,Model(),true);yield return driver.Open("chapter-a");driver.BeginActions();Exception caught=null;
                yield return Catch(driver.Restore(driver.Observe()),ex=>caught=ex);
                Assert.IsInstanceOf<InvalidOperationException>(caught);Assert.IsNotInstanceOf<SessionProductFailure>(caught);
            }
        }
        [UnityTest] public IEnumerator ContinuingFramesWithStuckServiceIsProductFailure()
        {
            using(var game=new Sample(Model(),Fault.Pending)){
                var driver=new SessionDriver(game,Model(),true);Exception caught=null;
                yield return Catch(driver.Open("chapter-a"),ex=>caught=ex);
                Assert.IsInstanceOf<SessionProductFailure>(caught);Assert.Greater(driver.LastReceipt.completedFrame,driver.LastReceipt.startedFrame);
            }
        }
        [UnityTest] public IEnumerator InvalidCandidateCaptureIsProductFailure()
        {
            using(var game=new Sample(Model(),Fault.MissingPlayer)){
                Exception caught=null;var driver=new SessionDriver(game,Model(),true,save=>Model().Validate(save)??(save.actors.Count(x=>x.kind=="player")==1?null:"one player required"));
                yield return Catch(driver.Open("chapter-a"),ex=>caught=ex);
                Assert.IsInstanceOf<SessionProductFailure>(caught);
            }
        }
        [UnityTest] public IEnumerator OperationIdIsNotAnUndeclaredRequirement()
        {
            using(var game=new Sample(Model(),Fault.NoOperationId)){
                var driver=new SessionDriver(game,Model(),true,Model().Validate);
                yield return driver.Open("chapter-a");
                var save=driver.Observe();save.values[0].value=2;
                yield return driver.Restore(save);
                Assert.AreEqual("READY",driver.LastReceipt.status);
                Assert.AreEqual(2,driver.LastSave.values[0].value);
            }
        }
        [UnityTest] public IEnumerator NullOperationIsStillAProductFailure()
        {
            using(var game=new Sample(Model(),Fault.NullOperation)){
                var driver=new SessionDriver(game,Model(),true,Model().Validate);Exception caught=null;
                yield return Catch(driver.Open("chapter-a"),ex=>caught=ex);
                Assert.IsInstanceOf<SessionProductFailure>(caught);
            }
        }
        [UnityTest] public IEnumerator ValidatorBugIsNotChargedToProduct()
        {
            using(var game=new Sample(Model())){
                var driver=new SessionDriver(game,Model(),true,save=>throw new InvalidOperationException("author validator bug"));Exception caught=null;
                yield return Catch(driver.Open("chapter-a"),ex=>caught=ex);
                Assert.IsInstanceOf<InvalidOperationException>(caught);
                Assert.IsNotInstanceOf<SessionProductFailure>(caught);
            }
        }
        [Test] public void NewRequirementCannotBeAppliedToOldInput()
        {
            using(var game=new Sample(Model()))Assert.Throws<InvalidOperationException>(()=>new SessionDriver(game,Model(),false));
        }
        [UnityTest] public IEnumerator UnverifiedRestoreIsAuthorFailureBeforeCallingProduct()
        {
            using(var game=new Sample(Model())){
                var driver=new SessionDriver(game,Model(),true);yield return driver.Open("chapter-a");Exception caught=null;
                yield return Catch(driver.Restore(driver.Observe()),ex=>caught=ex);
                Assert.IsInstanceOf<InvalidOperationException>(caught);Assert.IsNotInstanceOf<SessionProductFailure>(caught);
            }
        }
        [Test] public void DuplicateAndNonFiniteStatesAreRejected()
        {
            using(var game=new Sample(Model())){
                var save=game.Capture();save.actors.Add(save.actors[0]);Assert.AreEqual("duplicate_actor",Model().Validate(save));
                save=game.Capture();save.values[0].value=double.NaN;Assert.AreEqual("non_finite_value",Model().Validate(save));
            }
        }
    }
}
