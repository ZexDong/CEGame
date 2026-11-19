using System;
using System.Collections.Generic;
using UnityEngine;

namespace GameCreate.Session
{
    public enum OperationState { Pending, Completed, Rejected }

    [Serializable] public sealed class SessionOperation
    {
        public string id;
        public OperationState state;
        public string code;
        public string message;
    }
    [Serializable] public sealed class NamedNumber
    {
        public string name;
        public double value;
    }
    [Serializable] public sealed class ActorSave
    {
        public string id;
        public string kind;
        public string entryId;
        public string state;
        public bool present;
        public Vector3 position;
        public float facing = 1;
        public List<NamedNumber> values = new List<NamedNumber>();
    }
    [Serializable] public sealed class SessionSave
    {
        public string contract = "game-session/v1";
        public string contentVersion;
        public string entryId;
        public string phase;
        public int seed;
        public List<NamedNumber> values = new List<NamedNumber>();
        public List<ActorSave> actors = new List<ActorSave>();
        public string opaqueData;
    }
    [Serializable] public sealed class Landmark
    {
        public string name;
        public bool present;
        public Vector3 position;
        public Bounds bounds;
    }
    [Serializable] public sealed class EntryDescription
    {
        public string id;
        public Bounds worldBounds;
        public List<Landmark> landmarks = new List<Landmark>();
    }

    public interface IGameSession
    {
        string ContractVersion { get; }
        IReadOnlyList<string> EntryIds { get; }
        SessionOperation OpenEntry(string entryId, int seed);
        SessionSave Capture();
        SessionOperation Restore(SessionSave save);
        void ResumeSimulation();
        EntryDescription DescribeCurrentEntry();
        GameObject ResolveActor(string actorId);
    }

    // General format utilities only. Content rules belong to the game.
    public static class SessionFormat
    {
        public static SessionSave Clone(SessionSave save)
        {
            if (save == null) throw new ArgumentNullException(nameof(save));
            return JsonUtility.FromJson<SessionSave>(JsonUtility.ToJson(save));
        }
        public static bool Finite(double value) => !double.IsNaN(value) && !double.IsInfinity(value);
        public static bool Finite(Vector3 value) => Finite(value.x) && Finite(value.y) && Finite(value.z);
        public static bool TryNumber(IReadOnlyList<NamedNumber> values, string name, out double value)
        {
            value = 0;
            if (values == null) return false;
            var count = 0;
            foreach (var entry in values) if (entry != null && entry.name == name) { value = entry.value; count++; }
            return count == 1 && Finite(value);
        }
        public static string ValidateShape(SessionSave save)
        {
            if (save == null || save.contract != "game-session/v1") return "invalid_schema";
            if (string.IsNullOrWhiteSpace(save.contentVersion) || string.IsNullOrWhiteSpace(save.entryId) || string.IsNullOrWhiteSpace(save.phase)) return "missing_identity";
            var numbers = ValidateNumbers(save.values);
            if (numbers != null) return numbers;
            if (save.actors == null) return "missing_actors";
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (var actor in save.actors)
            {
                if (actor == null || string.IsNullOrWhiteSpace(actor.id) || string.IsNullOrWhiteSpace(actor.kind) ||
                    string.IsNullOrWhiteSpace(actor.entryId) || string.IsNullOrWhiteSpace(actor.state)) return "missing_actor_identity";
                if (!ids.Add(actor.id)) return "duplicate_actor";
                if (!Finite(actor.position) || !Finite(actor.facing)) return "non_finite_pose";
                numbers = ValidateNumbers(actor.values);
                if (numbers != null) return numbers;
            }
            return null;
        }
        static string ValidateNumbers(IReadOnlyList<NamedNumber> values)
        {
            if (values == null) return "missing_values";
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var value in values)
            {
                if (value == null || string.IsNullOrWhiteSpace(value.name)) return "missing_value_name";
                if (!names.Add(value.name)) return "duplicate_value";
                if (!Finite(value.value)) return "non_finite_value";
            }
            return null;
        }
    }
}
