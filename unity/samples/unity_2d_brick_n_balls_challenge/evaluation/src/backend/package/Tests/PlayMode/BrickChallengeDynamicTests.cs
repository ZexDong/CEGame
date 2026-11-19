using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using NUnit.Framework;
using OmniGame.Benchmark.BrickChallenge.Contracts;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using UnityEngine.UI;
using Object = UnityEngine.Object;

namespace OmniGame.Benchmark.BrickChallenge.Evaluator.PlayMode
{
    public sealed class BrickChallengeDynamicTests
    {
        private enum Boundary
        {
            Left,
            Right,
            Top
        }

        private const string SessionEnvironment = "BRICK_EVALUATION_SESSION_ID";
        private const string ReopenReceiptEnvironment = "BRICK_REOPEN_RECEIPT_PATH";
        private Mouse mouse;
        private Keyboard keyboard;
        private IBrickChallengeProbe probe;

        private sealed class AudioCueObservation
        {
            public bool CueSeen;
            public bool SourcePlaying;
            public float PeakOutput;
            public int Sequence;
            public BrickChallengeAudioCue LastCue;
        }

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            EmitIdentity("playmode");
            InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
#if UNITY_EDITOR
            InputSystem.settings.editorInputBehaviorInPlayMode = InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
#endif
            foreach (Mouse device in InputSystem.devices.OfType<Mouse>().ToArray()) InputSystem.DisableDevice(device);
            mouse = InputSystem.AddDevice<Mouse>("BrickEvaluatorMouse");
            keyboard = InputSystem.AddDevice<Keyboard>("BrickEvaluatorKeyboard");
            mouse.MakeCurrent();
            TestContext.WriteLine("BENCHMARK_INPUT_ROUTE=NewInputSystemVirtualMouseKeyboard");
            Screen.SetResolution(1280, 720, false);
            yield return null;
            AsyncOperation load = SceneManager.LoadSceneAsync("BrickChallenge", LoadSceneMode.Single);
            while (!load.isDone) yield return null;
            for (int i = 0; i < 3; i++) yield return null;
            probe = Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .OfType<IBrickChallengeProbe>().SingleOrDefault();
            Assert.That(probe, Is.Not.Null, "Exactly one active public probe is required.");
            AssertCleanMenu(true);
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            if (mouse != null && mouse.added) InputSystem.RemoveDevice(mouse);
            if (keyboard != null && keyboard.added) InputSystem.RemoveDevice(keyboard);
            yield return null;
        }

        [UnityTest]
        public IEnumerator D2_MenuStartAndOriginalInitialContent_15()
        {
            yield return StartRun();
            AssertInitialRun();
        }

