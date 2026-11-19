using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEngine;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    [Serializable]
    internal sealed class TrajectoryCheckEvidence
    {
        public string check_id;
        public string expected;
        public string observed;
        public string status = "pending";
        public string blocked_by;
        public string message;
    }

    [Serializable]
    internal sealed class PointerRouteEventEvidence
    {
        public string phase;
        public int frame;
        public int pointer_id;
        public string button;
        public float screen_x;
        public float screen_y;
    }

    [Serializable]
    internal sealed class TrajectoryStepEvidence
    {
        public string step_id;
        public string operation;
        public string target;
        public string status = "pending";
        public string message;
        public int frame_start;
        public int frame_end;
        public double elapsed_ms;
        public float screen_x;
        public float screen_y;
        public int screen_width;
        public int screen_height;
        public int input_device_id;
        public int display_index;
        public string input_route;
        public string top_hit;
        public string ui_resolution;
        public string pre_snapshot;
        public string post_snapshot;
        public List<PointerRouteEventEvidence> pointer_events =
            new List<PointerRouteEventEvidence>();
        public List<TrajectoryCheckEvidence> checks = new List<TrajectoryCheckEvidence>();
    }

    [Serializable]
    internal sealed class TrajectoryRunEvidence
    {
        public int schema_version = 2;
        public string evaluator_protocol = "trajectory-v8-unity-cli-readonly-probe";
        public string trajectory_id;
        public string title;
        public string input_backend =
            "Unity.InputSystem.MouseState -> InputSystemUIInputModule -> EventSystem";
        public string started_utc;
        public string finished_utc;
        public bool passed;
        public string failure;
        public string definition_sha256;
        public int checks_passed;
        public int checks_failed;
        public int checks_blocked;
        public List<TrajectoryStepEvidence> steps = new List<TrajectoryStepEvidence>();
    }

    internal static class TrajectoryEvidenceWriter
    {
        public static string ResolveOutputDirectory()
        {
            string output = FindCommandLineValue("-omnigameTrajectoryOutput");
            if (string.IsNullOrWhiteSpace(output))
            {
                output = Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".",
                    "BenchmarkResults", "trajectory-evidence");
            }
            return output;
        }

        public static string Write(TrajectoryRunEvidence evidence)
        {
            evidence.finished_utc = DateTime.UtcNow.ToString("O");
            string output = ResolveOutputDirectory();

            Directory.CreateDirectory(output);
            string path = Path.Combine(output, evidence.trajectory_id + ".json");
            File.WriteAllText(path, JsonUtility.ToJson(evidence, true));
            return path;
        }

        private static string FindCommandLineValue(string key)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int index = 0; index < args.Length - 1; index++)
            {
                if (string.Equals(args[index], key, StringComparison.OrdinalIgnoreCase))
                {
                    return args[index + 1].Trim('"');
                }
            }
            return null;
        }
    }

    internal static class EvaluatorDisplayResolution
    {
        public const int RequiredWidth = 1280;
        public const int RequiredHeight = 720;

        public static string ConfigurationRoute { get; private set; } = "not_attempted";
        private static object configuredGroup;
        private static int configuredCustomTotalIndex = -1;
        private static readonly List<UnityEngine.Object> configuredViews =
            new List<UnityEngine.Object>();
        private static readonly List<int> originalSelectedIndices = new List<int>();
        public static bool IsCurrentExact => IsExact(Screen.width, Screen.height);
        public static string Diagnostic =>
            $"observed {Screen.width}x{Screen.height}; route={ConfigurationRoute}";

        public static bool IsExact(int width, int height) =>
            width == RequiredWidth && height == RequiredHeight;

        public static IEnumerator Ensure1280x720()
        {
            if (!IsCurrentExact)
            {
                ConfigureEditorGameView();
            }
            Screen.SetResolution(RequiredWidth, RequiredHeight, false);

            float deadline = Time.realtimeSinceStartup + 5f;
            int stableFrames = 0;
            while (Time.realtimeSinceStartup < deadline && stableFrames < 2)
            {
                yield return null;
                stableFrames = IsCurrentExact ? stableFrames + 1 : 0;
            }
        }

        public static void Restore()
        {
            try
            {
                Type gameViewType = Type.GetType("UnityEditor.GameView, UnityEditor");
                PropertyInfo selectedSizeIndex = gameViewType?.GetProperty(
                    "selectedSizeIndex",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                for (int index = 0; index < configuredViews.Count; index++)
                {
                    if (configuredViews[index] != null &&
                        index < originalSelectedIndices.Count)
                    {
                        selectedSizeIndex?.SetValue(configuredViews[index],
                            originalSelectedIndices[index]);
                    }
                }

                if (configuredGroup != null && configuredCustomTotalIndex >= 0)
                {
                    Type groupType = configuredGroup.GetType();
                    MethodInfo removeCustom = groupType.GetMethod("RemoveCustomSize",
                        BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                    removeCustom?.Invoke(configuredGroup,
                        new object[] { configuredCustomTotalIndex });
                }
            }
            catch (Exception exception)
            {
                ConfigurationRoute += ";restore_error=" +
                                      exception.GetType().Name + ":" + exception.Message;
            }
            finally
            {
                configuredViews.Clear();
                originalSelectedIndices.Clear();
                configuredGroup = null;
                configuredCustomTotalIndex = -1;
            }
        }

        private static void ConfigureEditorGameView()
        {
            try
            {
                Type gameViewType = Type.GetType("UnityEditor.GameView, UnityEditor");
                Type playModeViewType = Type.GetType(
                    "UnityEditor.PlayModeView, UnityEditor");
                if (gameViewType == null || playModeViewType == null)
                {
                    ConfigurationRoute = "unavailable:UnityEditor.GameView";
                    return;
                }

                var views = new List<UnityEngine.Object>();
                MethodInfo getMain = playModeViewType.GetMethod(
                    "GetMainPlayModeView",
                    BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
                if (getMain?.Invoke(null, null) is UnityEngine.Object main)
                {
                    views.Add(main);
                }
                foreach (UnityEngine.Object view in Resources.FindObjectsOfTypeAll(
                             gameViewType))
                {
                    if (view != null && !views.Contains(view)) views.Add(view);
                }
                if (views.Count == 0)
                {
                    Type editorWindowType = Type.GetType(
                        "UnityEditor.EditorWindow, UnityEditor");
                    MethodInfo getWindow = editorWindowType?.GetMethod("GetWindow",
                        BindingFlags.Static | BindingFlags.Public, null,
                        new[] { typeof(Type) }, null);
                    if (getWindow?.Invoke(null, new object[] { gameViewType })
                        is UnityEngine.Object created)
                    {
                        views.Add(created);
                    }
                }

                PropertyInfo selectedSizeIndex = gameViewType.GetProperty(
                    "selectedSizeIndex",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                Type gameViewSizesType = Type.GetType(
                    "UnityEditor.GameViewSizes, UnityEditor");
                Type gameViewSizeType = Type.GetType(
                    "UnityEditor.GameViewSize, UnityEditor");
                Type gameViewSizeTypeEnum = Type.GetType(
                    "UnityEditor.GameViewSizeType, UnityEditor");
                Type groupTypeEnum = Type.GetType(
                    "UnityEditor.GameViewSizeGroupType, UnityEditor");
                PropertyInfo instance = gameViewSizesType?.GetProperty("instance",
                    BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic |
                    BindingFlags.FlattenHierarchy);
                object sizes = instance?.GetValue(null);
                MethodInfo getGroup = gameViewSizesType?.GetMethod("GetGroup",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                object standalone = groupTypeEnum == null
                    ? null
                    : Enum.Parse(groupTypeEnum, "Standalone");
                object group = sizes == null || standalone == null
                    ? null
                    : getGroup?.Invoke(sizes, new[] { standalone });
                Type groupType = group?.GetType();
                MethodInfo addCustom = groupType?.GetMethod("AddCustomSize",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                MethodInfo indexOf = groupType?.GetMethod("IndexOf",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                MethodInfo getBuiltinCount = groupType?.GetMethod("GetBuiltinCount",
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                ConstructorInfo constructor = gameViewSizeType?.GetConstructor(
                    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                    null, new[]
                    {
                        gameViewSizeTypeEnum, typeof(int), typeof(int), typeof(string)
                    }, null);
                if (selectedSizeIndex == null || group == null || addCustom == null ||
                    indexOf == null || getBuiltinCount == null || constructor == null ||
                    views.Count == 0)
                {
                    ConfigurationRoute = "unavailable:GameViewSizes.in_memory_api";
                    return;
                }

                object fixedResolution = Enum.Parse(gameViewSizeTypeEnum,
                    "FixedResolution");
                object customSize = constructor.Invoke(new[]
                {
                    fixedResolution, RequiredWidth, RequiredHeight,
                    "OmniGame Evaluator 1280x720 " + Guid.NewGuid().ToString("N")
                });
                addCustom.Invoke(group, new[] { customSize });
                int customIndex = (int)indexOf.Invoke(group, new[] { customSize });
                int totalIndex = (int)getBuiltinCount.Invoke(group, null) + customIndex;
                if (customIndex < 0)
                {
                    ConfigurationRoute = "error:in_memory_size_index_not_found";
                    return;
                }
                configuredGroup = group;
                configuredCustomTotalIndex = totalIndex;
                foreach (UnityEngine.Object view in views)
                {
                    configuredViews.Add(view);
                    originalSelectedIndices.Add((int)selectedSizeIndex.GetValue(view));
                    selectedSizeIndex.SetValue(view, totalIndex);
                }
                ConfigurationRoute = "GameViewSizes.AddCustomSize+selectedSizeIndex";
            }
            catch (Exception exception)
            {
                ConfigurationRoute = "error:" + exception.GetType().Name + ":" +
                                     exception.Message;
            }
        }
    }
}

