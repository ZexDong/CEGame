using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using GameCreate.Benchmark.NoirRoombreak;
using Benchmark.Dashboard;
using UnityEngine;
using UnityEngine.UI;

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
            var candidates = UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                .Where(x => x && x.enabled && x.sprite != null && x.color.a > .05f)
                .Select(x => new { transform = x.transform, distance = Vector2.Distance((Vector2)Camera.main.WorldToScreenPoint(x.bounds.center), target) })
                .OrderBy(x => x.distance).ToArray();
            return candidates.Length > 0 && candidates[0].distance < 180f ? candidates[0].transform : null;
        }

        public static Vector3 RealPlayerPosition(INoirRoombreakProbe probe)
        {
            var player = FindPlayerTransform(probe);
            if (player) return player.position;
            if (probe != null)
            {
                var closest = UnityEngine.Object.FindObjectsByType<Image>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Where(VisibleImage).Select(x => ScreenRect(x.rectTransform, x.canvas))
                    .Select(x => new { rect = x, distance = Vector2.Distance(x.center, probe.PlayerScreenPosition) })
                    .OrderBy(x => x.distance).FirstOrDefault();
                if (closest != null && closest.distance < 180f) return new Vector3(closest.rect.center.x, closest.rect.center.y, 0f);
            }
            return new Vector3(probe == null ? 0f : probe.PlayerScreenPosition.x, probe == null ? 0f : probe.PlayerScreenPosition.y, 0f);
        }
        public static int ActiveCameraCount() => UnityEngine.Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.isActiveAndEnabled);
        public static int VisibleSpriteCount() => VisibleVisualCount();
        public static int VisibleVisualCount()
        {
            var spriteRenderers = UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.enabled && x.sprite != null && x.color.a > .05f);
            var images = UnityEngine.Object.FindObjectsByType<Image>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(VisibleImage);
            var rawImages = UnityEngine.Object.FindObjectsByType<RawImage>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(VisibleRawImage);
            var onGuiAssets = OnGuiVisualAssets();
            var onGuiVisible = onGuiAssets.Count > 0 && CapturedGameplayFrameHasVisualVariation(out _);
            return spriteRenderers + images + rawImages + (onGuiVisible ? onGuiAssets.Count : 0);
        }
        public static int SolidColliderCount() => UnityEngine.Object.FindObjectsByType<Collider2D>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.enabled && !x.isTrigger);
        public static int VisibleCanvasCount() => UnityEngine.Object.FindObjectsByType<Canvas>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.isActiveAndEnabled);

        public static bool ReadableActor(Transform actor,out string observed)
        {
            observed="actor renderer missing";
            if(actor==null||Camera.main==null||!actor.TryGetComponent<SpriteRenderer>(out var renderer)||renderer.sprite==null)return false;
            var sprite=renderer.sprite;var rect=sprite.rect;Texture2D decoded=null;
            try
            {
#if UNITY_EDITOR
                var path=UnityEditor.AssetDatabase.GetAssetPath(sprite.texture);
                if(string.IsNullOrWhiteSpace(path)||!System.IO.File.Exists(path))throw new InvalidOperationException("Cannot independently inspect actor texture alpha.");
                decoded=new Texture2D(2,2);if(!decoded.LoadImage(System.IO.File.ReadAllBytes(path)))throw new InvalidOperationException("Actor texture decode failed.");
                var pixels=decoded.GetPixels32();var xMin=(int)rect.xMax;var xMax=(int)rect.xMin;var yMin=(int)rect.yMax;var yMax=(int)rect.yMin;
                for(var y=(int)rect.yMin;y<(int)rect.yMax;y++)for(var x=(int)rect.xMin;x<(int)rect.xMax;x++)
                    if(pixels[y*decoded.width+x].a>64){xMin=Math.Min(xMin,x);xMax=Math.Max(xMax,x);yMin=Math.Min(yMin,y);yMax=Math.Max(yMax,y);}
                var a=Camera.main.WorldToScreenPoint(renderer.bounds.min);var b=Camera.main.WorldToScreenPoint(renderer.bounds.max);
                var width=Mathf.Abs(b.x-a.x)*Math.Max(0,xMax-xMin+1)/rect.width;
                var height=Mathf.Abs(b.y-a.y)*Math.Max(0,yMax-yMin+1)/rect.height;
                observed=$"visible actor pixels={width:F1}x{height:F1}";
                return width>=6&&height>=12;
#else
                throw new InvalidOperationException("Actor alpha observation requires the bound editor asset source.");
#endif
            }
            finally{if(decoded!=null)UnityEngine.Object.Destroy(decoded);}
        }

        public static bool SuppliedAssembly(bool actionPlaybackObserved, string expectedActionAudioRole, out bool suppliedActionFeedback, out string observed)
        {
            var sprites = UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(x => x && x.enabled && x.sprite != null && x.color.a > .05f).ToArray();
            var images = UnityEngine.Object.FindObjectsByType<Image>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(VisibleImage).ToArray();
            var rawImages = UnityEngine.Object.FindObjectsByType<RawImage>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(VisibleRawImage).ToArray();
            var onGuiAssets = OnGuiVisualAssets();
            var onGuiFrameObserved = "not-checked";
            var onGuiFrameVisible = onGuiAssets.Count > 0 && CapturedGameplayFrameHasVisualVariation(out onGuiFrameObserved);
            var spriteRoles = new HashSet<string>(StringComparer.Ordinal);
#if UNITY_EDITOR
            foreach (var renderer in sprites)
            {
                AddVisualRole(renderer.sprite, spriteRoles);
            }
            foreach (var image in images) AddVisualRole(image.sprite, spriteRoles);
            foreach (var image in rawImages) AddVisualRole(image.texture, spriteRoles);
            // Serialized fields on an OnGUI component are only inventory.  They
            // become scoring evidence after the captured gameplay frame proves
            // that the OnGUI path actually rendered visible, non-flat pixels.
            if (onGuiFrameVisible) foreach (var asset in onGuiAssets) AddVisualRole(asset, spriteRoles);
#endif
            var audio = InspectSuppliedAudio(actionPlaybackObserved, expectedActionAudioRole);
            suppliedActionFeedback = audio.actionFeedback;
            var visibleVisuals = sprites.Length + images.Length + rawImages.Length + (onGuiFrameVisible ? onGuiAssets.Count : 0);
            observed = $"visibleVisuals={visibleVisuals};spriteRenderers={sprites.Length};uiImages={images.Length};rawImages={rawImages.Length};onGuiReferencedAssets={onGuiAssets.Count};onGuiFrameVisible={onGuiFrameVisible}[{onGuiFrameObserved}];catalogSpriteRoles={string.Join(",", spriteRoles.OrderBy(x => x, StringComparer.Ordinal))};audioSources={audio.sourceCount};referencedCatalogClips={audio.clipCount};audioRoles={string.Join(",", audio.roles)};audioOrigins={audio.origins};actionPlayback={actionPlaybackObserved};expectedActionRole={expectedActionAudioRole};catalogActionFeedback={audio.actionFeedback};canvases={VisibleCanvasCount()}";
            return visibleVisuals >= 3 && spriteRoles.Count >= 2 && audio.inventory && actionPlaybackObserved && UnityEngine.Object.FindFirstObjectByType<AudioListener>() != null;
        }

        static bool VisibleImage(Image image) => image && image.isActiveAndEnabled && image.gameObject.activeInHierarchy && image.sprite != null && image.color.a > .05f && image.canvas != null && image.canvas.isActiveAndEnabled && image.canvasRenderer.GetAlpha() > .05f;
        static bool VisibleRawImage(RawImage image) => image && image.isActiveAndEnabled && image.gameObject.activeInHierarchy && image.texture != null && image.color.a > .05f && image.canvas != null && image.canvas.isActiveAndEnabled && image.canvasRenderer.GetAlpha() > .05f;

        static HashSet<UnityEngine.Object> OnGuiVisualAssets()
        {
            var assets = new HashSet<UnityEngine.Object>();
            foreach (var component in UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                if (!component || !component.isActiveAndEnabled || !component.gameObject.activeInHierarchy || !HasOnGui(component.GetType())) continue;
                CollectReferencedVisualAssets(component, assets);
            }
            return assets;
        }

        static bool HasOnGui(Type type) => type != null && type.GetMethod("OnGUI", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic) != null;

        static bool CapturedGameplayFrameHasVisualVariation(out string observed)
        {
            observed = "capture=missing";
            Texture2D texture = null;
            try
            {
                var path = Environment.GetEnvironmentVariable("NOIR_ROOMBREAK_HEADFUL_SCREENSHOT_PATH");
                var source = "headful_standalone";
                if (string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path)) return false;
                if (!System.IO.File.Exists(path)) return false;
                texture = new Texture2D(2, 2, TextureFormat.RGB24, false);
                if (!texture.LoadImage(System.IO.File.ReadAllBytes(path), false) || texture.width < 32 || texture.height < 32) { observed = "capture=unreadable"; return false; }
                var colors = new HashSet<int>();
                var minimum = 1f; var maximum = 0f;
                for (var y = 1; y <= 8; y++) for (var x = 1; x <= 15; x++)
                {
                    var color = texture.GetPixel(texture.width * x / 16, texture.height * y / 9);
                    var luminance = color.r * .2126f + color.g * .7152f + color.b * .0722f;
                    minimum = Mathf.Min(minimum, luminance); maximum = Mathf.Max(maximum, luminance);
                    colors.Add((Mathf.RoundToInt(color.r * 15) << 8) | (Mathf.RoundToInt(color.g * 15) << 4) | Mathf.RoundToInt(color.b * 15));
                }
                observed = $"source={source};capture={texture.width}x{texture.height};sampleColors={colors.Count};lumaRange={maximum-minimum:F3}";
                return colors.Count >= 6 && maximum - minimum >= .12f;
            }
            catch (Exception ex) { observed = "capture-exception=" + ex.GetType().Name; return false; }
            finally { if (texture) UnityEngine.Object.Destroy(texture); }
        }

        static void CollectReferencedVisualAssets(MonoBehaviour component, HashSet<UnityEngine.Object> assets)
        {
            foreach (var field in component.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
            {
                if (field.IsStatic || field.IsNotSerialized) continue;
                if (typeof(Sprite).IsAssignableFrom(field.FieldType) || typeof(Texture).IsAssignableFrom(field.FieldType))
                {
                    try { if (field.GetValue(component) is UnityEngine.Object asset && asset) assets.Add(asset); } catch { }
                    continue;
                }
                if (!typeof(IEnumerable).IsAssignableFrom(field.FieldType) || field.FieldType == typeof(string)) continue;
                var elementType = field.FieldType.IsArray ? field.FieldType.GetElementType() : (field.FieldType.IsGenericType ? field.FieldType.GetGenericArguments().FirstOrDefault() : null);
                if (elementType == null || (!typeof(Sprite).IsAssignableFrom(elementType) && !typeof(Texture).IsAssignableFrom(elementType))) continue;
                try { if (field.GetValue(component) is IEnumerable values) foreach (var value in values) if (value is UnityEngine.Object asset && asset) assets.Add(asset); } catch { }
            }
        }

#if UNITY_EDITOR
        static void AddVisualRole(UnityEngine.Object asset, HashSet<string> roles)
        {
            if (!asset) return;
            var path = UnityEditor.AssetDatabase.GetAssetPath(asset);
            if (string.IsNullOrWhiteSpace(path) && asset is Sprite sprite && sprite.texture != null) path = UnityEditor.AssetDatabase.GetAssetPath(sprite.texture);
            if (SpriteRolesByCatalogPath.TryGetValue(SuppliedAssetRules.Normalize(path), out var role)) roles.Add(role);
            else
            {
                var texturePath=asset is Sprite image && image.texture!=null?UnityEditor.AssetDatabase.GetAssetPath(image.texture):path;
                var contentRole=SuppliedSpriteContent.Role(texturePath);
                if(contentRole!=null)roles.Add(contentRole);
            }
        }
#endif

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
            var visited=new HashSet<object>(ReferenceComparer.Instance);
            var stack=new Stack<(object value,int depth)>();stack.Push((component,0));var budget=4096;
            while(stack.Count>0&&budget-->0)
            {
                var entry=stack.Pop();var value=entry.value;
                if(value==null||entry.depth>5)continue;
                if(value is AudioClip clip){if(clip){clips.Add(clip);origins.Add("game-owned reference graph");}continue;}
                var type=value.GetType();
                if(type.IsPrimitive||type.IsEnum||value is string||!visited.Add(value))continue;
                if(value is IDictionary dictionary){foreach(var item in dictionary.Values)stack.Push((item,entry.depth+1));continue;}
                if(value is IList list){for(var i=0;i<list.Count&&i<2048;i++)stack.Push((list[i],entry.depth+1));continue;}
                if(value is UnityEngine.Object&&value!=component&&!(value is ScriptableObject))continue;
                if(type.Namespace!=null&&(type.Namespace.StartsWith("System",StringComparison.Ordinal)||type.Namespace.StartsWith("UnityEngine",StringComparison.Ordinal)))continue;
                foreach(var field in type.GetFields(BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic))
                {
                    if(field.IsStatic)continue;
                    try{stack.Push((field.GetValue(value),entry.depth+1));}catch{}
                }
            }
        }
        sealed class ReferenceComparer : IEqualityComparer<object>
        {
            public static readonly ReferenceComparer Instance=new ReferenceComparer();
            public new bool Equals(object a,object b)=>ReferenceEquals(a,b);
            public int GetHashCode(object value)=>System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(value);
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

        public static bool VisibleSpriteNear(Vector2 screenPoint, out Color color, out string observed)
        {
            color = Color.clear;
            observed = "visual=none";
            try
            {
                if (!Finite(screenPoint)) return false;
                var bestDistance = float.PositiveInfinity;
                var bestColor = Color.clear;
                var bestName = "none";
                if (Camera.main != null)
                {
                    var spriteCandidates = UnityEngine.Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(x => x && x.enabled && x.sprite != null && x.color.a > .05f)
                        .Select(x => new { renderer = x, distance = Vector2.Distance((Vector2)Camera.main.WorldToScreenPoint(x.bounds.center), screenPoint) }).OrderBy(x => x.distance).ToArray();
                    if (spriteCandidates.Length > 0 && spriteCandidates[0].distance <= 96f)
                    {
                        color = spriteCandidates[0].renderer.color;
                        observed = $"visual=SpriteRenderer:{spriteCandidates[0].renderer.name};distance={spriteCandidates[0].distance:F1};color={color}";
                        return true;
                    }
                }
                foreach (var image in UnityEngine.Object.FindObjectsByType<Image>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(VisibleImage))
                {
                    var rect = ScreenRect(image.rectTransform, image.canvas);
                    var distance = Vector2.Distance(rect.center, screenPoint);
                    if (distance < bestDistance) { bestDistance = distance; bestColor = image.color; bestName = "Image:" + image.name; }
                }
                if (bestDistance > 96f) return false;
                color = bestColor;
                observed = $"visual={bestName};distance={bestDistance:F1};color={color}";
                return true;
            }
            catch (Exception ex) { observed = "visual-exception=" + ex.GetType().Name; return false; }
        }

        public static bool TryFindInteractableButtonScreenRect(Rect preferredRect, out Rect rect, out string observed)
        {
            rect = Rect.zero;
            observed = "buttons=0";
            try
            {
                Canvas.ForceUpdateCanvases();
                var buttons = UnityEngine.Object.FindObjectsByType<Button>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Where(x => x && x.isActiveAndEnabled && x.interactable && x.gameObject.activeInHierarchy && x.transform is RectTransform && x.GetComponentInParent<Canvas>() is Canvas canvas && canvas.isActiveAndEnabled)
                    .Select(x => new { button = x, canvas = x.GetComponentInParent<Canvas>(), rect = ScreenRect((RectTransform)x.transform, x.GetComponentInParent<Canvas>()) })
                    .Where(x => ValidRect(x.rect, 8f, 8f) && OnScreen(x.rect.center, 8f))
                    .Select(x => new { x.button, x.canvas, x.rect, score = Mathf.Min(RectDistance(x.rect, preferredRect), RectDistance(x.rect, PreferredRectForCanvas(preferredRect, x.canvas))) })
                    .OrderBy(x => x.score).ToArray();
                observed = "buttons=" + buttons.Length;
                if (buttons.Length == 0) return false;
                if (buttons.Length > 1 && buttons[1].score - buttons[0].score < Mathf.Max(8f, buttons[0].score * .2f)) { observed += $";ambiguous={buttons[0].button.name}:{buttons[0].score:F1},{buttons[1].button.name}:{buttons[1].score:F1}"; return false; }
                rect = buttons[0].rect;
                observed += $";selected={buttons[0].button.name};score={buttons[0].score:F1};rect={rect}";
                return true;
            }
            catch (Exception ex) { observed = "button-rect-exception=" + ex.GetType().Name; return false; }
        }

        static Rect PreferredRectForCanvas(Rect preferred, Canvas canvas)
        {
            if (canvas == null) return preferred;
            var scaler = canvas.GetComponent<CanvasScaler>();
            if (scaler == null || scaler.referenceResolution.x <= 0 || scaler.referenceResolution.y <= 0 || canvas.scaleFactor <= 0) return preferred;
            var center = new Vector2(Screen.width * .5f, Screen.height * .5f) + (preferred.center - scaler.referenceResolution * .5f) * canvas.scaleFactor;
            var size = preferred.size * canvas.scaleFactor;
            return new Rect(center - size * .5f, size);
        }

        static readonly string[] DashboardSlots = { "room_index", "room_count", "bonds", "maximum_bonds", "dash_charges", "maximum_dash_charges", "player_alive", "player_grounded", "player_dashing", "player_invulnerable", "anda_chasing", "obser_lock_visible", "obser_laser_visible", "defeated_enemy_count", "soft_respawn_count", "global_respawn_count", "last_respawn_kind", "state_sequence" };
        static readonly string[] DashboardTargets = { "start_button", "pause_resume_control", "success_return_control", "restart_button" };

        public static IGameStateDashboard FindDashboard()
        {
            try
            {
                var dashboards = UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .OfType<IGameStateDashboard>().ToArray();
                foreach (var dashboard in dashboards)
                    if (DashboardContractOk(dashboard, out _)) return dashboard;
                return dashboards.FirstOrDefault();
            }
            catch { return null; }
        }

        public static bool DashboardContractOk(IGameStateDashboard dashboard, out string observed)
        {
            observed = "dashboard=null"; if (dashboard == null) return false;
            try
            {
                var snapshot = dashboard.Capture(); if (snapshot == null) { observed = "snapshot=null"; return false; }
                var slots = snapshot.slots ?? new List<SlotEntry>(); var entities = snapshot.entities ?? new List<EntityEntry>(); var targets = snapshot.targets ?? new List<TargetEntry>();
                var slotNames = slots.Select(x => x == null ? "" : x.name).ToArray(); var targetNames = targets.Select(x => x == null ? "" : x.kind).ToArray();
                var finiteSlots = slots.All(x => x != null && !string.IsNullOrWhiteSpace(x.name) && Finite(x.value));
                var uniqueSlots = slotNames.Distinct(StringComparer.Ordinal).Count() == slotNames.Length; var requiredSlots = DashboardSlots.All(x => slotNames.Contains(x, StringComparer.Ordinal));
                var uniqueTargets = targetNames.Distinct(StringComparer.Ordinal).Count() == targetNames.Length; var requiredTargets = DashboardTargets.All(x => targetNames.Contains(x, StringComparer.Ordinal));
                var entitiesOk = entities.All(x => x != null && (x.kind == "player" || x.kind == "anda" || x.kind == "obser") && x.cell != null && x.cell.Length == 2 && x.cell[0] >= 0 && x.cell[0] <= Screen.width && x.cell[1] >= 0 && x.cell[1] <= Screen.height && !string.IsNullOrWhiteSpace(x.state) && x.GetType().GetFields().All(f => f.Name == "kind" || f.Name == "cell" || f.Name == "state"));
                var targetsOk = targets.All(x => x != null && DashboardTargets.Contains(x.kind, StringComparer.Ordinal) && x.visible == x.interactable && (!x.visible || ValidRect(x.rect) && OnScreen(new Vector2(x.rect.xMin, x.rect.yMin)) && OnScreen(new Vector2(x.rect.xMax, x.rect.yMax))));
                var json = DashboardJson.ToJson(snapshot); var jsonShape = json.StartsWith("{") && json.EndsWith("}") && json.Contains("\"slots\":{") && json.Contains("\"entities\":[") && !json.Contains("\"id\":") && !json.Contains("\"room\":") && !json.Contains("\"visible\":true,\"id\"");
                observed = $"version={dashboard.ContractVersion};phase={DashboardJson.PhaseName(snapshot.phase)};revision={snapshot.revision};slots={slotNames.Length};targets={targetNames.Length};entities={entities.Count};jsonShape={jsonShape}";
                return dashboard.ContractVersion == "game-state-dashboard/v2" && snapshot.phase != GamePhase.NotReady && snapshot.revision >= 0 && finiteSlots && uniqueSlots && requiredSlots && uniqueTargets && requiredTargets && entitiesOk && targetsOk && jsonShape;
            }
            catch (Exception ex) { observed = "dashboard-exception=" + ex.GetType().Name; return false; }
        }

        public static bool DashboardMatchesProbe(IGameStateDashboard dashboard, INoirRoombreakProbe probe, out string observed)
        {
            observed = "dashboard-or-probe-null"; if (dashboard == null || probe == null) return false;
            try
            {
                var snapshot = dashboard.Capture(); if (snapshot == null) { observed = "snapshot=null"; return false; }
                var slots = (snapshot.slots ?? new List<SlotEntry>()).Where(x => x != null).ToDictionary(x => x.name, x => x.value, StringComparer.Ordinal);
                var expectedPhase = probe.CurrentScreen == NoirScreen.Menu ? GamePhase.Menu : probe.CurrentScreen == NoirScreen.Playing ? GamePhase.Playing : probe.CurrentScreen == NoirScreen.Paused ? GamePhase.Paused : GamePhase.Won;
                bool Slot(string name, float value) => slots.TryGetValue(name, out var actual) && Mathf.Abs(actual - value) < .001f;
                var slotsOk =
                    Slot("room_index", probe.CurrentRoomIndex) &&
                    Slot("room_count", probe.RoomCount) &&
                    Slot("bonds", probe.Bonds) &&
                    Slot("maximum_bonds", probe.MaximumBonds) &&
                    Slot("dash_charges", probe.DashCharges) &&
                    Slot("maximum_dash_charges", probe.MaximumDashCharges) &&
                    Slot("player_alive", probe.PlayerAlive ? 1 : 0) &&
                    Slot("player_grounded", probe.PlayerGrounded ? 1 : 0) &&
                    Slot("player_dashing", probe.PlayerDashing ? 1 : 0) &&
                    Slot("player_invulnerable", probe.PlayerInvulnerable ? 1 : 0) &&
                    Slot("anda_chasing", probe.AndaChasing ? 1 : 0) &&
                    Slot("obser_lock_visible", probe.ObserLockVisible ? 1 : 0) &&
                    Slot("obser_laser_visible", probe.ObserLaserVisible ? 1 : 0) &&
                    Slot("defeated_enemy_count", probe.DefeatedEnemyCount) &&
                    Slot("soft_respawn_count", probe.SoftRespawnCount) &&
                    Slot("global_respawn_count", probe.GlobalRespawnCount) &&
                    Slot("last_respawn_kind", (int)probe.LastRespawnKind) &&
                    Slot("state_sequence", probe.StateSequence);

                var entities = snapshot.entities ?? new List<EntityEntry>();
                var entityPhase = expectedPhase == GamePhase.Playing || expectedPhase == GamePhase.Paused;
                var players = entities.Where(x => x != null && x.kind == "player").ToArray();
                var playerOk = entityPhase
                    ? players.Length == 1 && players[0].cell != null && players[0].cell.Length == 2 &&
                      Vector2.Distance(new Vector2(players[0].cell[0], players[0].cell[1]), probe.PlayerScreenPosition) <= 4f &&
                      string.Equals(players[0].state, ExpectedPlayerState(probe), StringComparison.Ordinal)
                    : players.Length == 0;

                NoirEnemySnapshot[] expectedEnemies;
                try
                {
                    expectedEnemies = entityPhase
                        ? (probe.Enemies ?? Array.Empty<NoirEnemySnapshot>()).Where(x => x.Visible && x.RoomIndex == probe.CurrentRoomIndex).ToArray()
                        : Array.Empty<NoirEnemySnapshot>();
                }
                catch { expectedEnemies = Array.Empty<NoirEnemySnapshot>(); }
                var actualEnemies = entities.Where(x => x != null && (x.kind == "anda" || x.kind == "obser")).ToArray();
                var enemiesOk = CurrentRoomEnemiesMatch(actualEnemies, expectedEnemies);
                var onlyExpectedEntities = entities.All(x => x != null && (x.kind == "player" || x.kind == "anda" || x.kind == "obser"));

                var targets = snapshot.targets ?? new List<TargetEntry>();
                var start = targets.FirstOrDefault(x => x != null && x.kind == "start_button");
                var pause = targets.FirstOrDefault(x => x != null && x.kind == "pause_resume_control");
                var success = targets.FirstOrDefault(x => x != null && x.kind == "success_return_control");
                var restart = targets.FirstOrDefault(x => x != null && x.kind == "restart_button");

                var startExpected = probe.CurrentScreen == NoirScreen.Menu;
                var pauseExpected = probe.CurrentScreen == NoirScreen.Paused;
                var successExpected = probe.CurrentScreen == NoirScreen.Success;
                var restartExpected = pauseExpected || successExpected;
                var startOk = TargetStateMatches(start, startExpected) && (!startExpected || ValidRect(probe.StartButtonScreenRect) && RectDistance(start.rect, probe.StartButtonScreenRect) <= 4f);
                var pauseRender = "not-required";
                var successRender = "not-required";
                var restartRender = "not-required";
                var pauseOk = TargetStateMatches(pause, pauseExpected) && (!pauseExpected || ValidRect(probe.PausePanelScreenRect) && RectDistance(pause.rect, probe.PausePanelScreenRect) <= 4f && RenderedUiRectMatches(pause.rect, out pauseRender));
                var successOk = TargetStateMatches(success, successExpected) && (!successExpected || ValidRect(probe.SuccessPanelScreenRect) && RectDistance(success.rect, probe.SuccessPanelScreenRect) <= 4f && RenderedUiRectMatches(success.rect, out successRender));
                var restartOk = TargetStateMatches(restart, restartExpected) && (!restartExpected || RenderedUiRectMatches(restart.rect, out restartRender));
                var targetsOk = startOk && pauseOk && successOk && restartOk;

                observed = $"phase={snapshot.phase}/{expectedPhase};slots={slots.Count}/18;slotsOk={slotsOk};player={players.Length},ok={playerOk};enemies={actualEnemies.Length}/{expectedEnemies.Length},ok={enemiesOk};onlyExpectedEntities={onlyExpectedEntities};targets=start:{startOk},pause:{pauseOk}[{pauseRender}],success:{successOk}[{successRender}],restart:{restartOk}[{restartRender}]";
                return snapshot.phase == expectedPhase && slotsOk && playerOk && enemiesOk && onlyExpectedEntities && targetsOk;
            }
            catch (Exception ex) { observed = "dashboard-crosscheck-exception=" + ex.GetType().Name; return false; }
        }

        static bool CurrentRoomEnemiesMatch(IReadOnlyCollection<EntityEntry> actual, IReadOnlyCollection<NoirEnemySnapshot> expected)
        {
            if (actual.Count != expected.Count) return false;
            var remaining = actual.ToList();
            foreach (var enemy in expected)
            {
                var kind = enemy.Kind == NoirEnemyKind.Anda ? "anda" : "obser";
                var state = ExpectedEnemyState(enemy.State);
                var bestIndex = -1;
                var bestDistance = float.PositiveInfinity;
                for (var i = 0; i < remaining.Count; i++)
                {
                    var candidate = remaining[i];
                    if (candidate.cell == null || candidate.cell.Length != 2 || !string.Equals(candidate.kind, kind, StringComparison.Ordinal) || !string.Equals(candidate.state, state, StringComparison.Ordinal)) continue;
                    var distance = Vector2.Distance(new Vector2(candidate.cell[0], candidate.cell[1]), enemy.ScreenPosition);
                    if (distance < bestDistance) { bestDistance = distance; bestIndex = i; }
                }
                if (bestIndex < 0 || bestDistance > 4f) return false;
                remaining.RemoveAt(bestIndex);
            }
            return remaining.Count == 0;
        }

        static string ExpectedPlayerState(INoirRoombreakProbe probe)
        {
            if (!probe.PlayerAlive) return "dead";
            if (probe.PlayerDashing) return "dashing";
            if (probe.PlayerInvulnerable) return "invulnerable";
            return probe.PlayerGrounded ? "grounded" : "airborne";
        }

        static string ExpectedEnemyState(NoirEnemyState state)
        {
            switch (state)
            {
                case NoirEnemyState.Patrol: return "patrol";
                case NoirEnemyState.Alert: return "alert";
                case NoirEnemyState.Chase: return "chase";
                case NoirEnemyState.Locking: return "locking";
                case NoirEnemyState.Firing: return "firing";
                case NoirEnemyState.Defeated: return "defeated";
                default: return "idle";
            }
        }

        static bool TargetStateMatches(TargetEntry target, bool expectedActive) =>
            target != null && target.visible == expectedActive && target.interactable == expectedActive && (!expectedActive || ValidRect(target.rect));

        static bool RenderedUiRectMatches(Rect expected, out string observed)
        {
            observed = "graphics=0";
            try
            {
                Canvas.ForceUpdateCanvases();
                var candidates = UnityEngine.Object.FindObjectsByType<Graphic>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Where(x => x && x.isActiveAndEnabled && x.gameObject.activeInHierarchy && x.canvas != null && x.canvas.isActiveAndEnabled && x.color.a > .01f && x.canvasRenderer.GetAlpha() > .01f)
                    .Select(x => ScreenRect(x.rectTransform, x.canvas))
                    .Where(x => ValidRect(x, 1f, 1f)).ToArray();
                var best = candidates.Length == 0 ? float.PositiveInfinity : candidates.Min(x => RectDistance(x, expected));
                observed = $"graphics={candidates.Length};bestRectDistance={(float.IsInfinity(best) ? "inf" : best.ToString("F1"))}";
                return best <= 8f;
            }
            catch (Exception ex) { observed = "render-rect-exception=" + ex.GetType().Name; return false; }
        }

        static Rect ScreenRect(RectTransform transform, Canvas canvas)
        {
            var corners = new Vector3[4];
            transform.GetWorldCorners(corners);
            var camera = canvas.renderMode == RenderMode.ScreenSpaceOverlay ? null : (canvas.worldCamera != null ? canvas.worldCamera : Camera.main);
            var points = corners.Select(x => RectTransformUtility.WorldToScreenPoint(camera, x)).ToArray();
            var minimumX = points.Min(x => x.x); var maximumX = points.Max(x => x.x);
            var minimumY = points.Min(x => x.y); var maximumY = points.Max(x => x.y);
            return Rect.MinMaxRect(minimumX, minimumY, maximumX, maximumY);
        }

        static float RectDistance(Rect a, Rect b) => Mathf.Abs(a.x-b.x)+Mathf.Abs(a.y-b.y)+Mathf.Abs(a.width-b.width)+Mathf.Abs(a.height-b.height);
        public static string Snapshot(INoirRoombreakProbe probe)
        {
            if (probe == null) return "probe=null";
            NoirEnemySnapshot[] enemies;
            try { enemies = probe.Enemies == null ? Array.Empty<NoirEnemySnapshot>() : probe.Enemies.ToArray(); }
            catch (Exception ex) { return "probe-enemies-error=" + ex.GetType().Name; }
            return $"screen={probe.CurrentScreen};room={probe.CurrentRoomIndex}/{probe.RoomCount};bonds={probe.Bonds}/{probe.MaximumBonds};dash={probe.DashCharges}/{probe.MaximumDashCharges};alive={probe.PlayerAlive};grounded={probe.PlayerGrounded};dashing={probe.PlayerDashing};invulnerable={probe.PlayerInvulnerable};player=({probe.PlayerScreenPosition.x:F1},{probe.PlayerScreenPosition.y:F1});andaChase={probe.AndaChasing};obserLock={probe.ObserLockVisible};obserLaser={probe.ObserLaserVisible};defeated={probe.DefeatedEnemyCount};soft={probe.SoftRespawnCount};global={probe.GlobalRespawnCount};lastRespawn={probe.LastRespawnKind};enemies={enemies.Length};sequence={probe.StateSequence}";
        }
        public static string VisibleTextSnapshot()
        {
            try
            {
                var values = UnityEngine.Object.FindObjectsByType<Text>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Where(x => x && x.isActiveAndEnabled && x.gameObject.activeInHierarchy && !string.IsNullOrWhiteSpace(x.text))
                    .Select(x => x.text.Trim()).ToList();
                foreach (var component in UnityEngine.Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                {
                    if (!component || !component.isActiveAndEnabled || !component.gameObject.activeInHierarchy) continue;
                    var type = component.GetType();
                    if (string.Equals(type.FullName, "TMPro.TextMeshProUGUI", StringComparison.Ordinal) || string.Equals(type.FullName, "TMPro.TextMeshPro", StringComparison.Ordinal))
                    {
                        try
                        {
                            var property = type.GetProperty("text", BindingFlags.Instance | BindingFlags.Public);
                            var value = property == null ? null : property.GetValue(component) as string;
                            if (!string.IsNullOrWhiteSpace(value)) values.Add(value.Trim());
                        }
                        catch { }
                        continue;
                    }
                    if (!HasOnGui(type)) continue;
                    foreach (var field in type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
                    {
                        if (field.IsStatic || field.FieldType != typeof(string)) continue;
                        var name = field.Name.ToLowerInvariant();
                        if (!name.Contains("text") && !name.Contains("message") && !name.Contains("feedback") && !name.Contains("title") && !name.Contains("label")) continue;
                        try { var value = field.GetValue(component) as string; if (!string.IsNullOrWhiteSpace(value)) values.Add(value.Trim()); } catch { }
                    }
                }
                return string.Join(" | ", values.Distinct(StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal));
            }
            catch { return string.Empty; }
        }
    }
}
