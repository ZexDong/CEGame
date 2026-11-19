using System;
using System.Collections;
using System.IO;
using System.Linq;
using GameCreate.Kitchen;
using GameCreate.Session;
using GameCreate.Session.PublicChecks;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.Kitchen.PublicChecks
{
    // Optional public development checks for the published kitchen state semantics.
    // These checks do not implement gameplay or replace normal player-input testing.
    public sealed class KitchenPublicSessionChecks
    {
        const string FinalScene = "Assets/UndercookedChallenge/Scenes/UndercookedKitchen.unity";
        IGameSession service;

        [UnitySetUp]
        public IEnumerator LoadDeliveredScene()
        {
            Time.timeScale = 1;
            Assert.IsTrue(Application.CanStreamedLevelBeLoaded(FinalScene), "The final kitchen Scene must be saved and enabled in Build Settings.");
            var load = SceneManager.LoadSceneAsync(FinalScene, LoadSceneMode.Single);
            Assert.IsNotNull(load);
            while (!load.isDone) yield return null;
            yield return null;
            var services = UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(x => x.isActiveAndEnabled).OfType<IGameSession>().ToArray();
            Assert.AreEqual(1, services.Length, "Exactly one active IGameSession is required.");
            service = services[0];
            Assert.AreEqual("game-session/v1", service.ContractVersion);
            CollectionAssert.AreEquivalent(new[] { "kitchen" }, service.EntryIds);
        }

        [TearDown] public void RestoreTimeScale() { Time.timeScale = 1; }

        IEnumerator Complete(SessionOperation operation)
        {
            Assert.IsNotNull(operation);
            var deadline = Time.realtimeSinceStartupAsDouble + 10;
            while (operation.state == OperationState.Pending && Time.realtimeSinceStartupAsDouble < deadline) yield return null;
            Assert.AreEqual(OperationState.Completed, operation.state, operation.code + " " + operation.message);
        }

        SessionSave Capture()
        {
            var save = service.Capture();
            Assert.IsNull(KitchenSessionRules.Validate(save, service.DescribeCurrentEntry()), "Captured state violates the published kitchen rules.");
            return save;
        }

        [UnityTest]
        public IEnumerator FreshEntry_IsValidAndDescribesRealKitchen()
        {
            yield return Complete(service.OpenEntry("kitchen", 0));
            var save = Capture();
            Assert.AreEqual("playing", save.phase, "OpenEntry commits the normal active shift (SESSION-01)");
            Assert.AreEqual(9, save.actors.Count);
            var description = service.DescribeCurrentEntry();
            Assert.IsNotNull(description);
            foreach (var name in new[] { "chef-1-spawn", "chef-2-spawn", "open-floor", "tomato-crate-approach", "counter-approach", "chopping-board-approach", "pot-approach", "plate-rack-approach", "delivery-approach", "trash-approach" })
                Assert.AreEqual(1, description.landmarks.Count(x => x.name == name && x.present), "Missing required landmark " + name);
            foreach (var actor in save.actors.Where(x => x.present))
            {
                var real = service.ResolveActor(actor.id);
                Assert.IsNotNull(real, actor.id + " must resolve to a real object.");
                Assert.That(Vector3.Distance(actor.position, real.transform.position), Is.LessThanOrEqualTo(.0001f), actor.id + " pose mismatch");
            }
        }

        [UnityTest]
        public IEnumerator DuplicateItemRestore_IsRejectedWithoutPartialWrite()
        {
            yield return Complete(service.OpenEntry("kitchen", 0));
            var before = Capture();
            var invalid = SessionFormat.Clone(before);
            Set(invalid.actors.Single(x => x.id == "chef-1").values, "held_id", 100);
            Set(invalid.actors.Single(x => x.id == "chef-1").values, "held_kind", 1);
            Set(invalid.actors.Single(x => x.id == "chef-2").values, "held_id", 100);
            Set(invalid.actors.Single(x => x.id == "chef-2").values, "held_kind", 1);
            Set(invalid.values, "next_item_id", 101);
            var operation = service.Restore(invalid);
            Assert.AreEqual(OperationState.Rejected, operation.state, "Duplicated item ownership must be rejected atomically.");
            yield return null;
            PublicSessionAssertions.Equivalent(before, service.Capture(), "Rejected restore must be atomic (SESSION-04 / SESSION-11)");
        }

        [UnityTest]
        public IEnumerator LegalEditableTimerAndScore_RoundTrip()
        {
            yield return Complete(service.OpenEntry("kitchen", 0));
            var edited = SessionFormat.Clone(Capture());
            edited.phase = "playing";
            Set(edited.values, "score", 13);
            Set(edited.values, "shift_remaining", 30);
            yield return Complete(service.Restore(edited));
            var beforeWait = SessionFormat.Clone(Capture());
            yield return null;
            yield return null;
            PublicSessionAssertions.Equivalent(beforeWait, Capture(), "Restore loading suspension (SESSION-11)");
            service.ResumeSimulation();
            var after = Capture();
            PublicSessionAssertions.Equivalent(edited, after, "Legal edited state and release round-trip (SESSION-03)");
            Assert.AreEqual("playing", after.phase);
            Assert.AreEqual(13, Number(after.values, "score"));
            Assert.That(Number(after.values, "shift_remaining"), Is.EqualTo(30).Within(.0001));
        }

        static void Set(System.Collections.Generic.List<NamedNumber> values, string name, double value) { values.Single(x => x.name == name).value = value; }
        static double Number(System.Collections.Generic.List<NamedNumber> values, string name) => values.Single(x => x.name == name).value;
    }
}
