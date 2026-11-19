using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using TMPro;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;
using UnityEngine.UI;
using Object = UnityEngine.Object;

namespace GameCreate.Undercooked.Evaluator
{
    // Versioned observer correction. Never inspects a candidate type, field or method.
    // All geometry comes from real Colliders, never render bounds or asset padding.
    [Serializable] public sealed class CollisionSample
    {
        public Vector3 position;
        public float realtime, gap, penetration, side;
    }
    [Serializable] public sealed class CollisionObservation
    {
        public bool geometry_available, approach_direction_available, did_not_cross = true, did_not_penetrate = true, at_contact;
        public int chef_colliders, station_colliders;
        public float max_step, contact_tolerance, penetration_tolerance, max_penetration;
        public string unavailable_reason;
        public List<CollisionSample> samples = new List<CollisionSample>();
        public bool Blocked => geometry_available && approach_direction_available && did_not_cross && did_not_penetrate && at_contact;
    }
    public sealed class ColliderMotionProbe
    {
        readonly GameObject chef, station;
        readonly Collider[] bodies, obstacles;
        readonly Vector3 normal, axis;
        readonly Dictionary<int, Vector3> previous = new Dictionary<int, Vector3>();
        readonly Dictionary<int, Quaternion> previousRotation = new Dictionary<int, Quaternion>();
        Vector3 lastRoot;
        readonly float skin, offsets;
        public readonly CollisionObservation Result = new CollisionObservation();
        static Collider[] Solids(GameObject go) => go.GetComponentsInChildren<Collider>(false)
            .Where(c => c.enabled && c.gameObject.activeInHierarchy && !c.isTrigger).ToArray();
        static bool PenetrationShape(Collider c) => c is BoxCollider || c is SphereCollider ||
            c is CapsuleCollider || c is CharacterController || (c is MeshCollider m && m.convex);
        public ColliderMotionProbe(GameObject chef, GameObject station, Vector3 floorNormal)
        {
            this.chef = chef; this.station = station;
            normal = floorNormal.normalized;
            axis = Vector3.ProjectOnPlane(station.transform.position - chef.transform.position, normal).normalized;
            bodies = Solids(chef); obstacles = Solids(station);
            Result.chef_colliders = bodies.Length; Result.station_colliders = obstacles.Length;
            Result.approach_direction_available = axis.sqrMagnitude > .9f;
            Result.geometry_available = bodies.Length > 0 && obstacles.Length > 0 &&
                bodies.All(b => obstacles.All(o => PenetrationShape(b) || PenetrationShape(o)));
            if (!Result.geometry_available)
                Result.unavailable_reason = "No supported live collider pair; missing a Unity Collider is not itself a public product violation.";
            skin = bodies.OfType<CharacterController>().Select(c => c.skinWidth).DefaultIfEmpty(0).Max();
            offsets = bodies.Select(c => c.contactOffset).DefaultIfEmpty(0).Max() +
                obstacles.Select(c => c.contactOffset).DefaultIfEmpty(0).Max();
            Result.penetration_tolerance = .005f + skin;
            lastRoot = chef.transform.position;
            foreach (var b in bodies) { previous[b.GetInstanceID()] = b.transform.position; previousRotation[b.GetInstanceID()] = b.transform.rotation; }
            Sample();
        }
        static float Gap(Collider a, Collider b)
        {
            // Alternating closest points uses collision geometry, including rotation/scale.
            var pa = a.ClosestPoint(b.bounds.center); var pb = b.ClosestPoint(pa);
            for (int i = 0; i < 8; i++) { pa = a.ClosestPoint(pb); pb = b.ClosestPoint(pa); }
            return Vector3.Distance(pa, pb);
        }
        public void Sample()
        {
            var p = chef.transform.position;
            var step = Vector3.ProjectOnPlane(p - lastRoot, normal).magnitude;
            Result.max_step = Mathf.Max(Result.max_step, step);
            var side = Vector3.Dot(Vector3.ProjectOnPlane(p - station.transform.position, normal), axis);
            Result.did_not_cross &= side <= .005f;
            float gap = float.PositiveInfinity, penetration = 0;
            if (Result.geometry_available)
            {
                foreach (var b in bodies) foreach (var o in obstacles)
                {
                    // Hypothetical positions are arguments only: no transform/state write.
                    // Intermediate checks catch a one-frame tunnel with nonoverlapping endpoints.
                    var old = previous[b.GetInstanceID()];
                    var e=b.bounds.extents;var f=o.bounds.extents;
                    var extent = Mathf.Max(.0001f, new[]{e.x,e.y,e.z,f.x,f.y,f.z}.Where(x=>x>0).Min()/2);
                    int required=Mathf.Max(1,Mathf.CeilToInt(Vector3.Distance(old,b.transform.position)/extent));
                    if(required>4096){Result.geometry_available=false;Result.unavailable_reason="Swept collision precision budget exceeded; no product verdict.";continue;}
                    int segments=required;
                    for (int n = 0; n <= segments; n++)
                    {
                        var pose = Vector3.Lerp(old, b.transform.position, (float)n / segments);
                        var rotation=Quaternion.Slerp(previousRotation[b.GetInstanceID()],b.transform.rotation,(float)n/segments);
                        if (Physics.ComputePenetration(b, pose, rotation, o, o.transform.position, o.transform.rotation, out var direction, out var depth))
                            penetration = Mathf.Max(penetration, depth);
                    }
                    gap = Mathf.Min(gap, Gap(b, o));
                }
                Result.did_not_penetrate &= penetration <= Result.penetration_tolerance;
                Result.max_penetration = Mathf.Max(Result.max_penetration, penetration);
                // Discrete player movement may stop one actual movement quantum short.
                Result.contact_tolerance = Mathf.Max(.025f, offsets + skin + Result.max_step);
                Result.at_contact = gap <= Result.contact_tolerance;
            }
            Result.samples.Add(new CollisionSample { position = p, realtime = Time.realtimeSinceStartup,
                gap = float.IsInfinity(gap) ? -1 : gap, penetration = penetration, side = side });
            foreach (var b in bodies) { previous[b.GetInstanceID()] = b.transform.position; previousRotation[b.GetInstanceID()] = b.transform.rotation; }
            lastRoot = p;
        }
        public static bool MovementPass(bool moved1, bool stayed2, bool switchedOnce, bool moved2, bool stayed1, CollisionObservation collision)
            => moved1 && stayed2 && switchedOnce && moved2 && stayed1 && collision.Blocked;
    }

