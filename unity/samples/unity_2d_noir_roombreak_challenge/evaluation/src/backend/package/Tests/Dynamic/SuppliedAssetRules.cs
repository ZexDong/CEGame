using System;
using System.Collections.Generic;
using System.Linq;

namespace GameCreate.NoirRoombreak.Evaluator
{
    /// <summary>Public-catalog path rules shared by runtime inspection and the no-Unity regression check.</summary>
    public static class SuppliedAssetRules
    {
        public sealed class Identity
        {
            public Identity(string path) { Path = Normalize(path); }
            public string Path { get; }
        }

        static readonly Dictionary<string, string> AudioRolesByPath = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["assets/taskassets/noirsource/audio/enemy/alertsound.wav"] = "alert",
            ["assets/taskassets/noirsource/audio/enemy/dash.wav"] = "dash",
            ["assets/taskassets/noirsource/audio/enemy/lasershoot.wav"] = "laser",
            ["assets/taskassets/noirsource/audio/player/attack.wav"] = "attack",
            ["assets/taskassets/noirsource/audio/player/dash.wav"] = "dash",
            ["assets/taskassets/noirsource/audio/player/jump.wav"] = "jump",
            ["assets/taskassets/noirsource/audio/player/kill.wav"] = "kill",
            ["assets/taskassets/noirsource/audio/player/playerdeath.wav"] = "death"
        };

        public static string Normalize(string path) => (path ?? string.Empty).Replace('\\', '/').Trim().ToLowerInvariant();

        public static bool TryGetAudioRole(Identity identity, out string role)
        {
            role = null;
            if (identity == null) return false;
            return AudioRolesByPath.TryGetValue(identity.Path, out role);
        }

        public static string[] AudioRoles(IEnumerable<Identity> identities)
        {
            var roles = new HashSet<string>(StringComparer.Ordinal);
            foreach (var identity in identities ?? Enumerable.Empty<Identity>()) if (TryGetAudioRole(identity, out var role)) roles.Add(role);
            return roles.OrderBy(x => x, StringComparer.Ordinal).ToArray();
        }

        public static bool HasEquivalentAudioInventory(IEnumerable<Identity> identities, int audioSourceCount, bool actionPlaybackObserved, out string[] roles)
        {
            roles = AudioRoles(identities);
            var hasOutputRoute = audioSourceCount > 0 || actionPlaybackObserved;
            return roles.Length >= 3 && hasOutputRoute;
        }

        public static bool HasSuppliedActionFeedback(IEnumerable<Identity> identities, string expectedRole, bool actionPlaybackObserved)
        {
            if (!actionPlaybackObserved || string.IsNullOrWhiteSpace(expectedRole)) return false;
            return AudioRoles(identities).Contains(expectedRole.Trim().ToLowerInvariant(), StringComparer.Ordinal);
        }
    }
}
