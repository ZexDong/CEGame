using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;

namespace GameCreate.NoirRoombreak.Evaluator
{
    public static class RuntimeInspector
    {
        static readonly Dictionary<string, string> SpriteRolesByCatalogPath = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["assets/taskassets/noirsource/sprites/player/idle.png"] = "player",
            ["assets/taskassets/noirsource/sprites/player/backattack.png"] = "player",
            ["assets/taskassets/noirsource/sprites/anda/andaidle.png"] = "anda",
            ["assets/taskassets/noirsource/sprites/anda/andadead.png"] = "anda",
            ["assets/taskassets/noirsource/sprites/vig/vigia.png"] = "obser",
            ["assets/taskassets/noirsource/sprites/tile/ground.png"] = "room",
            ["assets/taskassets/noirsource/sprites/tile/obstacle.png"] = "room"
        };

        public static bool Finite(Vector2 value) => Finite(value.x) && Finite(value.y);
        public static bool Finite(float value) => !float.IsNaN(value) && !float.IsInfinity(value);
        public static bool OnScreen(Vector2 value, float margin = 32f) => Finite(value) && value.x >= -margin && value.x <= Screen.width + margin && value.y >= -margin && value.y <= Screen.height + margin;
        public static bool ValidRect(Rect value, float minimumWidth = 20f, float minimumHeight = 20f) => Finite(value.x) && Finite(value.y) && Finite(value.width) && Finite(value.height) && value.width >= minimumWidth && value.height >= minimumHeight;

        public static Transform FindPlayerTransform(INoirRoombreakProbe probe)
        {
            if (probe == null || !OnScreen(probe.PlayerScreenPosition, 256f) || Camera.main == null) return null;
            var target = probe.PlayerScreenPosition;
            var candidates = UnityEngine.Object.FindObjectsByType<Collider2D>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(x => x && x.enabled && !x.isTrigger && x.GetComponentInChildren<Renderer>(false) != null)
                .Select(x => new { transform = x.transform, distance = Vector2.Distance((Vector2)Camera.main.WorldToScreenPoint(x.bounds.center), target) })
                .OrderBy(x => x.distance).ToArray();
            return candidates.Length > 0 && candidates[0].distance < 180f ? candidates[0].transform : null;
        }

