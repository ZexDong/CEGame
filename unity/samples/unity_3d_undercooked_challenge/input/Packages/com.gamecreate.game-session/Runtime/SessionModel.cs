using System;
using System.Collections.Generic;
using System.Linq;

namespace GameCreate.Session
{
    [Serializable] public sealed class NumberRule
    {
        public string name;
        public double minimum, maximum;
        public bool integer, editable;
    }
    [Serializable] public sealed class ActorRule
    {
        public string kind;
        public string[] states;
        public bool poseEditable, stateEditable;
    }
    [Serializable] public sealed class SessionModel
    {
        public string contract = "game-session/v1";
        public string contentVersion;
        public string[] entries, phases, requiredLandmarks;
        public float operationTimeoutSeconds = 10;
        public NumberRule[] values;
        public ActorRule[] actorKinds;

        public string Validate(SessionSave save)
        {
            var shape = SessionFormat.ValidateShape(save);
            if (shape != null) return shape;
            if (contract != save.contract || contentVersion != save.contentVersion) return "wrong_content_version";
            if (!(entries ?? Array.Empty<string>()).Contains(save.entryId)) return "unknown_entry";
            if (!(phases ?? Array.Empty<string>()).Contains(save.phase)) return "unknown_phase";
            var required = values ?? Array.Empty<NumberRule>();
            if (required.Select(x=>x.name).Distinct().Count()!=required.Length) throw new InvalidOperationException("Invalid content model: duplicate numeric definition.");
            if (save.values.Count != required.Length) return "wrong_value_set";
            foreach (var rule in required)
            {
                if (!SessionFormat.TryNumber(save.values, rule.name, out var number)) return "missing_value";
                if (number < rule.minimum || number > rule.maximum || rule.integer && number != Math.Truncate(number)) return "value_out_of_range";
            }
            foreach (var actor in save.actors)
            {
                if (!entries.Contains(actor.entryId)) return "unknown_actor_entry";
                var types = (actorKinds ?? Array.Empty<ActorRule>()).Where(x=>x.kind==actor.kind).ToArray();
                if (types.Length!=1 || !(types[0].states ?? Array.Empty<string>()).Contains(actor.state)) return "unknown_actor_kind_or_state";
                if (actor.facing != -1 && actor.facing != 1) return "invalid_actor_facing";
            }
            return null;
        }
    }
}
