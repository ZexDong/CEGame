using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Session;
using UnityEngine;

namespace GameCreate.Evaluation.Session
{
    public sealed class SessionProductFailure : Exception
    {
        public string Capability { get; }
        public SessionProductFailure(string capability, string message) : base(message) { Capability = capability; }
    }
    [Serializable] public sealed class ActorObservation
    {
        public string actorId;
        public int instanceId;
        public Vector3 reported, enginePosition;
        public bool active;
        public int rendererCount;
    }
    [Serializable] public sealed class SessionReceipt
    {
        public string capability, entryId, operationId;
        public int startedFrame, completedFrame;
        public string status;
        public string error;
        public List<ActorObservation> actors = new List<ActorObservation>();
    }
    // Only public services are used: no candidate class/field names or reflection.
    // A driver instance owns one setup window. Beginning actions closes that
    // window permanently; later service writes are evaluator mistakes.
    public sealed class SessionDriver
    {
        readonly IGameSession game;
        readonly SessionModel model;
        readonly Func<SessionSave,string> validatePublicState;
        bool actionsStarted;
        public SessionReceipt LastReceipt { get; private set; }
        public SessionSave LastSave { get; private set; }
        public SessionDriver(IGameSession provider, SessionModel definition, bool declaredInFrozenInput, Func<SessionSave,string> publicStateValidator=null)
        {
            if (!declaredInFrozenInput) throw new InvalidOperationException("Undeclared session requirements cannot be charged to a candidate.");
            game = provider; model = definition ?? throw new ArgumentNullException(nameof(definition));
            validatePublicState=publicStateValidator;
            if (game == null) throw new SessionProductFailure("session-interface", "The public session component is absent.");
            if (Call("session-interface",()=>game.ContractVersion) != "game-session/v1") throw new SessionProductFailure("session-interface", "Wrong public session version.");
            if (!SessionFormat.Finite(model.operationTimeoutSeconds) || model.operationTimeoutSeconds <= 0 || model.operationTimeoutSeconds > 60)
                throw new InvalidOperationException("Invalid author-side operation timeout.");
        }
        public static IGameSession Find()
        {
            var providers = UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).OfType<IGameSession>().ToArray();
            if (providers.Length != 1) throw new SessionProductFailure("session-interface", "Exactly one active public session component is required; observed " + providers.Length);
            return providers[0];
        }
        void RequirePreparation()
        {
            if (actionsStarted) throw new InvalidOperationException("Evaluator attempted a session write after scored actions began.");
        }
        static T Call<T>(string capability,Func<T> action)
        {
            try { return action(); }
            catch (SessionProductFailure) { throw; }
            catch (Exception ex) { throw new SessionProductFailure(capability,"Candidate service threw: "+ex.GetType().Name+": "+ex.Message); }
        }
        public void BeginActions() {
            if (LastReceipt?.status != "READY") throw new InvalidOperationException("Actions need an independently verified entry.");
            Call("resume-simulation",()=>{game.ResumeSimulation();return true;});actionsStarted=true;
        }
        public IEnumerator Open(string entry, int seed = 0)
        {
            RequirePreparation();
            if (!(model.entries ?? Array.Empty<string>()).Contains(entry)) throw new InvalidOperationException("Evaluator requested an undeclared entry.");
            var entries=Call("entry-catalogue",()=>game.EntryIds);
            if (entries == null || entries.Distinct().Count() != entries.Count || !entries.Contains(entry))
                throw new SessionProductFailure("entry:"+entry, "Declared chapter is missing or entry catalogue is ambiguous.");
            yield return Execute("entry:"+entry, entry, () => game.OpenEntry(entry,seed));
        }
        public IEnumerator Restore(SessionSave save)
        {
            RequirePreparation();
            var invalid = model.Validate(save);
            if (invalid != null) throw new InvalidOperationException("Evaluator constructed an invalid setup save: " + invalid);
            if (validatePublicState==null) throw new InvalidOperationException("A validator for the complete published game-state rules is required before restore; format validity alone is insufficient.");
            invalid=validatePublicState(save);
            if (invalid!=null) throw new InvalidOperationException("Evaluator violated a published state precondition: "+invalid);
            // Preserve the expected request independently of both caller-owned
            // cached snapshots and any mutation performed by the service.
            var expected = SessionFormat.Clone(save);
            var copy = SessionFormat.Clone(expected);
            yield return Execute("restore:"+expected.entryId, expected.entryId, () => game.Restore(copy));
            if (!SamePublicState(expected,LastSave)) Fail("restore:"+expected.entryId,"Completed restore did not reconstruct the requested public state.");
        }
        IEnumerator Execute(string capability, string entry, Func<SessionOperation> invoke)
        {
            RequirePreparation();
            LastReceipt = new SessionReceipt { capability=capability,entryId=entry,startedFrame=Time.frameCount,status="RUNNING" };
            SessionOperation operation = null;
            try { operation = invoke(); }
            catch (Exception ex) { Fail(capability,"Candidate service threw: "+ex.GetType().Name+": "+ex.Message); }
            // The public contract polls the returned object, not an ID lookup.
            // An optional diagnostic ID cannot block an otherwise valid service.
            if (operation == null) Fail(capability,"Candidate returned no operation object.");
            LastReceipt.operationId=operation.id;
            var deadline = Time.realtimeSinceStartup + model.operationTimeoutSeconds;
            while (operation.state==OperationState.Pending && Time.realtimeSinceStartup<deadline) yield return null;
            if (operation.state!=OperationState.Completed) Fail(capability, operation.state==OperationState.Rejected ? "Candidate rejected valid request: "+operation.code : "Candidate operation timed out while Unity frames continued.");
            Verify(entry);
            var committed=SessionFormat.Clone(LastSave);
            var actualBefore=LastReceipt.actors.ToDictionary(x=>x.actorId,x=>x.enginePosition,StringComparer.Ordinal);
            var priorObservations=LastReceipt.actors.Count;
            yield return null;yield return null;
            Verify(entry);
            if(!SamePublicState(committed,LastSave,.00001f)||LastReceipt.actors.Skip(priorObservations).Any(x=>!actualBefore.TryGetValue(x.actorId,out var p)||Vector3.Distance(p,x.enginePosition)>.00001f))
                Fail(capability,"Gameplay advanced before the committed state was released.");
            LastReceipt.completedFrame=Time.frameCount;LastReceipt.status="READY";
        }
        void Fail(string capability,string message)
        {
            if (LastReceipt != null) { LastReceipt.status="PRODUCT_CONTRACT_FAILURE";LastReceipt.error=message;LastReceipt.completedFrame=Time.frameCount; }
            throw new SessionProductFailure(capability,message);
        }
        public SessionSave Observe()
        {
            SessionSave save = null;
            try { save=game.Capture(); }
            catch (Exception ex) { throw new SessionProductFailure("capture", "Candidate capture threw: "+ex.GetType().Name); }
            var invalid=model.Validate(save);
            if (invalid!=null) throw new SessionProductFailure("capture", "Candidate capture is invalid: "+invalid);
            return save;
        }
        void Verify(string entry)
        {
            var save=Observe();
            if (save.entryId!=entry) Fail(LastReceipt.capability,"Completed request opened a different chapter.");
            var instances=new HashSet<int>();
            foreach (var actor in save.actors.Where(x=>x.present))
            {
                var root=Call("actor:"+actor.id,()=>game.ResolveActor(actor.id));
                if (root==null || !root.activeInHierarchy) Fail("actor:"+actor.id,"A reported present actor has no active engine object.");
                if (!instances.Add(root.GetInstanceID())) Fail("actor:"+actor.id,"Distinct reported actors alias one engine object.");
                var renderers=root.GetComponentsInChildren<Renderer>().Where(x=>x.enabled && x.gameObject.activeInHierarchy).ToArray();
                var fact=new ActorObservation {actorId=actor.id,instanceId=root.GetInstanceID(),reported=actor.position,enginePosition=root.transform.position,active=root.activeInHierarchy,rendererCount=renderers.Length};
                LastReceipt.actors.Add(fact);
                if (!SessionFormat.Finite(root.transform.position) || Vector3.Distance(actor.position,root.transform.position)>.02f)
                    Fail("actor:"+actor.id,"Reported actor pose differs from actual engine pose.");
            }
            var layout=Call("layout:"+entry,()=>game.DescribeCurrentEntry());
            if (layout==null || layout.id!=entry || !SessionFormat.Finite(layout.worldBounds.center) || !SessionFormat.Finite(layout.worldBounds.size) ||
                layout.worldBounds.size.x<=0 || layout.worldBounds.size.y<=0 || layout.worldBounds.size.z<0 || layout.landmarks==null)
                Fail("layout:"+entry,"Current entry description is missing or invalid.");
            if (layout.landmarks.Select(x=>x?.name).Distinct().Count()!=layout.landmarks.Count ||
                (model.requiredLandmarks??Array.Empty<string>()).Any(name=>!layout.landmarks.Any(x=>x!=null && x.name==name && x.present && SessionFormat.Finite(x.position))))
                Fail("layout:"+entry,"Declared landmarks are missing or ambiguous.");
            // Check unedited product data before it becomes evaluator setup.
            // A returned diagnostic denotes invalid candidate data; an exception
            // in the author-owned validator remains an evaluator error.
            var publicStateError=validatePublicState?.Invoke(save);
            if(publicStateError!=null) Fail("capture", "Candidate capture violates published state rules: "+publicStateError);
            LastSave=SessionFormat.Clone(save);
        }
        static bool SamePublicState(SessionSave a,SessionSave b,float poseTolerance=.02f)
        {
            if (a.entryId!=b.entryId || a.contentVersion!=b.contentVersion || a.phase!=b.phase || a.seed!=b.seed || a.actors.Count!=b.actors.Count || a.values.Count!=b.values.Count) return false;
            bool Numbers(List<NamedNumber> left,List<NamedNumber> right) => left.Count==right.Count && left.All(x=>SessionFormat.TryNumber(right,x.name,out var value) && Math.Abs(x.value-value)<.00001);
            if (!Numbers(a.values,b.values)) return false;
            foreach (var actor in a.actors)
            {
                var other=b.actors.SingleOrDefault(x=>x.id==actor.id);
                if (other==null || actor.kind!=other.kind || actor.entryId!=other.entryId || actor.state!=other.state || actor.present!=other.present ||
                    Vector3.Distance(actor.position,other.position)>poseTolerance || actor.facing!=other.facing || !Numbers(actor.values,other.values)) return false;
            }
            return true;
        }
        public void CheckDetachedCapture()
        {
            var first=Observe();var before=JsonUtility.ToJson(first);
            var second=Observe();
            if(ReferenceEquals(first,second)||ReferenceEquals(first.values,second.values)||ReferenceEquals(first.actors,second.actors)||
                first.values.Any(x=>second.values.Any(y=>ReferenceEquals(x,y)))||first.actors.Any(x=>second.actors.Any(y=>ReferenceEquals(x,y))))
                throw new SessionProductFailure("capture","Capture reused mutable snapshot objects.");
            if (JsonUtility.ToJson(second)!=before) throw new SessionProductFailure("capture","Capture changed state within the same frame.");
            if (first.values.Count>0) first.values[0].value+=1;
            if (first.actors.Count>0) first.actors[0].position+=Vector3.one;
            if (JsonUtility.ToJson(Observe())!=before) throw new SessionProductFailure("capture","Capture leaked mutable aliases to game state.");
        }
        public void CheckInvalidRestore(SessionSave invalid)
        {
            RequirePreparation();
            if (model.Validate(invalid)==null) throw new InvalidOperationException("Rejection control is not invalid under the public format.");
            var before=JsonUtility.ToJson(Observe());
            var operation=Call("invalid-restore",()=>game.Restore(SessionFormat.Clone(invalid)));
            if (operation==null || operation.state!=OperationState.Rejected || JsonUtility.ToJson(Observe())!=before)
                throw new SessionProductFailure("invalid-restore","Invalid restore was not rejected immediately and without state changes.");
        }
    }
}
