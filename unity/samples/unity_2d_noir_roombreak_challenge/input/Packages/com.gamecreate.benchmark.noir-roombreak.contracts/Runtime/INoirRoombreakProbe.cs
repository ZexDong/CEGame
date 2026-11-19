using System.Collections.Generic;
using UnityEngine;

namespace GameCreate.Benchmark.NoirRoombreak
{
    public enum NoirScreen
    {
        Menu,
        Playing,
        Paused,
        Success
    }

    public enum NoirEnemyKind
    {
        Anda,
        Obser
    }

    public enum NoirEnemyState
    {
        Idle,
        Patrol,
        Alert,
        Chase,
        Locking,
        Firing,
        Defeated
    }

    public enum NoirRespawnKind
    {
        None,
        RoomSoftRespawn,
        BenchGlobalRespawn
    }

    public readonly struct NoirEnemySnapshot
    {
        public NoirEnemySnapshot(int id, NoirEnemyKind kind, NoirEnemyState state, int roomIndex, Vector2 screenPosition, bool visible)
        {
            Id = id;
            Kind = kind;
            State = state;
            RoomIndex = roomIndex;
            ScreenPosition = screenPosition;
            Visible = visible;
        }

        public int Id { get; }
        public NoirEnemyKind Kind { get; }
        public NoirEnemyState State { get; }
        public int RoomIndex { get; }
        public Vector2 ScreenPosition { get; }
        public bool Visible { get; }
    }

    // Observation only. An implementation must not use this surface to drive, skip, or mutate gameplay.
    public interface INoirRoombreakProbe
    {
        NoirScreen CurrentScreen { get; }
        // Menu reports -1. Player Rooms 1 through 5 report zero-based indices 0 through 4.
        int CurrentRoomIndex { get; }
        int RoomCount { get; }
        int Bonds { get; }
        int MaximumBonds { get; }
        int DashCharges { get; }
        int MaximumDashCharges { get; }
        bool PlayerAlive { get; }
        bool PlayerGrounded { get; }
        bool PlayerDashing { get; }
        bool PlayerInvulnerable { get; }
        Vector2 PlayerScreenPosition { get; }
        Rect CurrentRoomScreenRect { get; }
        Rect StartButtonScreenRect { get; }
        Rect PausePanelScreenRect { get; }
        Rect SuccessPanelScreenRect { get; }
        bool AndaChasing { get; }
        bool ObserLockVisible { get; }
        bool ObserLaserVisible { get; }
        int DefeatedEnemyCount { get; }
        int SoftRespawnCount { get; }
        int GlobalRespawnCount { get; }
        NoirRespawnKind LastRespawnKind { get; }
        int StateSequence { get; }
        IReadOnlyList<NoirEnemySnapshot> Enemies { get; }
    }
}

