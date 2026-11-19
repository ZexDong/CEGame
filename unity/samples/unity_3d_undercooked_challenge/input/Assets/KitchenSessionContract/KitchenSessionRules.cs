using System;
using System.Collections.Generic;
using System.Linq;
using GameCreate.Session;
using UnityEngine;

namespace GameCreate.Kitchen
{
    // Public content validation for game-session/v1. This optional development aid
    // validates save data; it does not implement kitchen mechanics or certify gameplay.
    public static class KitchenSessionRules
    {
        public const string EntryId = "kitchen";
        public const string ContentVersion = "undercooked-session-v2-20260909";
        [Serializable] sealed class ContentModel { public NumberRule[] values; public ContentActorRule[] actorKinds; }
        [Serializable] sealed class ContentActorRule { public string kind; public NumberRule[] values; }
        static readonly string[] Phases = { "menu", "playing", "paused", "result" };
        static readonly string[] ActorIds = { "chef-1", "chef-2", "tomato-crate", "counter", "chopping-board", "pot", "plate-rack", "delivery", "trash" };
        static readonly string[] RequiredLandmarks = { "chef-1-spawn", "chef-2-spawn", "open-floor", "tomato-crate-approach", "counter-approach", "chopping-board-approach", "pot-approach", "plate-rack-approach", "delivery-approach", "trash-approach" };
        static readonly string[] TopValueNames = {
            "score", "shift_remaining", "active_chef", "order_spawn_remaining", "next_item_id", "next_order_id", "delivered_orders", "expired_orders",
            "chop_seconds", "cook_seconds", "burn_seconds", "order_lifetime", "order_interval",
            "floor_origin_x", "floor_origin_y", "floor_origin_z", "floor_normal_x", "floor_normal_y", "floor_normal_z",
            "move_right_x", "move_right_y", "move_right_z", "move_forward_x", "move_forward_y", "move_forward_z",
            "order_1_id", "order_1_remaining", "order_1_initial", "order_2_id", "order_2_remaining", "order_2_initial", "order_3_id", "order_3_remaining", "order_3_initial"
        };

        public static string Validate(SessionSave save, EntryDescription description = null)
        {
            var shape = SessionFormat.ValidateShape(save);
            if (shape != null) return shape;
            if (!string.Equals(save.contentVersion, ContentVersion, StringComparison.Ordinal)) return "wrong_content_version";
            if (!string.Equals(save.entryId, EntryId, StringComparison.Ordinal)) return "unknown_entry";
            if (!Phases.Contains(save.phase, StringComparer.Ordinal)) return "unknown_phase";
            var resource = Resources.Load<TextAsset>("session-model");
            if (!resource) return "missing_public_model";
            var model = JsonUtility.FromJson<ContentModel>(resource.text);
            if (model == null || model.values == null || model.actorKinds == null) return "invalid_public_model";
            var error = CheckRanges(save.values, model.values);
            if (error != null) return error;
            error = CheckNumbers(save.values, TopValueNames);
            if (error != null) return error;
            if (!Get(save.values, "active_chef", out var activeChef) || activeChef != 1 && activeChef != 2) return "invalid_active_chef";
            if (!Get(save.values, "shift_remaining", out var remaining) || remaining < 0 || remaining > 120) return "invalid_shift_time";
            if (!Get(save.values, "score", out var score) || score < -100000 || score > 1000000 || Math.Truncate(score) != score) return "invalid_score";
            if (!Get(save.values, "chop_seconds", out var chopSeconds) || chopSeconds < 1 || chopSeconds > 120) return "invalid_chop_duration";
            if (!Get(save.values, "cook_seconds", out var cookSeconds) || cookSeconds < 4 || cookSeconds > 8) return "invalid_cook_duration";
            if (!Get(save.values, "burn_seconds", out var burnSeconds) || burnSeconds < 5 || burnSeconds > 120) return "invalid_burn_duration";
            if (!Get(save.values, "order_lifetime", out var orderLifetime) || orderLifetime < 25 || orderLifetime > 120) return "invalid_order_lifetime";
            if (!Get(save.values, "order_interval", out var orderInterval) || orderInterval < 1 || orderInterval > 120) return "invalid_order_interval";
            error = CheckGeometry(save);
            if (error != null) return error;
            error = CheckOrders(save.values, orderLifetime, orderInterval);
            if (error != null) return error;
            error = CheckActors(save, model, chopSeconds, cookSeconds, burnSeconds);
            if (error != null) return error;
            if (save.phase == "menu")
            {
                if (score != 0 || remaining != 120 || activeChef != 1) return "menu_not_clean";
                if (!GetInt(save.values, "delivered_orders", out var delivered) || delivered != 0 || !GetInt(save.values, "expired_orders", out var expired) || expired != 0) return "menu_counters_not_clean";
                if (LiveOrderCount(save.values) != 0) return "menu_has_orders";
            }
            else if (save.phase == "result")
            {
                if (remaining != 0) return "result_time_not_zero";
            }
            else if (remaining <= 0 || remaining > 120) return "active_time_out_of_range";
            error = CheckDescription(description, save.values);
            return error;
        }

