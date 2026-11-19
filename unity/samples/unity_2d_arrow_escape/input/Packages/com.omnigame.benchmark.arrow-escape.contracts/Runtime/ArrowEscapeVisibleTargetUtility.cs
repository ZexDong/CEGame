using System;
using System.Linq;
using UnityEngine;

namespace OmniGame.Benchmark.ArrowEscape.V2
{
    /// <summary>
    /// Convenience capture for ordinary GameObject-backed targets. Custom/IMGUI
    /// implementations may construct the same read-only snapshot from their
    /// current finite on-screen Rect instead.
    /// </summary>
    public static class ArrowEscapeVisibleTargetUtility
    {
        public static ArrowEscapeVisibleTargetSnapshot Capture(
            string id,
            ArrowEscapeVisibleTargetKind kind,
            GameObject target,
            bool interactable = true,
            string visualState = "normal")
        {
            Rect rect = ScreenRect(target);
            bool visible = target != null && target.activeInHierarchy &&
                           IsFinite(rect) && rect.width >= 1f && rect.height >= 1f &&
                           rect.xMax > 0f && rect.yMax > 0f &&
                           rect.xMin < Screen.width && rect.yMin < Screen.height;
            return new ArrowEscapeVisibleTargetSnapshot
            {
                Id = id,
                Kind = kind,
                ScreenRect = rect,
                Visible = visible,
                Interactable = visible && interactable,
                VisualState = visualState ?? "normal"
            };
        }

        public static Rect ScreenRect(GameObject target)
        {
            if (target == null) return default;
            RectTransform rectTransform = target.GetComponent<RectTransform>();
            if (rectTransform != null)
            {
                var corners = new Vector3[4];
                rectTransform.GetWorldCorners(corners);
                Canvas canvas = rectTransform.GetComponentInParent<Canvas>();
                Camera camera = canvas != null &&
                                canvas.renderMode != RenderMode.ScreenSpaceOverlay
                    ? canvas.worldCamera
                    : null;
                Vector2[] screen = corners.Select(corner =>
                    RectTransformUtility.WorldToScreenPoint(camera, corner)).ToArray();
                return Rect.MinMaxRect(screen.Min(p => p.x), screen.Min(p => p.y),
                    screen.Max(p => p.x), screen.Max(p => p.y));
            }

            Renderer[] renderers = target.GetComponentsInChildren<Renderer>(true)
                .Where(item => item != null && item.enabled &&
                               item.gameObject.activeInHierarchy)
                .ToArray();
            Camera worldCamera = Camera.main ?? UnityEngine.Object
                .FindObjectsByType<Camera>(FindObjectsInactive.Exclude,
                    FindObjectsSortMode.None)
                .FirstOrDefault(item => item.isActiveAndEnabled);
            if (renderers.Length == 0 || worldCamera == null) return default;
            bool initialized = false;
            Rect result = default;
            foreach (Renderer renderer in renderers)
            {
                Bounds bounds = renderer.bounds;
                Vector3 min = worldCamera.WorldToScreenPoint(bounds.min);
                Vector3 max = worldCamera.WorldToScreenPoint(bounds.max);
                Rect current = Rect.MinMaxRect(Mathf.Min(min.x, max.x),
                    Mathf.Min(min.y, max.y), Mathf.Max(min.x, max.x),
                    Mathf.Max(min.y, max.y));
                result = initialized ? Union(result, current) : current;
                initialized = true;
            }
            return result;
        }

        public static bool IsFinite(Rect rect) =>
            IsFinite(rect.x) && IsFinite(rect.y) &&
            IsFinite(rect.width) && IsFinite(rect.height);

        private static bool IsFinite(float value) =>
            !float.IsNaN(value) && !float.IsInfinity(value);

        private static Rect Union(Rect a, Rect b) => Rect.MinMaxRect(
            Mathf.Min(a.xMin, b.xMin), Mathf.Min(a.yMin, b.yMin),
            Mathf.Max(a.xMax, b.xMax), Mathf.Max(a.yMax, b.yMax));
    }
}
