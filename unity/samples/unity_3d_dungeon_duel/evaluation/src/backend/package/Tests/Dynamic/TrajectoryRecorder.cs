using System;
using System.Collections.Generic;
using System.Linq;

namespace OmniGame.Benchmark.DungeonDuel.Trajectory
{
    internal sealed class TrajectoryRecorder
    {
        readonly TrajectoryDefinition definition;
        readonly TrajectoryRunEvidence evidence;
        readonly Dictionary<string, TrajectoryStepEvidence> steps;
        readonly HashSet<string> recordedChecks = new HashSet<string>(StringComparer.Ordinal);

        public TrajectoryRecorder(string trajectoryId)
        {
            definition = TrajectoryDefinitionLoader.Load(trajectoryId, out string sha256);
            evidence = new TrajectoryRunEvidence
            {
                trajectory_id = trajectoryId,
                title = definition.title,
                definition_sha256 = sha256,
                started_utc = DateTime.UtcNow.ToString("O")
            };
            steps = new Dictionary<string, TrajectoryStepEvidence>(StringComparer.Ordinal);

            foreach (TrajectoryDefinitionStep item in definition.steps)
            {
                var step = new TrajectoryStepEvidence
                {
                    step_id = item.step_id,
                    operation = item.operation,
                    target = item.target
                };
                steps.Add(item.step_id, step);
                evidence.steps.Add(step);
            }
        }

        public TrajectoryStepEvidence Step(string id)
        {
            if (!steps.TryGetValue(id, out TrajectoryStepEvidence step))
            {
                throw new InvalidOperationException(
                    $"Trajectory {definition.id} does not declare step {id}.");
            }

            if (step.frame_start == 0)
            {
                step.frame_start = UnityEngine.Time.frameCount;
            }
            return step;
        }

        public void Pass(string stepId, string checkId, string expected, string observed)
        {
            Add(stepId, new TrajectoryCheckEvidence
            {
                check_id = checkId,
                expected = expected,
                observed = observed,
                status = "pass"
            });
        }

        public void Fail(string stepId, string checkId, string expected, string observed, string message)
        {
            Add(stepId, new TrajectoryCheckEvidence
            {
                check_id = checkId,
                expected = expected,
                observed = observed,
                status = "fail",
                message = message
            });
        }

        public void Block(string stepId, string checkId, string blockedBy, string message = null)
        {
            Add(stepId, new TrajectoryCheckEvidence
            {
                check_id = checkId,
                status = "blocked",
                blocked_by = blockedBy,
                message = message ?? "Check could not run because an earlier prerequisite failed."
            });
        }

        public bool HasFailure => evidence.steps.SelectMany(step => step.checks)
            .Any(check => check.status == "fail");

        /// <summary>
        /// Presentation/audio failures are scored in D5 and must remain visible in
        /// the sealed evidence, but they must not prevent later native gameplay
        /// trajectories from running. A stale HUD must not turn a valid movement,
        /// combat, gate, or Restart observation into a blocked-tail artifact.
        /// </summary>
        public bool HasBlockingFailure => evidence.steps
            .SelectMany(step => step.checks)
            .Any(check => check.status == "fail" &&
                          !IsNonBlockingPresentationCheck(check.check_id));

        static bool IsNonBlockingPresentationCheck(string checkId)
        {
            if (string.IsNullOrWhiteSpace(checkId)) return false;
            return checkId.Contains(".hud_semantics", StringComparison.Ordinal) ||
                   checkId.Contains(".feedback_surface", StringComparison.Ordinal) ||
                   checkId.Contains(".audio.", StringComparison.Ordinal) ||
                   checkId.EndsWith(".boss_presented", StringComparison.Ordinal) ||
                   checkId.StartsWith("navigation.camera_", StringComparison.Ordinal) ||
                   checkId.Equals("navigation.camera.tracked_distance",
                       StringComparison.Ordinal);
        }

        public string Snapshot(object value) =>
            value == null ? "null" : UnityEngine.JsonUtility.ToJson(value);

        public bool Complete()
        {
            string blockedBy = evidence.steps.SelectMany(step => step.checks)
                .FirstOrDefault(check => check.status == "fail")?.check_id ?? "not_executed";

            foreach (TrajectoryDefinitionStep item in definition.steps)
            {
                foreach (string checkId in item.check_ids ?? Array.Empty<string>())
                {
                    if (!recordedChecks.Contains(checkId))
                    {
                        Block(item.step_id, checkId, blockedBy);
                    }
                }
            }

            foreach (TrajectoryStepEvidence step in evidence.steps)
            {
                // Preserve the frame at which this step's last check was actually
                // recorded.  Only synthesized/not-executed steps reach completion
                // without an end frame; stamping every step with the trajectory's
                // final frame makes earlier input callbacks and assertions appear to
                // belong to a much wider evidence window than they did.
                if (step.frame_end == 0)
                {
                    step.frame_end = UnityEngine.Time.frameCount;
                }
                step.status = step.checks.Any(check => check.status == "fail")
                    ? "fail"
                    : step.checks.Any(check => check.status == "blocked")
                        ? "blocked"
                        : "pass";
                step.message = step.checks.FirstOrDefault(check => check.status == "fail")?.message;
            }

            TrajectoryCheckEvidence[] checks = evidence.steps.SelectMany(step => step.checks).ToArray();
            evidence.checks_passed = checks.Count(check => check.status == "pass");
            evidence.checks_failed = checks.Count(check => check.status == "fail");
            evidence.checks_blocked = checks.Count(check => check.status == "blocked");
            evidence.passed = evidence.checks_failed == 0 && evidence.checks_blocked == 0;
            evidence.failure = checks.FirstOrDefault(check => check.status == "fail")?.message;
            TrajectoryEvidenceWriter.Write(evidence);
            return evidence.passed;
        }

        void Add(string stepId, TrajectoryCheckEvidence check)
        {
            if (!definition.AllCheckIds().Contains(check.check_id, StringComparer.Ordinal))
            {
                throw new InvalidOperationException(
                    $"Trajectory {definition.id} does not declare check {check.check_id}.");
            }
            if (!recordedChecks.Add(check.check_id))
            {
                throw new InvalidOperationException(
                    $"Trajectory {definition.id} recorded duplicate check {check.check_id}.");
            }

            TrajectoryStepEvidence step = Step(stepId);
            step.checks.Add(check);
            step.frame_end = UnityEngine.Time.frameCount;
        }
    }
}
