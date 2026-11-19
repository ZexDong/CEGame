using System.Collections.Generic;
using UnityEngine;

namespace OmniGame.Benchmark.BrickChallenge.Contracts
{
    public enum BrickChallengeScreen
    {
        Menu,
        Playing,
        GameOver
    }

    public enum BrickChallengeAudioCue
    {
        None,
        ButtonClicked,
        BallShoot,
        WallHit,
        BrickHit,
        BrickDestroyed,
        BallLost
    }

    public readonly struct BrickChallengeBrickSnapshot
    {
        public BrickChallengeBrickSnapshot(int id, int health, Vector2 screenPosition, bool visible)
        {
            Id = id;
            Health = health;
            ScreenPosition = screenPosition;
            Visible = visible;
        }

        public int Id { get; }
        public int Health { get; }
        public Vector2 ScreenPosition { get; }
        public bool Visible { get; }
    }

    public interface IBrickChallengeProbe
    {
        BrickChallengeScreen CurrentScreen { get; }
        int Score { get; }
        int BallsRemaining { get; }
        int ActiveBallCount { get; }
        int BricksRemaining { get; }
        bool MenuPresentationVisible { get; }
        bool HudPresentationVisible { get; }
        bool TerminalPresentationVisible { get; }
        Rect StartButtonScreenRect { get; }
        Rect TerminalButtonScreenRect { get; }
        Rect HudScreenRect { get; }
        Rect PlayfieldScreenRect { get; }
        Vector2 LauncherScreenPosition { get; }
        IReadOnlyList<Vector2> ActiveBallScreenPositions { get; }
        IReadOnlyList<BrickChallengeBrickSnapshot> Bricks { get; }
        BrickChallengeAudioCue LastAudioCue { get; }
        int AudioCueSequence { get; }
        int GetAudioCueCount(BrickChallengeAudioCue cue);
    }
}
