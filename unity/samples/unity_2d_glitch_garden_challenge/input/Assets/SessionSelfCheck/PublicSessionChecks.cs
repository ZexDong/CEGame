using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.Session.PublicChecks
{
    // Public development checks for game-session/v1. No gameplay implementation.
    // These checks cover basic service behavior, not the complete game contract.
    public sealed class PublicSessionChecks
    {
        [Serializable] sealed class Manifest { public string required_final_scene; }
        IGameSession service;
        SessionModel model;

        [UnitySetUp]
        public IEnumerator LoadDeliveredScene()
        {
            Time.timeScale = 1;
            var root = Path.GetDirectoryName(Application.dataPath);
            var manifest = JsonUtility.FromJson<Manifest>(File.ReadAllText(Path.Combine(root, "BENCHMARK_MANIFEST.json")));
            Assert.IsTrue(Application.CanStreamedLevelBeLoaded(manifest.required_final_scene),
                "The required final scene must be saved and enabled in Build Settings.");
            var load = SceneManager.LoadSceneAsync(manifest.required_final_scene, LoadSceneMode.Single);
            Assert.IsNotNull(load);
            while (!load.isDone) yield return null;
            yield return null;
            var services = UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsSortMode.None)
                .Where(x => x.isActiveAndEnabled).OfType<IGameSession>().ToArray();
            Assert.AreEqual(1, services.Length, "Exactly one active IGameSession is required.");
            service = services[0];
            var resource = Resources.Load<TextAsset>("session-model");
            Assert.IsNotNull(resource, "The public runtime session model must be available.");
            model = JsonUtility.FromJson<SessionModel>(resource.text);
            Assert.AreEqual(model.contract, service.ContractVersion, "Use the published service contract version.");
            Assert.IsNotNull(service.EntryIds);
            CollectionAssert.AreEquivalent(model.entries, service.EntryIds, "Publish every declared chapter exactly once.");
        }

        [TearDown]
        public void ReleaseTestTimeScale() { Time.timeScale = 1; }

        IEnumerator Complete(SessionOperation operation, string context)
        {
            Assert.IsNotNull(operation, context + ": a request must return an operation object.");
            var deadline = Time.realtimeSinceStartupAsDouble + model.operationTimeoutSeconds;
            while (operation.state == OperationState.Pending && Time.realtimeSinceStartupAsDouble < deadline)
                yield return null;
            Assert.AreEqual(OperationState.Completed, operation.state,
                context + ": " + operation.code + " " + operation.message);
        }

        SessionSave CaptureValid()
        {
            var save = service.Capture();
            Assert.IsNull(model.Validate(save), "Capture must include the public version, numeric fields, and valid actor records.");
            return save;
        }

        [UnityTest]
        public IEnumerator ChapterEntry_CommitsStateAndKeepsItSuspended()
        {
            foreach (var entry in model.entries)
            {
                yield return Complete(service.OpenEntry(entry, 0), "Open " + entry);
                var before = SessionFormat.Clone(CaptureValid());
                Assert.AreEqual(entry, before.entryId, "The completed operation must open the requested chapter.");
                yield return null;
                yield return null;
                PublicSessionAssertions.Equivalent(before, CaptureValid(), "Chapter loading suspension");
            }
        }

        [UnityTest]
        public IEnumerator Capture_IsDetached_AndRestoreRoundTripsAcrossChapters()
        {
            for (var index = 0; index < model.entries.Length; index++)
            {
                yield return Complete(service.OpenEntry(model.entries[index], 0), "Open for capture");
                var captured = CaptureValid();
                var saved = SessionFormat.Clone(captured);
                captured.phase = "public-check-detached-copy";
                if (captured.values.Count > 0) captured.values[0].value += 1;
                if (captured.actors.Count > 0)
                {
                    captured.actors[0].position += Vector3.right;
                    if (captured.actors[0].values.Count > 0) captured.actors[0].values[0].value += 1;
                }
                PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Mutating a captured copy must not mutate the game");
                yield return Complete(service.OpenEntry(model.entries[(index + 1) % model.entries.Length], 0), "Open before restore");
                yield return Complete(service.Restore(SessionFormat.Clone(saved)), "Restore own valid save");
                PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Restored public state");
                PublicSessionAssertions.RealActors(service, CaptureValid());
                yield return null;
                PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Restore loading suspension");
                service.ResumeSimulation();
                PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Releasing loading suspension preserves the committed state");
            }
        }

        [UnityTest]
        public IEnumerator InvalidRequests_AreRejectedWithoutPartialWrites()
        {
            yield return Complete(service.OpenEntry(model.entries[0], 0), "Open before invalid requests");
            var saved = SessionFormat.Clone(CaptureValid());
            var unknown = "public-check-unknown-entry";
            while (model.entries.Contains(unknown)) unknown += "-unknown";
            var operation = service.OpenEntry(unknown, 0);
            Assert.IsNotNull(operation);
            Assert.AreEqual(OperationState.Rejected, operation.state, "Unknown chapter IDs are rejected immediately.");
            PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Rejected chapter request");
            var invalid = SessionFormat.Clone(saved);
            invalid.contract = "public-check-invalid-schema";
            operation = service.Restore(invalid);
            Assert.IsNotNull(operation);
            Assert.AreEqual(OperationState.Rejected, operation.state, "Invalid schema is rejected immediately.");
            PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Rejected restore");
            yield return null;
            PublicSessionAssertions.Equivalent(saved, CaptureValid(), "Rejected requests preserve loading suspension");
        }

        [UnityTest]
        public IEnumerator SceneDescription_AndActorPosesReferToRealObjects()
        {
            foreach (var entry in model.entries)
            {
                yield return Complete(service.OpenEntry(entry, 0), "Open for scene identity");
                var save = CaptureValid();
                var description = service.DescribeCurrentEntry();
                Assert.IsNotNull(description, "The active chapter needs a description.");
                Assert.AreEqual(entry, description.id);
                Assert.IsTrue(SessionFormat.Finite(description.worldBounds.center));
                Assert.IsTrue(SessionFormat.Finite(description.worldBounds.size));
                Assert.IsNotNull(description.landmarks);
                foreach (var name in model.requiredLandmarks)
                {
                    var matches = description.landmarks.Where(x => x != null && x.name == name).ToArray();
                    Assert.AreEqual(1, matches.Length, "Missing or duplicate required landmark: " + name);
                    Assert.IsTrue(matches[0].present, "Required landmark is missing: " + name);
                    Assert.IsTrue(SessionFormat.Finite(matches[0].position));
                }
                PublicSessionAssertions.RealActors(service, save);
            }
        }
    }

    public static class PublicSessionAssertions
    {
        public static void Equivalent(SessionSave expected, SessionSave actual, string context)
        {
            Assert.IsNotNull(actual, context);
            Assert.AreEqual(expected.contract, actual.contract, context + ": contract");
            Assert.AreEqual(expected.contentVersion, actual.contentVersion, context + ": content version");
            Assert.AreEqual(expected.entryId, actual.entryId, context + ": chapter");
            Assert.AreEqual(expected.phase, actual.phase, context + ": phase");
            Assert.AreEqual(expected.seed, actual.seed, context + ": seed");
            Numbers(expected.values, actual.values, context);
            Assert.IsNotNull(actual.actors, context);
            CollectionAssert.AreEquivalent(expected.actors.Select(x => x.id), actual.actors.Select(x => x.id), context + ": actor identities");
            foreach (var actor in expected.actors)
            {
                var other = actual.actors.Single(x => x.id == actor.id);
                Assert.AreEqual(actor.kind, other.kind, context + ": actor kind " + actor.id);
                Assert.AreEqual(actor.entryId, other.entryId, context + ": actor chapter " + actor.id);
                Assert.AreEqual(actor.state, other.state, context + ": actor state " + actor.id);
                Assert.AreEqual(actor.present, other.present, context + ": actor presence " + actor.id);
                Assert.That(Vector3.Distance(actor.position, other.position), Is.LessThanOrEqualTo(0.0001f), context + ": actor pose " + actor.id);
                Assert.AreEqual(actor.facing, other.facing, context + ": actor facing " + actor.id);
                Numbers(actor.values, other.values, context + ": actor " + actor.id);
            }
            // Opaque data representation and collection order are implementation choices.
        }

        static void Numbers(List<NamedNumber> expected, List<NamedNumber> actual, string context)
        {
            Assert.IsNotNull(actual, context);
            CollectionAssert.AreEquivalent(expected.Select(x => x.name), actual.Select(x => x.name), context + ": numeric names");
            foreach (var number in expected)
                Assert.AreEqual(number.value, actual.Single(x => x.name == number.name).value, context + ": " + number.name);
        }

        public static void RealActors(IGameSession service, SessionSave save)
        {
            var objects = new HashSet<GameObject>();
            foreach (var actor in save.actors.Where(x => x.present))
            {
                var real = service.ResolveActor(actor.id);
                Assert.IsNotNull(real, "Present actor does not resolve: " + actor.id);
                Assert.IsTrue(real.scene.IsValid() && real.scene.isLoaded && real.activeInHierarchy, "Actor must belong to the active game: " + actor.id);
                Assert.IsTrue(objects.Add(real), "Different present actors resolved to the same object: " + actor.id);
                Assert.That(Vector3.Distance(actor.position, real.transform.position), Is.LessThanOrEqualTo(0.0001f), "Actor pose disagrees with the real object: " + actor.id);
            }
        }
    }
}
