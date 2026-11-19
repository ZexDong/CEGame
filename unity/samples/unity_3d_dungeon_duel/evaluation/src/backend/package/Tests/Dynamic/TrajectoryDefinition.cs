using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    [Serializable]
    internal sealed class TrajectoryDefinitionStep
    {
        public string step_id;
        public string operation;
        public string target;
        public string[] check_ids = Array.Empty<string>();
    }

    [Serializable]
    internal sealed class TrajectoryDefinition
    {
        public int schema_version;
        public string id;
        public string title;
        public TrajectoryDefinitionStep[] steps = Array.Empty<TrajectoryDefinitionStep>();

        public IEnumerable<string> AllCheckIds() =>
            (steps ?? Array.Empty<TrajectoryDefinitionStep>())
            .Where(step => step != null)
            .SelectMany(step => step.check_ids ?? Array.Empty<string>())
            .Where(value => !string.IsNullOrWhiteSpace(value));
    }

    internal static class TrajectoryDefinitionLoader
    {
        public static TrajectoryDefinition Load(string id, out string sha256)
        {
            TextAsset text = Resources.Load<TextAsset>("TrajectoryDefinitions/" + id);
            if (text == null)
            {
                throw new InvalidOperationException(
                    $"Missing trajectory JSON resource: TrajectoryDefinitions/{id}.json");
            }

            sha256 = ComputeSha256(text.text);
            TrajectoryDefinition definition = JsonUtility.FromJson<TrajectoryDefinition>(text.text);
            if (definition == null || definition.schema_version != 1 ||
                !string.Equals(definition.id, id, StringComparison.Ordinal))
            {
                throw new InvalidOperationException($"Invalid trajectory definition for {id}.");
            }

            string[] ids = definition.AllCheckIds().ToArray();
            if (ids.Length == 0 || ids.Distinct(StringComparer.Ordinal).Count() != ids.Length)
            {
                throw new InvalidOperationException(
                    $"Trajectory definition {id} must contain unique check IDs.");
            }

            return definition;
        }

        static string ComputeSha256(string value)
        {
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(value));
                return BitConverter.ToString(hash).Replace("-", string.Empty).ToLowerInvariant();
            }
        }
    }
}
