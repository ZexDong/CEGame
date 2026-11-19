using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
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
    internal sealed class InputActionEventEvidence
    {
        public string phase;
        public string action;
        public string control_path;
        public int device_id;
        public int frame;
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
        public string top_hit;
        public int screen_width;
        public int screen_height;
        public int mouse_device_id;
        public int keyboard_device_id;
        public List<InputActionEventEvidence> input_action_events =
            new List<InputActionEventEvidence>();
        public string pre_snapshot;
        public string post_snapshot;
        public List<TrajectoryCheckEvidence> checks = new List<TrajectoryCheckEvidence>();
    }

    [Serializable]
    internal sealed class TrajectoryRunEvidence
    {
        public int schema_version = 1;
        public string evaluator_protocol = "game-independent-d1-d6-v2";
        public string trajectory_id;
        public string title;
        public string input_backend =
            "Unity InputSystem current virtual Mouse/Keyboard -> cross-frame device state -> independently observed gameplay/UI consequences; InputAction/Physics/NavMesh diagnostic only";
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
        public static string Write(TrajectoryRunEvidence evidence)
        {
            evidence.finished_utc = DateTime.UtcNow.ToString("O");
            string output = FindCommandLineValue("-omnigameTrajectoryOutput");
            if (string.IsNullOrWhiteSpace(output))
            {
                output = FindCommandLineValue("-omnigameDungeonDuelTrajectoryOutput");
            }
            if (string.IsNullOrWhiteSpace(output))
            {
                output = Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".",
                    "BenchmarkResults", "dungeon-duel-trajectory-evidence");
            }

            Directory.CreateDirectory(output);
            string path = Path.Combine(output, evidence.trajectory_id + ".json");
            File.WriteAllText(path, JsonUtility.ToJson(evidence, true));
            return path;
        }

        static string FindCommandLineValue(string key)
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
}
