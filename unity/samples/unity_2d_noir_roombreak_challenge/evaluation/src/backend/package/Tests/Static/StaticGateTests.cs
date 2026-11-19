using System.Collections;
using System.IO;
using System.Linq;
using GameCreate.Benchmark.NoirRoombreak;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using UnityEngine.UI;

namespace GameCreate.NoirRoombreak.Evaluator
{
    public sealed class StaticGateTests
    {
        const string ScenePath = "Assets/NoirChallenge/Scenes/NoirRoombreak.unity";

        [UnityTest]
        public IEnumerator STATIC01_LoadCompileCameraAndRuntimeEntry()
        {
            LogAssert.ignoreFailingMessages = true;
            EvidenceStore.Initialize("static", "No player input; saved-entry engineering gate only");
            EvidenceStore.BeginTrajectory("STATIC01", "STATIC01_LoadCompileCameraAndRuntimeEntry", "");
            var root = Directory.GetParent(Application.dataPath)?.FullName ?? string.Empty;
            var contract = Path.Combine(root, "Packages", "com.gamecreate.benchmark.noir-roombreak.contracts", "Runtime", "INoirRoombreakProbe.cs");
            var catalogJson = Path.Combine(root, "ASSET_CATALOG.json");
            var catalogMd = Path.Combine(root, "ASSET_CATALOG.md");
            var publicBaseline = File.Exists(contract) && File.Exists(catalogJson) && File.Exists(catalogMd);
            Record("D1_IMPORT_COMPILE", 3f, publicBaseline, "candidate imports and compiles, and retains the published observation contract plus asset catalog", $"unityPhaseReached=true;contract={File.Exists(contract)};catalogJson={File.Exists(catalogJson)};catalogMd={File.Exists(catalogMd)}", "COMMON-BASELINE");
            Record("D1_FINAL_SCENE", 2.5f, false, "saved final Scene loads as the configured entry", "not observed", "COMMON-BASELINE", "FLOW-01", "CAMERA-01");
            Record("D1_RUNTIME_PROBE", 2.5f, false, "at least one active implementation of the published read-only Probe contract", "not observed", "COMMON-BASELINE");
            Record("D1_REAL_FRAME", 2f, false, "real frames contain rendered 2D world or usable UI content", "not observed", "COMMON-BASELINE", "FLOW-01", "AV-01");

            var buildPath = SceneUtility.GetScenePathByBuildIndex(0);
            var loadable = buildPath == ScenePath && Application.CanStreamedLevelBeLoaded(ScenePath);
            AsyncOperation load = null;
            if (loadable)
            {
                try { load = SceneManager.LoadSceneAsync(ScenePath, LoadSceneMode.Single); }
                catch { loadable = false; }
            }
            loadable &= load != null;
            if (loadable)
            {
                var until = Time.realtimeSinceStartup + 15f;
                while (!load.isDone && Time.realtimeSinceStartup < until) yield return null;
                loadable = load.isDone && SceneManager.GetActiveScene().path == ScenePath;
            }
            Record("D1_FINAL_SCENE", 2.5f, loadable, "saved final Scene loads as the configured entry", $"build0={buildPath};active={SceneManager.GetActiveScene().path}", "COMMON-BASELINE", "FLOW-01", "CAMERA-01");

            if (loadable)
            {
                var before = Time.frameCount;
                yield return null;
                yield return null;
                Canvas.ForceUpdateCanvases();
                var probes = Object.FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Where(x => x is INoirRoombreakProbe).ToArray();
                Record("D1_RUNTIME_PROBE", 2.5f, probes.Length >= 1, "at least one active implementation of the published read-only Probe contract", $"probes={probes.Length};types={string.Join(",", probes.Select(x => x.GetType().FullName))}", "COMMON-BASELINE");
                var cameras = Object.FindObjectsByType<Camera>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.isActiveAndEnabled);
                var sprites = Object.FindObjectsByType<SpriteRenderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.enabled && x.sprite != null);
                var renderers = Object.FindObjectsByType<Renderer>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.enabled);
                var canvases = Object.FindObjectsByType<Canvas>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.isActiveAndEnabled);
                var colliders = Object.FindObjectsByType<Collider2D>(FindObjectsInactive.Exclude, FindObjectsSortMode.None).Count(x => x && x.enabled && !x.isTrigger);
                var graphics = Object.FindObjectsByType<Graphic>(FindObjectsInactive.Exclude, FindObjectsSortMode.None)
                    .Where(x => x && x.isActiveAndEnabled && x.gameObject.activeInHierarchy && x.canvas != null && x.canvas.isActiveAndEnabled &&
                                x.color.a > .05f && x.canvasRenderer.GetAlpha() > .05f && x.rectTransform.rect.width > .5f && x.rectTransform.rect.height > .5f)
                    .ToArray();
                var graphicCanvases = graphics.Select(x => x.canvas).Distinct().Count();
                var worldFrame = (sprites > 0 || renderers > 0) && colliders > 0;
                var uiFrame = graphics.Length > 0 && graphicCanvases > 0;
                var real = Time.frameCount > before && (uiFrame || (worldFrame && cameras > 0));
                Record("D1_REAL_FRAME", 2f, real, "real frames contain rendered 2D world or usable UI content", $"frame={before}->{Time.frameCount};cameras={cameras};sprites={sprites};renderers={renderers};canvases={canvases};uiGraphics={graphics.Length};uiGraphicCanvases={graphicCanvases};solid2D={colliders};worldFrame={worldFrame};uiFrame={uiFrame}", "COMMON-BASELINE", "FLOW-01", "AV-01");
                EvidenceStore.EndTrajectory("STATIC01", "completed", probes.Length > 0 ? probes[0].GetInstanceID().ToString() : "");
            }
            else EvidenceStore.EndTrajectory("STATIC01", "candidate-entry-missing", "");
            LogAssert.ignoreFailingMessages = false;
        }

        static void Record(string id, float weight, bool passed, string expected, string observed, params string[] requirements)
            => EvidenceStore.Check(id, "D1", weight, passed, expected, observed, requirements);
    }
}
