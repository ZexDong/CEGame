using UnityEngine;

namespace GameCreate.NoirRoombreak.Evaluator.Standalone
{
    [DefaultExecutionOrder(32000)]
    internal sealed class StandaloneOnGuiSentinel : MonoBehaviour
    {
        public bool Visible;
        public static Rect RectFor(int width) => new Rect(Mathf.Max(8, width - 72), 8, 64, 64);

        void OnGUI()
        {
                       if (!Visible) return;
            var oldColor = GUI.color;
            var oldDepth = GUI.depth;
            GUI.depth = -32000;
            var rect = RectFor(Screen.width);
            Draw(rect, Color.black);
            Draw(new Rect(rect.x + 4, rect.y + 4, 26, 26), new Color(1, 0, 1, 1));                       Draw(new Rect(rect.x + 34, rect.y + 4, 26, 26), new Color(0, 1, 1, 1));            Draw(new Rect(rect.x + 4, rect.y + 34, 26, 26), new Color(1, 1, 0, 1));
            Draw(new Rect(rect.x + 34, rect.y + 34, 26, 26), new Color(0, 1, 0, 1));
            GUI.color = oldColor;
            GUI.depth = oldDepth;
        }

        static void Draw(Rect rect, Color color)
        {
            GUI.color = color;
            GUI.DrawTexture(rect, Texture2D.whiteTexture);
        }

        public static int MatchPixels(Texture2D texture)
        {
            if (texture == null || texture.width < 80 || texture.height < 80) return 0;
            var rect = RectFor(texture.width);
            var matches = 0;
            matches += MatchBlock(texture, Mathf.RoundToInt(rect.x + 11), Mathf.RoundToInt(rect.y + 11), 12, 0);
            matches += MatchBlock(texture, Mathf.RoundToInt(rect.x + 41), Mathf.RoundToInt(rect.y + 11), 12, 1);
            matches += MatchBlock(texture, Mathf.RoundToInt(rect.x + 11), Mathf.RoundToInt(rect.y + 41), 12, 2);
            matches += MatchBlock(texture, Mathf.RoundToInt(rect.x + 41), Mathf.RoundToInt(rect.y + 41), 12, 3);
            return matches;
        }

        static int MatchBlock(Texture2D texture, int guiX, int guiY, int size, int kind)
        {
            var matches = 0;
            for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
            {
                var px = Mathf.Clamp(guiX + x, 0, texture.width - 1);
                var py = Mathf.Clamp(texture.height - 1 - (guiY + y), 0, texture.height - 1);
                var color = texture.GetPixel(px, py);
                var match = kind == 0 ? color.r > .72f && color.g < .35f && color.b > .72f
                    : kind == 1 ? color.r < .35f && color.g > .72f && color.b > .72f
                    : kind == 2 ? color.r > .72f && color.g > .72f && color.b < .35f
                    : color.r < .35f && color.g > .72f && color.b < .35f;
                if (match) matches++;
            }
            return matches;
        }
    }
}