        static string CheckRanges(IReadOnlyList<NamedNumber> values, NumberRule[] rules)
        {
            if (rules == null) return "missing_value_rules";
            var error = CheckNumbers(values, rules.Select(x => x.name).ToArray());
            if (error != null) return error;
            foreach (var rule in rules)
                if (!Get(values, rule.name, out var number) || number < rule.minimum || number > rule.maximum || rule.integer && Math.Truncate(number) != number) return "value_out_of_range:" + rule.name;
            return null;
        }

        static string CheckNumbers(IReadOnlyList<NamedNumber> values, IReadOnlyCollection<string> expected)
        {
            if (values == null) return "missing_values";
            var names = values.Where(x => x != null).Select(x => x.name).ToArray();
            if (names.Length != expected.Count || names.Distinct(StringComparer.Ordinal).Count() != names.Length || expected.Any(x => !names.Contains(x, StringComparer.Ordinal))) return "wrong_value_set";
            if (values.Any(x => x == null || string.IsNullOrWhiteSpace(x.name) || !SessionFormat.Finite(x.value))) return "invalid_value";
            return null;
        }

        static string CheckGeometry(SessionSave save)
        {
            if (!GetVector(save.values, "floor_origin", out var origin) || !GetVector(save.values, "floor_normal", out var normal) || !GetVector(save.values, "move_right", out var right) || !GetVector(save.values, "move_forward", out var forward)) return "missing_geometry";
            if (!ApproximatelyUnit(normal) || !ApproximatelyUnit(right) || !ApproximatelyUnit(forward)) return "non_unit_geometry_basis";
            if (Mathf.Abs(Vector3.Dot(normal, right)) > .02f || Mathf.Abs(Vector3.Dot(normal, forward)) > .02f || Mathf.Abs(Vector3.Dot(right, forward)) > .02f) return "non_orthogonal_geometry_basis";
            if (Get(save.values, "next_item_id", out var nextItem) && nextItem < 1 || Get(save.values, "next_order_id", out var nextOrder) && nextOrder < 1) return "invalid_next_id";
            return null;
        }

        static string CheckOrders(IReadOnlyList<NamedNumber> values, double lifetime, double interval)
        {
            var compact = true; var seen = new HashSet<long>(); long previous = 0; var live = 0;
            for (var i = 1; i <= 3; i++)
            {
                if (!GetInt(values, $"order_{i}_id", out var id) || !Get(values, $"order_{i}_remaining", out var rem) || !Get(values, $"order_{i}_initial", out var initial)) return "missing_order_slot";
                if (id == 0)
                {
                    if (rem != 0 || initial != 0) return "empty_order_not_zero";
                    compact = false;
                }
                else
                {
                    if (!compact || !seen.Add(id) || id <= previous || initial < 25 || initial > lifetime || rem <= 0 || rem > initial) return "invalid_order_slot";
                    previous = id; live++;
                }
            }
            if (!Get(values, "order_spawn_remaining", out var spawn) || spawn < 0 || spawn > interval) return "invalid_order_spawn_timer";
            if (!GetInt(values, "next_order_id", out var next) || next <= previous) return "invalid_next_order_id";
            return live > 3 ? "too_many_orders" : null;
        }