    [Serializable] public sealed class BehavioralCollisionObservation
    {
        public bool did_not_cross, stopped_under_input, moved_away;
        public float retreat_distance;
        public List<Vector3> forward_positions=new List<Vector3>();
        public bool Blocked=>did_not_cross&&stopped_under_input&&moved_away;
    }
    public static class BehavioralCollisionOracle
    {
        public static Key[] Keys(Vector3 direction,Vector3 right,Vector3 forward)
        {
            var keys=new List<Key>();var x=Vector3.Dot(direction,right);var z=Vector3.Dot(direction,forward);
            if(Mathf.Abs(x)>.15f)keys.Add(x>0?Key.D:Key.A);if(Mathf.Abs(z)>.15f)keys.Add(z>0?Key.W:Key.S);return keys.ToArray();
        }
        public static BehavioralCollisionObservation Evaluate(List<Vector3> positions,Vector3 target,Vector3 direction,Vector3 afterRetreat)
        {
            var o=new BehavioralCollisionObservation{forward_positions=positions};if(positions.Count<6)return o;
            var last=positions[positions.Count-1];var tail=positions.Skip(positions.Count*2/3).ToArray();
            o.did_not_cross=positions.All(p=>Vector3.Dot(p-target,direction)<-.005f);
            o.stopped_under_input=tail.All(p=>Vector3.Distance(p,last)<.015f)&&Vector3.Dot(last-positions[0],direction)>=-.015f;
            o.retreat_distance=Vector3.Dot(last-afterRetreat,direction);o.moved_away=o.retreat_distance>.1f;return o;
        }
        public static IEnumerator Acquire(GameCreate.Evaluation.Session.PlayerInputDriver input,Transform chef,Vector3 target,Vector3 right,Vector3 forward,Action<BehavioralCollisionObservation> completed)
        {
            var direction=Vector3.ProjectOnPlane(target-chef.position,Vector3.Cross(right,forward)).normalized;
            if(direction.sqrMagnitude<.9f)throw new InvalidOperationException("No direction for behavioral collision observation.");
            var positions=new List<Vector3>{chef.position};var keys=Keys(direction,right,forward);var end=Time.realtimeSinceStartup+.85f;
            // Fixed direction deliberately continues beyond the station root if there is no
            // actual collision; a target-following navigator would stop and fake blocking.
            while(Time.realtimeSinceStartup<end){yield return input.Frame(keys);positions.Add(chef.position);}yield return input.Frame();
            var reverse=Keys(-direction,right,forward);end=Time.realtimeSinceStartup+.25f;
            while(Time.realtimeSinceStartup<end)yield return input.Frame(reverse);yield return input.Frame();
            completed(Evaluate(positions,target,direction,chef.position));
        }
    }

