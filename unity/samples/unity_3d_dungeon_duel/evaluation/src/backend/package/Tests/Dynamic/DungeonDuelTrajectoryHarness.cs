using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.EventSystems;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    internal sealed class DungeonDuelTrajectoryHarness
    {
        public IDungeonDuelBenchmarkProbe Probe { get; private set; }
        public int SceneHandle { get; private set; } = -1;
        public InputSystemPlayerDriver Driver { get; } = new InputSystemPlayerDriver();
        public string LastObservationFailure { get; private set; }

        DungeonDuelTrajectoryIntent currentTrajectory = DungeonDuelTrajectoryIntent.CanonicalSuccess;
        RuntimeSemanticObserver semanticObserver;
        readonly Dictionary<DungeonDuelWorldTargetId, Vector3> verifiedWorldTargets =
            new Dictionary<DungeonDuelWorldTargetId, Vector3>();
        OpaqueHudState lastOpaqueHudState;

        public IEnumerator LoadFresh(
            DungeonDuelTrajectoryIntent trajectory,
            TrajectoryRecorder recorder,
            string stepId = "setup",
            string checkPrefix = "setup")
        {
            AsyncOperation operation = null;
            try
            {
                operation = SceneManager.LoadSceneAsync(
                    DungeonDuelContractConstants.MainScenePath, LoadSceneMode.Single);
            }
            catch (Exception exception)
            {
                recorder.Fail(stepId, checkPrefix + ".scene", "loadable canonical Dungeon Duel scene",
                    exception.GetType().Name,
                    "setup.scene_load: canonical Dungeon Duel scene is missing from the active " +
                    "build profile or could not be loaded. " + exception.Message);
                yield break;
            }

            if (operation == null)
            {
                recorder.Fail(stepId, checkPrefix + ".scene", "loadable canonical Dungeon Duel scene",
                    "null AsyncOperation",
                    "setup.scene_load: canonical Dungeon Duel scene is missing from the active build profile.");
                yield break;
            }

            while (!operation.isDone)
            {
                yield return null;
            }
            recorder.Pass(stepId, checkPrefix + ".scene", DungeonDuelContractConstants.MainScenePath,
                SceneManager.GetActiveScene().path);

            // Let ordinary gameplay bootstrap before discovery. The public
            // read-only probe is mandatory in v2. Every trajectory starts from
            // the candidate's normal canonical scene and prepares later states
            // only through ordinary player input.
            yield return null;
            yield return null;
            IDungeonDuelBenchmarkProbe[] probes = FindProbes();
            Probe = probes.Length == 1 ? probes[0] : null;
            if (Probe == null)
            {
                recorder.Fail(stepId, checkPrefix + ".submission_probe",
                    "exactly one public IDungeonDuelBenchmarkProbe",
                    $"found {probes.Length}",
                    "The public submission/tool contract requires one truthful read-only probe.");
                yield break;
            }
            if (!string.Equals(Probe.ContractVersion,
                    DungeonDuelContractConstants.ContractVersion,
                    StringComparison.Ordinal))
            {
                recorder.Fail(stepId, checkPrefix + ".submission_probe.version",
                    DungeonDuelContractConstants.ContractVersion,
                    Probe.ContractVersion ?? "<null>",
                    "The public probe contract version does not match this benchmark version.");
                yield break;
            }
            recorder.Pass(stepId, checkPrefix + ".submission_probe.version",
                DungeonDuelContractConstants.ContractVersion,
                Probe.ContractVersion);
            recorder.Pass(stepId, checkPrefix + ".submission_probe",
                "one public read-only probe",
                Probe.GetType().FullName + " @ " + Probe.ContractVersion);

            string cleanStartObservation =
                "clean canonical scene; evaluator will prepare the " + trajectory +
                " journey through normal player input";
            currentTrajectory = trajectory;
            verifiedWorldTargets.Clear();
            yield return null;
            yield return null;
            semanticObserver = new RuntimeSemanticObserver();
            if (!semanticObserver.Initialize(
                    SceneManager.GetActiveScene(), Probe, out string semanticFailure))
            {
                recorder.Fail(stepId, checkPrefix + ".semantic_discovery",
                    "native Player, two Imps, Boss, and physical gate",
                    semanticFailure ?? "semantic discovery failed",
                    "The scene did not expose independently observable gameplay actors and gate state.");
                yield break;
            }
            SceneHandle = SceneManager.GetActiveScene().handle;
            DungeonDuelGameSnapshot loaded = Snapshot();
            if (loaded == null || loaded.Player == null || loaded.Boss == null)
            {
                recorder.Fail(stepId, checkPrefix + ".semantic_discovery",
                    "native component-backed gameplay state",
                    LastObservationFailure ?? "uninitialized snapshot",
                    "The clean scene did not expose a real component-backed gameplay state.");
                yield break;
            }

            recorder.Pass(stepId, checkPrefix + ".semantic_discovery",
                "native Player, two Imps, Boss, and physical gate",
                semanticObserver.DiscoverySummary);
            recorder.Pass(stepId, checkPrefix + ".clean_start",
                "clean canonical scene for " + trajectory,
                cleanStartObservation + "; " + recorder.Snapshot(loaded));
            ValidateAndCacheWorldTargets(recorder, stepId, checkPrefix + ".world_target");
        }

        public Vector3 WorldTarget(DungeonDuelWorldTargetId targetId)
        {
            return verifiedWorldTargets.TryGetValue(targetId, out Vector3 target)
                ? target
                : new Vector3(float.PositiveInfinity, float.PositiveInfinity,
                    float.PositiveInfinity);
        }

        public DungeonDuelGameSnapshot Snapshot()
        {
            string failure = "semantic observer is unavailable";
            if (semanticObserver != null && semanticObserver.TryBuildSnapshot(
                    out DungeonDuelGameSnapshot observed, out failure))
            {
                LastObservationFailure = null;
                return observed;
            }

            LastObservationFailure = failure;
            return null;
        }

        public GameObject ActorTarget(DungeonDuelActorId actorId) =>
            semanticObserver?.ActorTarget(actorId);

        public bool IsActorPresented(DungeonDuelActorId actorId) =>
            semanticObserver != null && semanticObserver.IsActorPresented(actorId);

        public Vector3 GateCenter => semanticObserver?.GateCenter ?? Vector3.zero;

        public bool IsBeyondGate(Vector3 startSide, Vector3 current) =>
            semanticObserver != null && semanticObserver.IsBeyondGate(startSide, current);

        public bool IsGateBlocking => semanticObserver != null &&
                                      semanticObserver.IsGateBlocking();

        public bool TryBuildBeyondGateTarget(
            out Vector3 target,
            out string observation)
        {
            target = Vector3.zero;
            observation = "missing";
            GameObject player = ActorTarget(DungeonDuelActorId.Player);
            if (player == null || semanticObserver == null) return false;
            Vector3 forward = semanticObserver.GateForward;
            if (forward.sqrMagnitude < 0.01f) return false;
            forward.Normalize();
            Vector3 side = new Vector3(-forward.z, 0f, forward.x);
            var rejected = new List<string>();
            foreach ((Vector3 desired, string source) in BuildBeyondGateCandidates(
                         verifiedWorldTargets, GateCenter, forward, side))
            {
                if (!HasBeyondGateTargetClearance(desired, GateCenter, forward) ||
                    !IsBeyondGate(player.transform.position, desired))
                {
                    rejected.Add($"{source}:{desired:F2} lacks safe clearance beyond the native gate plane");
                    continue;
                }
                if (TryValidateGroundTarget(desired, out Vector3 candidate,
                        out string detail, out _) &&
                    HasBeyondGateTargetClearance(candidate, GateCenter, forward) &&
                    IsBeyondGate(player.transform.position, candidate))
                {
                    target = candidate;
                    observation = $"source={source}; {detail}";
                    return true;
                }
                rejected.Add($"{source}:{desired:F2} is not currently camera-projectable ground");
            }
            observation = string.Join(" | ", rejected.Take(10));
            return false;
        }

        public bool TryBuildGateApproachTarget(
            out Vector3 target,
            out string observation)
        {
            target = Vector3.zero;
            observation = "missing";
            GameObject player = ActorTarget(DungeonDuelActorId.Player);
            if (player == null || semanticObserver == null) return false;
            Vector3 forward = semanticObserver.GateForward;
            if (forward.sqrMagnitude < 0.01f) return false;
            forward.Normalize();
            Vector3 side = new Vector3(-forward.z, 0f, forward.x);
            Vector3 start = player.transform.position;
            float startDistance = HorizontalDistance(start, GateCenter);
            float bestDistance = float.PositiveInfinity;
            string bestObservation = null;
            var rejected = new List<string>();

            foreach ((Vector3 desired, string source) in BuildGateApproachCandidates(
                         verifiedWorldTargets, start, GateCenter, forward, side))
            {
                if (!IsFinite(desired) || IsBeyondGate(start, desired))
                {
                    rejected.Add($"{source}:{desired:F2} is not on the player's gate side");
                    continue;
                }
                if (!TryValidateGroundTarget(desired, out Vector3 candidate,
                        out string detail, out string failure) || IsBeyondGate(start, candidate))
                {
                    rejected.Add($"{source}:{desired:F2} {failure ?? "crosses the native gate plane"}");
                    continue;
                }
                float distance = HorizontalDistance(candidate, GateCenter);
                if (distance > startDistance - 1f || distance >= bestDistance) continue;
                target = candidate;
                bestDistance = distance;
                bestObservation = $"source={source}; gateDistance={startDistance:F2}->{distance:F2}; {detail}";
            }

            if (bestObservation == null)
            {
                observation = string.Join(" | ", rejected.Take(10));
                return false;
            }
            observation = bestObservation;
            return true;
        }

        internal static IEnumerable<(Vector3 point, string source)>
            BuildBeyondGateCandidates(
                IReadOnlyDictionary<DungeonDuelWorldTargetId, Vector3> verifiedTargets,
                Vector3 gateCenter,
                Vector3 forward,
                Vector3 side)
        {
            // Public Probe targets have already passed the same finite,
            // reachability, Physics and live-camera validation used by normal
            // navigation. Consider them before generic gate-relative samples;
            // the caller still revalidates current visibility and the native
            // gate plane, so this does not trust the Probe or bypass input.
            foreach (DungeonDuelWorldTargetId id in new[]
            {
                DungeonDuelWorldTargetId.MoveTargetB,
                DungeonDuelWorldTargetId.MoveTargetA,
                DungeonDuelWorldTargetId.DashTarget
            })
            {
                if (verifiedTargets != null &&
                    verifiedTargets.TryGetValue(id, out Vector3 verified) &&
                    IsFinite(verified))
                {
                    yield return (verified, "verified public world target " + id);
                }
            }

            yield return (gateCenter + forward * 3.2f + side * 4.5f,
                "native gate-relative sample");
            yield return (gateCenter + forward * 3.2f - side * 4.5f,
                "native gate-relative sample");
            yield return (gateCenter + forward * 4.5f + side * 3.5f,
                "native gate-relative sample");
        }

        internal static bool HasBeyondGateTargetClearance(
            Vector3 point,
            Vector3 gateCenter,
            Vector3 gateForward) =>
            gateForward.sqrMagnitude > 0.01f &&
            Vector3.Dot(point - gateCenter, gateForward.normalized) >= 1.5f;

        internal static IEnumerable<(Vector3 point, string source)>
            BuildGateApproachCandidates(
                IReadOnlyDictionary<DungeonDuelWorldTargetId, Vector3> verifiedTargets,
                Vector3 playerPosition,
                Vector3 gateCenter,
                Vector3 gateForward,
                Vector3 side)
        {
            foreach (DungeonDuelWorldTargetId id in new[]
            {
                DungeonDuelWorldTargetId.MoveTargetB,
                DungeonDuelWorldTargetId.MoveTargetA,
                DungeonDuelWorldTargetId.DashTarget
            })
            {
                if (verifiedTargets != null &&
                    verifiedTargets.TryGetValue(id, out Vector3 verified) && IsFinite(verified))
                    yield return (verified, "verified public world target " + id);
            }

            Vector3 toGate = gateCenter - playerPosition;
            toGate.y = 0f;
            if (toGate.sqrMagnitude > 0.01f)
            {
                float maximumStep = Mathf.Max(0f, toGate.magnitude - 3.2f);
                foreach (float requested in new[] { 8f, 6f, 4f })
                {
                    float step = Mathf.Min(requested, maximumStep);
                    if (step >= 1f)
                        yield return (playerPosition + toGate.normalized * step,
                            $"player-to-gate {step:F1}m hop");
                }
            }

            Vector3 forward = gateForward.normalized;
            yield return (gateCenter - forward * 3.2f, "native gate-front sample");
            yield return (gateCenter - forward * 4.5f + side * 2f,
                "native gate-front lateral sample");
            yield return (gateCenter - forward * 4.5f - side * 2f,
                "native gate-front lateral sample");
        }

        public AudioSemanticState CaptureAudioState()
        {
            Scene active = SceneManager.GetActiveScene();
            AudioSource[] sources = UnityEngine.Object.FindObjectsByType<AudioSource>(
                    FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(source => source != null && source.gameObject.scene == active &&
                                 source.isActiveAndEnabled && source.isPlaying &&
                                 source.clip != null)
                .ToArray();
            return new AudioSemanticState
            {
                PlayingSourceCount = sources.Length,
                LoopingSourceCount = sources.Count(source => source.loop),
                Clips = sources.Select(source => new AudioClipState
                {
                    InstanceId = source.clip.GetInstanceID(),
                    Name = source.clip.name,
                    Loop = source.loop,
                    SourceName = source.gameObject.name
                }).ToList()
            };
        }

        public IEnumerator WaitFor(
            Func<DungeonDuelGameSnapshot, bool> predicate,
            float timeoutSeconds,
            TrajectoryRecorder recorder,
            string stepId,
            string checkId,
            string expected,
            string failureMessage)
        {
            float started = Time.realtimeSinceStartup;
            DungeonDuelGameSnapshot snapshot = Snapshot();
            while ((snapshot == null || !predicate(snapshot)) &&
                   Time.realtimeSinceStartup - started < timeoutSeconds)
            {
                yield return null;
                snapshot = Snapshot();
            }

            TrajectoryStepEvidence step = recorder.Step(stepId);
            step.post_snapshot = recorder.Snapshot(snapshot);
            step.elapsed_ms = (Time.realtimeSinceStartup - started) * 1000.0;
            if (snapshot != null && predicate(snapshot))
            {
                recorder.Pass(stepId, checkId, expected, recorder.Snapshot(snapshot));
            }
            else
            {
                recorder.Fail(stepId, checkId, expected,
                    snapshot == null ? LastObservationFailure ?? "null" : recorder.Snapshot(snapshot),
                    failureMessage);
            }
        }

        public IEnumerator WaitForRestartedScene(
            int oldSceneHandle,
            TrajectoryRecorder recorder,
            string stepId,
            string checkId)
        {
            float deadline = Time.realtimeSinceStartup + 5f;
            DungeonDuelGameSnapshot restarted = null;
            string refreshObservation = "Restart transition not observed";
            while (Time.realtimeSinceStartup < deadline)
            {
                if (TryRefreshFreshRestart(oldSceneHandle, out restarted,
                        out refreshObservation))
                {
                    ValidateAndCacheWorldTargets(recorder, stepId,
                        checkId + ".world_target");
                    break;
                }
                yield return null;
            }

            if (restarted != null && IsFreshEncounter(restarted))
            {
                recorder.Pass(stepId, checkId,
                    "fresh encounter rediscovered after normal Restart input",
                    refreshObservation + "; " + recorder.Snapshot(restarted));
            }
            else
            {
                recorder.Fail(stepId, checkId,
                    "fresh encounter rediscovered after normal Restart input",
                    refreshObservation,
                    "Restart did not reconstruct and rediscover a complete fresh encounter within the timeout.");
            }
        }

        /// <summary>
        /// Activates the public-contract uGUI Restart target through the same
        /// virtual Mouse route used for gameplay. No screen-grid guessing or
        /// direct callback invocation is allowed in v2.
        /// </summary>
        public IEnumerator ActivateVisibleRestartControl(
            int oldSceneHandle,
            TrajectoryRecorder recorder,
            string stepId,
            string visibleCheckId,
            string topHitCheckId,
            string routeCheckId)
        {
            bool structuredFound = TryFindVisibleRestartControl(
                out VisibleUiTarget structured, out string structuredFailure);
            if (!structuredFound)
            {
                recorder.Fail(stepId, visibleCheckId,
                    "visible runtime uGUI Restart control",
                    structuredFailure ?? "not found",
                    "The public v2 UI contract was not satisfied.");
                recorder.Block(stepId, topHitCheckId, visibleCheckId,
                    "No visible uGUI Restart target was available.");
                recorder.Block(stepId, routeCheckId, visibleCheckId,
                    "No normal pointer route could be attempted.");
                yield break;
            }

            var targets = new List<ScreenProbeTarget>
            {
                new ScreenProbeTarget
                {
                    ScreenPosition = structured.ScreenPosition,
                    Observation = structured.Observation
                }
            };
            var capture = new PlayerViewCapture();
            yield return CapturePlayerView(capture);

            var result = new ScreenProbeResult();
            yield return Driver.ClickScreensUntil(
                targets,
                () => TryRefreshFreshRestart(oldSceneHandle, out _, out _),
                recorder,
                stepId,
                routeCheckId,
                result);

            capture.Dispose();
            if (result.Succeeded)
            {
                string observed =
                    $"screen=({result.ScreenPosition.x:F1},{result.ScreenPosition.y:F1}); " +
                    $"attempts={result.Attempts}; source={result.Observation}; " +
                    $"uGuiSemanticTarget=true; overlayPixels={capture.OverlayPixelCount}";
                recorder.Pass(stepId, visibleCheckId,
                    "visible terminal Restart/Retry control with an operable normal pointer route",
                    observed);
                recorder.Pass(stepId, topHitCheckId,
                    "the clicked visible screen target is behaviorally the Restart control",
                    "one normal click at the recorded coordinate produced the complete fresh-state transition");
            }
            else
            {
                string observed =
                    $"uGuiTarget={structuredFound}; targetFailure={structuredFailure}; " +
                    $"overlayPixels={capture.OverlayPixelCount}; attempts={result.Attempts}; " +
                    $"predicateFailure={result.LastPredicateFailure ?? "none"}";
                recorder.Fail(stepId, visibleCheckId,
                    "visible terminal Restart/Retry control with an operable normal pointer route",
                    observed,
                    "The normal click on the public uGUI Restart target did not produce a fresh encounter.");
                recorder.Block(stepId, topHitCheckId, visibleCheckId,
                    "No behavioral Restart hit could be established.");
            }
        }

        bool TryRefreshFreshRestart(
            int oldSceneHandle,
            out DungeonDuelGameSnapshot snapshot,
            out string observation)
        {
            snapshot = null;
            Scene active = SceneManager.GetActiveScene();
            observation = active.IsValid()
                ? $"oldHandle={oldSceneHandle}; activeHandle={active.handle}"
                : "active scene is invalid";
            if (!active.IsValid() || !active.isLoaded)
            {
                return false;
            }

            IDungeonDuelBenchmarkProbe[] probes = FindProbes();
            IDungeonDuelBenchmarkProbe candidateProbe =
                probes.Length == 1 ? probes[0] : null;
            var candidateObserver = new RuntimeSemanticObserver();
            string discoveryFailure = null;
            string snapshotFailure = null;
            bool initialized = candidateObserver.Initialize(
                active, candidateProbe, out discoveryFailure);
            bool captured = initialized && candidateObserver.TryBuildSnapshot(
                out snapshot, out snapshotFailure);
            if (!captured || !IsFreshEncounter(snapshot))
            {
                observation += "; discovery=" +
                    (discoveryFailure ?? snapshotFailure ?? "state is not fresh");
                snapshot = null;
                return false;
            }

            Probe = candidateProbe;
            currentTrajectory = DungeonDuelTrajectoryIntent.CanonicalSuccess;
            semanticObserver = candidateObserver;
            SceneHandle = active.handle;
            verifiedWorldTargets.Clear();
            lastOpaqueHudState = null;
            observation += "; restartMode=" +
                           (active.handle == oldSceneHandle
                               ? "same-scene rebuild"
                               : "scene reload") +
                           "; " + candidateObserver.DiscoverySummary;
            return true;
        }

        static bool IsFreshEncounter(DungeonDuelGameSnapshot snapshot) =>
            snapshot != null && snapshot.Phase == DungeonDuelGamePhase.Playing &&
            snapshot.Player != null && !snapshot.Player.IsDead &&
            Mathf.Abs(snapshot.Player.Health - snapshot.Player.MaxHealth) <= 0.05f &&
            snapshot.ImpsAlive == 2 && snapshot.Boss != null &&
            !snapshot.Boss.IsDead && snapshot.Boss.IsDormant &&
            !snapshot.GateOpen && snapshot.GateBlocking &&
            snapshot.DashCooldownRemaining <= 0.1f;

        public IEnumerator Dispose()
        {
            yield return Driver.Dispose();
            Probe = null;
            SceneHandle = -1;
            semanticObserver = null;
            verifiedWorldTargets.Clear();
            lastOpaqueHudState = null;
        }

        public bool TryFindVisibleRestartControl(
            out VisibleUiTarget target,
            out string failure)
        {
            target = null;
            failure = null;
            VisibleTextRecord[] labels = UiSemanticProbe
                .Capture(SceneManager.GetActiveScene()).Texts
                .Where(item => item != null && IsRestartLabel(item.Text) &&
                               item.Alpha > 0.08f && item.FontSize >= 8f &&
                               item.ScreenRect.width >= 12f &&
                               item.ScreenRect.height >= 8f)
                .OrderByDescending(item => IsExactRestartLabel(item.Text))
                .ThenByDescending(item => item.FontSize)
                .ToArray();

            foreach (VisibleTextRecord label in labels)
            {
                Vector2 screen = label.ScreenRect.center;
                if (screen.x < 0f || screen.x > Screen.width ||
                    screen.y < 0f || screen.y > Screen.height)
                {
                    continue;
                }

                bool hasTopHit = TryRaycastTopUi(
                    screen, out GameObject topHit, out string raycastObservation);
                if (!hasTopHit || topHit.GetComponentInParent<Canvas>() == null)
                {
                    continue;
                }
                target = new VisibleUiTarget
                {
                    ScreenPosition = screen,
                    Label = label.Text,
                    TopHit = topHit,
                    Observation =
                        $"source={label.Source}; label='{label.Text}'; " +
                        $"font={label.FontSize:F1}; alpha={label.Alpha:F2}; " +
                        $"rect={label.ScreenRect}; screen=({screen.x:F1},{screen.y:F1}); " +
                        $"topHit={raycastObservation}"
                };
                return true;
            }

            failure = "No readable runtime uGUI/TMP Restart text with a top GraphicRaycaster hit was found.";
            return false;
        }

        static bool TryRaycastTopUi(
            Vector2 screen,
            out GameObject topHit,
            out string observation)
        {
            topHit = null;
            observation = "no raycast result";
            EventSystem eventSystem = EventSystem.current;
            GameObject temporaryEventSystem = null;
            try
            {
                if (eventSystem == null)
                {
                    temporaryEventSystem = new GameObject(
                        "OmniGame Temporary UI Raycast EventSystem",
                        typeof(EventSystem));
                    temporaryEventSystem.hideFlags =
                        HideFlags.HideAndDontSave;
                    eventSystem = temporaryEventSystem.GetComponent<EventSystem>();
                }

                var pointer = new PointerEventData(eventSystem)
                {
                    position = screen
                };
                var results = new List<RaycastResult>();
                eventSystem.RaycastAll(pointer, results);
                RaycastResult first = results.FirstOrDefault(item =>
                    item.gameObject != null && item.gameObject.activeInHierarchy);
                if (first.gameObject == null)
                {
                    observation = "EventSystem/GraphicRaycaster returned no active result";
                    return false;
                }

                topHit = first.gameObject;
                observation = $"{topHit.name} via {first.module?.GetType().Name ?? "unknown raycaster"}";
                return true;
            }
            finally
            {
                if (temporaryEventSystem != null)
                {
                    UnityEngine.Object.DestroyImmediate(temporaryEventSystem);
                }
            }
        }

        static bool IsRestartLabel(string value)
        {
            string normalized = NormalizeName(value);
            return normalized.Contains("restart") ||
                   normalized.Contains("retry") ||
                   normalized.Contains("playagain") ||
                   normalized.Contains("tryagain") ||
                   (value ?? string.Empty).Contains("Restart") ||
                   (value ?? string.Empty).Contains("Restart");
        }

        static bool IsExactRestartLabel(string value)
        {
            string normalized = NormalizeName(value);
            return normalized == "restart" || normalized == "retry" ||
                   normalized == "playagain" || normalized == "tryagain" ||
                   value == "Restart" || value == "Restart";
        }

        /// <summary>
        /// Captures the actually composited player view for later D6 comparison and
        /// performs a deliberately implementation-neutral D5 feedback probe.  The
        /// probe never looks for a particular Canvas, hierarchy, class, label, or
        /// layout: it only proves that the rendered frame is non-empty and that the
        /// player-facing composite contains meaningful presentation beyond a bare
        /// camera render, and that a live runtime uGUI/TMP Canvas renderer is
        /// present. Pure IMGUI, UI Toolkit and Editor-only UI are outside the
        /// public v2 contract.
        /// </summary>
        public IEnumerator CaptureFeedbackSurface(
            string stateId,
            TrajectoryRecorder recorder,
            string stepId,
            string checkId)
        {
            var capture = new PlayerViewCapture();
            yield return CapturePlayerView(capture);
            try
            {
                Texture2D composite = capture.Composite;
                if (composite == null || composite.width < 64 || composite.height < 64)
                {
                    recorder.Fail(stepId, checkId,
                        "a non-empty composited player view with visible feedback",
                        composite == null ? "no screenshot" :
                            $"{composite.width}x{composite.height}; {capture.Error}",
                        "The running game did not expose a captureable player-facing frame.");
                    yield break;
                }

                Color32[] compositePixels = composite.GetPixels32();
                int nonUniformPixels = CountNonDominantPixels(compositePixels);
                bool visibleCanvas = UnityEngine.Object
                    .FindObjectsByType<CanvasRenderer>(
                        FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Any(renderer => renderer != null && !renderer.cull &&
                                     renderer.GetAlpha() > 0.01f &&
                                     renderer.gameObject.activeInHierarchy);
                bool valid = nonUniformPixels >= 128 && visibleCanvas;

                string directory = Path.Combine(
                    FindTrajectoryOutputDirectory(), "visual-candidates");
                Directory.CreateDirectory(directory);
                string path = Path.Combine(directory, stateId + ".png");
                File.WriteAllBytes(path, composite.EncodeToPNG());

                string observed =
                    $"{composite.width}x{composite.height}; nonUniform={nonUniformPixels}; " +
                    $"runtimeCanvas={visibleCanvas}; " +
                    $"compositedBackbuffer={capture.CapturedBackbuffer}; " +
                    $"overlayPixels={capture.OverlayPixelCount}; " +
                    $"overlayBounds={capture.OverlayBounds}; file={path}; " +
                    $"captureDiagnostic={capture.Error ?? "none"}";
                if (valid)
                {
                    recorder.Pass(stepId, checkId,
                        "non-empty composited frame with player-facing feedback", observed);
                }
                else
                {
                    recorder.Fail(stepId, checkId,
                        "non-empty composited frame with player-facing feedback", observed,
                        "The gameplay rendered, but no meaningful HUD/result feedback surface " +
                        "could be distinguished from the bare world view.");
                }
            }
            finally
            {
                capture.Dispose();
            }
        }

        public IEnumerator ValidateHudSemantics(
            DungeonDuelGameSnapshot state,
            HudSemanticState expectation,
            TrajectoryRecorder recorder,
            string stepId,
            string checkId)
        {
            yield return null;
            UiSemanticSnapshot ui = UiSemanticProbe.Capture(
                SceneManager.GetActiveScene());
            if (UiSemanticProbe.Validate(ui, state, expectation, out string failure))
            {
                recorder.Pass(stepId, checkId,
                    $"visible semantic HUD synchronized for {expectation}",
                    ui.Describe());
                lastOpaqueHudState = null;
            }
            else
            {
                recorder.Fail(stepId, checkId,
                    $"visible runtime uGUI/TMP HUD synchronized for {expectation}",
                    (ui?.Describe() ?? "missing") + "; " + failure,
                    "The candidate did not satisfy the public v2 structured runtime UI contract.");
            }
        }

        IEnumerator CapturePlayerView(PlayerViewCapture capture)
        {
            if (capture == null) yield break;

            // WaitForEndOfFrame does not resume reliably in headless Editor
            // PlayMode. A late-execution evaluator capture reads the composited
            // backbuffer during a repaint; deterministic Camera.Render remains
            // as a bounded diagnostic fallback.
            yield return null;
            int screenWidth = Math.Max(1, Screen.width);
            int screenHeight = Math.Max(1, Screen.height);
            GameObject probeObject = null;
            PlayerViewBackbufferProbe probe = null;
            try
            {
                if (screenWidth >= 64 && screenHeight >= 64)
                {
                    probeObject = new GameObject("Evaluator Player View Capture Probe");
                    probeObject.hideFlags = HideFlags.HideAndDontSave;
                    probe = probeObject.AddComponent<PlayerViewBackbufferProbe>();
                    probe.Begin(screenWidth, screenHeight);
                }
            }
            catch (Exception exception)
            {
                capture.Error = "backbuffer probe " + exception.GetType().Name +
                                ": " + exception.Message;
            }

            if (probe != null)
            {
                for (int frame = 0; frame < 6 && !probe.Completed; frame++)
                {
                    // Batch-mode PlayMode does not keep an Editor Game view repainting
                    // continuously. Request the real PlayMode view repaint explicitly
                    // so the late probe can observe the composited framebuffer.
                    if (!RequestEditorPlayerViewRepaint(out string repaintDiagnostic) &&
                        string.IsNullOrWhiteSpace(capture.Error))
                    {
                        capture.Error = repaintDiagnostic;
                    }
                    yield return null;
                }
                capture.Composite = probe.TakeCapture();
                capture.CapturedBackbuffer = capture.Composite != null;
                if (!string.IsNullOrWhiteSpace(probe.Error))
                {
                    capture.Error = (capture.Error == null ? string.Empty : capture.Error + "; ") +
                                    probe.Error;
                }
                if (!probe.Completed)
                {
                    capture.Error = (capture.Error == null ? string.Empty : capture.Error + "; ") +
                                    "no player-view repaint observed within six frames";
                }
            }
            if (probeObject != null) UnityEngine.Object.Destroy(probeObject);
            yield return null;

            Camera camera = Camera.main ?? UnityEngine.Object
                .FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
            int renderWidth = capture.Composite == null
                ? Math.Max(640, screenWidth)
                : capture.Composite.width;
            int renderHeight = capture.Composite == null
                ? Math.Max(360, screenHeight)
                : capture.Composite.height;
            try
            {
                capture.CameraOnly = camera == null
                    ? null
                    : CaptureCamera(camera, renderWidth, renderHeight);
            }
            catch (Exception exception)
            {
                capture.Error = (capture.Error == null ? string.Empty : capture.Error + "; ") +
                                "camera " + exception.GetType().Name + ": " +
                                exception.Message;
            }

            if (capture.Composite == null && capture.CameraOnly != null)
            {
                capture.Composite = capture.CameraOnly;
                capture.CameraOnly = null;
            }
            capture.AnalyzeOverlay();
        }

        static bool RequestEditorPlayerViewRepaint(out string diagnostic)
        {
#if UNITY_EDITOR
            try
            {
                bool invoked = false;
                foreach (var request in new[]
                {
                    new
                    {
                        TypeName = "UnityEditor.PlayModeView, UnityEditor",
                        MethodName = "RepaintAll"
                    },
                    new
                    {
                        TypeName = "UnityEditorInternal.InternalEditorUtility, UnityEditor",
                        MethodName = "RepaintAllViews"
                    }
                })
                {
                    Type type = Type.GetType(request.TypeName, false);
                    var method = type?.GetMethod(
                        request.MethodName,
                        System.Reflection.BindingFlags.Static |
                        System.Reflection.BindingFlags.Public |
                        System.Reflection.BindingFlags.NonPublic);
                    if (method == null) continue;
                    method.Invoke(null, null);
                    invoked = true;
                }

                diagnostic = invoked
                    ? null
                    : "no Editor PlayMode repaint API was available";
                return invoked;
            }
            catch (Exception exception)
            {
                diagnostic = "Editor PlayMode repaint " +
                             exception.GetType().Name + ": " + exception.Message;
                return false;
            }
#else
            diagnostic = "Editor PlayMode repaint unavailable outside the Editor";
            return false;
#endif
        }

        static bool StateMatchesHudExpectation(
            DungeonDuelGameSnapshot state,
            HudSemanticState expectation)
        {
            if (state == null || state.Player == null || state.Boss == null)
                return false;
            switch (expectation)
            {
                case HudSemanticState.Initial:
                case HudSemanticState.Restarted:
                    return IsFreshEncounter(state);
                case HudSemanticState.CombatDamage:
                    return state.Player.Health < state.Player.MaxHealth - 0.01f ||
                           (state.ImpA != null &&
                            state.ImpA.Health < state.ImpA.MaxHealth - 0.01f) ||
                           (state.ImpB != null &&
                            state.ImpB.Health < state.ImpB.MaxHealth - 0.01f) ||
                           state.Boss.Health < state.Boss.MaxHealth - 0.01f;
                case HudSemanticState.GateLocked:
                    return state.Phase == DungeonDuelGamePhase.Playing &&
                           state.ImpsAlive >= 1 && !state.GateOpen &&
                           state.GateBlocking && state.Boss.IsDormant;
                case HudSemanticState.GateOpen:
                    return state.Phase == DungeonDuelGamePhase.Playing &&
                           state.ImpsAlive == 0 && state.GateOpen &&
                           !state.GateBlocking && !state.Boss.IsDormant;
                case HudSemanticState.DashCooldown:
                    return state.Phase == DungeonDuelGamePhase.Playing &&
                           state.DashCooldownRemaining > 0.1f;
                case HudSemanticState.DashReady:
                    return state.Phase == DungeonDuelGamePhase.Playing &&
                           state.DashCooldownRemaining <= 0.1f;
                case HudSemanticState.Victory:
                    return state.Phase == DungeonDuelGamePhase.Won;
                case HudSemanticState.Defeat:
                    return state.Phase == DungeonDuelGamePhase.Lost &&
                           state.Player.IsDead;
                default:
                    return false;
            }
        }

        static string BuildHudStateSignature(
            DungeonDuelGameSnapshot state,
            HudSemanticState expectation)
        {
            if (state == null) return expectation + ":null";
            return $"{expectation};phase={state.Phase};" +
                   $"player={state.Player?.Health:F1}/{state.Player?.MaxHealth:F1};" +
                   $"impA={state.ImpA?.Health:F1};impB={state.ImpB?.Health:F1};" +
                   $"imps={state.ImpsAlive};gate={state.GateOpen}/{state.GateBlocking};" +
                   $"bossDormant={state.Boss?.IsDormant};" +
                   $"dash={state.DashCooldownRemaining:F1}";
        }

        internal static IEnumerable<ScreenProbeTarget> BuildGenericBehavioralScreenTargets() =>
            BuildBehavioralScreenTargets(null);

        static IEnumerable<ScreenProbeTarget> BuildBehavioralScreenTargets(
            PlayerViewCapture capture)
        {
            var targets = new List<ScreenProbeTarget>();
            if (capture != null)
            {
                targets.AddRange(capture.OverlayCellCenters.Select(point =>
                    new ScreenProbeTarget
                    {
                        ScreenPosition = point,
                        Observation = "composited overlay cell"
                    }));

                if (capture.OverlayBounds.width > 1f &&
                    capture.OverlayBounds.height > 1f)
                {
                    float[] fractions = { 0.5f, 0.35f, 0.65f, 0.2f, 0.8f };
                    foreach (float y in fractions)
                    foreach (float x in fractions)
                    {
                        targets.Add(new ScreenProbeTarget
                        {
                            ScreenPosition = new Vector2(
                                Mathf.Lerp(capture.OverlayBounds.xMin,
                                    capture.OverlayBounds.xMax, x),
                                Mathf.Lerp(capture.OverlayBounds.yMin,
                                    capture.OverlayBounds.yMax, y)),
                            Observation = "normalized composited-overlay bounds"
                        });
                    }
                }
            }

            // Center-prioritized normalized coverage catches common terminal
            // cards without prescribing any concrete framework or pixel layout.
            float[] centerX = { 0.5f, 0.4f, 0.6f, 0.3f, 0.7f };
            float[] centerY = { 0.42f, 0.35f, 0.5f, 0.28f, 0.58f, 0.65f };
            foreach (float y in centerY)
            foreach (float x in centerX)
            {
                targets.Add(new ScreenProbeTarget
                {
                    ScreenPosition = new Vector2(Screen.width * x, Screen.height * y),
                    Observation = "center-prioritized normalized terminal probe"
                });
            }

            const int columns = 11;
            const int rows = 9;
            for (int row = 0; row < rows; row++)
            for (int column = 0; column < columns; column++)
            {
                float x = Mathf.Lerp(0.06f, 0.94f, column / (columns - 1f));
                float y = Mathf.Lerp(0.06f, 0.94f, row / (rows - 1f));
                targets.Add(new ScreenProbeTarget
                {
                    ScreenPosition = new Vector2(Screen.width * x, Screen.height * y),
                    Observation = "bounded full-screen normalized fallback"
                });
            }
            return targets;
        }

        void ValidateAndCacheWorldTargets(
            TrajectoryRecorder recorder,
            string stepId,
            string checkPrefix)
        {
            verifiedWorldTargets.Clear();
            foreach (DungeonDuelWorldTargetId targetId in new[]
            {
                DungeonDuelWorldTargetId.MoveTargetA,
                DungeonDuelWorldTargetId.MoveTargetB,
                DungeonDuelWorldTargetId.DashTarget
            })
            {
                if (TryObserveWorldTarget(targetId, out Vector3 target,
                        out string observation, out string failure))
                {
                    verifiedWorldTargets[targetId] = target;
                    recorder.Pass(stepId, checkPrefix + "." + targetId,
                        "independently camera-validated gameplay-space target",
                        observation);
                }
                else
                {
                    recorder.Fail(stepId, checkPrefix + "." + targetId,
                        "independently camera-validated gameplay-space target",
                        observation,
                        failure);
                }
            }

            if (verifiedWorldTargets.TryGetValue(
                    DungeonDuelWorldTargetId.MoveTargetA, out Vector3 targetA) &&
                verifiedWorldTargets.TryGetValue(
                    DungeonDuelWorldTargetId.MoveTargetB, out Vector3 targetB))
            {
                float separation = HorizontalDistance(targetA, targetB);
                if (separation >= 4f)
                {
                    recorder.Pass(stepId, checkPrefix + ".separation",
                        "MoveTargetA and MoveTargetB separated by at least 4m",
                        separation.ToString("F2") + "m");
                }
                else
                {
                    recorder.Fail(stepId, checkPrefix + ".separation",
                        "MoveTargetA and MoveTargetB separated by at least 4m",
                        separation.ToString("F2") + "m",
                        "The evaluator could not discover two meaningfully separated navigation targets.");
                }
            }
        }

        bool TryObserveWorldTarget(
            DungeonDuelWorldTargetId targetId,
            out Vector3 target,
            out string observation,
            out string failure)
        {
            target = Vector3.zero;
            observation = "missing";
            failure = null;
            try
            {
                var candidates = new List<(Vector3 point, string source)>();
                if (Probe != null)
                {
                    try
                    {
                        Vector3 hinted = Probe.GetWorldTargetPosition(targetId);
                        if (IsFinite(hinted)) candidates.Add((hinted, "public probe hint"));
                    }
                    catch
                    {
                        // A bad hint is non-fatal here; native spatial candidates
                        // still have to pass physics and reachability validation.
                    }
                }

                GameObject playerObject = ActorTarget(DungeonDuelActorId.Player);
                GameObject bossObject = ActorTarget(DungeonDuelActorId.Boss);
                if (playerObject == null || bossObject == null)
                {
                    failure = "Native actor discovery was unavailable while sampling targets.";
                    return false;
                }
                Vector3 origin = playerObject.transform.position;
                Vector3 forward = bossObject.transform.position - origin;
                forward.y = 0f;
                if (forward.sqrMagnitude < 0.01f) forward = Vector3.right;
                forward.Normalize();
                Vector3 side = new Vector3(-forward.z, 0f, forward.x);
                if (targetId == DungeonDuelWorldTargetId.MoveTargetA)
                {
                    candidates.Add((origin + forward * 5f, "native spatial sample"));
                    candidates.Add((origin + forward * 4f + side * 1.5f, "native spatial sample"));
                    candidates.Add((origin + forward * 3.5f - side * 1.5f, "native spatial sample"));
                }
                else if (targetId == DungeonDuelWorldTargetId.MoveTargetB)
                {
                    candidates.Add((origin + forward * 2f + side * 6f, "native spatial sample"));
                    candidates.Add((origin + forward * 2f - side * 6f, "native spatial sample"));
                    candidates.Add((origin + forward * 5f + side * 5f, "native spatial sample"));
                }
                else
                {
                    candidates.Add((origin + forward * 4.5f, "native spatial sample"));
                    candidates.Add((origin + forward * 4f + side, "native spatial sample"));
                    candidates.Add((origin + forward * 3.5f - side, "native spatial sample"));
                }

                Camera camera = Camera.main;
                if (camera != null)
                {
                    Vector2[] viewportSamples = targetId switch
                    {
                        DungeonDuelWorldTargetId.MoveTargetA => new[]
                        {
                            new Vector2(0.52f, 0.42f),
                            new Vector2(0.42f, 0.40f),
                            new Vector2(0.62f, 0.40f)
                        },
                        DungeonDuelWorldTargetId.MoveTargetB => new[]
                        {
                            new Vector2(0.72f, 0.42f),
                            new Vector2(0.28f, 0.42f),
                            new Vector2(0.68f, 0.55f),
                            new Vector2(0.32f, 0.55f)
                        },
                        _ => new[]
                        {
                            new Vector2(0.58f, 0.42f),
                            new Vector2(0.46f, 0.38f),
                            new Vector2(0.64f, 0.48f)
                        }
                    };
                    foreach (Vector2 viewport in viewportSamples)
                    {
                        if (TryViewportGroundPlanePoint(camera, viewport, origin.y,
                                out Vector3 planePoint))
                        {
                            candidates.Add((planePoint, "camera screen-plane sample"));
                        }
                    }
                }

                var rejected = new List<string>();
                foreach ((Vector3 point, string source) in candidates)
                {
                    if (targetId == DungeonDuelWorldTargetId.MoveTargetB &&
                        verifiedWorldTargets.TryGetValue(
                            DungeonDuelWorldTargetId.MoveTargetA, out Vector3 targetA) &&
                        HorizontalDistance(point, targetA) < 4f)
                    {
                        rejected.Add($"{source}:{point:F2} too close to target A");
                        continue;
                    }
                    if (TryValidateGroundTarget(point, out target,
                            out string detail, out string rejectedReason))
                    {
                        observation = $"trajectory={currentTrajectory}; source={source}; {detail}";
                        return true;
                    }
                    rejected.Add($"{source}:{point:F2} {rejectedReason}");
                }

                observation = string.Join(" | ", rejected.Take(10));
                failure = "No finite camera-visible gameplay-space target could be discovered.";
                return false;
            }
            catch (Exception exception)
            {
                observation = exception.GetType().Name;
                failure = "World-target verification threw: " + exception.Message;
                return false;
            }
        }

        bool TryValidateGroundTarget(
            Vector3 desired,
            out Vector3 target,
            out string observation,
            out string failure)
        {
            target = desired;
            observation = "missing";
            failure = null;
            if (!IsFinite(desired))
            {
                failure = "target is not finite";
                return false;
            }

            Camera camera = Camera.main ?? UnityEngine.Object
                .FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
            if (camera == null)
            {
                failure = "no enabled gameplay camera";
                return false;
            }

            GameObject player = ActorTarget(DungeonDuelActorId.Player);
            float groundY = player == null ? desired.y : player.transform.position.y;
            Vector3 candidate = desired;
            bool navHit = NavMesh.SamplePosition(
                desired, out NavMeshHit navSample, 2f, NavMesh.AllAreas);
            if (navHit && HorizontalDistance(desired, navSample.position) <= 2f)
            {
                candidate = navSample.position;
            }
            else
            {
                Vector3 desiredScreen = camera.WorldToScreenPoint(desired);
                if (desiredScreen.z > 0f)
                {
                    var plane = new Plane(Vector3.up, new Vector3(0f, groundY, 0f));
                    Ray desiredRay = camera.ScreenPointToRay(desiredScreen);
                    if (plane.Raycast(desiredRay, out float distance))
                    {
                        Vector3 planePoint = desiredRay.GetPoint(distance);
                        if (IsFinite(planePoint)) candidate = planePoint;
                    }
                }
            }

            Vector3 viewport = camera.WorldToViewportPoint(candidate + Vector3.up * 0.08f);
            if (viewport.z <= 0f || viewport.x < 0.03f ||
                viewport.x > 0.97f || viewport.y < 0.03f || viewport.y > 0.97f)
            {
                failure = "target is outside the live gameplay camera";
                return false;
            }

            Vector2 screen = new Vector2(viewport.x * Screen.width,
                viewport.y * Screen.height);
            bool physicsHit = Physics.Raycast(camera.ScreenPointToRay(screen),
                out RaycastHit physics, 250f, ~0, QueryTriggerInteraction.Ignore);
            target = candidate;
            observation =
                $"target={target:F2}; sourceDelta={HorizontalDistance(desired, target):F2}m; " +
                $"viewport={viewport:F3}; " +
                (navHit ? $"optionalNavMesh={navSample.position:F2}" :
                    "optionalNavMesh=<none>") + "; " +
                (physicsHit ? $"optionalPhysics={physics.collider.name}@{physics.point:F2}" :
                    "optionalPhysics=<none>") +
                $"; screenPlaneY={groundY:F2}";
            return true;
        }

        static bool TryViewportGroundPlanePoint(
            Camera camera,
            Vector2 viewport,
            float groundY,
            out Vector3 point)
        {
            point = default;
            if (camera == null) return false;
            Ray ray = camera.ViewportPointToRay(
                new Vector3(viewport.x, viewport.y, 0f));
            var plane = new Plane(Vector3.up, new Vector3(0f, groundY, 0f));
            if (!plane.Raycast(ray, out float distance) || distance <= 0f)
            {
                return false;
            }
            point = ray.GetPoint(distance);
            return IsFinite(point);
        }

        static string NormalizeName(string value) =>
            new string((value ?? string.Empty).Where(char.IsLetterOrDigit)
                .Select(char.ToLowerInvariant).ToArray());

        static bool IsFinite(Vector3 value) =>
            !float.IsNaN(value.x) && !float.IsInfinity(value.x) &&
            !float.IsNaN(value.y) && !float.IsInfinity(value.y) &&
            !float.IsNaN(value.z) && !float.IsInfinity(value.z);

        static float HorizontalDistance(Vector3 left, Vector3 right) =>
            Vector2.Distance(new Vector2(left.x, left.z), new Vector2(right.x, right.z));

        static Texture2D CaptureCamera(Camera camera, int width, int height)
        {
            var renderTexture = new RenderTexture(
                width, height, 24, RenderTextureFormat.ARGB32);
            var texture = new Texture2D(
                width, height, TextureFormat.RGBA32, false);
            RenderTexture previousActive = RenderTexture.active;
            RenderTexture previousTarget = camera.targetTexture;
            try
            {
                camera.targetTexture = renderTexture;
                renderTexture.Create();
                camera.Render();
                RenderTexture.active = renderTexture;
                texture.ReadPixels(new Rect(0f, 0f, width, height), 0, 0, false);
                texture.Apply(false, false);
                return texture;
            }
            finally
            {
                camera.targetTexture = previousTarget;
                RenderTexture.active = previousActive;
                renderTexture.Release();
                UnityEngine.Object.DestroyImmediate(renderTexture);
            }
        }

        static int CountNonDominantPixels(Color32[] pixels)
        {
            if (pixels == null || pixels.Length == 0) return 0;
            int dominant = pixels
                .GroupBy(pixel => ((pixel.r >> 4) << 8) |
                                  ((pixel.g >> 4) << 4) |
                                  (pixel.b >> 4))
                .Max(group => group.Count());
            return pixels.Length - dominant;
        }

        static string FindTrajectoryOutputDirectory()
        {
            string[] args = Environment.GetCommandLineArgs();
            foreach (string key in new[]
            {
                "-omnigameTrajectoryOutput",
                "-omnigameDungeonDuelTrajectoryOutput"
            })
            {
                for (int index = 0; index < args.Length - 1; index++)
                {
                    if (string.Equals(args[index], key,
                            StringComparison.OrdinalIgnoreCase))
                    {
                        return args[index + 1].Trim('"');
                    }
                }
            }
            return Path.Combine(
                Path.GetDirectoryName(Application.dataPath) ?? ".",
                "BenchmarkResults", "dungeon-duel-trajectory-evidence");
        }

        internal sealed class VisibleUiTarget
        {
            public Vector2 ScreenPosition;
            public string Label;
            public GameObject TopHit;
            public string Observation;
        }

        sealed class OpaqueHudState
        {
            public string StateSignature;
            public ulong OverlayFingerprint;
            public int OverlayPixelCount;
        }

        sealed class PlayerViewCapture : IDisposable
        {
            public Texture2D Composite;
            public Texture2D CameraOnly;
            public bool CapturedBackbuffer;
            public int OverlayPixelCount;
            public Rect OverlayBounds;
            public ulong OverlayFingerprint;
            public string Error;
            public List<Vector2> OverlayCellCenters { get; } =
                new List<Vector2>();

            public void AnalyzeOverlay()
            {
                OverlayPixelCount = 0;
                OverlayBounds = default;
                OverlayFingerprint = 0UL;
                OverlayCellCenters.Clear();
                if (Composite == null || CameraOnly == null ||
                    Composite.width != CameraOnly.width ||
                    Composite.height != CameraOnly.height)
                {
                    return;
                }

                Color32[] composite = Composite.GetPixels32();
                Color32[] camera = CameraOnly.GetPixels32();
                int width = Composite.width;
                int height = Composite.height;
                int minX = width;
                int minY = height;
                int maxX = -1;
                int maxY = -1;
                const int columns = 12;
                const int rows = 8;
                var cells = new int[columns * rows];
                ulong hash = 1469598103934665603UL;
                for (int index = 0; index < composite.Length; index++)
                {
                    Color32 left = composite[index];
                    Color32 right = camera[index];
                    int difference = Math.Abs(left.r - right.r) +
                                     Math.Abs(left.g - right.g) +
                                     Math.Abs(left.b - right.b);
                    if (difference < 42) continue;

                    int x = index % width;
                    int y = index / width;
                    OverlayPixelCount++;
                    minX = Math.Min(minX, x);
                    minY = Math.Min(minY, y);
                    maxX = Math.Max(maxX, x);
                    maxY = Math.Max(maxY, y);
                    int column = Math.Min(columns - 1, x * columns / width);
                    int row = Math.Min(rows - 1, y * rows / height);
                    cells[row * columns + column]++;

                    hash ^= (ulong)(index + 1);
                    hash *= 1099511628211UL;
                    hash ^= (ulong)((left.r << 16) | (left.g << 8) | left.b);
                    hash *= 1099511628211UL;
                }

                if (OverlayPixelCount == 0) return;
                OverlayFingerprint = hash;
                OverlayBounds = Rect.MinMaxRect(
                    minX, minY, maxX + 1f, maxY + 1f);
                int cellWidth = Math.Max(1, width / columns);
                int cellHeight = Math.Max(1, height / rows);
                int minimumCellPixels = Math.Max(16,
                    Mathf.RoundToInt(cellWidth * cellHeight * 0.003f));
                var centers = new List<Vector2>();
                for (int row = 0; row < rows; row++)
                for (int column = 0; column < columns; column++)
                {
                    if (cells[row * columns + column] < minimumCellPixels) continue;
                    centers.Add(new Vector2(
                        (column + 0.5f) * width / columns,
                        (row + 0.5f) * height / rows));
                }
                Vector2 screenCenter = new Vector2(width * 0.5f, height * 0.5f);
                OverlayCellCenters.AddRange(centers
                    .OrderBy(point => Vector2.SqrMagnitude(point - screenCenter)));
            }

            public void Dispose()
            {
                if (Composite != null)
                {
                    UnityEngine.Object.DestroyImmediate(Composite);
                    Composite = null;
                }
                if (CameraOnly != null)
                {
                    UnityEngine.Object.DestroyImmediate(CameraOnly);
                    CameraOnly = null;
                }
            }
        }

        internal sealed class AudioClipState
        {
            public int InstanceId;
            public string Name;
            public bool Loop;
            public string SourceName;

            public override string ToString() =>
                $"{SourceName}:{Name}#{InstanceId},loop={Loop}";
        }

        internal sealed class AudioSemanticState
        {
            public int PlayingSourceCount;
            public int LoopingSourceCount;
            public List<AudioClipState> Clips = new List<AudioClipState>();

            public bool HasLoopingBattle => PlayingSourceCount > 0 &&
                                            LoopingSourceCount > 0 &&
                                            Clips.Any(clip => clip.Loop);

            public bool HasTransitionFrom(AudioSemanticState initial) =>
                initial != null && Clips.Any(current => initial.Clips.Any(previous =>
                    current.InstanceId != previous.InstanceId ||
                    (previous.Loop && !current.Loop)));

            public bool HasRestoredBattle(AudioSemanticState initial) =>
                initial != null && Clips.Any(current => current.Loop &&
                    initial.Clips.Any(previous => previous.Loop &&
                        (previous.InstanceId == current.InstanceId ||
                         string.Equals(previous.Name, current.Name,
                             StringComparison.OrdinalIgnoreCase))));

            public override string ToString() =>
                $"playing={PlayingSourceCount}, looping={LoopingSourceCount}; " +
                string.Join(" | ", Clips.Select(clip => clip.ToString()));
        }

        static IDungeonDuelBenchmarkProbe[] FindProbes() =>
            UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Include,
                    FindObjectsSortMode.None)
                .Where(item => item != null && item.isActiveAndEnabled)
                .OfType<IDungeonDuelBenchmarkProbe>()
                .ToArray();
    }

    [DefaultExecutionOrder(32000)]
    internal sealed class PlayerViewBackbufferProbe : MonoBehaviour
    {
        Texture2D captured;
        int width;
        int height;
        bool pending;

        public bool Completed { get; private set; }
        public string Error { get; private set; }

        public void Begin(int requestedWidth, int requestedHeight)
        {
            width = Math.Max(1, requestedWidth);
            height = Math.Max(1, requestedHeight);
            pending = true;
            Completed = false;
            Error = null;
        }

        void OnGUI()
        {
            if (!pending || Completed || Event.current == null ||
                Event.current.type != EventType.Repaint)
            {
                return;
            }

            try
            {
                captured = new Texture2D(width, height, TextureFormat.RGBA32, false);
                captured.ReadPixels(new Rect(0f, 0f, width, height), 0, 0, false);
                captured.Apply(false, false);
            }
            catch (Exception exception)
            {
                if (captured != null)
                {
                    UnityEngine.Object.DestroyImmediate(captured);
                    captured = null;
                }
                Error = "backbuffer Repaint " + exception.GetType().Name +
                        ": " + exception.Message;
            }
            finally
            {
                pending = false;
                Completed = true;
            }
        }

        public Texture2D TakeCapture()
        {
            Texture2D result = captured;
            captured = null;
            return result;
        }

        void OnDestroy()
        {
            if (captured != null) UnityEngine.Object.DestroyImmediate(captured);
        }
    }
}



