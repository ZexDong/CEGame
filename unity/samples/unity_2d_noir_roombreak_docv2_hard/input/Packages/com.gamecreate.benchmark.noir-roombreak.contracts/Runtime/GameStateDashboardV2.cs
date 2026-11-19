using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using UnityEngine;

namespace Benchmark.Dashboard
{
    public enum GamePhase
    {
        NotReady,
        Menu,
        Playing,
        Paused,
        Won,
        Lost
    }

    [Serializable]
    public sealed class SlotEntry
    {
        public string name;
        public float value;
    }

    [Serializable]
    public sealed class EntityEntry
    {
        public string kind;
        public int[] cell;
        public string state;
    }

    [Serializable]
    public sealed class TargetEntry
    {
        public string kind;
        public Rect rect;
        public bool visible;
        public bool interactable;
    }

    [Serializable]
    public sealed class Snapshot
    {
        public int revision;
        public GamePhase phase = GamePhase.NotReady;
        public List<SlotEntry> slots = new List<SlotEntry>();
        public List<EntityEntry> entities = new List<EntityEntry>();
        public List<TargetEntry> targets = new List<TargetEntry>();
    }

    /// <summary>
    /// The primary game-state-dashboard/v2 observation surface. It deliberately
    /// contains no action, reset, teleport, damage, victory, or scoring method.
    /// </summary>
    public interface IGameStateDashboard
    {
        string ContractVersion { get; }
        Snapshot Capture();
    }

    /// <summary>
    /// Produces the exact public dashboard JSON shape. The in-process C# slot
    /// list is serialized as the contract's name-to-number JSON object.
    /// </summary>
    public static class DashboardJson
    {
        public static string ToJson(Snapshot snapshot, bool includeRevision = true)
        {
            if (snapshot == null) throw new ArgumentNullException(nameof(snapshot));

            var inv = CultureInfo.InvariantCulture;
            var builder = new StringBuilder();
            builder.Append('{');
            if (includeRevision)
                builder.Append("\"revision\":").Append(snapshot.revision).Append(',');

            builder.Append("\"phase\":\"").Append(PhaseName(snapshot.phase)).Append("\",\"slots\":{");
            for (var i = 0; i < snapshot.slots.Count; i++)
            {
                var slot = snapshot.slots[i];
                if (i > 0) builder.Append(',');
                builder.Append('\"').Append(Escape(slot.name)).Append("\":")
                    .Append(slot.value.ToString(inv));
            }

            builder.Append("},\"entities\":[");
            for (var i = 0; i < snapshot.entities.Count; i++)
            {
                var entity = snapshot.entities[i];
                if (i > 0) builder.Append(',');
                builder.Append("{\"kind\":\"").Append(Escape(entity.kind))
                    .Append("\",\"cell\":[")
                    .Append(entity.cell != null && entity.cell.Length > 0 ? entity.cell[0].ToString(inv) : "0")
                    .Append(',')
                    .Append(entity.cell != null && entity.cell.Length > 1 ? entity.cell[1].ToString(inv) : "0")
                    .Append("],\"state\":\"").Append(Escape(entity.state)).Append("\"}");
            }

            builder.Append("],\"targets\":[");
            for (var i = 0; i < snapshot.targets.Count; i++)
            {
                var target = snapshot.targets[i];
                if (i > 0) builder.Append(',');
                builder.Append("{\"kind\":\"").Append(Escape(target.kind)).Append("\",\"rect\":[")
                    .Append(target.rect.x.ToString(inv)).Append(',')
                    .Append(target.rect.y.ToString(inv)).Append(',')
                    .Append(target.rect.width.ToString(inv)).Append(',')
                    .Append(target.rect.height.ToString(inv))
                    .Append("],\"visible\":").Append(target.visible ? "true" : "false")
                    .Append(",\"interactable\":").Append(target.interactable ? "true" : "false")
                    .Append('}');
            }

            return builder.Append("]}").ToString();
        }

        public static string PhaseName(GamePhase phase)
        {
            switch (phase)
            {
                case GamePhase.Menu: return "menu";
                case GamePhase.Playing: return "playing";
                case GamePhase.Paused: return "paused";
                case GamePhase.Won: return "won";
                case GamePhase.Lost: return "lost";
                default: return "not_ready";
            }
        }

        static string Escape(string value) =>
            (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"");
    }
}