        public static Vector3 RealPlayerPosition(INoirRoombreakProbe probe)
        {
            var player = FindPlayerTransform(probe);
            return player ? player.position : new Vector3(probe == null ? 0f : probe.PlayerScreenPosition.x, probe == null ? 0f : probe.PlayerScreenPosition.y, 0f);
        }
        public static int ActiveCameraCount() => UnityEngine.Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.isActiveAndEnabled);
        public static int VisibleSpriteCount() => UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.enabled && x.sprite != null && x.color.a > .05f);
        public static int SolidColliderCount() => UnityEngine.Object.FindObjectsByType<Collider2D>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.enabled && !x.isTrigger);
        public static int VisibleCanvasCount() => UnityEngine.Object.FindObjectsByType<Canvas>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.isActiveAndEnabled);

        public static bool SuppliedAssembly(bool actionPlaybackObserved, string expectedActionAudioRole, out bool suppliedActionFeedback, out string observed)
        {
            var sprites = UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(x => x && x.enabled && x.sprite != null).ToArray();
            var spriteRoles = new HashSet<string>(StringComparer.Ordinal);
#if UNITY_EDITOR
            foreach (var renderer in sprites)
            {
                var path = UnityEditor.AssetDatabase.GetAssetPath(renderer.sprite);
                if (string.IsNullOrWhiteSpace(path) && renderer.sprite.texture != null) path = UnityEditor.AssetDatabase.GetAssetPath(renderer.sprite.texture);
                if (SpriteRolesByCatalogPath.TryGetValue(SuppliedAssetRules.Normalize(path), out var role)) spriteRoles.Add(role);
            }
#endif
            var audio = InspectSuppliedAudio(actionPlaybackObserved, expectedActionAudioRole);
            suppliedActionFeedback = audio.actionFeedback;
            observed = $"visibleSprites={sprites.Length};catalogSpriteRoles={string.Join(",", spriteRoles.OrderBy(x => x, StringComparer.Ordinal))};audioSources={audio.sourceCount};referencedCatalogClips={audio.clipCount};audioRoles={string.Join(",", audio.roles)};audioOrigins={audio.origins};actionPlayback={actionPlaybackObserved};expectedActionRole={expectedActionAudioRole};catalogActionFeedback={audio.actionFeedback};canvases={VisibleCanvasCount()}";
            return sprites.Length >= 3 && spriteRoles.Count >= 2 && audio.inventory && VisibleCanvasCount() > 0;
        }

        sealed class AudioAssemblySnapshot
        {
            public int sourceCount;
            public int clipCount;
            public bool inventory;
            public bool actionFeedback;
            public string[] roles = Array.Empty<string>();
            public string origins = "none";
        }

        static AudioAssemblySnapshot InspectSuppliedAudio(bool actionPlaybackObserved, string expectedActionAudioRole)
        {
            var sources = UnityEngine.Object.FindObjectsByType<AudioSource>(FindObjectsInactive.Include, FindObjectsSortMode.None).Where(x => x).ToArray();
            var clips = new HashSet<AudioClip>();
            var origins = new HashSet<string>(StringComparer.Ordinal);
            foreach (var source in sources) if (source.clip != null) { clips.Add(source.clip); origins.Add("AudioSource.clip"); }
            foreach (var component in UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Include, FindObjectsSortMode.None)) CollectReferencedAudioClips(component, clips, origins);
            var identities = clips.Select(IdentityFor).Where(x => x != null).ToArray();
            var supplied = identities.Where(x => SuppliedAssetRules.TryGetAudioRole(x, out _)).ToArray();
            var inventory = SuppliedAssetRules.HasEquivalentAudioInventory(supplied, sources.Length, actionPlaybackObserved, out var roles);
            return new AudioAssemblySnapshot
            {
                sourceCount = sources.Length,
                clipCount = supplied.Length,
                inventory = inventory,
                actionFeedback = SuppliedAssetRules.HasSuppliedActionFeedback(supplied, expectedActionAudioRole, actionPlaybackObserved),
                roles = roles,
                origins = origins.Count == 0 ? "none" : string.Join(",", origins.OrderBy(x => x, StringComparer.Ordinal))
            };
        }

        static void CollectReferencedAudioClips(MonoBehaviour component, HashSet<AudioClip> clips, HashSet<string> origins)
        {
            if (!component) return;
            var fields = component.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            foreach (var field in fields)
            {
                if (field.IsStatic || field.IsNotSerialized) continue;
                if (field.FieldType == typeof(AudioClip))
                {
                    try { var clip = field.GetValue(component) as AudioClip; if (clip != null) { clips.Add(clip); origins.Add("MonoBehaviour.AudioClip"); } } catch { }
                    continue;
                }
                if (!typeof(IEnumerable).IsAssignableFrom(field.FieldType) || field.FieldType == typeof(string)) continue;
                Type elementType = field.FieldType.IsArray ? field.FieldType.GetElementType() : (field.FieldType.IsGenericType ? field.FieldType.GetGenericArguments().FirstOrDefault() : null);
                if (elementType != typeof(AudioClip)) continue;
                try
                {
                    if (!(field.GetValue(component) is IEnumerable values)) continue;
                    foreach (var value in values) if (value is AudioClip clip) { clips.Add(clip); origins.Add("MonoBehaviour.AudioClipCollection"); }
                }
                catch { }
            }
        }

        static SuppliedAssetRules.Identity IdentityFor(AudioClip clip)
        {
            if (!clip) return null;
#if UNITY_EDITOR
            var path = UnityEditor.AssetDatabase.GetAssetPath(clip).Replace('\\', '/');
            return new SuppliedAssetRules.Identity(path);
#else
            return new SuppliedAssetRules.Identity(string.Empty);
#endif
        }

        public static int[] PlayingAudioSourceIds() => UnityEngine.Object.FindObjectsByType<AudioSource>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(x => x && x.isPlaying).Select(x => x.GetInstanceID()).OrderBy(x => x).ToArray();

        public static bool ActionPlaybackObserved(IEnumerable<int> before, out string observed)
        {
            var prior = new HashSet<int>(before ?? Array.Empty<int>());
            var now = PlayingAudioSourceIds();
            var newlyPlaying = now.Where(x => !prior.Contains(x)).ToArray();
            observed = $"playingBefore={string.Join(",", prior.OrderBy(x => x))};playingAfter={string.Join(",", now)};newlyPlaying={string.Join(",", newlyPlaying)}";
            return newlyPlaying.Length > 0;
        }

        public static bool EffectPlaying(out string observed)
        {
            var playing = UnityEngine.Object.FindObjectsByType<AudioSource>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(x => x && x.isPlaying).Select(x => x.clip ? x.clip.name : x.name).ToArray();
            observed = "playing=" + string.Join(",", playing);
            return playing.Length > 0;
        }

        public static string Snapshot(INoirRoombreakProbe probe)
        {
            if (probe == null) return "probe=null";
            NoirEnemySnapshot[] enemies;
            try { enemies = probe.Enemies == null ? Array.Empty<NoirEnemySnapshot>() : probe.Enemies.ToArray(); }
            catch (Exception ex) { return "probe-enemies-error=" + ex.GetType().Name; }
            return $"screen={probe.CurrentScreen};room={probe.CurrentRoomIndex}/{probe.RoomCount};bonds={probe.Bonds}/{probe.MaximumBonds};dash={probe.DashCharges}/{probe.MaximumDashCharges};alive={probe.PlayerAlive};grounded={probe.PlayerGrounded};dashing={probe.PlayerDashing};invulnerable={probe.PlayerInvulnerable};player=({probe.PlayerScreenPosition.x:F1},{probe.PlayerScreenPosition.y:F1});andaChase={probe.AndaChasing};obserLock={probe.ObserLockVisible};obserLaser={probe.ObserLaserVisible};defeated={probe.DefeatedEnemyCount};soft={probe.SoftRespawnCount};global={probe.GlobalRespawnCount};lastRespawn={probe.LastRespawnKind};enemies={enemies.Length};sequence={probe.StateSequence}";
        }
    }
}


