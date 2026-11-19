using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GameCreate.Session;
using GameCreate.Session.PublicChecks;
using GameCreate.Stormbound.Contract;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.Stormbound.PublicChecks
{
    // Optional checks of the published save contract. No game mechanics or player route.
    public sealed class StormboundPublicSessionChecks
    {
        [Serializable] sealed class Manifest { public string required_final_scene; }
        [Serializable] sealed class PublicRules { public int seed; }
        [Serializable] sealed class KindValues { public NumberRule[] island; }
        [Serializable] sealed class PublicDocument { public PublicRules rules; public KindValues actorValues; }
        IGameSession service;
        SessionModel model;
        PublicDocument document;

        [UnitySetUp]
        public IEnumerator LoadSavedGame()
        {
            Time.timeScale = 1;
            var root = Path.GetDirectoryName(Application.dataPath);
            var manifest = JsonUtility.FromJson<Manifest>(
                File.ReadAllText(Path.Combine(root, "BENCHMARK_MANIFEST.json")));
            Assert.IsTrue(Application.CanStreamedLevelBeLoaded(manifest.required_final_scene),
                "Save and enable the declared final scene before running post-implementation checks.");
            var load = SceneManager.LoadSceneAsync(manifest.required_final_scene, LoadSceneMode.Single);
            Assert.IsNotNull(load);
            var deadline = Time.realtimeSinceStartupAsDouble + 15;
            while (!load.isDone && Time.realtimeSinceStartupAsDouble < deadline) yield return null;
            Assert.IsTrue(load.isDone, "The saved scene did not load.");
            yield return null;
            var services = UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsSortMode.None)
                .Where(x => x.isActiveAndEnabled).OfType<IGameSession>().ToArray();
            Assert.AreEqual(1, services.Length, "Exactly one active public session service is required.");
            service = services[0];
            var resource = Resources.Load<TextAsset>("session-model");
            Assert.IsNotNull(resource);
            document = JsonUtility.FromJson<PublicDocument>(resource.text);
            model = JsonUtility.FromJson<SessionModel>(resource.text);
        }

        [TearDown]
        public void ReleaseTestTimeScale() { Time.timeScale = 1; }

        IEnumerator Complete(SessionOperation operation, string context)
        {
            Assert.IsNotNull(operation, context);
            var deadline = Time.realtimeSinceStartupAsDouble + model.operationTimeoutSeconds;
            while (operation.state == OperationState.Pending &&
                   Time.realtimeSinceStartupAsDouble < deadline) yield return null;
            Assert.AreEqual(OperationState.Completed, operation.state,
                context + ": " + operation.code + " " + operation.message);
        }

        IEnumerator Open()
        {
            yield return Complete(service.OpenEntry(model.entries[0], document.rules.seed),
                "Open the published normal entry");
        }

        SessionSave CaptureValid()
        {
            var save = service.Capture();
            Assert.IsNull(StormboundStateRules.Validate(save), "Capture violates the public model.");
            return save;
        }

        static NamedNumber Number(List<NamedNumber> values, string name)
        {
            return values.Single(x => x.name == name);
        }

        Dictionary<string, Vector3> RealPoses(SessionSave save)
        {
            PublicSessionAssertions.RealActors(service, save);
            return save.actors.Where(x => x.present).ToDictionary(x => x.id,
                x => service.ResolveActor(x.id).transform.position);
        }

        void SameRealPoses(Dictionary<string, Vector3> expected, string context)
        {
            foreach (var pair in expected)
            {
                var real = service.ResolveActor(pair.Key);
                Assert.IsNotNull(real, context + ": " + pair.Key);
                Assert.That(Vector3.Distance(pair.Value, real.transform.position),
                    Is.LessThanOrEqualTo(0.0001f), context + ": " + pair.Key);
            }
        }

        [UnityTest]
        public IEnumerator CaptureIsDetached_AndOwnSaveRoundTripsAllPublishedFields()
        {
            yield return Open();
            var captured = CaptureValid();
            var saved = SessionFormat.Clone(captured);
            PublicSessionAssertions.Equivalent(saved, captured, "Detached copy initially agrees");
            captured.phase = "detached-copy-only";
            captured.values[0].value += 1;
            captured.actors[0].position += Vector3.right;
            var withValues = captured.actors.First(x => x.values.Count > 0);
            withValues.values[0].value += 1;
            captured.actors.RemoveAt(captured.actors.Count - 1);
            captured.opaqueData = "detached-copy-only";
            PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Mutating Capture cannot mutate the game");
            yield return Open();
            yield return Complete(service.Restore(SessionFormat.Clone(saved)), "Restore the complete captured save");
            PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Own-save round trip");
            RealPoses(CaptureValid());
            yield return null;
            PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Restored state stays service-suspended");
            // Opaque serialization representation is not fixed by the public contract.
        }

        [UnityTest]
        public IEnumerator LegalFoodAndPauseEditsRoundTrip_AndPauseKeepsRealObjectsStill()
        {
            yield return Open();
            var edited = SessionFormat.Clone(CaptureValid());
            var island = edited.actors.First(x => x.kind == "island");
            var food = Number(island.values, "food");
            var maximum = document.actorValues.island.Single(x => x.name == "food").maximum;
            food.value = food.value < maximum ? food.value + 1 : food.value - 1;
            Number(edited.values, "paused").value = 1;
            Assert.IsNull(StormboundStateRules.Validate(edited), "Development edit must itself be legal.");
            yield return Complete(service.Restore(edited), "Restore legal editable resource and pause state");
            PublicSessionAssertions.Equivalent(edited, CaptureValid(), "Editable fields are not overwritten by opaque data");
            var real = RealPoses(CaptureValid());
            service.ResumeSimulation();
            yield return null;
            yield return null;
            PublicSessionAssertions.Equivalent(edited, CaptureValid(), "Saved pause intent survives service release");
            SameRealPoses(real, "Paused real objects");
        }

        IEnumerator RejectUnchanged(SessionSave invalid, bool identityError)
        {
            var before = SessionFormat.Clone(CaptureValid());
            var poses = RealPoses(before);
            Assert.IsNotNull(StormboundStateRules.Validate(invalid), "Invalid-request check must be invalid by the public rules.");
            var operation = service.Restore(invalid);
            Assert.IsNotNull(operation);
            if (identityError) Assert.AreEqual(OperationState.Rejected, operation.state,
                "Invalid identities are rejected immediately.");
            var deadline = Time.realtimeSinceStartupAsDouble + model.operationTimeoutSeconds;
            while (operation.state == OperationState.Pending && Time.realtimeSinceStartupAsDouble < deadline)
            {
                PublicSessionAssertions.Equivalent(before, CaptureValid(), "Pending rejection cannot partially write");
                SameRealPoses(poses, "Pending invalid request");
                yield return null;
            }
            Assert.AreEqual(OperationState.Rejected, operation.state, "Invalid relationships must be rejected.");
            PublicSessionAssertions.Equivalent(before, CaptureValid(), "Rejected restore keeps all published fields");
            SameRealPoses(poses, "Rejected restore keeps real objects");
            yield return null;
            PublicSessionAssertions.Equivalent(before, CaptureValid(), "Rejection preserves service suspension");
        }

        [UnityTest]
        public IEnumerator DuplicateIdentityAndInconsistentPassengerOwnershipAreRejectedAtomically()
        {
            yield return Open();
            var duplicate = SessionFormat.Clone(CaptureValid());
            duplicate.actors[1].id = duplicate.actors[0].id;
            yield return RejectUnchanged(duplicate, true);
            var ownership = SessionFormat.Clone(CaptureValid());
            var boat = ownership.actors.Single(x => x.kind == "boat");
            Number(boat.values, "passengers").value = 1;
            yield return RejectUnchanged(ownership, false);
        }

        [UnityTest]
        public IEnumerator ActorQueriesResolveUniqueRealObjectsBeforeAndAfterRestore()
        {
            yield return Open();
            var saved = SessionFormat.Clone(CaptureValid());
            var description = service.DescribeCurrentEntry();
            Assert.IsNotNull(description);
            Assert.AreEqual(saved.entryId, description.id);
            Assert.IsTrue(SessionFormat.Finite(description.worldBounds.center));
            Assert.IsTrue(SessionFormat.Finite(description.worldBounds.size));
            foreach (var name in model.requiredLandmarks)
            {
                var matches = description.landmarks.Where(x => x != null && x.name == name).ToArray();
                Assert.AreEqual(1, matches.Length, "Landmark identity: " + name);
                Assert.IsTrue(matches[0].present, name);
                Assert.IsTrue(SessionFormat.Finite(matches[0].position), name);
            }
            RealPoses(saved);
            yield return Complete(service.Restore(SessionFormat.Clone(saved)), "Restore before real-object query");
            PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Real-object round trip");
            var poses = RealPoses(CaptureValid());
            yield return null;
            SameRealPoses(poses, "Suspended actual actor transforms");
        }
    }
}