    [Serializable] public sealed class VisibleUiSurface
    {
        public string text, style;
        public int instance_id;
        public Vector2 screen_position;
    }
    [Serializable] public sealed class ResultUiObservation
    {
        public double score;
        public List<VisibleUiSurface> surfaces = new List<VisibleUiSurface>();
        public bool restart_hint_visible, restart_control_visible, restart_operable;
        public string restart_route;
    }
    public static class ResultUiOracle
    {
        static readonly Regex Grade = new Regex(@"\b(Bronze|Silver|Gold)\b", RegexOptions.IgnoreCase);
        static readonly Regex Number = new Regex(@"(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])");
        // Match markup syntax, not ordinary less-than/greater-than comparisons in legends.
        public static string Plain(string text) => Regex.Replace(text ?? "", @"</?[A-Za-z][^>]*>", "");
        public static bool HasPublicRestartKey(string text) => Regex.IsMatch(Plain(text), @"(?<![\p{L}\p{N}_])R(?![\p{L}\p{N}_])", RegexOptions.IgnoreCase);
        public static bool MenuAffordance(string text, bool visibleActionableButton) =>
            KitchenRun.Label(Plain(text), "Start", "Play", "Begin") &&
            (visibleActionableButton || KitchenRun.Label(Plain(text), "Enter", "Return", "Space"));
        static Vector2 Center(RectTransform rect)
        {
            var canvas = rect.GetComponentInParent<Canvas>();
            var cam = canvas.renderMode == RenderMode.ScreenSpaceOverlay ? null : canvas.worldCamera;
            return RectTransformUtility.WorldToScreenPoint(cam, rect.TransformPoint(rect.rect.center));
        }
        static string Style(Color color, float size, string fontStyle) =>
            ColorUtility.ToHtmlStringRGBA(color) + ":" + size.ToString("R", CultureInfo.InvariantCulture) + ":" + fontStyle;
        public static List<VisibleUiSurface> Capture()
        {
            var rows = new List<VisibleUiSurface>();
            foreach (var t in Object.FindObjectsByType<TMP_Text>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                if (t.isActiveAndEnabled && t.color.a > .05f && KitchenRun.Visible(t.rectTransform))
                    rows.Add(new VisibleUiSurface { text = t.text, style = Style(t.color, t.fontSize, t.fontStyle.ToString()), instance_id = t.GetInstanceID(), screen_position = Center(t.rectTransform) });
            foreach (var t in Object.FindObjectsByType<Text>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                if (t.isActiveAndEnabled && t.color.a > .05f && KitchenRun.Visible(t.rectTransform))
                    rows.Add(new VisibleUiSurface { text = t.text, style = Style(t.color, t.fontSize, t.fontStyle.ToString()), instance_id = t.GetInstanceID(), screen_position = Center(t.rectTransform) });
            return rows;
        }
        static Dictionary<string, int> Tokens(ResultUiObservation observation, bool grades, bool withStyle = false)
        {
            var bag = new Dictionary<string, int>(StringComparer.Ordinal);
            foreach (var surface in observation.surfaces)
            {
                var raw=surface.text??"";var source=withStyle?raw:Plain(raw);
                var matcher=withStyle?new Regex(@"</?[A-Za-z][^>]*>|"+(grades?Grade.ToString():Number.ToString()),RegexOptions.IgnoreCase):(grades?Grade:Number);
                var attributes=new Dictionary<string,string>();
                foreach (Match match in matcher.Matches(source))
                {
                    if(withStyle&&match.Value.StartsWith("<"))
                    {
                        var tag=Regex.Match(match.Value,@"^<(\/?)(color|b|i|size|u|mark|font-weight)(?:=([^>]+))?>$",RegexOptions.IgnoreCase);
                        if(tag.Success){var name=tag.Groups[2].Value.ToLowerInvariant();if(tag.Groups[1].Value=="/")attributes.Remove(name);else attributes[name]=tag.Groups[3].Value.ToLowerInvariant();}
                        continue;
                    }
                    var token = grades ? match.Value.ToLowerInvariant() :
                        double.Parse(match.Value, CultureInfo.InvariantCulture).ToString("R", CultureInfo.InvariantCulture);
                    var key = token + "|" + (withStyle ? (surface.style ?? "")+string.Join(";",attributes.OrderBy(k=>k.Key).Select(k=>k.Key+"="+k.Value)) : "");
                    if (!bag.ContainsKey(key)) bag[key] = 0;
                    bag[key]++;
                }
            }
            return bag;
        }
        public static bool[] CurrentValues(IReadOnlyList<ResultUiObservation> observations, bool grades)
        {
            // Subtract presentation tokens common to every independent score state.
            // Instance IDs and whole-text strings are deliberately not correspondence keys.
            // A static legend cannot pass even if another part of the Text changes score.
            var bags = observations.Select(o => Tokens(o, grades)).ToArray();
            var common = new Dictionary<string, int>();
            foreach (var key in bags.SelectMany(b => b.Keys).Distinct())
                common[key] = bags.Min(b => b.TryGetValue(key, out var n) ? n : 0);
            var verdict = observations.Select((o, i) =>
            {
                string expected = grades ? (o.score < 40 ? "bronze" : o.score < 80 ? "silver" : "gold") : o.score.ToString("R", CultureInfo.InvariantCulture);
                var residual = bags[i].Where(kv => kv.Value > common[kv.Key]).Select(kv => kv.Key.Split('|')[0]).ToArray();
                return residual.Contains(expected) && (!grades || residual.All(t => t == expected));
            }).ToArray();
            if (grades && !verdict.All(v => v))
            {
                // Legal fixed labels with a moving highlight: a stable presentation style
                // must select only the expected grade in every score range. Merely changing
                // the color of an entire legend does not identify one current grade.
                var styled = observations.Select(o => Tokens(o, true, true)).ToArray();
                var styles = styled.SelectMany(b => b.Keys.Select(k => k.Substring(k.IndexOf('|') + 1))).Distinct();
                bool selection = styles.Any(style => observations.Select((o, i) =>
                {
                    var expected = o.score < 40 ? "bronze" : o.score < 80 ? "silver" : "gold";
                    var selected = styled[i].Where(kv => kv.Value > 0 && kv.Key.Substring(kv.Key.IndexOf('|') + 1) == style)
                        .Select(kv => kv.Key.Split('|')[0]).Distinct().ToArray();
                    return selected.Length == 1 && selected[0] == expected;
                }).All(v => v));
                if (selection) return observations.Select(o => true).ToArray();
            }
            return verdict;
        }
        public static Button[] VisibleButtons()
        {
            var labels = Capture().Select(s => s.instance_id).ToHashSet();
            return Object.FindObjectsByType<Button>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(b => b.isActiveAndEnabled && b.IsInteractable() && KitchenRun.Visible((RectTransform)b.transform) &&
                    (b.GetComponentsInChildren<Text>(false).Any(t => labels.Contains(t.GetInstanceID())) ||
                     b.GetComponentsInChildren<TMP_Text>(false).Any(t => labels.Contains(t.GetInstanceID()))))
                .OrderByDescending(b => Center((RectTransform)b.transform).y).ThenBy(b => Center((RectTransform)b.transform).x).ToArray();
        }
        public static IEnumerator Click(Button button)
        {
            // Normal mouse device input. Never invoke onClick, ExecuteEvents, or a game API.
            var mouse = Mouse.current;
            if (mouse == null) throw new InvalidOperationException("PlayerInputDriver must own an active mouse before a UI test.");
            var position = Center((RectTransform)button.transform);
            mouse.MakeCurrent(); InputSystem.QueueStateEvent(mouse, new MouseState { position = position }); yield return null;
            InputSystem.QueueStateEvent(mouse, new MouseState { position = position }.WithButton(MouseButton.Left)); yield return null;
            InputSystem.QueueStateEvent(mouse, new MouseState { position = position }); yield return null;
        }
        public static bool RestartVisibleAndOperable(ResultUiObservation o) =>
            (o.restart_hint_visible || o.restart_control_visible) && o.restart_operable;
    }
}