        static string CheckActors(SessionSave save, ContentModel model, double chopSeconds, double cookSeconds, double burnSeconds)
        {
            if (save.actors == null || save.actors.Any(x => !ActorIds.Contains(x.id))) return "wrong_actor_set";
            if (save.phase != "menu" && save.actors.Count != ActorIds.Length) return "wrong_actor_set";
            var byId = save.actors.ToDictionary(x => x.id, StringComparer.Ordinal);
            if (save.phase != "menu" && ActorIds.Any(id => !byId.ContainsKey(id))) return "missing_actor";
            var itemIds = new Dictionary<long, string>(); long maxItem = 0;
            foreach (var id in byId.Keys)
            {
                var actor = byId[id];
                if (save.phase != "menu" && !actor.present || actor.entryId != EntryId || actor.state != "normal" || actor.facing != 1 || !SessionFormat.Finite(actor.position)) return "invalid_actor_identity";
                var rule = model.actorKinds.FirstOrDefault(x => x.kind == actor.kind);
                if (rule == null) return "unknown_actor_kind";
                var rangeError = CheckRanges(actor.values, rule.values); if (rangeError != null) return rangeError;
                if (id.StartsWith("chef-", StringComparison.Ordinal))
                {
                    if (actor.kind != "chef") return "wrong_actor_kind";
                    var error = CheckChef(actor, itemIds, ref maxItem); if (error != null) return error;
                }
                else
                {
                    var expectedKind = id.Replace("-", "_");
                    if (actor.kind != expectedKind) return "wrong_actor_kind";
                    var error = CheckStation(actor, id, itemIds, ref maxItem, chopSeconds, cookSeconds, burnSeconds); if (error != null) return error;
                }
                if (actor.kind == "chef" && !InsideGeometryPlane(actor.position, save.values)) return "chef_off_floor_plane";
                if (save.phase == "menu" && !CleanContainer(actor)) return "menu_containers_not_clean";
            }
            if (!GetInt(save.values, "next_item_id", out var next) || next <= maxItem) return "invalid_next_item_id";
            return null;
        }

        static string CheckChef(ActorSave actor, IDictionary<long, string> itemIds, ref long maxItem)
        {
            var names = new[] { "held_id", "held_kind", "heading_degrees" }; var error = CheckNumbers(actor.values, names); if (error != null) return error;
            if (!GetInt(actor.values, "held_id", out var id) || !GetInt(actor.values, "held_kind", out var kind) || kind < 0 || kind > 4) return "invalid_chef_held_item";
            if ((id == 0) != (kind == 0)) return "item_identity_mismatch";
            if (id > 0 && !RegisterItem(id, actor.id, itemIds, ref maxItem)) return "duplicate_item_identity";
            if (!Get(actor.values, "heading_degrees", out var heading) || heading < 0 || heading > 360) return "invalid_heading";
            return null;
        }

        static string CheckStation(ActorSave actor, string id, IDictionary<long, string> itemIds, ref long maxItem, double chopSeconds, double cookSeconds, double burnSeconds)
        {
            var names = new List<string> { "interaction_distance", "approach_heading_degrees" };
            if (id == "counter") names.AddRange(new[] { "item_id", "item_kind" });
            if (id == "chopping-board") names.AddRange(new[] { "item_id", "item_kind", "chop_elapsed" });
            if (id == "pot") names.AddRange(new[] { "item_id", "item_kind", "ingredient_1_id", "ingredient_2_id", "ingredient_3_id", "cook_elapsed", "burn_elapsed" });
            var error = CheckNumbers(actor.values, names); if (error != null) return error;
            if (!Get(actor.values, "interaction_distance", out var reach) || reach <= 0 || !Get(actor.values, "approach_heading_degrees", out var heading) || heading < 0 || heading > 360) return "invalid_station_geometry";
            if (id == "counter" || id == "chopping-board" || id == "pot")
            {
                if (!GetInt(actor.values, "item_id", out var item) || !GetInt(actor.values, "item_kind", out var kind) || (item == 0) != (kind == 0)) return "item_identity_mismatch";
                if (id == "counter" && kind > 4 || id == "chopping-board" && kind > 2 || id == "pot" && kind != 0 && kind != 5 && kind != 6) return "invalid_station_item_kind";
                if (item > 0 && !RegisterItem(item, actor.id, itemIds, ref maxItem)) return "duplicate_item_identity";
                if (id == "chopping-board")
                {
                    if (!Get(actor.values, "chop_elapsed", out var chop) || chop < 0 || chop > 120 || kind == 0 && chop != 0 || kind == 1 && chop >=  chopSeconds || kind == 2 && Math.Abs(chop - chopSeconds) > .0001) return "invalid_chop_state";
                }
                if (id == "pot")
                {
                    var ingredients = new long[3]; for (var i = 0; i < 3; i++) { if (!GetInt(actor.values, $"ingredient_{i + 1}_id", out ingredients[i])) return "missing_pot_ingredient"; if (ingredients[i] > 0 && !RegisterItem(ingredients[i], actor.id + $"/ingredient-{i + 1}", itemIds, ref maxItem)) return "duplicate_item_identity"; }
                    if (ingredients.SkipWhile(x => x > 0).Any(x => x > 0)) return "non_compact_pot_ingredients";
                    if (kind != 0 && ingredients.Any(x => x != 0)) return "finished_pot_has_ingredients";
                    if (!Get(actor.values, "cook_elapsed", out var cook) || !Get(actor.values, "burn_elapsed", out var burn) || cook < 0 || burn < 0 || cook > cookSeconds || burn > burnSeconds) return "invalid_pot_timers";
                    var count = ingredients.Count(x => x > 0);
                    if (kind == 0 && (burn != 0 || count < 3 && cook != 0 || count == 3 && cook >= cookSeconds) || kind == 5 && (Math.Abs(cook - cookSeconds) > .0001 || burn >= burnSeconds) || kind == 6 && (Math.Abs(cook - cookSeconds) > .0001 || Math.Abs(burn - burnSeconds) > .0001)) return "invalid_pot_state";
                }
            }
            return null;
        }

