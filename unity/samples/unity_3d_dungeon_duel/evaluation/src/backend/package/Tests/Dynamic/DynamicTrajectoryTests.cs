using System.Collections;
using NUnit.Framework;
using OmniGame.Benchmark.DungeonDuel.V2;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    [TestFixture]
    public sealed class DynamicTrajectoryTests
    {
        [UnityTest, Order(10)]
        public IEnumerator TRAJ01_CanonicalMoveFightGateDashVictoryRestart()
        {
            var recorder = new TrajectoryRecorder("canonical_success");
            var harness = new DungeonDuelTrajectoryHarness();
            yield return harness.LoadFresh(DungeonDuelTrajectoryIntent.CanonicalSuccess, recorder);

            DungeonDuelGameSnapshot initial = harness.Snapshot();
            DungeonDuelTrajectoryHarness.AudioSemanticState initialAudio =
                harness.CaptureAudioState();
            Check(recorder, "initial", "canonical.initial.playing",
                initial != null && initial.Phase == DungeonDuelGamePhase.Playing,
                "Playing", initial == null ? "null" : initial.Phase.ToString(),
                "The clean canonical scene must begin in the playable phase.");
            Check(recorder, "initial", "canonical.initial.gate_locked",
                initial != null && !initial.GateOpen && initial.GateBlocking,
                "closed blocking gate", recorder.Snapshot(initial),
                "The canonical journey must begin behind a closed blocking Boss gate.");
            Check(recorder, "initial", "canonical.initial.imps_alive",
                initial != null && initial.ImpsAlive == 2,
                "2 living Imps", initial == null ? "null" : initial.ImpsAlive.ToString(),
                "The canonical journey must begin with both Imps alive.");
            GameObject initialBoss = harness.ActorTarget(DungeonDuelActorId.Boss);
            Check(recorder, "initial", "canonical.initial.boss_presented",
                harness.IsActorPresented(DungeonDuelActorId.Boss),
                "the dormant Boss remains visibly staged behind the gate",
                initialBoss == null
                    ? "null"
                    : $"active={initialBoss.activeInHierarchy}; " +
                      $"renderers={initialBoss.GetComponentsInChildren<Renderer>(true).Length}",
                "The dormant Boss exists but is hidden instead of visibly staged in the opening encounter.");
            Check(recorder, "initial", "canonical.initial.dash_ready",
                initial != null && initial.DashCooldownRemaining <= 0.05f,
                "Dash ready", initial == null ? "null" : initial.DashCooldownRemaining.ToString("F2"),
                "Dash must be ready at the start of the canonical journey.");
            Check(recorder, "initial", "canonical.initial.audio.battle_loop",
                initialAudio.HasLoopingBattle,
                "at least one playing looping battle-music source",
                initialAudio.ToString(),
                "Active play did not expose native looping battle music.");
            if (!recorder.HasBlockingFailure)
            {
                yield return harness.CaptureFeedbackSurface(
                    "01_initial_play", recorder, "initial",
                    "canonical.initial.feedback_surface");
                yield return harness.ValidateHudSemantics(
                    initial, HudSemanticState.Initial, recorder, "initial",
                    "canonical.initial.hud_semantics");
            }

            if (!recorder.HasBlockingFailure)
            {
                Vector3 moveTarget = harness.WorldTarget(DungeonDuelWorldTargetId.MoveTargetA);
                yield return harness.Driver.ClickWorld(moveTarget, MouseButton.Left, recorder,
                    "move", "canonical.move.input.route");
                yield return harness.WaitFor(snapshot =>
                        HorizontalDistance(snapshot.Player.Position, moveTarget) <= 1.8f,
                    4f, recorder, "move", "canonical.move.reached",
                    "player settles near MoveTargetA",
                    "The real left-click did not move the player to the canonical target.");
            }

            if (!recorder.HasBlockingFailure)
            {
                GameObject impA = harness.ActorTarget(DungeonDuelActorId.ImpA);
                yield return harness.Driver.ClickActor(impA, MouseButton.Right, recorder,
                    "imp_a", "canonical.imp_a.input.route");
                yield return harness.WaitFor(snapshot => snapshot.ImpA.IsDead,
                    4f, recorder, "imp_a", "canonical.imp_a.dead", "ImpA dead",
                    "The selected first Imp did not die through normal approach/cooldown attacks.");
                DungeonDuelGameSnapshot afterImpA = harness.Snapshot();
                Check(recorder, "imp_a", "canonical.after_imp_a.gate_closed",
                    afterImpA != null && !afterImpA.GateOpen,
                    "gate remains closed", recorder.Snapshot(afterImpA),
                    "The Boss gate opened before both Imps were defeated.");
                Check(recorder, "imp_a", "canonical.after_imp_a.gate_blocking",
                    afterImpA != null && afterImpA.GateBlocking,
                    "gate remains physically blocking", recorder.Snapshot(afterImpA),
                    "The Boss gate stopped blocking after only one Imp was defeated.");
                Check(recorder, "imp_a", "canonical.after_imp_a.boss_dormant",
                    afterImpA != null && afterImpA.Boss.IsDormant && !afterImpA.Boss.IsDead,
                    "living dormant Boss", recorder.Snapshot(afterImpA?.Boss),
                    "The Boss activated before both Imps were defeated.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.ValidateHudSemantics(
                        afterImpA, HudSemanticState.GateLocked, recorder, "imp_a",
                        "canonical.after_imp_a.hud_semantics");
                }
            }

            if (!recorder.HasBlockingFailure)
            {
                yield return WaitRealtime(0.65f);
                GameObject impB = harness.ActorTarget(DungeonDuelActorId.ImpB);
                yield return harness.Driver.ClickActor(impB, MouseButton.Right, recorder,
                    "imp_b", "canonical.imp_b.input.route");
                yield return harness.WaitFor(snapshot => snapshot.ImpB.IsDead,
                    4f, recorder, "imp_b", "canonical.imp_b.dead", "ImpB dead",
                    "The selected second Imp did not die through normal approach/cooldown attacks.");
                DungeonDuelGameSnapshot afterImps = harness.Snapshot();
                Check(recorder, "imp_b", "canonical.gate.open",
                    afterImps != null && afterImps.GateOpen && !afterImps.GateBlocking,
                    "open non-blocking gate", recorder.Snapshot(afterImps),
                    "Defeating both Imps did not open and clear the Boss gate.");
                Check(recorder, "imp_b", "canonical.boss.active",
                    afterImps != null && !afterImps.Boss.IsDormant && !afterImps.Boss.IsDead,
                    "living active Boss", recorder.Snapshot(afterImps?.Boss),
                    "The Boss did not activate after the second Imp died.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.ValidateHudSemantics(
                        afterImps, HudSemanticState.GateOpen, recorder, "imp_b",
                        "canonical.gate.hud_semantics");
                }
            }

            if (!recorder.HasBlockingFailure)
            {
                GameObject boss = harness.ActorTarget(DungeonDuelActorId.Boss);
                yield return harness.Driver.MovePointerToActor(boss, recorder,
                    "dash_pointer", "canonical.pointer.route");
                Vector3 beforeDash = harness.Snapshot().Player.Position;
                yield return harness.Driver.PressKey(Key.Digit2, recorder,
                    "dash_key", "canonical.dash.input.route");
                yield return WaitRealtime(0.2f);
                DungeonDuelGameSnapshot afterDash = harness.Snapshot();
                Check(recorder, "dash_key", "canonical.dash.displacement",
                    afterDash != null && HorizontalDistance(beforeDash, afterDash.Player.Position) >= 3f,
                    "at least 3m displacement", recorder.Snapshot(afterDash?.Player),
                    "Keyboard 2 did not produce a meaningful Dash displacement.");
                Check(recorder, "dash_key", "canonical.dash.cooldown",
                    afterDash != null && afterDash.DashCooldownRemaining >= 2f,
                    "active cooldown near 3s",
                    afterDash == null ? "null" : afterDash.DashCooldownRemaining.ToString("F2"),
                    "Dash did not start its public cooldown.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.ValidateHudSemantics(
                        afterDash, HudSemanticState.DashCooldown, recorder, "dash_key",
                        "canonical.dash.hud_semantics");
                }
            }

            if (!recorder.HasBlockingFailure)
            {
                yield return WaitRealtime(0.45f);
                GameObject boss = harness.ActorTarget(DungeonDuelActorId.Boss);
                yield return harness.Driver.ClickActor(boss, MouseButton.Right, recorder,
                    "boss_attack", "canonical.boss.input.route");
                yield return harness.WaitFor(snapshot =>
                        snapshot.Phase == DungeonDuelGamePhase.Won && snapshot.Boss.IsDead,
                    6f, recorder, "boss_attack", "canonical.victory.reached",
                    "Boss dead and Victory phase",
                    "The selected Boss did not reach stable Victory through normal cooldown attacks.");
                DungeonDuelTrajectoryHarness.AudioSemanticState victoryAudio =
                    harness.CaptureAudioState();
                Check(recorder, "boss_attack", "canonical.victory.audio.transition",
                    victoryAudio.PlayingSourceCount > 0 &&
                    victoryAudio.HasTransitionFrom(initialAudio),
                    "Victory changes the native playing clip or loop mode",
                    victoryAudio.ToString(),
                    "Victory did not audibly transition away from looping battle music.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.CaptureFeedbackSurface(
                        "03_victory", recorder, "boss_attack",
                        "canonical.victory.feedback_surface");
                    yield return harness.ValidateHudSemantics(
                        harness.Snapshot(), HudSemanticState.Victory, recorder,
                        "boss_attack", "canonical.victory.hud_semantics");
                }

                Vector3 frozen = harness.Snapshot().Player.Position;
                Vector3 terminalTarget = harness.WorldTarget(DungeonDuelWorldTargetId.MoveTargetB);
                yield return harness.Driver.ClickWorld(terminalTarget, MouseButton.Left, recorder,
                    "terminal_probe", "canonical.terminal.input.route");
                yield return WaitRealtime(0.4f);
                DungeonDuelGameSnapshot terminal = harness.Snapshot();
                Check(recorder, "terminal_probe", "canonical.terminal.freeze",
                    terminal != null && terminal.Phase == DungeonDuelGamePhase.Won &&
                    HorizontalDistance(frozen, terminal.Player.Position) <= 0.2f,
                    "Victory remains stable and movement frozen", recorder.Snapshot(terminal),
                    "Terminal Victory accepted later movement or changed phase.");
            }

            if (!recorder.HasBlockingFailure)
            {
                int oldSceneHandle = harness.SceneHandle;
                yield return harness.ActivateVisibleRestartControl(
                    oldSceneHandle,
                    recorder,
                    "restart_ui",
                    "canonical.restart.control.visible",
                    "canonical.restart.control.top_hit",
                    "canonical.restart.input.route");
                yield return harness.WaitForRestartedScene(oldSceneHandle, recorder,
                    "restart_ui", "canonical.restart.semantic_reloaded");
                DungeonDuelGameSnapshot restarted = harness.Snapshot();
                Check(recorder, "restart_ui", "canonical.restart.initial",
                    IsInitialState(restarted), "complete initial state", recorder.Snapshot(restarted),
                    "Restart did not reconstruct the complete initial encounter.");
                DungeonDuelTrajectoryHarness.AudioSemanticState restartedAudio =
                    harness.CaptureAudioState();
                Check(recorder, "restart_ui", "canonical.restart.audio.restored",
                    restartedAudio.HasRestoredBattle(initialAudio),
                    "Restart restores the original looping battle-music identity",
                    restartedAudio.ToString(),
                    "Restart did not restore native looping battle music.");
                Check(recorder, "restart_ui", "canonical.restart.audio.no_duplicate",
                    restartedAudio.PlayingSourceCount > 0 &&
                    restartedAudio.PlayingSourceCount <=
                    Mathf.Max(1, initialAudio.PlayingSourceCount),
                    "Restart has no duplicated active music sources",
                    $"initial={initialAudio}; restarted={restartedAudio}",
                    "Restart layered duplicate playing music sources.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.CaptureFeedbackSurface(
                        "04_restart", recorder, "restart_ui",
                        "canonical.restart.feedback_surface");
                    yield return harness.ValidateHudSemantics(
                        restarted, HudSemanticState.Restarted, recorder, "restart_ui",
                        "canonical.restart.hud_semantics");
                }

                if (!recorder.HasBlockingFailure)
                {
                    Vector3 target = harness.WorldTarget(DungeonDuelWorldTargetId.MoveTargetA);
                    yield return harness.Driver.ClickWorld(target, MouseButton.Left, recorder,
                        "restart_move", "canonical.restart.move.input.route");
                    yield return harness.WaitFor(snapshot =>
                            HorizontalDistance(snapshot.Player.Position, target) <= 1.8f,
                        4f, recorder, "restart_move", "canonical.restart.move.reached",
                        "restarted player reaches MoveTargetA",
                        "Player input was not reusable after canonical Restart.");
                }
            }

            yield return harness.Dispose();
            Assert.That(recorder.Complete(), Is.True,
                "Canonical Dungeon Duel trajectory failed; inspect its evidence JSON.");
        }

        [UnityTest, Order(20)]
        public IEnumerator TRAJ02_NavigationAndCamera()
        {
            var recorder = new TrajectoryRecorder("navigation_camera");
            var harness = new DungeonDuelTrajectoryHarness();
            yield return harness.LoadFresh(DungeonDuelTrajectoryIntent.Navigation, recorder);

            DungeonDuelGameSnapshot initial = harness.Snapshot();
            Vector3 start = initial?.Player?.Position ?? Vector3.zero;
            Vector3 cameraStart = Camera.main == null ? Vector3.zero : Camera.main.transform.position;
            Vector3 targetA = harness.WorldTarget(DungeonDuelWorldTargetId.MoveTargetA);

            if (!recorder.HasBlockingFailure)
            {
                yield return harness.Driver.ClickWorld(targetA, MouseButton.Left, recorder,
                    "move_a", "navigation.move_a.input.route");
                yield return harness.WaitFor(snapshot =>
                        HorizontalDistance(snapshot.Player.Position, targetA) <= 1.8f,
                    5f, recorder, "move_a", "navigation.move_a.reached",
                    "player reaches MoveTargetA",
                    "The player did not settle near the first navigable target.");
                DungeonDuelGameSnapshot atA = harness.Snapshot();
                Check(recorder, "move_a", "navigation.move_a.distance",
                    atA != null && HorizontalDistance(start, atA.Player.Position) >= 2.5f,
                    "at least 2.5m movement", recorder.Snapshot(atA?.Player),
                    "The first click produced no meaningful player movement.");
                CheckPlayerVisible(recorder, "camera_a", "navigation.camera_a.player_visible",
                    atA?.Player?.Position ?? Vector3.zero);
            }

            Vector3 targetB = harness.WorldTarget(DungeonDuelWorldTargetId.MoveTargetB);
            Vector3 atAPosition = harness.Snapshot()?.Player?.Position ?? Vector3.zero;
            if (!recorder.HasBlockingFailure)
            {
                yield return harness.Driver.ClickWorld(targetB, MouseButton.Left, recorder,
                    "move_b", "navigation.move_b.input.route");
                yield return harness.WaitFor(snapshot =>
                        HorizontalDistance(snapshot.Player.Position, targetB) <= 2f,
                    7f, recorder, "move_b", "navigation.move_b.reached",
                    "player reaches MoveTargetB",
                    "The player did not settle near the second separated target.");
                DungeonDuelGameSnapshot atB = harness.Snapshot();
                Check(recorder, "move_b", "navigation.move_b.distance",
                    atB != null && HorizontalDistance(atAPosition, atB.Player.Position) >= 3.5f,
                    "at least 3.5m second movement", recorder.Snapshot(atB?.Player),
                    "The second target was not spatially distinct from the first.");
                CheckPlayerVisible(recorder, "camera_b", "navigation.camera_b.player_visible",
                    atB?.Player?.Position ?? Vector3.zero);
                Vector3 cameraEnd = Camera.main == null ? Vector3.zero : Camera.main.transform.position;
                Check(recorder, "camera_b", "navigation.camera.tracked_distance",
                    Vector3.Distance(cameraStart, cameraEnd) >= 2f,
                    "camera follows player by at least 2m", Vector3.Distance(cameraStart, cameraEnd).ToString("F2"),
                    "The gameplay camera did not follow the moving player.");
            }

            yield return harness.Dispose();
            Assert.That(recorder.Complete(), Is.True,
                "Navigation/camera trajectory failed; inspect its evidence JSON.");
        }

        [UnityTest, Order(30)]
        public IEnumerator TRAJ03_CombatLoop()
        {
            var recorder = new TrajectoryRecorder("combat_loop");
            var harness = new DungeonDuelTrajectoryHarness();
            yield return harness.LoadFresh(DungeonDuelTrajectoryIntent.PlayerCombat, recorder);

            if (!recorder.HasBlockingFailure)
            {
                DungeonDuelGameSnapshot tuning = harness.Snapshot();
                Check(recorder, "attack_one", "combat.initial.tuning",
                    HasExpectedTuning(tuning),
                    "GDD TUNING-01 actor health, speed, range, damage and cooldown",
                    DescribeTuning(tuning),
                    "The clean encounter tuning did not match the public GDD values.");
                DungeonDuelTrajectoryHarness.AudioSemanticState combatAudio =
                    harness.CaptureAudioState();
                Check(recorder, "attack_one", "combat.audio.battle_loop",
                    combatAudio.HasLoopingBattle,
                    "combat loop has playing looping battle music",
                    combatAudio.ToString(),
                    "The combat trajectory had no native looping battle soundtrack.");
                float healthBefore = harness.Snapshot().ImpA.Health;
                GameObject imp = harness.ActorTarget(DungeonDuelActorId.ImpA);
                yield return harness.Driver.ClickActor(imp, MouseButton.Right, recorder,
                    "attack_one", "combat.attack.input.route");
                yield return harness.WaitFor(snapshot => snapshot.ImpA.Health < healthBefore,
                    7f, recorder, "attack_one", "combat.attack.damage",
                    "ImpA health decreases after selection and approach",
                    "The real right-click did not select, approach, and damage ImpA.");
                if (!recorder.HasBlockingFailure)
                {
                    recorder.Pass("attack_one", "combat.attack.damage_input.route",
                        "the one routed right-click remains the selected combat intent",
                        "damage followed the original click without evaluator-side state mutation");
                }
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.CaptureFeedbackSurface(
                        "02_combat", recorder, "attack_one",
                        "combat.damage.feedback_surface");
                    yield return harness.ValidateHudSemantics(
                        harness.Snapshot(), HudSemanticState.CombatDamage, recorder,
                        "attack_one", "combat.damage.hud_semantics");
                }
            }

            if (!recorder.HasBlockingFailure)
            {
                yield return harness.WaitFor(snapshot => snapshot.ImpA.IsDead,
                    4f, recorder, "attack_finish", "combat.followup.resolution",
                    "the selected target continues through cooldown attacks until death",
                    "Combat stopped after the first damage event instead of resolving the selected Imp.");
                DungeonDuelGameSnapshot afterFirst = harness.Snapshot();
                Check(recorder, "attack_finish", "combat.imp.dead",
                    afterFirst != null && afterFirst.ImpA.IsDead,
                    "ImpA reaches stable death", recorder.Snapshot(afterFirst?.ImpA),
                    "The selected Imp did not reach stable death.");
                yield return WaitRealtime(0.5f);
                DungeonDuelGameSnapshot stable = harness.Snapshot();
                Check(recorder, "attack_finish", "combat.imp.stable_dead",
                    stable != null && stable.ImpA.IsDead,
                    "Imp remains dead and out of combat", recorder.Snapshot(stable?.ImpA),
                    "The defeated Imp returned to active combat.");
            }

            if (!recorder.HasBlockingFailure)
            {
                yield return harness.LoadFresh(DungeonDuelTrajectoryIntent.EnemyThreat, recorder,
                    "threat_setup", "threat_setup");
                DungeonDuelGameSnapshot before = harness.Snapshot();
                float initialDistance = before == null ? float.MaxValue :
                    HorizontalDistance(before.Player.Position, before.ImpA.Position);
                Vector3 engage = harness.WorldTarget(
                    DungeonDuelWorldTargetId.MoveTargetA);
                yield return harness.Driver.ClickWorld(
                    engage, MouseButton.Left, recorder,
                    "threat", "combat.threat.engage.input.route");
                const float threatTimeout = 10f;
                yield return harness.WaitFor(snapshot => snapshot.Player.Health < before.Player.Health,
                    threatTimeout, recorder, "threat", "combat.threat.damage",
                    "player HP reduced by live enemy AI",
                    "A living Imp did not damage the player without evaluator-side damage injection.");
                DungeonDuelGameSnapshot after = harness.Snapshot();
                float finalDistance = after == null ? float.MaxValue :
                    HorizontalDistance(after.Player.Position, after.ImpA.Position);
                Check(recorder, "threat", "combat.threat.approach",
                    after != null && finalDistance <= initialDistance + 0.25f && finalDistance <= 3.2f,
                    "Imp approaches into attack range",
                    $"initial={initialDistance:F2}, final={finalDistance:F2}",
                    "The enemy threat did not approach or remain in its valid attack range.");
                Check(recorder, "threat", "combat.threat.player_alive",
                    after != null && !after.Player.IsDead && after.Player.Health > 0f,
                    "player damaged but still alive", recorder.Snapshot(after?.Player),
                    "The threat trajectory could not isolate a non-terminal enemy damage event.");
            }

            yield return harness.Dispose();
            Assert.That(recorder.Complete(), Is.True,
                "Combat trajectory failed; inspect its evidence JSON.");
        }

        [UnityTest, Order(40)]
        public IEnumerator TRAJ04_DashAndGate()
        {
            var recorder = new TrajectoryRecorder("dash_gate");
            var harness = new DungeonDuelTrajectoryHarness();
            yield return harness.LoadFresh(DungeonDuelTrajectoryIntent.Dash, recorder);

            Vector3 dashTarget = harness.WorldTarget(DungeonDuelWorldTargetId.DashTarget);
            Vector3 beforeDash = harness.Snapshot()?.Player?.Position ?? Vector3.zero;
            if (!recorder.HasBlockingFailure)
            {
                yield return harness.Driver.MovePointerToWorld(dashTarget, recorder,
                    "dash_pointer", "dash.pointer.route");
                yield return harness.Driver.PressKey(Key.Digit2, recorder,
                    "dash_one", "dash.first.input.route");
                yield return WaitRealtime(0.15f);
                DungeonDuelGameSnapshot afterDash = harness.Snapshot();
                Check(recorder, "dash_one", "dash.first.displacement",
                    afterDash != null && HorizontalDistance(beforeDash, afterDash.Player.Position) >= 3f,
                    "at least 3m Dash", recorder.Snapshot(afterDash?.Player),
                    "Keyboard 2 did not create meaningful Dash displacement.");
                Check(recorder, "dash_one", "dash.first.cooldown",
                    afterDash != null && afterDash.DashCooldownRemaining >= 2f,
                    "cooldown active", afterDash == null ? "null" :
                        afterDash.DashCooldownRemaining.ToString("F2"),
                    "Dash did not start its cooldown.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.ValidateHudSemantics(
                        afterDash, HudSemanticState.DashCooldown, recorder,
                        "dash_one", "dash.cooldown.hud_semantics");
                }
            }

            Vector3 afterFirstPosition = harness.Snapshot()?.Player?.Position ?? Vector3.zero;
            if (!recorder.HasBlockingFailure)
            {
                yield return harness.Driver.PressKey(Key.Digit2, recorder,
                    "dash_repeat", "dash.repeat.input.route");
                yield return WaitRealtime(0.2f);
                DungeonDuelGameSnapshot repeated = harness.Snapshot();
                Check(recorder, "dash_repeat", "dash.repeat.blocked",
                    repeated != null && HorizontalDistance(afterFirstPosition,
                        repeated.Player.Position) <= 0.4f,
                    "immediate repeat rejected", recorder.Snapshot(repeated?.Player),
                    "Dash cooldown allowed an immediate second displacement.");
            }

            if (!recorder.HasBlockingFailure)
            {
                yield return harness.WaitFor(snapshot => snapshot.DashCooldownRemaining <= 0.001f,
                    4.3f, recorder, "dash_recover", "dash.cooldown.recovered",
                    "Dash cooldown returns to ready",
                    "Dash did not become ready again after its public cooldown.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.ValidateHudSemantics(
                        harness.Snapshot(), HudSemanticState.DashReady, recorder,
                        "dash_recover", "dash.ready.hud_semantics");
                }
                Vector3 beforeSecond = harness.Snapshot().Player.Position;
                yield return harness.Driver.PressKey(Key.Digit2, recorder,
                    "dash_recover", "dash.second.input.route");
                yield return WaitRealtime(0.15f);
                DungeonDuelGameSnapshot afterSecond = harness.Snapshot();
                Check(recorder, "dash_recover", "dash.second.displacement",
                    afterSecond != null && HorizontalDistance(beforeSecond,
                        afterSecond.Player.Position) >= 2.5f,
                    "Dash reusable after cooldown", recorder.Snapshot(afterSecond?.Player),
                    "Dash did not become reusable after cooldown recovery.");
            }

            if (!recorder.HasBlockingFailure)
            {
                yield return harness.LoadFresh(DungeonDuelTrajectoryIntent.GateUnlock, recorder,
                    "gate_setup", "gate_setup");
                if (!recorder.HasBlockingFailure)
                {
                    Vector3 approach = harness.WorldTarget(
                        DungeonDuelWorldTargetId.MoveTargetA);
                    yield return harness.Driver.ClickWorld(
                        approach, MouseButton.Left, recorder,
                        "gate_prepare", "gate.prepare.approach.input.route");
                    yield return WaitUntilActorWithin(
                        harness, DungeonDuelActorId.ImpA, 3.35f, 6f);
                    GameObject firstImp = harness.ActorTarget(DungeonDuelActorId.ImpA);
                    yield return harness.Driver.ClickActor(firstImp, MouseButton.Right, recorder,
                        "gate_prepare", "gate.prepare.first_imp.resolution");
                    yield return harness.WaitFor(snapshot => snapshot.ImpA.IsDead,
                        4f, recorder, "gate_prepare", "gate.prepare.first_imp.dead",
                        "one Imp defeated through real input",
                        "Native canonical preparation could not reach the one-Imp gate state.");
                }
                DungeonDuelGameSnapshot beforeGate = harness.Snapshot();
                Check(recorder, "gate_setup", "gate.before.closed",
                    beforeGate != null && beforeGate.ImpsAlive == 1 && !beforeGate.GateOpen,
                    "gate closed with one Imp alive", recorder.Snapshot(beforeGate),
                    "The final-Imp state did not have exactly one living Imp and a closed gate.");
                Check(recorder, "gate_setup", "gate.before.blocking",
                    beforeGate != null && beforeGate.GateBlocking,
                    "gate collision enabled", recorder.Snapshot(beforeGate),
                    "The closed Boss gate was not physically blocking.");
                Check(recorder, "gate_setup", "gate.before.boss_dormant",
                    beforeGate != null && beforeGate.Boss.IsDormant,
                    "Boss dormant", recorder.Snapshot(beforeGate?.Boss),
                    "The Boss activated before the final Imp died.");

                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.ValidateHudSemantics(
                        beforeGate, HudSemanticState.GateLocked, recorder,
                        "gate_setup", "gate.before.hud_semantics");
                    bool targetFound = harness.TryBuildBeyondGateTarget(
                        out Vector3 beyondGate, out string targetObservation);
                    string stagingFailure = null;
                    for (int hop = 1; hop <= 3; hop++)
                    {
                        string routeId = $"gate.stage.hop{hop}.input.route";
                        string progressId = $"gate.stage.hop{hop}.progress";
                        if (targetFound)
                        {
                            recorder.Pass("gate_stage", routeId,
                                "normal LMB staging only when the current view cannot reach gate-side ground",
                                "not required; " + targetObservation);
                            recorder.Pass("gate_stage", progressId,
                                "camera is close enough to discover native Boss-side ground",
                                "not required; beyond-gate target already visible");
                            continue;
                        }

                        if (!harness.TryBuildGateApproachTarget(
                                out Vector3 approach, out string approachObservation))
                        {
                            recorder.Fail("gate_stage", routeId,
                                "camera-projectable real ground on the player's side that approaches the gate",
                                approachObservation,
                                "No normal-input staging target toward the gate was visible from the current camera.");
                            recorder.Block("gate_stage", progressId, routeId);
                            stagingFailure = routeId;
                            break;
                        }

                        float beforeDistance = HorizontalDistance(
                            harness.Snapshot().Player.Position, harness.GateCenter);
                        yield return harness.Driver.ClickWorld(
                            approach, MouseButton.Left, recorder, "gate_stage", routeId);
                        if (recorder.HasBlockingFailure)
                        {
                            stagingFailure = routeId;
                            break;
                        }
                        yield return harness.WaitFor(snapshot => snapshot != null &&
                                !snapshot.Player.IsDead &&
                                (HorizontalDistance(snapshot.Player.Position, harness.GateCenter) <=
                                 beforeDistance - 1f ||
                                 HorizontalDistance(snapshot.Player.Position, approach) <= 2.25f),
                            6f, recorder, "gate_stage", progressId,
                            "normal LMB movement makes measurable start-side progress toward the gate",
                            "The staged gate approach did not make normal movement progress.");
                        if (recorder.HasBlockingFailure)
                        {
                            stagingFailure = progressId;
                            break;
                        }
                        yield return WaitRealtime(0.3f);
                        targetFound = harness.TryBuildBeyondGateTarget(
                            out beyondGate, out targetObservation);
                    }

                    if (stagingFailure != null)
                    {
                        recorder.Block("gate_setup", "gate.behind_target.discovered",
                            stagingFailure,
                            "Beyond-gate discovery could not continue because normal start-side staging failed.");
                    }
                    else
                    {
                        Check(recorder, "gate_setup", "gate.behind_target.discovered",
                            targetFound,
                            "camera-projectable destination beyond the native gate plane",
                            targetObservation,
                            "No implementation-neutral destination beyond the Boss gate was discoverable after normal start-side staging.");
                    }

                    if (!recorder.HasBlockingFailure)
                    {
                        float bossHealthBefore = beforeGate.Boss.Health;
                        Vector3 bossPositionBefore = beforeGate.Boss.Position;
                        GameObject boss = harness.ActorTarget(DungeonDuelActorId.Boss);
                        yield return harness.Driver.ClickActor(boss, MouseButton.Right, recorder,
                            "gate_locked_boss", "gate.locked_boss.input.route");
                        yield return WaitRealtime(0.45f);
                        DungeonDuelGameSnapshot lockedBoss = harness.Snapshot();
                        Check(recorder, "gate_locked_boss", "gate.before.boss_unattackable",
                            lockedBoss != null && lockedBoss.Boss.IsDormant &&
                            Mathf.Abs(lockedBoss.Boss.Health - bossHealthBefore) <= 0.01f &&
                            HorizontalDistance(lockedBoss.Boss.Position, bossPositionBefore) <= 0.15f,
                            "dormant Boss ignores attacks before unlock",
                            recorder.Snapshot(lockedBoss?.Boss),
                            "The Boss reacted to or took damage before the gate prerequisite completed.");

                        Vector3 startSide = lockedBoss.Player.Position;
                        yield return harness.Driver.ClickWorld(beyondGate, MouseButton.Left, recorder,
                            "gate_block_probe", "gate.blocked_move.input.route", true);
                        yield return WaitRealtime(2.2f);
                        DungeonDuelGameSnapshot blocked = harness.Snapshot();
                        Check(recorder, "gate_block_probe", "gate.before.physical_block",
                            blocked != null && harness.IsGateBlocking &&
                            !harness.IsBeyondGate(startSide, blocked.Player.Position),
                            "closed native collider prevents crossing the gate plane",
                            recorder.Snapshot(blocked?.Player),
                            "The player crossed the closed gate or no real blocking collider remained.");
                    }
                }

                if (!recorder.HasBlockingFailure)
                {
                    GameObject imp = harness.ActorTarget(DungeonDuelActorId.ImpB);
                    yield return harness.Driver.ClickActor(imp, MouseButton.Right, recorder,
                        "gate_unlock", "gate.final_imp.input.route");
                    yield return harness.WaitFor(snapshot => snapshot.ImpB.IsDead,
                        4f, recorder, "gate_unlock", "gate.final_imp.dead",
                        "final Imp dead", "The real final-Imp attack did not kill it.");
                    DungeonDuelGameSnapshot opened = harness.Snapshot();
                    Check(recorder, "gate_unlock", "gate.after.open",
                        opened != null && opened.GateOpen,
                        "gate open", recorder.Snapshot(opened),
                        "The second Imp death did not open the gate.");
                    Check(recorder, "gate_unlock", "gate.after.nonblocking",
                        opened != null && !opened.GateBlocking,
                        "gate collision cleared", recorder.Snapshot(opened),
                        "The opened gate still blocks the player.");
                    Check(recorder, "gate_unlock", "gate.after.boss_active",
                        opened != null && !opened.Boss.IsDormant,
                        "Boss active", recorder.Snapshot(opened?.Boss),
                        "The Boss remained dormant after the gate opened.");
                    if (!recorder.HasBlockingFailure)
                    {
                        yield return harness.ValidateHudSemantics(
                            opened, HudSemanticState.GateOpen, recorder,
                            "gate_unlock", "gate.after.hud_semantics");
                        bool targetFound = harness.TryBuildBeyondGateTarget(
                            out Vector3 beyondGate, out string targetObservation);
                        Check(recorder, "gate_cross", "gate.after.target.discovered",
                            targetFound,
                            "visible target beyond the opened gate",
                            targetObservation,
                            "The opened gate had no discoverable destination on the Boss side.");
                        if (!recorder.HasBlockingFailure)
                        {
                            Vector3 startSide = opened.Player.Position;
                            yield return harness.Driver.ClickWorld(
                                beyondGate, MouseButton.Left, recorder,
                                "gate_cross", "gate.after.cross.input.route");
                            yield return harness.WaitFor(snapshot =>
                                    harness.IsBeyondGate(startSide, snapshot.Player.Position),
                                4f, recorder, "gate_cross", "gate.after.crossed",
                                "player crosses the former gate plane",
                                "Clearing the gate collider did not let the player enter the Boss side.");
                        }
                        if (!recorder.HasBlockingFailure)
                        {
                            DungeonDuelGameSnapshot beforeBossAttack = harness.Snapshot();
                            GameObject boss = harness.ActorTarget(DungeonDuelActorId.Boss);
                            yield return harness.Driver.ClickActor(
                                boss, MouseButton.Right, recorder,
                                "gate_boss_attack", "gate.after.boss_attack.input.route");
                            yield return harness.WaitFor(snapshot =>
                                    snapshot.Boss.Health < beforeBossAttack.Boss.Health,
                                1.5f, recorder, "gate_boss_attack",
                                "gate.after.boss_damage",
                                "active Boss loses native Health after a real attack",
                                "The unlocked active Boss did not take damage after the player crossed the gate.");
                        }
                    }
                }
            }

            yield return harness.Dispose();
            Assert.That(recorder.Complete(), Is.True,
                "Dash/gate trajectory failed; inspect its evidence JSON.");
        }

        [UnityTest, Order(50)]
        public IEnumerator TRAJ05_DefeatAndRestart()
        {
            var recorder = new TrajectoryRecorder("defeat_restart");
            var harness = new DungeonDuelTrajectoryHarness();
            yield return harness.LoadFresh(DungeonDuelTrajectoryIntent.DefeatReady, recorder);

            float healthBefore = harness.Snapshot()?.Player?.Health ?? 0f;
            if (!recorder.HasBlockingFailure)
            {
                Vector3 engage = harness.WorldTarget(
                    DungeonDuelWorldTargetId.MoveTargetA);
                yield return harness.Driver.ClickWorld(
                    engage, MouseButton.Left, recorder,
                    "defeat_engage", "defeat.engage.resolution");
                const float damageTimeout = 10f;
                const float deathTimeout = 20f;
                yield return harness.WaitFor(snapshot => snapshot.Player.Health < healthBefore,
                    damageTimeout, recorder, "defeat", "defeat.enemy_damage",
                    "enemy AI reduces player HP",
                    "The normally engaged living enemy caused no player damage.");
                yield return harness.WaitFor(snapshot => snapshot.Player.IsDead,
                    deathTimeout, recorder, "defeat", "defeat.player_zero",
                    "player health reaches zero",
                    "Enemy attacks did not reach player death.");
                DungeonDuelGameSnapshot defeated = harness.Snapshot();
                Check(recorder, "defeat", "defeat.phase",
                    defeated != null && defeated.Phase == DungeonDuelGamePhase.Lost,
                    "Defeat phase", recorder.Snapshot(defeated),
                    "Player death did not produce the Defeat outcome.");
                yield return WaitRealtime(0.5f);
                DungeonDuelGameSnapshot stable = harness.Snapshot();
                Check(recorder, "defeat", "defeat.terminal_stable",
                    stable != null && stable.Phase == DungeonDuelGamePhase.Lost && stable.Player.IsDead,
                    "stable Defeat", recorder.Snapshot(stable),
                    "The Defeat result was not stable over time.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.CaptureFeedbackSurface(
                        "04_defeat", recorder, "defeat",
                        "defeat.feedback_surface");
                    yield return harness.ValidateHudSemantics(
                        stable, HudSemanticState.Defeat, recorder, "defeat",
                        "defeat.hud_semantics");
                }
            }

            if (!recorder.HasBlockingFailure)
            {
                int oldSceneHandle = harness.SceneHandle;
                yield return harness.Driver.PressKey(Key.R, recorder,
                    "restart", "defeat.restart.input.route");
                yield return harness.WaitForRestartedScene(oldSceneHandle, recorder,
                    "restart", "defeat.restart.semantic_reloaded");
                DungeonDuelGameSnapshot restarted = harness.Snapshot();
                Check(recorder, "restart", "defeat.restart.initial",
                    IsInitialState(restarted), "complete initial state", recorder.Snapshot(restarted),
                    "Restart from Defeat did not reconstruct the complete initial state.");
                yield return WaitRealtime(0.5f);
                DungeonDuelGameSnapshot stable = harness.Snapshot();
                Check(recorder, "restart", "defeat.restart.no_stale_terminal",
                    stable != null && stable.Phase == DungeonDuelGamePhase.Playing && !stable.Player.IsDead,
                    "no stale Defeat after delay", recorder.Snapshot(stable),
                    "A stale terminal state polluted the restarted game.");
                if (!recorder.HasBlockingFailure)
                {
                    yield return harness.CaptureFeedbackSurface(
                        "05_defeat_restart", recorder, "restart",
                        "defeat.restart.feedback_surface");
                    yield return harness.ValidateHudSemantics(
                        stable, HudSemanticState.Restarted, recorder, "restart",
                        "defeat.restart.hud_semantics");
                }
            }

            if (!recorder.HasBlockingFailure)
            {
                // The lateral target remains usable even when both naturally
                // active Imps converge on the direct forward lane after a
                // keyboard Restart.  The check still requires a fresh routed
                // LMB movement rather than accepting Dash displacement.
                Vector3 target = harness.WorldTarget(
                    DungeonDuelWorldTargetId.MoveTargetB);
                yield return harness.Driver.ClickWorld(target, MouseButton.Left, recorder,
                    "move", "defeat.restart.move.input.route");
                yield return harness.WaitFor(snapshot =>
                        HorizontalDistance(snapshot.Player.Position, target) <= 2f,
                    7f, recorder, "move", "defeat.restart.move.reached",
                    "restarted player reaches a separated native target",
                    "Movement was not reusable after restarting from Defeat.");
            }

            yield return harness.Dispose();
            Assert.That(recorder.Complete(), Is.True,
                "Defeat/Restart trajectory failed; inspect its evidence JSON.");
        }

        /// <summary>
        /// The final Dynamic test deliberately leaves ordinary runtime progress
        /// dirty.  The runner then closes this Unity process completely and
        /// launches the independent Fresh phase.  No restart or scene reload is
        /// performed here after the mutation.
        /// </summary>
        [UnityTest, Order(999)]
        public IEnumerator TRAJ99_LeaveDirtyStateForFreshProcess()
        {
            var recorder = new TrajectoryRecorder("reopen_prepare");
            var harness = new DungeonDuelTrajectoryHarness();
            yield return harness.LoadFresh(
                DungeonDuelTrajectoryIntent.CanonicalSuccess, recorder);

            DungeonDuelGameSnapshot initial = harness.Snapshot();
            Check(recorder, "initial", "reopen.prepare.initial_clean",
                IsInitialState(initial), "fresh FLOW-01 before dirtying",
                recorder.Snapshot(initial),
                "The reopen preparation could not begin from a clean encounter.");

            Vector3 beforeDash = initial?.Player?.Position ?? Vector3.zero;
            if (!recorder.HasBlockingFailure)
            {
                Vector3 dashTarget = harness.WorldTarget(
                    DungeonDuelWorldTargetId.DashTarget);
                yield return harness.Driver.MovePointerToWorld(
                    dashTarget, recorder, "dash_pointer",
                    "reopen.prepare.dash.pointer.route");
                yield return harness.Driver.PressKey(
                    Key.Digit2, recorder, "dash",
                    "reopen.prepare.dash.input.route");
                yield return WaitRealtime(0.15f);
                DungeonDuelGameSnapshot dashed = harness.Snapshot();
                Check(recorder, "dash", "reopen.prepare.dash.dirty",
                    dashed != null &&
                    HorizontalDistance(beforeDash, dashed.Player.Position) >= 2.5f &&
                    dashed.DashCooldownRemaining > 0.1f,
                    "moved Player with spent Dash cooldown",
                    recorder.Snapshot(dashed),
                    "The Dynamic process did not create a dirty Dash/movement state.");
            }

            if (!recorder.HasBlockingFailure)
            {
                GameObject imp = harness.ActorTarget(DungeonDuelActorId.ImpA);
                yield return harness.Driver.ClickActor(
                    imp, MouseButton.Right, recorder, "imp",
                    "reopen.prepare.imp.input.route");
                yield return harness.WaitFor(snapshot => snapshot.ImpA.IsDead,
                    4f, recorder, "imp", "reopen.prepare.imp.dead",
                    "one native Imp remains dead in the closing process",
                    "The Dynamic process could not leave enemy-death progress dirty.");
            }

            DungeonDuelGameSnapshot dirty = harness.Snapshot();
            bool dirtyState = dirty != null &&
                              (dirty.ImpA.IsDead || dirty.ImpsAlive < 2 ||
                               dirty.GateOpen ||
                               dirty.Phase != DungeonDuelGamePhase.Playing ||
                               dirty.DashCooldownRemaining > 0.1f ||
                               HorizontalDistance(beforeDash,
                                   dirty.Player.Position) >= 2.5f);
            Check(recorder, "dirty", "reopen.prepare.dirty_state",
                dirtyState,
                "health/death/progression/terminal/cooldown or position differs from FLOW-01",
                recorder.Snapshot(dirty),
                "No observable dirty runtime state existed before closing Dynamic.");
            Check(recorder, "dirty", "reopen.prepare.no_restart",
                dirtyState && SceneManager.GetActiveScene().isLoaded &&
                harness.SceneHandle == SceneManager.GetActiveScene().handle,
                "dirty scene remains loaded without Restart",
                $"sceneHandle={harness.SceneHandle}; {recorder.Snapshot(dirty)}",
                "The preparation did not leave the dirty encounter loaded for process close.");

            // Dispose only the evaluator's virtual devices.  The gameplay scene
            // and its dirty runtime state intentionally remain loaded until the
            // Unity Dynamic process exits.
            yield return harness.Dispose();
            Assert.That(recorder.Complete(), Is.True,
                "Reopen preparation failed; inspect reopen_prepare.json.");
        }

        static bool IsInitialState(DungeonDuelGameSnapshot snapshot) =>
            snapshot != null && snapshot.Phase == DungeonDuelGamePhase.Playing &&
            snapshot.Player != null && !snapshot.Player.IsDead &&
            Mathf.Abs(snapshot.Player.Health - snapshot.Player.MaxHealth) <= 0.01f &&
            snapshot.ImpsAlive == 2 && snapshot.Boss != null && snapshot.Boss.IsDormant &&
            !snapshot.GateOpen && snapshot.GateBlocking && snapshot.DashCooldownRemaining <= 0.05f;

        static bool HasExpectedTuning(DungeonDuelGameSnapshot snapshot) =>
            snapshot != null &&
            ActorTuningMatches(snapshot.Player, 120f, 7f, 3.2f, 34f, 0.55f) &&
            ActorTuningMatches(snapshot.ImpA, 62f, 3.8f, 2.1f, 8f, 1.10f) &&
            ActorTuningMatches(snapshot.ImpB, 62f, 3.8f, 2.1f, 8f, 1.10f) &&
            ActorTuningMatches(snapshot.Boss, 185f, 3.6f, 2.8f, 17f, 1.25f);

        static bool ActorTuningMatches(
            DungeonDuelActorSnapshot actor,
            float health,
            float speed,
            float range,
            float damage,
            float cooldown) =>
            actor != null &&
            Mathf.Abs(actor.MaxHealth - health) <= 0.05f &&
            Mathf.Abs(actor.MoveSpeed - speed) <= 0.05f &&
            Mathf.Abs(actor.AttackRange - range) <= 0.05f &&
            Mathf.Abs(actor.AttackDamage - damage) <= 0.05f &&
            Mathf.Abs(actor.AttackCooldown - cooldown) <= 0.02f;

        static string DescribeTuning(DungeonDuelGameSnapshot snapshot) =>
            snapshot == null
                ? "null"
                : $"P={DescribeTuning(snapshot.Player)}; A={DescribeTuning(snapshot.ImpA)}; " +
                  $"B={DescribeTuning(snapshot.ImpB)}; Boss={DescribeTuning(snapshot.Boss)}";

        static string DescribeTuning(DungeonDuelActorSnapshot actor) =>
            actor == null
                ? "null"
                : $"hp={actor.MaxHealth:F2},speed={actor.MoveSpeed:F2}," +
                  $"range={actor.AttackRange:F2},damage={actor.AttackDamage:F2}," +
                  $"cooldown={actor.AttackCooldown:F2}";

        static void CheckPlayerVisible(
            TrajectoryRecorder recorder,
            string stepId,
            string checkId,
            Vector3 playerPosition)
        {
            Camera camera = Camera.main;
            Vector3 viewport = camera == null ? new Vector3(-1f, -1f, -1f) :
                camera.WorldToViewportPoint(playerPosition + Vector3.up);
            bool visible = camera != null && viewport.z > 0f &&
                           viewport.x >= 0.05f && viewport.x <= 0.95f &&
                           viewport.y >= 0.05f && viewport.y <= 0.95f;
            Check(recorder, stepId, checkId, visible, "player inside camera viewport",
                viewport.ToString("F3"), "The gameplay camera lost the live player.");
        }

        static void Check(
            TrajectoryRecorder recorder,
            string stepId,
            string checkId,
            bool condition,
            string expected,
            string observed,
            string failure)
        {
            if (condition)
            {
                recorder.Pass(stepId, checkId, expected, observed);
            }
            else
            {
                recorder.Fail(stepId, checkId, expected, observed, failure);
            }
        }

        static float HorizontalDistance(Vector3 left, Vector3 right) =>
            Vector2.Distance(new Vector2(left.x, left.z), new Vector2(right.x, right.z));

        static IEnumerator WaitUntilActorWithin(
            DungeonDuelTrajectoryHarness harness,
            DungeonDuelActorId actorId,
            float maximumDistance,
            float timeoutSeconds)
        {
            float deadline = Time.realtimeSinceStartup + timeoutSeconds;
            while (Time.realtimeSinceStartup < deadline)
            {
                DungeonDuelGameSnapshot snapshot = harness.Snapshot();
                DungeonDuelActorSnapshot actor = snapshot == null
                    ? null
                    : actorId == DungeonDuelActorId.ImpA
                        ? snapshot.ImpA
                        : actorId == DungeonDuelActorId.ImpB
                            ? snapshot.ImpB
                            : actorId == DungeonDuelActorId.Boss
                                ? snapshot.Boss
                                : snapshot.Player;
                if (snapshot?.Player != null && actor != null &&
                    HorizontalDistance(snapshot.Player.Position, actor.Position) <= maximumDistance)
                    yield break;
                yield return null;
            }
        }

        static IEnumerator WaitRealtime(float seconds)
        {
            float until = Time.realtimeSinceStartup + seconds;
            while (Time.realtimeSinceStartup < until)
            {
                yield return null;
            }
        }
    }
}



