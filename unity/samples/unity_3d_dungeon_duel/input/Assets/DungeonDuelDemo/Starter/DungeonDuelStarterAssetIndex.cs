using UnityEngine;
using UnityEngine.AI;
using UnityEngine.InputSystem;

namespace DungeonDuelStarter
{
    [CreateAssetMenu(menuName = "Dungeon Duel/Starter Asset Index")]
    public sealed class DungeonDuelStarterAssetIndex : ScriptableObject
    {
        public GameObject PlayerVisual;
        public GameObject ImpVisual;
        public GameObject BossVisual;
        public GameObject BossGateVisual;
        public GameObject AttackVfx;
        public GameObject DashVfx;
        public GameObject DeathVfx;
        public NavMeshData BakedNavMesh;
        public InputActionAsset InputActions;
        public AudioClip BattleMusic;
        public AudioClip VictoryMusic;
    }
}