        [UnityTest]
        public IEnumerator D2_CompleteClickLaunchesVisibleMovingBall_15()
        {
            yield return StartRun();
            Vector2 point = PrimaryBrickTarget();
            yield return Click(point);
            Assert.That(probe.BallsRemaining, Is.EqualTo(2));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(1));
            Vector2 before = probe.ActiveBallScreenPositions.Single();
            yield return new WaitForSecondsRealtime(0.12f);
            Vector2 after = probe.ActiveBallScreenPositions.Single();
            Assert.That(Vector2.Distance(before, after), Is.GreaterThan(2f), "The launched visible ball must move across real frames.");
        }

        [UnityTest]
        public IEnumerator D3_OneFullClickConsumesExactlyOneBall_4()
        {
            yield return StartRun();
            Vector2 point = PrimaryBrickTarget();
            yield return PressOnly(point);
            Assert.That(probe.BallsRemaining, Is.EqualTo(3), "A half-action cannot consume a ball.");
            yield return Release(point);
            Assert.That(probe.BallsRemaining, Is.EqualTo(2));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(1));
            yield return new WaitForSecondsRealtime(0.08f);
            Assert.That(probe.BallsRemaining, Is.EqualTo(2), "Holding/release must not duplicate one full click.");
        }

        [UnityTest]
        public IEnumerator D3_OneContactChangesOnlyOneBrickByExactlyOneHealth_4()
        {
            yield return StartRun();
            Dictionary<int, int> before = VisibleHealth();
            yield return Click(PrimaryBrickTarget());
            yield return WaitForScoreAtLeast(1, 8f);
            Dictionary<int, int> after = VisibleHealth();
            List<int> changed = before.Keys.Where(id => after.ContainsKey(id) && after[id] != before[id]).ToList();
            Assert.That(changed.Count, Is.EqualTo(1), "One contact must change one brick only.");
            int id = changed.Single();
            Assert.That(before[id] - after[id], Is.EqualTo(1), "One contact must remove exactly one health.");
            Assert.That(probe.BricksRemaining, Is.EqualTo(24), "A three-health brick must survive its first contact.");
            yield return Capture("brick_hit");
        }

        [UnityTest]
        public IEnumerator D3_EachDamageAddsExactlyOneScore_4()
        {
            yield return StartRun();
            yield return Click(PrimaryBrickTarget());
            yield return WaitForScoreAtLeast(1, 8f);
            int totalDamage = 24 * 3 - probe.Bricks.Sum(item => item.Health);
            Assert.That(probe.Score, Is.EqualTo(totalDamage), "Score must equal total brick-health damage exactly.");
            Assert.That(probe.Score, Is.EqualTo(1), "The first isolated contact must award exactly one point.");
        }

        [UnityTest]
        public IEnumerator D3_InvalidPointerRoutesDoNotLaunchOrScore_4()
        {
            yield return StartRun();
            yield return Click(probe.HudScreenRect.center);
            yield return Click(new Vector2(probe.PlayfieldScreenRect.xMin - 40f, probe.PlayfieldScreenRect.center.y));
            yield return PressOnly(PrimaryBrickTarget());
            yield return new WaitForSecondsRealtime(0.08f);
            Assert.That(probe.BallsRemaining, Is.EqualTo(3));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(0));
            Assert.That(probe.Score, Is.EqualTo(0));
            yield return Release(PrimaryBrickTarget());
            Assert.That(probe.BallsRemaining, Is.EqualTo(2));
        }

        [UnityTest]
        public IEnumerator D3_BallsReboundFromSideAndTopBoundaries_2()
        {
            yield return StartRun();
            yield return ObserveBoundaryRebound(Boundary.Left);
            Assert.That(probe.Score, Is.EqualTo(0), "A left-wall rebound before any brick contact must not award score.");

            yield return PressKey(Key.R);
            AssertInitialRun();
            yield return ObserveBoundaryRebound(Boundary.Right);
            Assert.That(probe.Score, Is.EqualTo(0), "A right-wall rebound before any brick contact must not award score.");

            yield return PressKey(Key.R);
            AssertInitialRun();
            yield return ObserveBoundaryRebound(Boundary.Top);
        }

        [UnityTest]
        public IEnumerator D3_BallLeavingBelowLauncherIsRemoved_2()
        {
            yield return StartRun();
            Vector2 missLane = MissTarget();
            yield return Click(missLane);
            Assert.That(probe.BallsRemaining, Is.EqualTo(2));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(1));

            float started = Time.realtimeSinceStartup;
            float deadline = started + 35f;
            bool observedBelowLauncher = false;
            while (probe.ActiveBallCount > 0 && Time.realtimeSinceStartup < deadline)
            {
                if (probe.ActiveBallCount == 1)
                    observedBelowLauncher |= probe.ActiveBallScreenPositions.Single().y < probe.LauncherScreenPosition.y;
                yield return null;
            }
            Assert.That(probe.ActiveBallCount, Is.EqualTo(0), "A ball that travels below the launcher boundary must be removed.");
            Assert.That(observedBelowLauncher, Is.True, "The evaluator did not observe the ball crossing below the visible launcher before removal.");
            Assert.That(probe.BallsRemaining, Is.EqualTo(2), "Removing an already-launched ball must not consume another ball.");
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.Playing), "One lost ball must not end a run while unlaunched balls remain.");
            TestContext.WriteLine($"BENCHMARK_LOWER_EXIT=target:{missLane.x:R},{missLane.y:R}|elapsed:{Time.realtimeSinceStartup - started:R}|belowLauncher:{observedBelowLauncher}");
        }

        [UnityTest]
        public IEnumerator D4_NormalInputCanClearFieldIntoSharedResult_5()
        {
            yield return StartRun();
            foreach (Vector2 target in ClearTargets()) yield return Click(target);
            yield return WaitForTerminal(40f);
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.GameOver));
            Assert.That(probe.BricksRemaining, Is.EqualTo(0));
            Assert.That(probe.TerminalPresentationVisible, Is.True);
            Assert.That(ValidRect(probe.TerminalButtonScreenRect), Is.True);
            yield return Click(probe.TerminalButtonScreenRect.center);
            AssertCleanMenu(false);
        }

        [UnityTest]
        public IEnumerator D4_NormalInputCanExhaustBallsIntoSharedResult_5()
        {
            yield return StartRun();
            Vector2 miss = MissTarget();
            for (int i = 0; i < 3; i++) yield return Click(miss);
            Assert.That(probe.BallsRemaining, Is.EqualTo(0));
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.Playing), "Failure must wait while active balls remain.");
            yield return WaitForTerminal(30f);
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.GameOver));
            Assert.That(probe.BricksRemaining, Is.GreaterThan(0));
            Assert.That(probe.TerminalPresentationVisible, Is.True);
        }

        [UnityTest]
        public IEnumerator D4_DirtyRunRestartIsCleanAndAcceptsExactlyOneInput_5()
        {
            yield return StartRun();
            yield return Click(PrimaryBrickTarget());
            yield return WaitForScoreAtLeast(1, 8f);
            Assert.That(probe.Score, Is.GreaterThan(0));
            yield return PressKey(Key.R);
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.Playing));
            AssertInitialRun();
            yield return Click(PrimaryBrickTarget());
            Assert.That(probe.BallsRemaining, Is.EqualTo(2));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(1));
        }

        [UnityTest]
        public IEnumerator D4_WriteDirtyReopenReceipt_5()
        {
            string receiptPath = Environment.GetEnvironmentVariable(ReopenReceiptEnvironment);
            Assert.That(string.IsNullOrWhiteSpace(receiptPath), Is.False, "Reopen receipt path was not supplied by the host wrapper.");
            yield return StartRun();
            yield return Click(PrimaryBrickTarget());
            yield return WaitForScoreAtLeast(1, 8f);
            Assert.That(probe.Score, Is.GreaterThan(0));
            Assert.That(probe.BallsRemaining, Is.LessThan(3));
            Directory.CreateDirectory(Path.GetDirectoryName(receiptPath));
            File.WriteAllText(receiptPath, JsonUtility.ToJson(new DirtyReceipt
            {
                session_id = SessionId(),
                process_id = Process.GetCurrentProcess().Id,
                scene = SceneManager.GetActiveScene().name,
                screen = probe.CurrentScreen.ToString(),
                score = probe.Score,
                balls_remaining = probe.BallsRemaining,
                active_balls = probe.ActiveBallCount,
                written_utc = DateTime.UtcNow.ToString("o")
            }, true));
            TestContext.WriteLine("BENCHMARK_DIRTY_RECEIPT=" + receiptPath);
        }

        [UnityTest]
        public IEnumerator D5_MenuHudAndSharedTerminalAreReadableAndUsable_4()
        {
            Assert.That(ValidRect(probe.StartButtonScreenRect), Is.True);
            Assert.That(VisibleTextContains("start"), Is.True);
            Assert.That(VisibleButtonCount(), Is.GreaterThanOrEqualTo(1));
            yield return Capture("menu");

            yield return StartRun();
            Assert.That(probe.HudPresentationVisible, Is.True);
            Assert.That(ValidRect(probe.HudScreenRect), Is.True);
            Assert.That(probe.Bricks.Count(item => item.Visible && probe.PlayfieldScreenRect.Contains(item.ScreenPosition)), Is.EqualTo(24));
            Assert.That(VisibleTextContains("score"), Is.True);
            Assert.That(VisibleTextContains("ball"), Is.True);
            yield return Capture("initial_gameplay");

            Vector2 miss = MissTarget();
            for (int i = 0; i < 3; i++) yield return Click(miss);
            yield return WaitForTerminal(30f);
            Assert.That(probe.TerminalPresentationVisible, Is.True);
            Assert.That(ValidRect(probe.TerminalButtonScreenRect), Is.True);
            Assert.That(VisibleTextContains("score"), Is.True);
            Assert.That(VisibleTextContains("menu"), Is.True);
            Assert.That(VisibleButtonCount(), Is.GreaterThanOrEqualTo(1));
            yield return Click(probe.TerminalButtonScreenRect.center);
            AssertCleanMenu(false);
        }

        [UnityTest]
        public IEnumerator D5_SuppliedVisualAssetsAndButtonStatesAreUsed_3()
        {
            string buttons = ButtonAssetNames();
            Assert.That(buttons, Does.Contain("Button_Default"));
            Assert.That(buttons, Does.Contain("Button_Hover"));
            Assert.That(buttons, Does.Contain("Button_Clicked"));

            yield return StartRun();
            string visible = VisibleSpriteNames();
            Assert.That(visible, Does.Contain("Brick"));
            Assert.That(visible, Does.Contain("Cannon_Base"));
            Assert.That(visible, Does.Contain("Cannon_Pipe"));
            Assert.That(visible, Does.Contain("Wall_Big"));
            Assert.That(visible, Does.Contain("Wall_Small"));
            yield return Click(PrimaryBrickTarget());
            Assert.That(VisibleSpriteNames(), Does.Contain("Ball"));
        }

        [UnityTest]
        public IEnumerator D5_SixSuppliedAudioRolesPlayFromNormalActions_3()
        {
            yield return ClickAndExpectAudio(probe.StartButtonScreenRect.center, BrickChallengeAudioCue.ButtonClicked, 2f);
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.Playing));
            Vector2 brickTarget = PrimaryBrickTarget();
            int hitBefore = probe.GetAudioCueCount(BrickChallengeAudioCue.BrickHit);
            int destroyedBefore = probe.GetAudioCueCount(BrickChallengeAudioCue.BrickDestroyed);
            yield return ClickAndExpectAudio(brickTarget, BrickChallengeAudioCue.BallShoot, 2f);
            yield return WaitForAudioCue(BrickChallengeAudioCue.BrickHit, hitBefore, 10f);

            var destroyed = new AudioCueObservation();
            yield return ObserveAudioCue(BrickChallengeAudioCue.BrickDestroyed, destroyedBefore, 2f, destroyed);
            for (int launch = 0; launch < 2 && !destroyed.CueSeen; launch++)
            {
                if (probe.BallsRemaining <= 0) break;
                yield return Click(brickTarget);
                yield return ObserveAudioCue(BrickChallengeAudioCue.BrickDestroyed, destroyedBefore, 5f, destroyed);
            }
            AssertAudioCueObservation(BrickChallengeAudioCue.BrickDestroyed, destroyedBefore, destroyed);

            yield return PressKey(Key.R);
            AssertInitialRun();
            int wallBefore = probe.GetAudioCueCount(BrickChallengeAudioCue.WallHit);
            yield return ClickAndExpectAudio(BoundaryTarget(Boundary.Left), BrickChallengeAudioCue.BallShoot, 2f);
            yield return WaitForAudioCue(BrickChallengeAudioCue.WallHit, wallBefore, 8f);

            yield return PressKey(Key.R);
            AssertInitialRun();
            int lostBefore = probe.GetAudioCueCount(BrickChallengeAudioCue.BallLost);
            yield return ClickAndExpectAudio(MissTarget(), BrickChallengeAudioCue.BallShoot, 2f);
            yield return WaitForAudioCue(BrickChallengeAudioCue.BallLost, lostBefore, 35f);
        }

        private IEnumerator StartRun()
        {
            yield return Click(probe.StartButtonScreenRect.center);
            yield return null;
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.Playing));
        }

        private void AssertCleanMenu(bool requireZeroScore)
        {
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.Menu));
            Assert.That(probe.MenuPresentationVisible, Is.True);
            Assert.That(probe.HudPresentationVisible, Is.False);
            Assert.That(probe.TerminalPresentationVisible, Is.False);
            if (requireZeroScore) Assert.That(probe.Score, Is.EqualTo(0));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(0));
        }

        private void AssertInitialRun()
        {
            Assert.That(probe.BricksRemaining, Is.EqualTo(24));
            Assert.That(probe.BallsRemaining, Is.EqualTo(3));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(0));
            Assert.That(probe.Score, Is.EqualTo(0));
            Assert.That(probe.Bricks.Count, Is.EqualTo(24));
            Assert.That(probe.Bricks.All(item => item.Visible && item.Health == 3), Is.True, "All original bricks begin with exactly three health.");
        }

        private Dictionary<int, int> VisibleHealth() => probe.Bricks.Where(item => item.Visible).ToDictionary(item => item.Id, item => item.Health);

        private Vector2 PrimaryBrickTarget() => probe.Bricks.Where(item => item.Visible)
            .OrderBy(item => item.ScreenPosition.y)
            .ThenBy(item => Mathf.Abs(item.ScreenPosition.x - probe.LauncherScreenPosition.x)).First().ScreenPosition;

        private IEnumerable<Vector2> ClearTargets()
        {
            List<BrickChallengeBrickSnapshot> visible = probe.Bricks.Where(item => item.Visible).OrderBy(item => item.ScreenPosition.x).ToList();
            float tolerance = Mathf.Max(20f, probe.PlayfieldScreenRect.width / 28f);
            var columns = new List<List<BrickChallengeBrickSnapshot>>();
            foreach (BrickChallengeBrickSnapshot brick in visible)
            {
                List<BrickChallengeBrickSnapshot> column = columns.FirstOrDefault(group => Mathf.Abs(group.Average(item => item.ScreenPosition.x) - brick.ScreenPosition.x) <= tolerance);
                if (column == null) { column = new List<BrickChallengeBrickSnapshot>(); columns.Add(column); }
                column.Add(brick);
            }
            List<Vector2> laneTargets = columns.Select(group => group.OrderBy(item => item.ScreenPosition.y).First().ScreenPosition).OrderBy(point => point.x).ToList();
            Assert.That(laneTargets.Count, Is.GreaterThanOrEqualTo(3));
            for (int i = 0; i < 3; i++) yield return laneTargets[i % laneTargets.Count];
        }

        private Vector2 MissTarget()
        {
            Rect area = probe.PlayfieldScreenRect;
            float inset = Mathf.Max(12f, area.width * 0.015f);
            float left = area.xMin + inset;
            float right = area.xMax - inset;
            float leftDistance = probe.Bricks.Where(item => item.Visible).Min(item => Mathf.Abs(item.ScreenPosition.x - left));
            float rightDistance = probe.Bricks.Where(item => item.Visible).Min(item => Mathf.Abs(item.ScreenPosition.x - right));
            return new Vector2(leftDistance >= rightDistance ? left : right, area.yMin + area.height * 0.48f);
        }

        private Vector2 BoundaryTarget(Boundary boundary)
        {
            Rect area = probe.PlayfieldScreenRect;
            Vector2 launcher = probe.LauncherScreenPosition;
            float lowLane = Mathf.Clamp(launcher.y + area.height * 0.14f, area.yMin + 40f, area.yMax - 80f);
            switch (boundary)
            {
                case Boundary.Left:
                    return new Vector2(area.xMin + area.width * 0.035f, lowLane);
                case Boundary.Right:
                    return new Vector2(area.xMax - area.width * 0.035f, lowLane);
                default:
                    // Reuse the proven empty side lane. The ball first travels outside the
                    // brick field, then reaches the top wall without an early brick reversal.
                    return MissTarget();
            }
        }

        private IEnumerator ObserveBoundaryRebound(Boundary boundary)
        {
            yield return Click(BoundaryTarget(boundary));
            Assert.That(probe.BallsRemaining, Is.EqualTo(2));
            Assert.That(probe.ActiveBallCount, Is.EqualTo(1));

            Rect area = probe.PlayfieldScreenRect;
            Vector2 previous = probe.ActiveBallScreenPositions.Single();
            bool approached = false;
            bool rebounded = false;
            float deadline = Time.realtimeSinceStartup + 6f;
            while (!rebounded && probe.ActiveBallCount == 1 && Time.realtimeSinceStartup < deadline)
            {
                yield return null;
                if (probe.ActiveBallCount != 1) break;
                Vector2 current = probe.ActiveBallScreenPositions.Single();
                Vector2 delta = current - previous;
                switch (boundary)
                {
                    case Boundary.Left:
                        approached |= delta.x < -0.05f;
                        rebounded = approached && current.x <= area.xMin + area.width * 0.22f &&
                            (delta.x > 0.05f || (Mathf.Abs(delta.x) <= 0.05f && Mathf.Abs(delta.y) > 0.05f));
                        break;
                    case Boundary.Right:
                        approached |= delta.x > 0.05f;
                        rebounded = approached && current.x >= area.xMax - area.width * 0.22f &&
                            (delta.x < -0.05f || (Mathf.Abs(delta.x) <= 0.05f && Mathf.Abs(delta.y) > 0.05f));
                        break;
                    default:
                        approached |= delta.y > 0.05f;
                        rebounded = approached && current.y >= area.yMax - area.height * 0.22f && delta.y < -0.05f;
                        break;
                }
                previous = current;
            }
            Assert.That(approached, Is.True, $"The ball never approached the {boundary.ToString().ToLowerInvariant()} boundary.");
            Assert.That(rebounded, Is.True, $"The ball did not visibly rebound from the {boundary.ToString().ToLowerInvariant()} boundary.");
        }

        private IEnumerator WaitForScoreAtLeast(int target, float seconds)
        {
            float deadline = Time.realtimeSinceStartup + seconds;
            while (probe.Score < target && Time.realtimeSinceStartup < deadline) yield return null;
            Assert.That(probe.Score, Is.GreaterThanOrEqualTo(target), "Timed out waiting for real brick-contact score.");
        }

        private IEnumerator WaitForTerminal(float seconds)
        {
            float deadline = Time.realtimeSinceStartup + seconds;
            while (probe.CurrentScreen == BrickChallengeScreen.Playing && Time.realtimeSinceStartup < deadline) yield return null;
            Assert.That(probe.CurrentScreen, Is.EqualTo(BrickChallengeScreen.GameOver), "Timed out waiting for the shared end-of-run screen.");
        }

        private static bool VisibleTextContains(string value)
        {
            foreach (MonoBehaviour component in Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                PropertyInfo property = component.GetType().GetProperty("text", BindingFlags.Instance | BindingFlags.Public);
                if (property == null || property.PropertyType != typeof(string) || !property.CanRead) continue;
                string text = property.GetValue(component) as string;
                if (!string.IsNullOrEmpty(text) && text.IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0) return true;
            }
            return false;
        }

        private static int VisibleButtonCount() => Object.FindObjectsByType<Button>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
            .Count(button => button.IsActive() && button.IsInteractable() && button.GetComponent<Graphic>() != null && button.GetComponent<Graphic>().raycastTarget);

        private static string VisibleSpriteNames()
        {
            var names = new List<string>();
            names.AddRange(Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(renderer => renderer.enabled && renderer.gameObject.activeInHierarchy && renderer.sprite != null)
                .Select(renderer => renderer.sprite.texture ? renderer.sprite.texture.name : renderer.sprite.name));
            names.AddRange(Object.FindObjectsByType<Image>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(image => image.enabled && image.gameObject.activeInHierarchy && image.sprite != null)
                .Select(image => image.sprite.texture ? image.sprite.texture.name : image.sprite.name));
            return string.Join("|", names.Distinct());
        }

        private static string ButtonAssetNames()
        {
            var names = new List<string>();
            foreach (Button button in Object.FindObjectsByType<Button>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                Image image = button.targetGraphic as Image;
                if (image && image.sprite) names.Add(image.sprite.texture ? image.sprite.texture.name : image.sprite.name);
                SpriteState state = button.spriteState;
                foreach (Sprite sprite in new[] { state.highlightedSprite, state.pressedSprite, state.selectedSprite, state.disabledSprite })
                    if (sprite) names.Add(sprite.texture ? sprite.texture.name : sprite.name);
            }
            return string.Join("|", names.Distinct());
        }

        private IEnumerator ClickAndExpectAudio(Vector2 point, BrickChallengeAudioCue cue, float seconds)
        {
            int before = probe.GetAudioCueCount(cue);
            Queue(point, true);
            yield return null;
            Queue(point, false);
            yield return WaitForAudioCue(cue, before, seconds);
            yield return null;
        }

        private IEnumerator WaitForAudioCue(BrickChallengeAudioCue cue, int before, float seconds)
        {
            var observation = new AudioCueObservation();
            yield return ObserveAudioCue(cue, before, seconds, observation);
            AssertAudioCueObservation(cue, before, observation);
        }

        private IEnumerator ObserveAudioCue(BrickChallengeAudioCue cue, int before, float seconds, AudioCueObservation observation)
        {
            float deadline = Time.realtimeSinceStartup + seconds;
            while (!observation.CueSeen && Time.realtimeSinceStartup < deadline)
            {
                observation.CueSeen = probe.GetAudioCueCount(cue) > before;
                if (observation.CueSeen) break;
                yield return null;
            }

            if (observation.CueSeen)
            {
                observation.Sequence = probe.AudioCueSequence;
                observation.LastCue = probe.LastAudioCue;
                for (int i = 0; i < 8; i++)
                {
                    SampleAudioPlayback(observation);
                    if (i >= 1 && (observation.SourcePlaying || observation.PeakOutput > 0.00001f)) break;
                    yield return null;
                }
            }
        }

        private void AssertAudioCueObservation(BrickChallengeAudioCue cue, int before, AudioCueObservation observation)
        {
            string suppliedName = SuppliedAudioName(cue);
            AudioClip supplied = Resources.Load<AudioClip>("BrickChallenge/Audio/" + suppliedName);
            Assert.That(supplied, Is.Not.Null, $"The protected supplied clip for {cue} is missing.");
            Assert.That(probe.GetAudioCueCount(cue), Is.GreaterThan(before), $"Normal player input did not emit the {cue} audio event.");
            Assert.That(observation.CueSeen, Is.True, $"Timed out waiting for the {cue} audio event.");
            Assert.That(observation.SourcePlaying || observation.PeakOutput > 0.00001f, Is.True,
                $"The {cue} event was reported but no live AudioSource/listener output was observed.");
            TestContext.WriteLine($"BENCHMARK_AUDIO_CUE={cue}|clip={supplied.name}|sequence={observation.Sequence}|last={observation.LastCue}|sourcePlaying={observation.SourcePlaying}|peak={observation.PeakOutput:R}");
        }

        private static void SampleAudioPlayback(AudioCueObservation observation)
        {
            const int sampleCount = 256;
            foreach (AudioSource source in Object.FindObjectsByType<AudioSource>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (!source) continue;
                observation.SourcePlaying |= source.isPlaying && !source.mute && source.volume > 0.0001f;
                try
                {
                    var samples = new float[sampleCount];
                    source.GetOutputData(samples, 0);
                    observation.PeakOutput = Mathf.Max(observation.PeakOutput, samples.Max(value => Mathf.Abs(value)));
                }
                catch (Exception) { }
            }
            for (int channel = 0; channel < 2; channel++)
            {
                try
                {
                    var samples = new float[sampleCount];
                    AudioListener.GetOutputData(samples, channel);
                    observation.PeakOutput = Mathf.Max(observation.PeakOutput, samples.Max(value => Mathf.Abs(value)));
                }
                catch (Exception) { }
            }
        }

        private static string SuppliedAudioName(BrickChallengeAudioCue cue)
        {
            switch (cue)
            {
                case BrickChallengeAudioCue.ButtonClicked: return "Button_Clicked";
                case BrickChallengeAudioCue.BallShoot: return "Ball_Shoot";
                case BrickChallengeAudioCue.WallHit: return "Wall_Hit";
                case BrickChallengeAudioCue.BrickHit: return "Brick_Hit";
                case BrickChallengeAudioCue.BrickDestroyed: return "Brick_Destroyed";
                case BrickChallengeAudioCue.BallLost: return "Ball_Lost";
                default: throw new ArgumentOutOfRangeException(nameof(cue), cue, null);
            }
        }

        private IEnumerator Click(Vector2 point) { yield return PressOnly(point); yield return Release(point); }
        private IEnumerator Capture(string state)
        {
            string directory = Environment.GetEnvironmentVariable("BRICK_CANDIDATE_SCREENSHOT_DIR");
            if (string.IsNullOrWhiteSpace(directory)) yield break;
            Directory.CreateDirectory(directory);
            string path = Path.Combine(directory, state + ".png");
            if (File.Exists(path)) File.Delete(path);
            const int width = 1280;
            const int height = 720;
            RenderTexture render = new RenderTexture(width, height, 24);
            Camera camera = Camera.main;
            Assert.That(camera, Is.Not.Null, "A camera is required for formal screenshots.");
            RenderTexture priorTarget = camera.targetTexture;
            RenderTexture priorActive = RenderTexture.active;
            float priorAspect = camera.aspect;
            Canvas[] canvases = Object.FindObjectsByType<Canvas>(FindObjectsInactive.Include, FindObjectsSortMode.None);
            var canvasModes = canvases.Select(canvas => canvas.renderMode).ToArray();
            var canvasCameras = canvases.Select(canvas => canvas.worldCamera).ToArray();
            var canvasDistances = canvases.Select(canvas => canvas.planeDistance).ToArray();
            for (int i = 0; i < canvases.Length; i++)
            {
                canvases[i].renderMode = RenderMode.ScreenSpaceCamera;
                canvases[i].worldCamera = camera;
                canvases[i].planeDistance = 1f;
            }
            Canvas.ForceUpdateCanvases();
            camera.aspect = (float)width / height;
            camera.targetTexture = render;
            camera.Render();
            RenderTexture.active = render;
            Texture2D texture = new Texture2D(width, height, TextureFormat.RGB24, false);
            texture.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            texture.Apply();
            File.WriteAllBytes(path, texture.EncodeToPNG());
            camera.targetTexture = priorTarget;
            camera.aspect = priorAspect;
            RenderTexture.active = priorActive;
            for (int i = 0; i < canvases.Length; i++)
            {
                canvases[i].renderMode = canvasModes[i];
                canvases[i].worldCamera = canvasCameras[i];
                canvases[i].planeDistance = canvasDistances[i];
            }
            Canvas.ForceUpdateCanvases();
            Object.Destroy(texture);
            render.Release();
            Object.Destroy(render);
            yield return null;
            Assert.That(File.Exists(path) && new FileInfo(path).Length >= 1000, Is.True, "Candidate screenshot was not emitted.");
            TestContext.WriteLine("BENCHMARK_SCREENSHOT=" + state + "|" + path);
        }
        private IEnumerator PressOnly(Vector2 point) { Queue(point, true); yield return null; }
        private IEnumerator Release(Vector2 point) { Queue(point, false); yield return null; yield return null; }
        private void Queue(Vector2 point, bool pressed)
        {
            var state = new MouseState { position = point };
            state = state.WithButton(MouseButton.Left, pressed);
            InputSystem.QueueStateEvent(mouse, state);
        }
        private IEnumerator PressKey(Key key)
        {
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(key)); yield return null;
            InputSystem.QueueStateEvent(keyboard, new KeyboardState()); yield return null; yield return null;
        }
        private static bool ValidRect(Rect rect) => rect.width > 20f && rect.height > 20f && rect.xMin >= -1f && rect.yMin >= -1f && rect.xMax <= Screen.width + 1f && rect.yMax <= Screen.height + 1f;
        private static string SessionId() => Environment.GetEnvironmentVariable(SessionEnvironment) ?? string.Empty;
        private static void EmitIdentity(string phase)
        {
            TestContext.WriteLine("BENCHMARK_PROCESS_ID=" + Process.GetCurrentProcess().Id);
            TestContext.WriteLine("BENCHMARK_SESSION_ID=" + SessionId());
            TestContext.WriteLine("BENCHMARK_PHASE=" + phase);
            TestContext.WriteLine("BENCHMARK_SCENE=BrickChallenge");
        }

        [Serializable]
        private sealed class DirtyReceipt
        {
            public string session_id;
            public int process_id;
            public string scene;
            public string screen;
            public int score;
            public int balls_remaining;
            public int active_balls;
            public string written_utc;
        }
    }
}
