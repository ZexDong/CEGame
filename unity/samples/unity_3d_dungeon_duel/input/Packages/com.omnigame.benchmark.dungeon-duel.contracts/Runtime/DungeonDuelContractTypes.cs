using System;
using UnityEngine;

namespace OmniGame.Benchmark.DungeonDuel.V2
{
    public enum DungeonDuelActorId
    {
        Player = 0,
        ImpA = 1,
        ImpB = 2,
        Boss = 3
    }

    public enum DungeonDuelWorldTargetId
    {
        MoveTargetA = 0,
        MoveTargetB = 1,
        DashTarget = 2
    }

    public enum DungeonDuelGamePhase
    {
        NotReady = 0,
        Playing = 1,
        Won = 2,
        Lost = 3
    }

    [Serializable]
    public sealed class DungeonDuelActorSnapshot
    {
        public DungeonDuelActorId ActorId;
        public Vector3 Position;
        public float Health;
        public float MaxHealth;
        public float MoveSpeed;
        public float AttackRange;
        public float AttackDamage;
        public float AttackCooldown;
        public bool IsDead;
        public bool IsDormant;
    }

    [Serializable]
    public sealed class DungeonDuelGameSnapshot
    {
        public DungeonDuelGamePhase Phase;
        public DungeonDuelActorSnapshot Player;
        public DungeonDuelActorSnapshot ImpA;
        public DungeonDuelActorSnapshot ImpB;
        public DungeonDuelActorSnapshot Boss;
        public int ImpsAlive;
        public bool GateOpen;
        public bool GateBlocking;
        public float DashCooldownRemaining;
        public bool BattleMusicPlaying;
    }
}
