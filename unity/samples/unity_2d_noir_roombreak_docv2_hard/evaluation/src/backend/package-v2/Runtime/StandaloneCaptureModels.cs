using System;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;
using UnityEngine.Rendering;

namespace GameCreate.NoirRoombreak.Evaluator.Standalone
{
    internal static class StandaloneCaptureContract
    {
        public const int Width = 1280;
        public const int Height = 720;
        public const int UiLayer = 31;
        public const int UiMask = unchecked(1 << UiLayer);
        public const string Method = "standalone-visible-two-layer-internal-composite-v3";

        public static string ScreenshotPath => Environment.GetEnvironmentVariable("NOIR_STANDALONE_SCREENSHOT_PATH") ?? "";
        public static string ReceiptPath => Environment.GetEnvironmentVariable("NOIR_STANDALONE_RECEIPT_PATH") ?? "";
        public static string DiagnosticDir => Environment.GetEnvironmentVariable("NOIR_STANDALONE_DIAGNOSTIC_DIR") ?? "";
        public static string RunId => Environment.GetEnvironmentVariable("NOIR_STANDALONE_RUN_ID") ?? "";

        public static string Sha256(string path)
        {
            using (var stream = File.OpenRead(path))
            using (var sha = SHA256.Create())
                return string.Concat(sha.ComputeHash(stream).Select(x => x.ToString("x2")));
        }

        public static void Write(CaptureReceipt receipt)
        {
            var path = ReceiptPath;
            if (string.IsNullOrWhiteSpace(path)) return;
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, JsonUtility.ToJson(receipt, true));
        }

        public static CaptureReceipt BaseReceipt(INoirRoombreakProbe probe, string inputPath)
        {
            var receipt = new CaptureReceipt
            {
                run_id = RunId,
                process_id = System.Diagnostics.Process.GetCurrentProcess().Id,
                unity_version = Application.unityVersion,
                scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene().path,
                input_path = inputPath ?? "",
                created_utc = DateTime.UtcNow.ToString("o"),
                screenshot_path = ScreenshotPath
            };
            if (probe == null) return receipt;
            receipt.semantic.screen = probe.CurrentScreen.ToString();
            receipt.semantic.room_index = probe.CurrentRoomIndex;
            receipt.semantic.room_count = probe.RoomCount;
            receipt.semantic.bonds = probe.Bonds;
            receipt.semantic.maximum_bonds = probe.MaximumBonds;
            receipt.semantic.dash = probe.DashCharges;
            receipt.semantic.maximum_dash = probe.MaximumDashCharges;
            receipt.semantic.alive = probe.PlayerAlive;
            receipt.semantic.defeated = probe.DefeatedEnemyCount;
            receipt.semantic.soft = probe.SoftRespawnCount;
            receipt.semantic.global = probe.GlobalRespawnCount;
            receipt.runtime_snapshot = Snapshot(probe);
            return receipt;
        }

        public static string Snapshot(INoirRoombreakProbe probe)
        {
            if (probe == null) return "probe=missing";
            return $"screen={probe.CurrentScreen};room={probe.CurrentRoomIndex}/{probe.RoomCount};bonds={probe.Bonds}/{probe.MaximumBonds};dash={probe.DashCharges}/{probe.MaximumDashCharges};alive={probe.PlayerAlive};defeated={probe.DefeatedEnemyCount};soft={probe.SoftRespawnCount};global={probe.GlobalRespawnCount}";
        }
    }

    internal sealed class CanvasState
    {
        public Canvas canvas;
        public bool enabled;
        public RenderMode mode;
        public Camera worldCamera;
        public float planeDistance;
    }

    internal sealed class LayerState
    {
        public GameObject gameObject;
        public int layer;
    }

    internal sealed class OverlayResult
    {
        public Texture2D texture;
        public int nonzero;
        public int partial;
        public int canvasCount;
        public int movedUiObjects;
        public int displacedForeign;
        public string renderPath = "";
        public bool canvasRestored;
        public bool layersRestored;
    }

    [Serializable]
    internal sealed class SemanticReceipt
    {
        public string screen = "";
        public int room_index = -1;
        public int room_count;
        public int bonds;
        public int maximum_bonds;
        public int dash;
        public int maximum_dash;
        public bool alive;
        public int defeated;
        public int soft;
        public int global;
    }

    [Serializable]
    internal sealed class SentinelReceipt
    {
        public bool proof_valid;
        public int proof_match_pixels;
        public string proof_sha256 = "";
        public bool clean_valid;
        public int clean_match_pixels;
        public string clean_base_sha256 = "";
        public string rect = "";
    }

    [Serializable]
    internal sealed class OverlayReceipt
    {
        public int canvas_count;
        public int moved_ui_object_count;
        public int displaced_foreign_layer31_count;
        public int dedicated_layer = StandaloneCaptureContract.UiLayer;
        public int culling_mask = StandaloneCaptureContract.UiMask;
        public int nonzero_alpha_pixels;
        public int partial_alpha_pixels;
        public string render_path = "";
        public string sha256 = "";
    }

    [Serializable]
    internal sealed class RestorationReceipt
    {
        public bool canvas_settings_restored;
        public bool layers_restored;
        public bool completed;
    }

    [Serializable]
    internal sealed class CaptureReceipt
    {
        public int schema_version = 2;
        public string method = StandaloneCaptureContract.Method;
        public string run_id = "";
        public string status = "not_started";
        public string classification = "";
        public bool valid;
        public int process_id;
        public string unity_version = "";
        public string scene = "";
        public string state = "initial_gameplay";
        public string input_path = "";
        public int width;
        public int height;
        public long bytes;
        public string sha256 = "";
        public string screenshot_path = "";
        public string runtime_snapshot = "";
        public SemanticReceipt semantic = new SemanticReceipt();
        public SentinelReceipt sentinel = new SentinelReceipt();
        public OverlayReceipt overlay = new OverlayReceipt();
        public RestorationReceipt restoration = new RestorationReceipt();
        public string created_utc = "";
        public string error = "";
        public int planned_exit_code;
    }
}
