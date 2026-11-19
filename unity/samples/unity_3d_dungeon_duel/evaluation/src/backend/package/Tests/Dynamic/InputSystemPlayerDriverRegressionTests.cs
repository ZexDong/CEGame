using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System;
using NUnit.Framework;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using Object = UnityEngine.Object;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    [TestFixture]
    public sealed class InputSystemPlayerDriverRegressionTests
    {
        [UnityTest, Order(-120)]
        public IEnumerator EVALUATOR_HEALTH_Dynamic_KeyboardRouteRetainsInputActionDiagnostics()
        {
            using var action = new InputAction(
                "RegressionDash", InputActionType.Button, "<Keyboard>/2");
            action.Enable();

            var driver = new InputSystemPlayerDriver();
            var recorder = new TrajectoryRecorder("dash_gate");
            yield return driver.PressKey(Key.Digit2, recorder,
                "dash_one", "dash.first.input.route");

            TrajectoryStepEvidence step = recorder.Step("dash_one");
            Assert.That(step.checks.Single(check =>
                check.check_id == "dash.first.input.route").status, Is.EqualTo("pass"));
            Assert.That(step.input_action_events.Any(item =>
                    item.phase == "performed" &&
                    item.action == "RegressionDash" &&
                    item.control_path.EndsWith("/2")),
                Is.True,
                "When a candidate uses InputAction, the optional callback diagnostic should remain available.");

            yield return driver.Dispose();
        }

        [UnityTest, Order(-110)]
        public IEnumerator EVALUATOR_HEALTH_Dynamic_MousePhysicsRouteUsesVisibleActorSurface()
        {
            using var action = new InputAction(
                "RegressionAttack", InputActionType.Button, "<Mouse>/rightButton");
            action.Enable();

            GameObject hijackerObject = new GameObject(
                "Candidate Camera.main Hijacker Regression",
                typeof(CameraMainHijackerFixture));
            CameraMainHijackerFixture hijacker =
                hijackerObject.GetComponent<CameraMainHijackerFixture>();
            int hijacksBeforeIsolation = hijacker.HijackCount;
            var isolation = new EvaluatorHealthSceneIsolation(
                "Evaluator Mouse Physics Health Fixture");

            GameObject cameraObject = new GameObject("ActorSamplingCamera", typeof(Camera));
            isolation.Move(cameraObject);
            cameraObject.tag = "MainCamera";
            Camera camera = cameraObject.GetComponent<Camera>();
            camera.orthographic = true;
            camera.orthographicSize = 4f;
            cameraObject.transform.position = new Vector3(1000f, 1000f, -10f);
            Vector3 expectedCameraPosition = cameraObject.transform.position;

            GameObject target = new GameObject("ActorSamplingTarget", typeof(BoxCollider));
            isolation.Move(target);
            target.transform.position = new Vector3(1000f, 1000f, 0f);
            target.GetComponent<BoxCollider>().size = new Vector3(4f, 2f, 1f);
            GameObject blocker = new GameObject("ActorCenterBlocker", typeof(BoxCollider));
            isolation.Move(blocker);
            blocker.transform.position = new Vector3(1000f, 1000f, -1f);
            blocker.GetComponent<BoxCollider>().size = new Vector3(1f, 2.4f, 0.5f);
            Physics.SyncTransforms();
            yield return null;

            var driver = new InputSystemPlayerDriver();
            var recorder = new TrajectoryRecorder("combat_loop");
            yield return driver.ClickActor(target, MouseButton.Right, recorder,
                "attack_one", "combat.attack.input.route");

            TrajectoryStepEvidence step = recorder.Step("attack_one");
            string routeStatus = step.checks.Single(check =>
                check.check_id == "combat.attack.input.route").status;
            string topHit = step.top_hit;
            float screenX = step.screen_x;
            bool attackPerformed = step.input_action_events.Any(item =>
                item.phase == "performed" && item.action == "RegressionAttack");
            int hijacksDuringIsolation = hijacker.HijackCount;
            Vector3 cameraPositionAfterRoute = cameraObject.transform.position;

            yield return driver.Dispose();
            Object.Destroy(hijackerObject);
            yield return null;
            yield return isolation.Restore();

            Assert.That(routeStatus, Is.EqualTo("pass"));
            Assert.That(topHit, Does.Contain("ActorSamplingTarget"));
            Assert.That(Mathf.Abs(screenX - Screen.width * 0.5f), Is.GreaterThan(5f),
                "The chosen world-space actor point must move away from its occluded center.");
            Assert.That(attackPerformed, Is.True);
            Assert.That(hijacksDuringIsolation, Is.EqualTo(hijacksBeforeIsolation),
                "A candidate-scene MonoBehaviour was still updating and could hijack Camera.main.");
            Assert.That(Vector3.Distance(cameraPositionAfterRoute, expectedCameraPosition),
                Is.LessThan(0.001f),
                "The isolated evaluator camera was moved by candidate-scene behavior.");
        }

        [UnityTest, Order(-100)]
        public IEnumerator EVALUATOR_HEALTH_Dynamic_NavMeshWorldRouteUsesRealPhysicsAndInput()
        {
            using var action = new InputAction(
                "EvaluatorHealthMove", InputActionType.Button, "<Mouse>/leftButton");
            action.Enable();

            GameObject hijackerObject = new GameObject(
                "Candidate Camera.main Hijacker NavMesh Regression",
                typeof(CameraMainHijackerFixture));
            CameraMainHijackerFixture hijacker =
                hijackerObject.GetComponent<CameraMainHijackerFixture>();
            int hijacksBeforeIsolation = hijacker.HijackCount;
            var isolation = new EvaluatorHealthSceneIsolation(
                "Evaluator NavMesh Health Fixture");

            const float origin = 2400f;
            GameObject cameraObject = new GameObject(
                "Evaluator Health NavMesh Camera", typeof(Camera));
            isolation.Move(cameraObject);
            cameraObject.tag = "MainCamera";
            Camera camera = cameraObject.GetComponent<Camera>();
            camera.orthographic = true;
            camera.orthographicSize = 6f;
            cameraObject.transform.position = new Vector3(origin, 12f, origin);
            cameraObject.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            Vector3 expectedCameraPosition = cameraObject.transform.position;

            GameObject floor = GameObject.CreatePrimitive(PrimitiveType.Cube);
            isolation.Move(floor);
            floor.name = "Evaluator Health NavMesh Floor";
            floor.transform.position = new Vector3(origin, -0.1f, origin);
            floor.transform.localScale = new Vector3(10f, 0.2f, 10f);

            NavMeshBuildSettings settings = NavMesh.GetSettingsByID(0);
            var sources = new List<NavMeshBuildSource>
            {
                new NavMeshBuildSource
                {
                    shape = NavMeshBuildSourceShape.Box,
                    size = new Vector3(10f, 0.2f, 10f),
                    transform = Matrix4x4.TRS(
                        new Vector3(origin, -0.1f, origin),
                        Quaternion.identity, Vector3.one),
                    area = 0
                }
            };
            NavMeshData data = NavMeshBuilder.BuildNavMeshData(
                settings, sources,
                new Bounds(new Vector3(origin, 0f, origin), new Vector3(20f, 5f, 20f)),
                Vector3.zero, Quaternion.identity);
            NavMeshDataInstance instance = default;
            if (data != null) instance = NavMesh.AddNavMeshData(data);
            Physics.SyncTransforms();
            yield return null;

            var driver = new InputSystemPlayerDriver();
            var recorder = new TrajectoryRecorder("navigation_camera");
            Vector3 target = new Vector3(origin + 2f, 0f, origin + 1f);
            yield return driver.ClickWorld(target, MouseButton.Left, recorder,
                "move_a", "navigation.move_a.input.route");
            TrajectoryStepEvidence step = recorder.Step("move_a");
            bool performed = step.input_action_events.Any(item =>
                item.phase == "performed" && item.action == "EvaluatorHealthMove");
            string status = step.checks.Single(check =>
                check.check_id == "navigation.move_a.input.route").status;
            int hijacksDuringIsolation = hijacker.HijackCount;
            Vector3 cameraPositionAfterRoute = cameraObject.transform.position;

            yield return driver.Dispose();
            if (data != null) instance.Remove();
            Object.Destroy(hijackerObject);
            yield return null;
            yield return isolation.Restore();

            Assert.That(data, Is.Not.Null,
                "Evaluator health prerequisite could not build an isolated NavMesh.");
            Assert.That(status, Is.EqualTo("pass"));
            Assert.That(step.top_hit, Does.Contain("Evaluator Health NavMesh Floor"));
            Assert.That(performed, Is.True,
                "The synthetic Physics/NavMesh route did not reach a real InputAction callback.");
            Assert.That(hijacksDuringIsolation, Is.EqualTo(hijacksBeforeIsolation),
                "A candidate-scene MonoBehaviour was still updating and could hijack Camera.main.");
            Assert.That(Vector3.Distance(cameraPositionAfterRoute, expectedCameraPosition),
                Is.LessThan(0.001f),
                "The isolated evaluator NavMesh camera was moved by candidate-scene behavior.");
        }

        [Test, Order(-80)]
        public void EVALUATOR_HEALTH_Dynamic_EvidenceSinkWritable()
        {
            string path = EvaluatorHealthArtifactWriter.Write("dynamic", 0);
            Assert.That(File.Exists(path), Is.True,
                "Evaluator health prerequisite could not write its protected evidence artifact.");
        }

        [Test, Order(-70)]
        public void EVALUATOR_HEALTH_Dynamic_PresentationFailureDoesNotBlockNativeTail()
        {
            var presentation = new TrajectoryRecorder("navigation_camera");
            presentation.Fail("camera_a", "navigation.camera_a.player_visible",
                "player inside camera viewport", "not visible", "fixture");
            Assert.That(presentation.HasFailure, Is.True);
            Assert.That(presentation.HasBlockingFailure, Is.False,
                "A D5 presentation failure must not block later native gameplay checks.");

            var gameplay = new TrajectoryRecorder("navigation_camera");
            gameplay.Fail("move_a", "navigation.move_a.reached",
                "player reaches target", "stalled", "fixture");
            Assert.That(gameplay.HasBlockingFailure, Is.True,
                "A native movement failure must still block dependent gameplay steps.");

            var verifiedTargets = new Dictionary<DungeonDuelWorldTargetId, Vector3>
            {
                [DungeonDuelWorldTargetId.MoveTargetA] = new Vector3(0f, 0f, 2f),
                [DungeonDuelWorldTargetId.MoveTargetB] = new Vector3(0f, 0f, 12f),
                [DungeonDuelWorldTargetId.DashTarget] = new Vector3(2f, 0f, 3f)
            };
            (Vector3 point, string source) firstBeyondCandidate =
                DungeonDuelTrajectoryHarness.BuildBeyondGateCandidates(
                    verifiedTargets, new Vector3(0f, 0f, 8f),
                    Vector3.forward, Vector3.right).First();
            Assert.That(firstBeyondCandidate.point,
                Is.EqualTo(verifiedTargets[DungeonDuelWorldTargetId.MoveTargetB]),
                "A verified public world target must be considered before generic gate offsets.");
            Assert.That(firstBeyondCandidate.source,
                Does.Contain("verified public world target"));

            Vector3 gateCenter = new Vector3(0f, 0f, 8f);
            Assert.That(DungeonDuelTrajectoryHarness.HasBeyondGateTargetClearance(
                    gateCenter + Vector3.forward * 0.5f,
                    gateCenter, Vector3.forward),
                Is.False,
                "A shallow verified target only 0.5m behind the gate must not be selected.");
            Assert.That(DungeonDuelTrajectoryHarness.HasBeyondGateTargetClearance(
                    gateCenter + Vector3.forward * 4f,
                    gateCenter, Vector3.forward),
                Is.True,
                "A verified target 4m behind the gate must retain safe crossing clearance.");
            List<(Vector3 point, string source)> approachCandidates =
                DungeonDuelTrajectoryHarness.BuildGateApproachCandidates(
                    verifiedTargets, Vector3.zero, gateCenter,
                    Vector3.forward, Vector3.right).ToList();
            Assert.That(approachCandidates.Any(item =>
                    Vector3.Distance(item.point, gateCenter - Vector3.forward * 3.2f) < 0.01f),
                Is.True,
                "Gate staging must include a native start-side gate-front point.");
            Assert.That(approachCandidates.Any(item =>
                    item.source.Contains("player-to-gate")),
                Is.True,
                "Gate staging must include bounded normal-input hops for follow cameras.");

            var activeUi = new UiSemanticSnapshot();
            activeUi.Texts.Add(new VisibleTextRecord
            {
                Text = "TANK  120 / 120 HP\nIMPS  2 / 2    GATE  LOCKED • BOSS DORMANT\nDASH  READY"
            });
            activeUi.Texts.Add(new VisibleTextRecord
            {
                Text = "LEFT CLICK  Move   •   RIGHT CLICK  Attack   •   2  Dash   •   R  Restart"
            });
            activeUi.Texts.Add(new VisibleTextRecord
            {
                Text = "Defeat both Imps — Gate locked"
            });
            var activeState = new DungeonDuelGameSnapshot
            {
                Phase = DungeonDuelGamePhase.Playing,
                Player = new DungeonDuelActorSnapshot
                {
                    ActorId = DungeonDuelActorId.Player,
                    Health = 120f,
                    MaxHealth = 120f
                },
                ImpsAlive = 2,
                GateOpen = false,
                GateBlocking = true,
                DashCooldownRemaining = 0f
            };
            Assert.That(UiSemanticProbe.TryReadTerminalPhase(activeUi,
                    out _, out _),
                Is.False,
                "The exact active objective 'Defeat both Imps — Gate locked' must not be parsed as a terminal result.");
            Assert.That(UiSemanticProbe.Validate(activeUi, activeState,
                    HudSemanticState.Initial, out string activeFailure),
                Is.True,
                activeFailure);

            var defeatUi = new UiSemanticSnapshot();
            defeatUi.Texts.Add(new VisibleTextRecord { Text = "DEFEAT" });
            defeatUi.Texts.Add(new VisibleTextRecord { Text = "RESTART ENCOUNTER" });
            Assert.That(UiSemanticProbe.TryReadTerminalPhase(defeatUi,
                    out DungeonDuelGamePhase defeatPhase, out _),
                Is.True,
                "A standalone DEFEAT title must remain a terminal result.");
            Assert.That(defeatPhase, Is.EqualTo(DungeonDuelGamePhase.Lost));
            Assert.That(UiSemanticProbe.Validate(defeatUi, activeState,
                    HudSemanticState.Initial, out string staleFailure),
                Is.False,
                "A real stale DEFEAT title must still fail active-play HUD validation.");
            Assert.That(staleFailure,
                Does.Contain("stale terminal label"));

            var combinedDefeatUi = new UiSemanticSnapshot();
            combinedDefeatUi.Texts.Add(new VisibleTextRecord
            {
                Text = "DEFEAT — The Tank has fallen"
            });
            Assert.That(UiSemanticProbe.TryReadTerminalPhase(combinedDefeatUi,
                    out DungeonDuelGamePhase combinedPhase, out _),
                Is.True,
                "A DEFEAT title with an explicitly delimited subtitle must remain terminal UI.");
            Assert.That(combinedPhase, Is.EqualTo(DungeonDuelGamePhase.Lost));
        }

        [UnityTest, Order(-90)]
        public IEnumerator EVALUATOR_HEALTH_Dynamic_AudioProbeMismatchIsLocalized()
        {
            UnityEngine.SceneManagement.Scene previous =
                UnityEngine.SceneManagement.SceneManager.GetActiveScene();
            UnityEngine.SceneManagement.Scene fixture =
                UnityEngine.SceneManagement.SceneManager.CreateScene(
                    "Evaluator Audio Mismatch Regression");
            UnityEngine.SceneManagement.SceneManager.SetActiveScene(fixture);

            GameObject player = MakeActor("Fixture Player", new Vector3(0f, 0.5f, 0f));
            GameObject impA = MakeActor("Fixture Imp A", new Vector3(2f, 0.5f, 2f));
            GameObject impB = MakeActor("Fixture Imp B", new Vector3(2f, 0.5f, -2f));
            GameObject boss = MakeActor("Fixture Boss", new Vector3(10f, 0.5f, 0f));
            GameObject gate = GameObject.CreatePrimitive(PrimitiveType.Cube);
            gate.name = "Fixture Gate";
            gate.transform.position = new Vector3(6f, 1.5f, 0f);
            gate.transform.localScale = new Vector3(0.5f, 3f, 6f);

            GameObject probeObject = new GameObject("Fixture Probe");
            AudioMismatchProbeFixture probe =
                probeObject.AddComponent<AudioMismatchProbeFixture>();
            probe.Configure(player, impA, impB, boss, gate);

            AudioClip clip = AudioClip.Create(
                "Fixture Battle Loop", 4410, 1, 44100, false);
            AudioSource source = probeObject.AddComponent<AudioSource>();
            source.clip = clip;
            source.loop = true;
            source.Play();
            Physics.SyncTransforms();
            yield return null;

            var observer = new RuntimeSemanticObserver();
            Assert.That(observer.Initialize(fixture, probe, out string discoveryFailure),
                Is.True, discoveryFailure);
            bool captured = observer.TryBuildSnapshot(
                out DungeonDuelGameSnapshot snapshot, out string snapshotFailure);

            Assert.That(captured, Is.True, snapshotFailure);
            Assert.That(snapshot, Is.Not.Null);
            Assert.That(snapshot.BattleMusicPlaying, Is.True,
                "Native AudioSource truth must be used for audio checkpoints.");
            Assert.That(observer.LastSnapshotDiagnostics,
                Does.Contain("battle-audio claim"),
                "The localized contradiction should remain auditable.");

            if (previous.IsValid() && previous.isLoaded)
                UnityEngine.SceneManagement.SceneManager.SetActiveScene(previous);
            yield return UnityEngine.SceneManagement.SceneManager.UnloadSceneAsync(fixture);
            Object.Destroy(clip);
        }

        static GameObject MakeActor(string name, Vector3 position)
        {
            GameObject actor = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            actor.name = name;
            actor.transform.position = position;
            return actor;
        }

    }

    /// <summary>
    /// Runs evaluator-owned Physics/Input fixtures in a temporary Scene while
    /// every root in the loaded candidate Scenes is inactive. A separate Scene
    /// alone is insufficient because candidate Update methods can still mutate
    /// the globally tagged Camera.main across Scene boundaries.
    /// </summary>
    internal sealed class EvaluatorHealthSceneIsolation
    {
        sealed class RootState
        {
            public GameObject Root;
            public bool ActiveSelf;
        }

        readonly Scene previousActiveScene;
        readonly Scene fixtureScene;
        readonly List<RootState> externalRoots = new List<RootState>();

        public EvaluatorHealthSceneIsolation(string name)
        {
            previousActiveScene = SceneManager.GetActiveScene();
            fixtureScene = SceneManager.CreateScene(
                name + " " + Guid.NewGuid().ToString("N"));

            for (int index = 0; index < SceneManager.sceneCount; index++)
            {
                Scene scene = SceneManager.GetSceneAt(index);
                if (!scene.IsValid() || !scene.isLoaded ||
                    scene.handle == fixtureScene.handle)
                {
                    continue;
                }

                foreach (GameObject root in scene.GetRootGameObjects())
                {
                    if (root == null) continue;
                    externalRoots.Add(new RootState
                    {
                        Root = root,
                        ActiveSelf = root.activeSelf
                    });
                    if (root.activeSelf) root.SetActive(false);
                }
            }

            if (!SceneManager.SetActiveScene(fixtureScene))
            {
                RestoreExternalRoots();
                throw new InvalidOperationException(
                    "Evaluator health could not activate its isolated fixture Scene.");
            }
        }

        public void Move(GameObject value)
        {
            if (value == null) throw new ArgumentNullException(nameof(value));
            if (value.transform.parent != null)
            {
                throw new InvalidOperationException(
                    "Evaluator fixture objects must be Scene roots before isolation.");
            }
            if (value.scene.handle != fixtureScene.handle)
                SceneManager.MoveGameObjectToScene(value, fixtureScene);
        }

        public IEnumerator Restore()
        {
            Scene restoreScene = previousActiveScene;
            if (!restoreScene.IsValid() || !restoreScene.isLoaded)
            {
                for (int index = 0; index < SceneManager.sceneCount; index++)
                {
                    Scene candidate = SceneManager.GetSceneAt(index);
                    if (candidate.IsValid() && candidate.isLoaded &&
                        candidate.handle != fixtureScene.handle)
                    {
                        restoreScene = candidate;
                        break;
                    }
                }
            }

            if (!restoreScene.IsValid() || !restoreScene.isLoaded ||
                !SceneManager.SetActiveScene(restoreScene))
            {
                RestoreExternalRoots();
                throw new InvalidOperationException(
                    "Evaluator health could not restore the prior active Scene.");
            }

            AsyncOperation unload = fixtureScene.IsValid() && fixtureScene.isLoaded
                ? SceneManager.UnloadSceneAsync(fixtureScene)
                : null;
            if (unload != null)
            {
                while (!unload.isDone) yield return null;
            }
            RestoreExternalRoots();
        }

        void RestoreExternalRoots()
        {
            foreach (RootState state in externalRoots)
            {
                if (state.Root != null && state.Root.activeSelf != state.ActiveSelf)
                    state.Root.SetActive(state.ActiveSelf);
            }
            externalRoots.Clear();
        }
    }

    public sealed class CameraMainHijackerFixture : MonoBehaviour
    {
        public int HijackCount { get; private set; }

        void Update()
        {
            Camera camera = Camera.main;
            if (camera == null) return;
            HijackCount++;
            camera.transform.position = new Vector3(-9000f, -9000f, -9000f);
            camera.transform.rotation = Quaternion.Euler(13f, 71f, 29f);
        }
    }

    public sealed class AudioMismatchProbeFixture : MonoBehaviour,
        IDungeonDuelBenchmarkProbe
    {
        GameObject player;
        GameObject impA;
        GameObject impB;
        GameObject boss;
        GameObject gate;

        public string ContractVersion => "2.0";

        public void Configure(
            GameObject playerTarget,
            GameObject impATarget,
            GameObject impBTarget,
            GameObject bossTarget,
            GameObject gateTarget)
        {
            player = playerTarget;
            impA = impATarget;
            impB = impBTarget;
            boss = bossTarget;
            gate = gateTarget;
        }

        public DungeonDuelGameSnapshot CaptureBenchmarkSnapshot() =>
            new DungeonDuelGameSnapshot
            {
                Phase = DungeonDuelGamePhase.Playing,
                Player = Actor(DungeonDuelActorId.Player, player, 120f, false),
                ImpA = Actor(DungeonDuelActorId.ImpA, impA, 62f, false),
                ImpB = Actor(DungeonDuelActorId.ImpB, impB, 62f, false),
                Boss = Actor(DungeonDuelActorId.Boss, boss, 185f, true),
                ImpsAlive = 2,
                GateOpen = false,
                GateBlocking = true,
                DashCooldownRemaining = 0f,
                BattleMusicPlaying = false
            };

        public GameObject GetActorPointerTarget(DungeonDuelActorId actorId) =>
            actorId == DungeonDuelActorId.Player ? player :
            actorId == DungeonDuelActorId.ImpA ? impA :
            actorId == DungeonDuelActorId.ImpB ? impB : boss;

        public GameObject GetGatePointerTarget() => gate;

        public Vector3 GetWorldTargetPosition(DungeonDuelWorldTargetId targetId) =>
            targetId == DungeonDuelWorldTargetId.MoveTargetA
                ? new Vector3(1f, 0f, 3f)
                : targetId == DungeonDuelWorldTargetId.MoveTargetB
                    ? new Vector3(3f, 0f, -3f)
                    : new Vector3(5f, 0f, 0f);

        static DungeonDuelActorSnapshot Actor(
            DungeonDuelActorId id,
            GameObject target,
            float health,
            bool dormant) => new DungeonDuelActorSnapshot
            {
                ActorId = id,
                Position = target.transform.position,
                Health = health,
                MaxHealth = health,
                MoveSpeed = 1f,
                AttackRange = 1f,
                AttackDamage = 1f,
                AttackCooldown = 1f,
                IsDead = false,
                IsDormant = dormant
            };
    }

    internal static class EvaluatorHealthArtifactWriter
    {
        [Serializable]
        sealed class Artifact
        {
            public int schema_version = 1;
            public string evaluator_health = "passed";
            public string phase;
            public int process_id;
            public int prior_process_id;
            public string written_utc;
        }

        public static string Write(string phase, int priorProcessId)
        {
            string output = FindCommandLineValue("-omnigameTrajectoryOutput") ??
                            FindCommandLineValue("-omnigameDungeonDuelTrajectoryOutput");
            if (string.IsNullOrWhiteSpace(output))
                throw new InvalidOperationException(
                    "Evaluator health prerequisite has no protected evidence output directory.");
            Directory.CreateDirectory(output);
            var artifact = new Artifact
            {
                phase = phase,
                process_id = Process.GetCurrentProcess().Id,
                prior_process_id = priorProcessId,
                written_utc = DateTime.UtcNow.ToString("O")
            };
            string path = Path.Combine(output, $"evaluator-health-{phase}.json");
            File.WriteAllText(path, JsonUtility.ToJson(artifact, true));
            return path;
        }

        public static string FindCommandLineValue(string key)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], key, StringComparison.OrdinalIgnoreCase))
                    return args[index + 1].Trim('"');
            }
            return null;
        }
    }
}

