using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.SceneManagement;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    /// <summary>
    /// Uses the mandatory public read-only probe, then cross-checks its claims
    /// against the real visible actor transforms, gate Collider, runtime UI and
    /// native AudioSources. The probe never performs player actions.
    /// </summary>
    internal sealed class RuntimeSemanticObserver
    {
        readonly Dictionary<DungeonDuelActorId, GameObject> actors =
            new Dictionary<DungeonDuelActorId, GameObject>();
        readonly Dictionary<GameObject, HealthBinding> healthBindings =
            new Dictionary<GameObject, HealthBinding>();
        Scene scene;
        IDungeonDuelBenchmarkProbe probe;
        Collider gateCollider;
        Renderer gateRenderer;
        Vector3 gateInitialPosition;
        Vector3 gateInitialCenter;
        Vector3 gateForward;

        public string DiscoverySummary { get; private set; }
        public string LastSnapshotDiagnostics { get; private set; }

        public bool Initialize(
            Scene activeScene,
            IDungeonDuelBenchmarkProbe publicProbe,
            out string failure)
        {
            scene = activeScene;
            probe = publicProbe;
            actors.Clear();
            healthBindings.Clear();
            gateCollider = null;
            gateRenderer = null;
            failure = null;

            if (!scene.IsValid() || !scene.isLoaded)
            {
                failure = "The active gameplay scene is not loaded.";
                return false;
            }

            if (probe == null)
            {
                failure = "The mandatory public read-only submission probe is missing.";
                return false;
            }
            if (!TryProbeActorHints(probe))
            {
                failure = "The public probe did not resolve four unique visible actor targets.";
                return false;
            }
            if (!ValidateActorSet(out failure))
                return false;
            if (!TryProbeGate(out failure))
                return false;

            DiscoverySummary =
                "actorSource=public read-only probe; " +
                string.Join(", ", actors.Select(pair =>
                    $"{pair.Key}={pair.Value.name}@{pair.Value.transform.position:F2}")) +
                $"; gateCollider={gateCollider.name}@{gateInitialCenter:F2}";
            return true;
        }

        public GameObject ActorTarget(DungeonDuelActorId id) =>
            actors.TryGetValue(id, out GameObject target) ? target : null;

        public bool IsActorPresented(DungeonDuelActorId id) =>
            actors.TryGetValue(id, out GameObject target) &&
            target != null && target.activeInHierarchy &&
            HasVisibleRenderer(target);

        public bool TryBuildSnapshot(
            out DungeonDuelGameSnapshot snapshot,
            out string failure)
        {
            snapshot = null;
            failure = null;
            LastSnapshotDiagnostics = string.Empty;
            try
            {
                if (!scene.IsValid() || !scene.isLoaded ||
                    SceneManager.GetActiveScene() != scene)
                {
                    failure = "The observed gameplay scene is no longer active.";
                    return false;
                }

                DungeonDuelGameSnapshot observed = probe.CaptureBenchmarkSnapshot();
                if (!ValidateProbeSnapshot(observed, out failure))
                    return false;

                var diagnostics = new List<string>();
                UiSemanticSnapshot ui = UiSemanticProbe.Capture(scene);
                if (UiSemanticProbe.TryReadLivingImpCount(ui, out int visibleImps,
                        out string impObservation) && visibleImps != observed.ImpsAlive)
                {
                    diagnostics.Add(
                        $"Probe Imp count ({observed.ImpsAlive}) disagrees with {impObservation}.");
                }
                if (UiSemanticProbe.TryReadGateOpen(ui, out bool visibleGateOpen,
                        out string gateObservation) && visibleGateOpen != observed.GateOpen)
                {
                    diagnostics.Add($"Probe gate state disagrees with {gateObservation}.");
                }
                bool battleMusic = UnityEngine.Object.FindObjectsByType<AudioSource>(
                        FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Any(source => source != null && source.gameObject.scene == scene &&
                                   source.isActiveAndEnabled && source.isPlaying &&
                                   source.clip != null && source.loop);
                if (UiSemanticProbe.TryReadTerminalPhase(ui,
                        out DungeonDuelGamePhase visiblePhase,
                        out string phaseObservation) && visiblePhase != observed.Phase)
                {
                    diagnostics.Add(
                        $"Probe phase {observed.Phase} disagrees with {phaseObservation}.");
                }
                if (observed.BattleMusicPlaying != battleMusic)
                {
                    diagnostics.Add(
                        $"Probe battle-audio claim ({observed.BattleMusicPlaying}) " +
                        $"disagrees with native looping AudioSource state ({battleMusic}).");
                }

                // UI and audio contradictions belong to their own D5/AUDIO checks. They
                // must not turn an otherwise observable gameplay implementation into a
                // trajectory-wide setup failure. Continue with the component-backed
                // snapshot and replace the audio convenience field with native truth;
                // later checkpoints still inspect the real uGUI and AudioSources.
                observed.BattleMusicPlaying = battleMusic;
                LastSnapshotDiagnostics = string.Join(" | ", diagnostics);

                snapshot = observed;
                return true;
            }
            catch (Exception exception)
            {
                failure = "Native semantic observation threw " +
                          exception.GetType().Name + ": " + exception.Message;
                return false;
            }
        }

        public bool IsGateBlocking() =>
            gateCollider != null && gateCollider.gameObject.activeInHierarchy &&
            gateCollider.enabled && !gateCollider.isTrigger;

        public Vector3 GateCenter =>
            gateCollider == null ? Vector3.zero : gateInitialCenter;

        public Vector3 GateForward => gateForward;

        public bool IsBeyondGate(Vector3 startSide, Vector3 current)
        {
            if (gateCollider == null || gateForward.sqrMagnitude < 0.01f) return false;
            Vector3 direction = gateForward;
            float gateProjection = Vector3.Dot(
                gateInitialCenter - startSide, direction);
            float currentProjection = Vector3.Dot(current - startSide, direction);
            return currentProjection >= gateProjection + 0.35f;
        }

        bool TryProbeGate(out string failure)
        {
            failure = null;
            GameObject gate;
            try { gate = probe.GetGatePointerTarget(); }
            catch (Exception exception)
            {
                failure = "The public gate target threw " +
                          exception.GetType().Name + ": " + exception.Message;
                return false;
            }
            if (gate == null || gate.scene != scene || !gate.activeInHierarchy)
            {
                failure = "The public probe did not resolve the visible active gate GameObject.";
                return false;
            }
            gateCollider = gate.GetComponentsInChildren<Collider>(true)
                .FirstOrDefault(item => item != null && item.enabled && !item.isTrigger);
            if (gateCollider == null)
            {
                failure = "The public gate target has no enabled non-trigger blocking Collider.";
                return false;
            }
            gateRenderer = gate.GetComponentInChildren<Renderer>(true);
            if (gateRenderer == null)
            {
                failure = "The public gate target has no visible Renderer.";
                return false;
            }
            gateInitialPosition = gateRenderer.transform.position;
            gateInitialCenter = gateCollider.bounds.center;
            Vector3 corridor = ActorTarget(DungeonDuelActorId.Boss).transform.position -
                               ActorTarget(DungeonDuelActorId.Player).transform.position;
            corridor.y = 0f;
            gateForward = corridor.sqrMagnitude > 0.01f
                ? corridor.normalized
                : Vector3.forward;
            return true;
        }

        bool ValidateProbeSnapshot(
            DungeonDuelGameSnapshot snapshot,
            out string failure)
        {
            failure = null;
            if (snapshot == null || snapshot.Player == null ||
                snapshot.ImpA == null || snapshot.ImpB == null ||
                snapshot.Boss == null)
            {
                failure = "The public probe returned an incomplete snapshot.";
                return false;
            }
            var expected = new Dictionary<DungeonDuelActorId, DungeonDuelActorSnapshot>
            {
                [DungeonDuelActorId.Player] = snapshot.Player,
                [DungeonDuelActorId.ImpA] = snapshot.ImpA,
                [DungeonDuelActorId.ImpB] = snapshot.ImpB,
                [DungeonDuelActorId.Boss] = snapshot.Boss
            };
            foreach (var pair in expected)
            {
                DungeonDuelActorSnapshot actor = pair.Value;
                if (actor.ActorId != pair.Key || !IsFinite(actor.Position) ||
                    float.IsNaN(actor.Health) || float.IsInfinity(actor.Health) ||
                    float.IsNaN(actor.MaxHealth) || float.IsInfinity(actor.MaxHealth) ||
                    !IsFiniteNonNegative(actor.MoveSpeed) ||
                    !IsFiniteNonNegative(actor.AttackRange) ||
                    !IsFiniteNonNegative(actor.AttackDamage) ||
                    !IsFiniteNonNegative(actor.AttackCooldown) ||
                    actor.MaxHealth <= 0f || actor.Health < -0.05f ||
                    actor.Health > actor.MaxHealth + 0.05f)
                {
                    failure = $"The public probe returned invalid {pair.Key} state.";
                    return false;
                }
                float distance = Vector3.Distance(
                    ActorTarget(pair.Key).transform.position, actor.Position);
                if (distance > 1.5f)
                {
                    failure = $"The public {pair.Key} position is {distance:F2} m from " +
                              "the real visible target Transform.";
                    return false;
                }
                if (actor.IsDead != (actor.Health <= 0.05f))
                {
                    failure = $"The public {pair.Key} death flag disagrees with health.";
                    return false;
                }
                GameObject target = ActorTarget(pair.Key);
                if (TryReadActorHealth(target, out float nativeHealth,
                        out float nativeMaximum, out string healthSource) &&
                    (Mathf.Abs(nativeHealth - actor.Health) > 0.1f ||
                     Mathf.Abs(nativeMaximum - actor.MaxHealth) > 0.1f))
                {
                    failure = $"The public {pair.Key} health disagrees with " +
                              $"{healthSource}: probe={actor.Health:F2}/{actor.MaxHealth:F2}, " +
                              $"native={nativeHealth:F2}/{nativeMaximum:F2}.";
                    return false;
                }
                NavMeshAgent agent = target.GetComponent<NavMeshAgent>();
                if (agent != null && agent.enabled &&
                    Mathf.Abs(agent.speed - actor.MoveSpeed) > 0.1f)
                {
                    failure = $"The public {pair.Key} move speed ({actor.MoveSpeed:F2}) " +
                              $"disagrees with its NavMeshAgent ({agent.speed:F2}).";
                    return false;
                }
            }
            int actualImps = (snapshot.ImpA.IsDead ? 0 : 1) +
                             (snapshot.ImpB.IsDead ? 0 : 1);
            if (snapshot.ImpsAlive != actualImps)
            {
                failure = "The public Imp count disagrees with the two Imp snapshots.";
                return false;
            }
            bool nativeBlocking = IsGateBlocking();
            if (snapshot.GateBlocking != nativeBlocking ||
                snapshot.GateOpen == snapshot.GateBlocking)
            {
                failure = "The public gate state disagrees with the real blocking Collider.";
                return false;
            }
            if (float.IsNaN(snapshot.DashCooldownRemaining) ||
                float.IsInfinity(snapshot.DashCooldownRemaining) ||
                snapshot.DashCooldownRemaining < -0.05f ||
                snapshot.DashCooldownRemaining > 30f)
            {
                failure = "The public Dash cooldown is invalid.";
                return false;
            }
            return true;
        }

        static bool IsFinite(Vector3 value) =>
            !float.IsNaN(value.x) && !float.IsInfinity(value.x) &&
            !float.IsNaN(value.y) && !float.IsInfinity(value.y) &&
            !float.IsNaN(value.z) && !float.IsInfinity(value.z);

        static bool IsFiniteNonNegative(float value) =>
            !float.IsNaN(value) && !float.IsInfinity(value) && value >= 0f;

        bool TryProbeActorHints(IDungeonDuelBenchmarkProbe probe)
        {
            if (probe == null) return false;
            try
            {
                var unique = new HashSet<GameObject>();
                foreach (DungeonDuelActorId id in Enum.GetValues(
                             typeof(DungeonDuelActorId)))
                {
                    GameObject target = probe.GetActorPointerTarget(id);
                    if (!IsUsableActor(id, target) || !unique.Add(target))
                    {
                        actors.Clear();
                        return false;
                    }
                    actors[id] = target;
                }
                return actors.Count == 4;
            }
            catch
            {
                actors.Clear();
                return false;
            }
        }

        bool TryDiscoverActors(out string failure)
        {
            failure = null;
            var candidates = new List<ActorCandidate>();
            foreach (MonoBehaviour component in UnityEngine.Object
                         .FindObjectsByType<MonoBehaviour>(
                             FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (component == null || component.gameObject.scene != scene ||
                    !component.gameObject.activeInHierarchy ||
                    !TryCreateHealthBinding(component, out HealthBinding binding) ||
                    !binding.TryRead(out float health, out float maxHealth))
                    continue;
                GameObject target = component.gameObject;
                if (!HasVisibleRenderer(target)) continue;
                if (candidates.Any(item => item.Target == target)) continue;
                candidates.Add(new ActorCandidate
                {
                    Target = target,
                    HealthBinding = binding,
                    Role = ReadSemanticRole(target),
                    RenderVolume = RendererVolume(target),
                    Health = health,
                    MaxHealth = maxHealth
                });
            }

            if (candidates.Count < 4)
            {
                AddBehaviorActorCandidates(candidates);
            }

            if (candidates.Count < 4)
            {
                failure = $"Scene discovery found only {candidates.Count} visible behavior-backed actors.";
                return false;
            }

            ActorCandidate player = candidates.FirstOrDefault(item =>
                item.Role == SemanticRole.Player) ??
                candidates.FirstOrDefault(item => item.Target.CompareTag("Player"));
            if (player == null)
            {
                failure = "Scene discovery could not distinguish the Player from health-backed actors.";
                return false;
            }

            List<ActorCandidate> enemies = candidates
                .Where(item => item != player)
                .ToList();
            ActorCandidate boss = enemies.FirstOrDefault(item =>
                item.Role == SemanticRole.Boss) ??
                enemies.OrderByDescending(item => item.RenderVolume).FirstOrDefault();
            List<ActorCandidate> imps = enemies
                .Where(item => item != boss &&
                               (item.Role == SemanticRole.Imp ||
                                item.Role == SemanticRole.Unknown))
                .OrderBy(item => item.Target.transform.position.x)
                .ThenBy(item => item.Target.transform.position.z)
                .Take(2)
                .ToList();
            if (boss == null || imps.Count != 2)
            {
                failure = "Scene discovery could not distinguish one Boss and two Imp threats.";
                return false;
            }

            actors[DungeonDuelActorId.Player] = player.Target;
            actors[DungeonDuelActorId.ImpA] = imps[0].Target;
            actors[DungeonDuelActorId.ImpB] = imps[1].Target;
            actors[DungeonDuelActorId.Boss] = boss.Target;
            foreach (ActorCandidate candidate in new[] { player, imps[0], imps[1], boss })
            {
                if (candidate.HealthBinding != null)
                    healthBindings[candidate.Target] = candidate.HealthBinding;
            }
            return true;
        }

        void AddBehaviorActorCandidates(List<ActorCandidate> candidates)
        {
            var targets = new HashSet<GameObject>(candidates.Select(item => item.Target));
            var behaviorTargets = new HashSet<GameObject>();
            foreach (NavMeshAgent agent in UnityEngine.Object.FindObjectsByType<NavMeshAgent>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (agent != null && agent.gameObject.scene == scene)
                    behaviorTargets.Add(agent.gameObject);
            }
            foreach (CharacterController controller in UnityEngine.Object
                         .FindObjectsByType<CharacterController>(
                             FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (controller != null && controller.gameObject.scene == scene)
                    behaviorTargets.Add(controller.gameObject);
            }
            foreach (Rigidbody body in UnityEngine.Object.FindObjectsByType<Rigidbody>(
                         FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (body != null && body.gameObject.scene == scene)
                    behaviorTargets.Add(body.gameObject);
            }

            // Animator-only characters are a final implementation-neutral
            // fallback for projects that move transforms directly. Ascend to
            // the first visible gameplay root rather than requiring a Collider
            // or using a render-only skeleton child.
            if (behaviorTargets.Count < 4)
            {
                foreach (Animator animator in UnityEngine.Object.FindObjectsByType<Animator>(
                             FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                {
                    if (animator == null || animator.gameObject.scene != scene) continue;
                    Transform cursor = animator.transform;
                    GameObject resolved = null;
                    while (cursor != null && cursor.gameObject.scene == scene)
                    {
                        if (HasVisibleRenderer(cursor.gameObject))
                        {
                            resolved = cursor.gameObject;
                            break;
                        }
                        cursor = cursor.parent;
                    }
                    if (resolved != null) behaviorTargets.Add(resolved);
                }
            }

            foreach (GameObject target in behaviorTargets)
            {
                if (!targets.Add(target) || !target.activeInHierarchy ||
                    !HasVisibleRenderer(target))
                    continue;
                HealthBinding binding = null;
                TryFindActorHealthBinding(target, out binding);
                candidates.Add(new ActorCandidate
                {
                    Target = target,
                    HealthBinding = binding,
                    Role = ReadSemanticRole(target),
                    RenderVolume = RendererVolume(target),
                    Health = binding != null && binding.TryRead(
                        out float current, out _) ? current : float.NaN,
                    MaxHealth = binding != null && binding.TryRead(
                        out _, out float maximum) ? maximum : float.NaN
                });
            }
        }

        bool ValidateActorSet(out string failure)
        {
            failure = null;
            var unique = new HashSet<GameObject>();
            foreach (DungeonDuelActorId id in Enum.GetValues(
                         typeof(DungeonDuelActorId)))
            {
                GameObject target = ActorTarget(id);
                if (!IsUsableActor(id, target) || !unique.Add(target))
                {
                    failure = $"{id} did not resolve to a unique gameplay actor with render and collider geometry.";
                    return false;
                }
            }
            return true;
        }

        bool TryObserveActor(
            DungeonDuelActorId id,
            UiSemanticSnapshot ui,
            bool gateBlocking,
            out DungeonDuelActorSnapshot snapshot,
            out string failure)
        {
            snapshot = null;
            failure = null;
            GameObject target = ActorTarget(id);
            if (target == null || target.scene != scene)
            {
                failure = $"{id} is no longer a scene actor.";
                return false;
            }
            bool rendered = HasVisibleRenderer(target);
            bool hasCollider = target.GetComponentsInChildren<Collider>(true).Any();
            bool collidable = target.activeInHierarchy &&
                target.GetComponentsInChildren<Collider>(true)
                .Any(collider => collider.enabled && collider.gameObject.activeInHierarchy &&
                                  !collider.isTrigger);
            bool hiddenDormantBoss = id == DungeonDuelActorId.Boss &&
                                     !target.activeInHierarchy;
            bool presentationDead = !hiddenDormantBoss && !target.activeInHierarchy ||
                                    (hasCollider && !collidable);

            bool exactHealth = TryReadActorHealth(target,
                out float health, out float maxHealth, out string healthSource);
            if (id == DungeonDuelActorId.Player &&
                UiSemanticProbe.TryReadPlayerHealth(ui,
                    out float visibleHealth, out float visibleMaximum,
                    out string hudObservation))
            {
                if (exactHealth &&
                    (Mathf.Abs(Mathf.Ceil(visibleHealth) - Mathf.Ceil(health)) > 1f ||
                     Mathf.Abs(Mathf.Ceil(visibleMaximum) - Mathf.Ceil(maxHealth)) > 1f))
                {
                    failure = $"Player native health {health:F1}/{maxHealth:F1} disagrees with {hudObservation}.";
                    return false;
                }
                if (!exactHealth)
                {
                    health = visibleHealth;
                    maxHealth = visibleMaximum;
                    exactHealth = true;
                    healthSource = hudObservation;
                }
            }

            bool dead;
            if (exactHealth)
            {
                if (maxHealth <= 0f || float.IsNaN(health) || float.IsInfinity(health) ||
                    health < -0.05f || health > maxHealth + 0.05f)
                {
                    failure = $"{id} has invalid independently observed health " +
                              $"{health}/{maxHealth} from {healthSource}.";
                    return false;
                }
                dead = health <= 0.05f;
                if (hasCollider && !hiddenDormantBoss && dead != presentationDead)
                {
                    failure = $"{id} health/presentation cross-check failed: " +
                               $"source={healthSource}, dead={dead}, rendered={rendered}, " +
                              $"collidable={collidable}, active={target.activeInHierarchy}.";
                    return false;
                }
            }
            else
            {
                // A candidate with no numeric health binding may still expose a
                // normal readable death flag. Collider disablement remains an
                // optional behavioral proxy only when the actor actually owns
                // Colliders; renderer-only actors are never classified dead just
                // because they use a different targeting implementation.
                bool hasDeathFlag = TryReadActorBool(target,
                    new[] { "isdead", "dead", "defeated", "isspent" }, out dead);
                if (!hasDeathFlag && hasCollider)
                {
                    dead = presentationDead;
                }
                else if (!hasDeathFlag)
                {
                    failure = $"{id} has neither readable health/death state nor an optional collider death signal.";
                    return false;
                }
                health = dead ? 0f : 1f;
                maxHealth = 1f;
                healthSource = hasDeathFlag
                    ? "readable death-state behavior proxy"
                    : "optional collider/renderer behavior proxy";
            }

            if (!dead && !rendered && !hiddenDormantBoss)
            {
                failure = $"{id} has no valid visible living/death presentation: " +
                           $"rendered={rendered}, hasCollider={hasCollider}, " +
                           $"collidable={collidable}, dead={dead}.";
                return false;
            }

            bool dormant = false;
            if (id == DungeonDuelActorId.Boss)
            {
                if (!(TryReadActorBool(target,
                          new[] { "isdormant", "dormant", "sleeping", "isinactive" },
                          out dormant)))
                {
                    NavMeshAgent agent = target.GetComponent<NavMeshAgent>();
                    bool motionSuppressed = agent == null || !agent.enabled ||
                                            !agent.isOnNavMesh || agent.isStopped;
                    dormant = gateBlocking && motionSuppressed;
                }
            }

            snapshot = new DungeonDuelActorSnapshot
            {
                ActorId = id,
                Position = target.transform.position,
                Health = Mathf.Max(0f, health),
                MaxHealth = maxHealth,
                IsDead = dead,
                IsDormant = dormant
            };
            return true;
        }

        bool TryDiscoverGate(out string failure)
        {
            failure = null;
            GameObject player = ActorTarget(DungeonDuelActorId.Player);
            GameObject boss = ActorTarget(DungeonDuelActorId.Boss);
            Vector3 start = player.transform.position;
            Vector3 end = boss.transform.position;
            Vector3 segment = end - start;
            segment.y = 0f;
            float length = segment.magnitude;
            if (length < 2f)
            {
                failure = "Player and Boss are too close to discover a separating gate.";
                return false;
            }
            Vector3 direction = segment / length;
            var actorObjects = new HashSet<GameObject>(actors.Values);
            var scored = new List<(Collider collider, float score)>();
            foreach (Collider collider in UnityEngine.Object.FindObjectsByType<Collider>(
                         FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (collider == null || collider.gameObject.scene != scene ||
                    !collider.gameObject.activeInHierarchy || collider.isTrigger ||
                    actorObjects.Any(actor => collider.transform == actor.transform ||
                                              collider.transform.IsChildOf(actor.transform)))
                    continue;
                Bounds bounds = collider.bounds;
                if (bounds.size.y < 1.25f || bounds.size.magnitude < 1.5f) continue;
                Vector3 delta = bounds.center - start;
                delta.y = 0f;
                float projection = Vector3.Dot(delta, direction);
                float t = projection / length;
                if (t < 0.45f || t > 0.95f) continue;
                Vector3 nearest = start + direction * projection;
                float perpendicular = HorizontalDistance(nearest, bounds.center);
                if (perpendicular > 4.5f) continue;
                bool hasRenderer = collider.GetComponent<Renderer>() != null ||
                                   collider.GetComponentInParent<Renderer>() != null ||
                                   collider.GetComponentInChildren<Renderer>(true) != null;
                float score = (hasRenderer ? 12f : 0f) +
                              bounds.size.y * 1.5f +
                              Mathf.Min(bounds.size.x + bounds.size.z, 10f) -
                              Mathf.Abs(t - 0.78f) * 18f - perpendicular * 3f;
                scored.Add((collider, score));
            }
            if (scored.Count == 0)
            {
                failure = "No tall non-trigger collider separates the Player and Boss spaces.";
                return false;
            }
            gateCollider = scored.OrderByDescending(item => item.score).First().collider;
            gateRenderer = gateCollider.GetComponent<Renderer>() ??
                           gateCollider.GetComponentInParent<Renderer>() ??
                           gateCollider.GetComponentInChildren<Renderer>(true);
            gateInitialPosition = gateRenderer != null
                ? gateRenderer.transform.position
                : gateCollider.transform.position;
            // Use the point where the selected transverse collider intersects
            // the native Player-to-Boss corridor, not an arbitrary child
            // collider's off-centre bounds.  Multi-piece gate prefabs often
            // expose pillar colliders whose bounds center sits near one edge.
            Vector3 selectedCenter = gateCollider.bounds.center;
            Vector3 selectedDelta = selectedCenter - start;
            selectedDelta.y = 0f;
            float selectedProjection = Vector3.Dot(selectedDelta, direction);
            gateInitialCenter = start + direction * selectedProjection;
            gateInitialCenter.y = start.y;
            gateForward = direction;
            return true;
        }

        bool IsGateVisiblyOpen(bool blocking)
        {
            if (blocking) return false;
            Transform visual = gateRenderer != null
                ? gateRenderer.transform
                : gateCollider?.transform;
            return visual == null ||
                   Vector3.Distance(visual.position, gateInitialPosition) >= 1f ||
                   !gateCollider.gameObject.activeInHierarchy || !gateCollider.enabled;
        }

        float DiscoverDashCooldownRemaining(UiSemanticSnapshot ui)
        {
            foreach (MonoBehaviour component in UnityEngine.Object
                         .FindObjectsByType<MonoBehaviour>(
                             FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (component == null || component.gameObject.scene != scene) continue;
                if (TryReadFloat(component,
                        new[] { "dashcooldownremaining", "remainingdashcooldown", "dashremaining" },
                        out float value) && value >= -0.05f && value < 120f)
                    return Mathf.Max(0f, value);
            }
            if (UiSemanticProbe.TryReadDashCooldown(ui, out float visible,
                    out _) && visible >= 0f && visible < 120f)
                return visible;
            return 0f;
        }

        bool TryReadActorHealth(
            GameObject target,
            out float health,
            out float maxHealth,
            out string source)
        {
            if (healthBindings.TryGetValue(target, out HealthBinding cached) &&
                cached.TryRead(out health, out maxHealth))
            {
                source = cached.Source;
                return true;
            }
            if (TryFindActorHealthBinding(target, out HealthBinding discovered) &&
                discovered.TryRead(out health, out maxHealth))
            {
                healthBindings[target] = discovered;
                source = discovered.Source;
                return true;
            }
            health = maxHealth = float.NaN;
            source = "none";
            return false;
        }

        static bool TryFindActorHealthBinding(
            GameObject target,
            out HealthBinding binding)
        {
            foreach (Component component in target.GetComponents<Component>()
                         .Concat(target.GetComponentsInChildren<Component>(true)))
            {
                if (component is MonoBehaviour &&
                    TryCreateHealthBinding(component, out binding))
                    return true;
            }
            binding = null;
            return false;
        }

        static bool TryCreateHealthBinding(object component, out HealthBinding binding)
        {
            binding = null;
            if (component == null) return false;
            MemberInfo[] members = PublicReadableMembers(component.GetType()).ToArray();

            MemberInfo namedCurrent = members.FirstOrDefault(member =>
                new[] { "health", "currenthealth", "hp", "currenthp" }
                    .Contains(Normalize(member.Name)) && IsNumericMember(component, member));
            MemberInfo namedMaximum = members.FirstOrDefault(member =>
                new[] { "maxhealth", "healthmax", "maximumhealth", "maxhp" }
                    .Contains(Normalize(member.Name)) && IsNumericMember(component, member));
            if (namedCurrent != null && namedMaximum != null)
            {
                binding = new HealthBinding(component, namedCurrent, namedMaximum,
                    "semantic current/max runtime members");
                return binding.TryRead(out _, out _);
            }

            // Implementation-neutral fallback: infer a stable current/capacity
            // pair from public numeric runtime state, without requiring any
            // spelling.  Equality at fresh start, plausible bounds, magnitude,
            // and negative evidence from action-tuning members are combined.
            // The chosen pair is then cached and cross-checked against visible
            // HUD values and collider/death behavior on every snapshot.
            var numeric = members
                .Select(member => new NumericMember
                {
                    Member = member,
                    Name = Normalize(member.Name),
                    Value = ReadNumeric(component, member, out float value)
                        ? value
                        : float.NaN
                })
                .Where(item => !float.IsNaN(item.Value) && !float.IsInfinity(item.Value) &&
                               item.Value >= 0f && item.Value <= 100000f)
                .ToArray();
            float bestScore = float.NegativeInfinity;
            MemberInfo bestA = null;
            MemberInfo bestB = null;
            for (int left = 0; left < numeric.Length; left++)
            {
                for (int right = left + 1; right < numeric.Length; right++)
                {
                    NumericMember a = numeric[left];
                    NumericMember b = numeric[right];
                    float maximum = Mathf.Max(a.Value, b.Value);
                    float minimum = Mathf.Min(a.Value, b.Value);
                    if (maximum < 5f || minimum > maximum) continue;
                    float score = Mathf.Log10(maximum + 1f) * 12f;
                    if (Mathf.Abs(a.Value - b.Value) <= 0.01f) score += 45f;
                    if (ContainsSemanticVitalToken(a.Name) || ContainsSemanticVitalToken(b.Name))
                        score += 20f;
                    if (ContainsCapacityToken(a.Name) ^ ContainsCapacityToken(b.Name)) score += 12f;
                    if (ContainsActionTuningToken(a.Name)) score -= 45f;
                    if (ContainsActionTuningToken(b.Name)) score -= 45f;
                    if (score <= bestScore) continue;
                    bestScore = score;
                    bestA = a.Member;
                    bestB = b.Member;
                }
            }
            if (bestA == null || bestB == null || bestScore < 20f) return false;
            binding = new HealthBinding(component, bestA, bestB,
                $"name-agnostic numeric pair {bestA.Name}/{bestB.Name}");
            return binding.TryRead(out _, out _);
        }

        static bool ContainsSemanticVitalToken(string value) =>
            new[] { "health", "vital", "life", "condition", "integrity", "reserve", "charge" }
                .Any(value.Contains);

        static bool ContainsCapacityToken(string value) =>
            new[] { "max", "maximum", "capacity", "ceiling", "limit", "total" }
                .Any(value.Contains);

        static bool ContainsActionTuningToken(string value) =>
            new[] { "attack", "damage", "range", "cooldown", "speed", "duration",
                    "distance", "radius", "time", "delay", "rate" }
                .Any(value.Contains);

        static bool IsNumericMember(object instance, MemberInfo member) =>
            ReadNumeric(instance, member, out _);

        static bool ReadNumeric(object instance, MemberInfo member, out float value)
        {
            object raw = ReadMember(instance, member);
            if (raw is float single) { value = single; return true; }
            if (raw is int integer) { value = integer; return true; }
            if (raw is double number) { value = (float)number; return true; }
            value = float.NaN;
            return false;
        }

        static bool TryReadActorBool(
            GameObject target,
            string[] names,
            out bool value)
        {
            foreach (Component component in target.GetComponents<Component>()
                         .Concat(target.GetComponentsInChildren<Component>(true)))
            {
                if (component != null && TryReadBool(component, names, out value)) return true;
            }
            value = false;
            return false;
        }

        static bool TryReadFloat(object instance, string[] names, out float value)
        {
            foreach (MemberInfo member in PublicReadableMembers(instance.GetType()))
            {
                string normalized = Normalize(member.Name);
                if (!names.Contains(normalized)) continue;
                object raw = ReadMember(instance, member);
                if (raw is float single) { value = single; return true; }
                if (raw is int integer) { value = integer; return true; }
                if (raw is double number) { value = (float)number; return true; }
            }
            value = float.NaN;
            return false;
        }

        static bool TryReadBool(object instance, string[] names, out bool value)
        {
            foreach (MemberInfo member in PublicReadableMembers(instance.GetType()))
            {
                if (!names.Contains(Normalize(member.Name))) continue;
                object raw = ReadMember(instance, member);
                if (raw is bool boolean) { value = boolean; return true; }
            }
            value = false;
            return false;
        }

        static IEnumerable<MemberInfo> PublicReadableMembers(Type type) =>
            type.GetProperties(BindingFlags.Instance | BindingFlags.Public)
                .Where(property => property.CanRead && property.GetIndexParameters().Length == 0)
                .Cast<MemberInfo>()
                .Concat(type.GetFields(BindingFlags.Instance | BindingFlags.Public));

        static object ReadMember(object instance, MemberInfo member)
        {
            try
            {
                return member is PropertyInfo property
                    ? property.GetValue(instance)
                    : ((FieldInfo)member).GetValue(instance);
            }
            catch
            {
                return null;
            }
        }

        static SemanticRole ReadSemanticRole(GameObject target)
        {
            if (target.CompareTag("Player")) return SemanticRole.Player;
            foreach (Component component in target.GetComponents<Component>()
                         .Concat(target.GetComponentsInChildren<Component>(true)))
            {
                if (component == null) continue;
                foreach (MemberInfo member in PublicReadableMembers(component.GetType()))
                {
                    string name = Normalize(member.Name);
                    if (name != "faction" && name != "role" && name != "actorid" &&
                        name != "actortype" && name != "type")
                        continue;
                    object value = ReadMember(component, member);
                    if (TryMapSemanticRoleValue(value, out SemanticRole namedRole))
                        return namedRole;
                }
            }

            // Equivalent projects are not required to preserve evaluator-known
            // member spellings.  Public enum/string values can still expose a
            // native semantic role (for example an Allegiance enum whose value
            // is Player, Imp, or Boss), so use those values only after the
            // conventional-name pass.  Restricting the fallback to enum/string
            // state avoids interpreting arbitrary object ToString() output as
            // a hidden evaluator interface.
            foreach (MonoBehaviour component in target.GetComponents<MonoBehaviour>()
                         .Concat(target.GetComponentsInChildren<MonoBehaviour>(true)))
            {
                if (component == null) continue;
                foreach (MemberInfo member in PublicReadableMembers(component.GetType()))
                {
                    Type valueType = member is PropertyInfo property
                        ? property.PropertyType
                        : ((FieldInfo)member).FieldType;
                    if (valueType != typeof(string) && !valueType.IsEnum) continue;
                    object value = ReadMember(component, member);
                    if (TryMapSemanticRoleValue(value, out SemanticRole inferredRole))
                        return inferredRole;
                }
            }
            return SemanticRole.Unknown;
        }

        static bool TryMapSemanticRoleValue(object raw, out SemanticRole role)
        {
            string value = raw?.ToString()?.ToLowerInvariant() ?? string.Empty;
            if (value.Contains("boss"))
            {
                role = SemanticRole.Boss;
                return true;
            }
            if (value.Contains("imp") || value.Contains("minion"))
            {
                role = SemanticRole.Imp;
                return true;
            }
            if (value.Contains("player") || value.Contains("hero") ||
                value.Contains("tank"))
            {
                role = SemanticRole.Player;
                return true;
            }
            role = SemanticRole.Unknown;
            return false;
        }

        static bool IsUsableActor(DungeonDuelActorId id, GameObject target)
        {
            if (target == null || !target.scene.IsValid()) return false;

            // Hiding the initially dormant Boss with SetActive(false) is a real
            // FLOW/VISUAL defect, but it must not erase evidence for unrelated
            // navigation, Imp combat, Restart and lifecycle behavior. Retain an
            // inactive Boss as an observable semantic target only when it is the
            // real authored object with render and collider geometry. A separate
            // non-blocking presentation check records the visible defect.
            if (id == DungeonDuelActorId.Boss)
            {
                return HasEnabledRendererGeometry(target) &&
                       target.GetComponentsInChildren<Collider>(true).Any();
            }

            return target.activeInHierarchy && HasVisibleRenderer(target);
        }

        static bool HasVisibleRenderer(GameObject target) =>
            target.GetComponentsInChildren<Renderer>(true)
                .Any(renderer => renderer.enabled && renderer.gameObject.activeInHierarchy);

        static bool HasEnabledRendererGeometry(GameObject target) =>
            target.GetComponentsInChildren<Renderer>(true)
                .Any(renderer => renderer != null && renderer.enabled);

        static float RendererVolume(GameObject target)
        {
            Renderer[] renderers = target.GetComponentsInChildren<Renderer>(true);
            if (renderers.Length == 0) return 0f;
            Bounds bounds = renderers[0].bounds;
            foreach (Renderer renderer in renderers.Skip(1)) bounds.Encapsulate(renderer.bounds);
            return Mathf.Max(0.001f, bounds.size.x * bounds.size.y * bounds.size.z);
        }

        static float HorizontalDistance(Vector3 left, Vector3 right) =>
            Vector2.Distance(new Vector2(left.x, left.z), new Vector2(right.x, right.z));

        static string Normalize(string value) =>
            new string((value ?? string.Empty)
                .Where(char.IsLetterOrDigit).Select(char.ToLowerInvariant).ToArray());

        enum SemanticRole { Unknown, Player, Imp, Boss }

        sealed class ActorCandidate
        {
            public GameObject Target;
            public HealthBinding HealthBinding;
            public SemanticRole Role;
            public float RenderVolume;
            public float Health;
            public float MaxHealth;
        }

        sealed class NumericMember
        {
            public MemberInfo Member;
            public string Name;
            public float Value;
        }

        sealed class HealthBinding
        {
            readonly object instance;
            readonly MemberInfo first;
            readonly MemberInfo second;

            public HealthBinding(
                object instance,
                MemberInfo first,
                MemberInfo second,
                string source)
            {
                this.instance = instance;
                this.first = first;
                this.second = second;
                Source = source;
            }

            public string Source { get; }

            public bool TryRead(out float current, out float maximum)
            {
                if (!ReadNumeric(instance, first, out float left) ||
                    !ReadNumeric(instance, second, out float right))
                {
                    current = maximum = float.NaN;
                    return false;
                }
                current = Mathf.Min(left, right);
                maximum = Mathf.Max(left, right);
                return maximum > 0f && current >= -0.05f &&
                       current <= maximum + 0.05f;
            }
        }
    }
}
