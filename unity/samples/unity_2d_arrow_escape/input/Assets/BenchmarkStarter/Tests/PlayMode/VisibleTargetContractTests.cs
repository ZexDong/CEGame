using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using NUnit.Framework;
using OmniGame.Benchmark.ArrowEscape.V2;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.ArrowEscape.PublicSmoke
{
    public sealed class VisibleTargetContractTests
    {
        private const string DashboardInterfaceName =
            "OmniGame.Benchmark.Dashboard.V3.IGameStateDashboard";
        private const string DashboardContractVersion = "game-state-dashboard/v3";

        [UnityTest]
        public IEnumerator MainScenePublishesCompleteVisibleTargetRegistry()
        {
            string scenePath = ArrowEscapeContractConstants.MainScenePath;
            bool sceneIsLoadable = Application.CanStreamedLevelBeLoaded(scenePath);
            Assert.That(sceneIsLoadable, Is.True,
                $"Add the required main scene to Build Settings: {scenePath}");
            if (!sceneIsLoadable) yield break;

            AsyncOperation load = SceneManager.LoadSceneAsync(scenePath, LoadSceneMode.Single);
            Assert.That(load, Is.Not.Null, $"Could not load main scene: {scenePath}");
            if (load == null) yield break;
            while (!load.isDone) yield return null;

            // Allow Start() and one layout pass to publish current runtime geometry.
            yield return null;
            Canvas.ForceUpdateCanvases();
            yield return null;

            IArrowEscapeReadOnlyProbe[] probes = UnityEngine.Object
                .FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Where(component => component != null && component.isActiveAndEnabled)
                .OfType<IArrowEscapeReadOnlyProbe>()
                .ToArray();

            Assert.That(probes, Has.Length.EqualTo(1),
                "The loaded main scene must contain exactly one active Arrow Escape probe.");
            IArrowEscapeReadOnlyProbe probe = probes[0];
            Assert.That(probe.ContractVersion,
                Is.EqualTo(ArrowEscapeContractConstants.ContractVersion));

            ArrowEscapeGameSnapshot snapshot = probe.CaptureBenchmarkSnapshot();
            Assert.That(snapshot, Is.Not.Null);
            Assert.That(snapshot.Arrows, Is.Not.Null);
            Assert.That(snapshot.VisibleTargets, Is.Not.Null);
            Assert.That(snapshot.LevelId,
                Is.EqualTo(ArrowEscapeContractConstants.TutorialLevelId),
                "The saved final scene must open into the fresh tutorial level.");
            Assert.That(snapshot.Phase, Is.EqualTo(ArrowEscapeGamePhase.Playing),
                "The saved final scene must be actively playable after startup.");
            Assert.That(snapshot.Arrows.Length, Is.GreaterThan(0),
                "The tutorial must contain at least one authored arrow.");

            MonoBehaviour[] activeComponents = UnityEngine.Object
                .FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .Where(component => component != null && component.isActiveAndEnabled)
                .ToArray();
            DashboardBinding[] dashboards = activeComponents
                .Select(TryBindDashboard)
                .Where(binding => binding != null)
                .ToArray();

            Assert.That(dashboards, Has.Length.EqualTo(1),
                $"The loaded main scene must contain exactly one active {DashboardInterfaceName}.");
            DashboardBinding dashboard = dashboards[0];
            Assert.That(dashboard.ContractVersion,
                Is.EqualTo(DashboardContractVersion));

            object firstDashboardSnapshot = CaptureDashboard(dashboard);
            AssertDashboardArraysArePresent(firstDashboardSnapshot);
            int firstRevision = GetDashboardRevision(firstDashboardSnapshot);

            // No player input or semantic state transition occurs during these idle frames.
            yield return null;
            yield return null;

            object secondDashboardSnapshot = CaptureDashboard(dashboard);
            AssertDashboardArraysArePresent(secondDashboardSnapshot);
            int secondRevision = GetDashboardRevision(secondDashboardSnapshot);
            Assert.That(secondRevision, Is.EqualTo(firstRevision),
                "Dashboard revision must remain stable while the reported game state is idle.");

            ArrowEscapeVisibleTargetSnapshot[] targets = snapshot.VisibleTargets;
            foreach (ArrowEscapeVisibleTargetSnapshot target in targets)
            {
                Assert.That(target, Is.Not.Null,
                    "VisibleTargets must not contain null entries.");
                AssertTargetBasics(target);
            }

            string[] duplicateKeys = targets
                .GroupBy(target => target.Kind + ":" + target.Id)
                .Where(group => group.Count() != 1)
                .Select(group => group.Key)
                .ToArray();
            Assert.That(duplicateKeys, Is.Empty,
                "Each VisibleTargets Kind + Id pair must be unique.");

            int nonExitedArrowCount = snapshot.Arrows.Count(arrow =>
                arrow != null && arrow.State != ArrowEscapeArrowState.Exited);
            int visibleArrowTargetCount = targets.Count(target =>
                target != null && target.Visible &&
                target.Kind == ArrowEscapeVisibleTargetKind.Arrow);
            Assert.That(visibleArrowTargetCount, Is.EqualTo(nonExitedArrowCount),
                "Visible Arrow target count must exactly match the non-exited arrow count.");

            foreach (ArrowEscapeArrowSnapshot arrow in snapshot.Arrows
                         .Where(arrow => arrow != null &&
                                         arrow.State != ArrowEscapeArrowState.Exited))
            {
                int count = targets.Count(target =>
                    target.Visible &&
                    target.Kind == ArrowEscapeVisibleTargetKind.Arrow &&
                    string.Equals(target.Id, arrow.Id));
                Assert.That(count, Is.EqualTo(1),
                    $"Non-exited arrow '{arrow.Id}' needs exactly one visible Arrow target with the same ID.");
            }

            AssertExactlyOneVisible(targets, ArrowEscapeVisibleTargetKind.Hint);
            AssertExactlyOneVisible(targets, ArrowEscapeVisibleTargetKind.Restart);
            AssertExactlyOneVisible(targets, ArrowEscapeVisibleTargetKind.NextLevel);
        }

        private static DashboardBinding TryBindDashboard(MonoBehaviour component)
        {
            Type dashboardInterface = component.GetType().GetInterfaces()
                .SingleOrDefault(candidate =>
                    string.Equals(candidate.FullName, DashboardInterfaceName,
                        StringComparison.Ordinal));
            if (dashboardInterface == null) return null;

            PropertyInfo contractProperty = dashboardInterface.GetProperty("ContractVersion");
            MethodInfo captureMethod = dashboardInterface.GetMethod("Capture");
            Assert.That(contractProperty, Is.Not.Null,
                $"{DashboardInterfaceName} must publish ContractVersion.");
            Assert.That(captureMethod, Is.Not.Null,
                $"{DashboardInterfaceName} must publish Capture().");

            string contractVersion = null;
            Assert.DoesNotThrow(() =>
                contractVersion = contractProperty.GetValue(component) as string,
                "Reading Dashboard ContractVersion must not throw.");
            return new DashboardBinding(component, captureMethod, contractVersion);
        }

        private static object CaptureDashboard(DashboardBinding dashboard)
        {
            object snapshot = null;
            Assert.DoesNotThrow(() =>
                snapshot = dashboard.CaptureMethod.Invoke(dashboard.Component, null),
                "IGameStateDashboard.Capture() must not throw in the loaded final scene.");
            Assert.That(snapshot, Is.Not.Null,
                "IGameStateDashboard.Capture() must return a snapshot.");
            return snapshot;
        }

        private static void AssertDashboardArraysArePresent(object snapshot)
        {
            foreach (string memberName in new[] { "facts", "entities", "targets", "relations" })
            {
                object value = GetDashboardMember(snapshot, memberName);
                Assert.That(value, Is.Not.Null,
                    $"Dashboard snapshot member '{memberName}' must not be null.");
                Assert.That(value, Is.InstanceOf<Array>(),
                    $"Dashboard snapshot member '{memberName}' must be an array.");
            }
        }

        private static int GetDashboardRevision(object snapshot)
        {
            object value = GetDashboardMember(snapshot, "revision");
            Assert.That(value, Is.TypeOf<int>(),
                "Dashboard snapshot revision must be an Int32.");
            return (int)value;
        }

        private static object GetDashboardMember(object snapshot, string memberName)
        {
            Type type = snapshot.GetType();
            FieldInfo field = type.GetField(memberName,
                BindingFlags.Instance | BindingFlags.Public);
            if (field != null) return field.GetValue(snapshot);

            PropertyInfo property = type.GetProperty(memberName,
                BindingFlags.Instance | BindingFlags.Public);
            Assert.That(property, Is.Not.Null,
                $"Dashboard snapshot is missing public member '{memberName}'.");
            return property.GetValue(snapshot);
        }

        private sealed class DashboardBinding
        {
            public readonly MonoBehaviour Component;
            public readonly MethodInfo CaptureMethod;
            public readonly string ContractVersion;

            public DashboardBinding(
                MonoBehaviour component,
                MethodInfo captureMethod,
                string contractVersion)
            {
                Component = component;
                CaptureMethod = captureMethod;
                ContractVersion = contractVersion;
            }
        }

        private static void AssertExactlyOneVisible(
            ArrowEscapeVisibleTargetSnapshot[] targets,
            ArrowEscapeVisibleTargetKind kind)
        {
            int count = targets.Count(target => target.Visible && target.Kind == kind);
            Assert.That(count, Is.EqualTo(1),
                $"Expected exactly one visible {kind} target.");
        }

        private static void AssertTargetBasics(ArrowEscapeVisibleTargetSnapshot target)
        {
            Assert.That(string.IsNullOrWhiteSpace(target.Id), Is.False,
                "Every visible-target registry entry needs an ID.");
            Assert.That(string.IsNullOrWhiteSpace(target.VisualState), Is.False,
                $"Target {target.Kind}:{target.Id} needs a non-empty VisualState.");
            Assert.That(target.Interactable && !target.Visible, Is.False,
                $"Target {target.Kind}:{target.Id} cannot be interactable while invisible.");
            if (!target.Visible) return;

            Rect rect = target.ScreenRect;
            Assert.That(IsFinite(rect), Is.True,
                $"Target {target.Kind}:{target.Id} has a non-finite ScreenRect.");
            Assert.That(rect.width, Is.GreaterThanOrEqualTo(2f),
                $"Target {target.Kind}:{target.Id} must be at least 2 pixels wide.");
            Assert.That(rect.height, Is.GreaterThanOrEqualTo(2f),
                $"Target {target.Kind}:{target.Id} must be at least 2 pixels high.");
            Assert.That(rect.xMax > 0f && rect.yMax > 0f &&
                        rect.xMin < Screen.width && rect.yMin < Screen.height,
                Is.True,
                $"Target {target.Kind}:{target.Id} must intersect the current game view.");
        }

        private static bool IsFinite(Rect rect) =>
            IsFinite(rect.x) && IsFinite(rect.y) &&
            IsFinite(rect.width) && IsFinite(rect.height);

        private static bool IsFinite(float value) =>
            !float.IsNaN(value) && !float.IsInfinity(value);
    }
}
