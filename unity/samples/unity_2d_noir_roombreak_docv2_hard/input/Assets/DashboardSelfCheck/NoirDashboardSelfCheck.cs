using System;
using System.Collections;
using System.Linq;
using Benchmark.Dashboard;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace GameCreate.Benchmark.NoirRoombreak.DashboardChecks
{
    public sealed class NoirDashboardSelfCheck
    {
        [Serializable] sealed class NamingTables
        {
            public string[] slots;
            public NamedKind[] entities;
            public NamedKind[] targets;
        }

        [Serializable] sealed class NamedKind
        {
            public string kind;
            public string[] states;
        }

        [UnityTest]
        public IEnumerator Snapshot_IsWellFormedAndCompleteForCurrentPhase()
        {
            const string finalScene = "Assets/NoirChallenge/Scenes/NoirRoombreak.unity";
            Assert.IsTrue(Application.CanStreamedLevelBeLoaded(finalScene),
                $"Required final Scene is missing from Build Settings: {finalScene}");
            var load = SceneManager.LoadSceneAsync(finalScene, LoadSceneMode.Single);
            Assert.IsNotNull(load, $"Could not start loading required final Scene: {finalScene}");
            while (!load.isDone) yield return null;
            yield return null;
            yield return null;

            var dashboard = UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsSortMode.None)
                .OfType<IGameStateDashboard>().FirstOrDefault();
            Assert.IsNotNull(dashboard, "No Benchmark.Dashboard.IGameStateDashboard implementation found.");
            Assert.AreEqual("game-state-dashboard/v2", dashboard.ContractVersion, "Wrong dashboard contract version.");

            var text = Resources.Load<TextAsset>("naming-tables");
            Assert.IsNotNull(text, "Assets/Resources/naming-tables.json is missing.");
            var naming = JsonUtility.FromJson<NamingTables>(text.text);
            Assert.IsNotNull(naming, "Naming tables could not be parsed.");

            var snapshot = dashboard.Capture();
            Assert.IsNotNull(snapshot, "Capture() returned null.");
            Assert.That(snapshot.phase, Is.Not.EqualTo(GamePhase.NotReady), "Dashboard is still the unimplemented skeleton.");
            Assert.That(snapshot.revision, Is.GreaterThanOrEqualTo(0));

            var slots = snapshot.slots ?? throw new AssertionException("slots is null.");
            Assert.That(slots.Select(x => x.name).Distinct().Count(), Is.EqualTo(slots.Count), "Duplicate slot name.");
            foreach (var required in naming.slots ?? Array.Empty<string>())
            {
                var slot = slots.SingleOrDefault(x => x.name == required);
                Assert.IsNotNull(slot, $"Missing required slot '{required}'.");
                Assert.IsFalse(float.IsNaN(slot.value) || float.IsInfinity(slot.value), $"Slot '{required}' is not finite.");
            }

            foreach (var entity in snapshot.entities ?? throw new AssertionException("entities is null."))
            {
                var definition = (naming.entities ?? Array.Empty<NamedKind>()).SingleOrDefault(x => x.kind == entity.kind);
                Assert.IsNotNull(definition, $"Unknown entity kind '{entity.kind}'.");
                Assert.Contains(entity.state, definition.states ?? Array.Empty<string>(), $"Unknown state for '{entity.kind}'.");
                Assert.IsTrue(entity.cell != null && entity.cell.Length == 2, $"Entity '{entity.kind}' must report a two-number cell.");
                Assert.That(entity.cell[0], Is.InRange(0, Math.Max(0, Screen.width)));
                Assert.That(entity.cell[1], Is.InRange(0, Math.Max(0, Screen.height)));
            }

            if (snapshot.phase == GamePhase.Playing || snapshot.phase == GamePhase.Paused)
                Assert.IsTrue(snapshot.entities.Any(x => x.kind == "player"), "Playing/paused snapshots must report the player.");

            var targets = snapshot.targets ?? throw new AssertionException("targets is null.");
            Assert.That(targets.Select(x => x.kind).Distinct().Count(), Is.EqualTo(targets.Count), "Duplicate target kind.");
            foreach (var required in naming.targets ?? Array.Empty<NamedKind>())
                Assert.IsTrue(targets.Any(x => x.kind == required.kind), $"Missing target '{required.kind}'.");
            foreach (var target in targets)
            {
                Assert.IsTrue((naming.targets ?? Array.Empty<NamedKind>()).Any(x => x.kind == target.kind), $"Unknown target '{target.kind}'.");
                Assert.IsFalse(float.IsNaN(target.rect.x) || float.IsNaN(target.rect.y) || float.IsNaN(target.rect.width) || float.IsNaN(target.rect.height));
                if (target.visible || target.interactable)
                {
                    Assert.That(target.rect.width, Is.GreaterThan(0));
                    Assert.That(target.rect.height, Is.GreaterThan(0));
                    Assert.That(target.rect.xMin, Is.GreaterThanOrEqualTo(0));
                    Assert.That(target.rect.yMin, Is.GreaterThanOrEqualTo(0));
                    Assert.That(target.rect.xMax, Is.LessThanOrEqualTo(Screen.width));
                    Assert.That(target.rect.yMax, Is.LessThanOrEqualTo(Screen.height));
                }
            }

            var json = DashboardJson.ToJson(snapshot);
            Assert.That(json, Does.StartWith("{").And.EndWith("}"));
            Assert.That(json, Does.Contain("\"revision\":").And.Contain("\"phase\":").And.Contain("\"slots\":{").And.Contain("\"entities\":[").And.Contain("\"targets\":["));
        }
    }
}