        static bool CleanContainer(ActorSave actor)
        {
            foreach (var number in actor.values)
                if ((number.name == "held_id" || number.name == "held_kind" || number.name == "item_id" || number.name == "item_kind" || number.name.StartsWith("ingredient_") || number.name == "chop_elapsed" || number.name == "cook_elapsed" || number.name == "burn_elapsed") && number.value != 0) return false;
            return true;
        }

        static bool RegisterItem(long id, string owner, IDictionary<long, string> items, ref long max)
        {
            if (id <= 0 || items.ContainsKey(id)) return false; items[id] = owner; if (id > max) max = id; return true;
        }

        static string CheckDescription(EntryDescription description, IReadOnlyList<NamedNumber> values)
        {
            if (description == null) return null;
            if (description.id != EntryId || !SessionFormat.Finite(description.worldBounds.center) || !SessionFormat.Finite(description.worldBounds.size) || description.worldBounds.size.x <= 0 || description.worldBounds.size.y <= 0 || description.worldBounds.size.z <= 0) return "invalid_entry_description";
            if (description.landmarks == null) return "wrong_landmark_set";
            foreach (var name in RequiredLandmarks)
            {
                var matches = description.landmarks.Where(x => x != null && x.name == name).ToArray(); if (matches.Length != 1 || !matches[0].present || !SessionFormat.Finite(matches[0].position) || !SessionFormat.Finite(matches[0].bounds.center) || !SessionFormat.Finite(matches[0].bounds.size)) return "missing_landmark";
                if (!description.worldBounds.Contains(matches[0].position)) return "landmark_outside_world_bounds";
            }
            return null;
        }

        static int LiveOrderCount(IReadOnlyList<NamedNumber> values) => Enumerable.Range(1, 3).Count(i => GetInt(values, $"order_{i}_id", out var id) && id > 0);
        static bool InsideGeometryPlane(Vector3 position, IReadOnlyList<NamedNumber> values) { if (!GetVector(values, "floor_origin", out var origin) || !GetVector(values, "floor_normal", out var normal)) return false; return Mathf.Abs(Vector3.Dot(position - origin, normal)) <= .08f; }
        static bool ApproximatelyUnit(Vector3 value) => Mathf.Abs(value.magnitude - 1f) <= .02f;
        static bool Get(IReadOnlyList<NamedNumber> values, string name, out double result) => SessionFormat.TryNumber(values, name, out result);
        static bool GetInt(IReadOnlyList<NamedNumber> values, string name, out long result) { result = 0; if (!Get(values, name, out var value) || Math.Truncate(value) != value) return false; result = (long)value; return true; }
        static bool GetVector(IReadOnlyList<NamedNumber> values, string prefix, out Vector3 value) { value = default; if (!Get(values, prefix + "_x", out var x) || !Get(values, prefix + "_y", out var y) || !Get(values, prefix + "_z", out var z)) return false; value = new Vector3((float)x, (float)y, (float)z); return SessionFormat.Finite(value); }
    }
}
