using System;

namespace OmniGame.Benchmark.SignCircuit.Evaluator
{
    /// <summary>
    /// One implementation-independent observation used to decide whether an E press
    /// caused a stable nearby interaction response. This model deliberately contains
    /// no Unity, candidate component, object-name, collider, or probe-state dependency.
    /// </summary>
    public sealed class InteractionResponseSample
    {
        public string NearbyVisual;
        public string Status;
        public int Progress;
        public float Timer;
        public float Realtime;
        public float PositionX;
        public float PositionY;
    }

    /// <summary>
    /// Pure classification result. Reason is a stable machine-readable token suitable
    /// for evaluator evidence and failure diagnostics.
    /// </summary>
    public sealed class InteractionResponseDecision
    {
        public bool Accepted;
        public string Reason;
        public float MaximumPenaltyDiscontinuity;
        public bool StatusChanged;
        public bool NearbyVisualChanged;
    }

    /// <summary>
    /// Separates an input-caused response from ambient scene/camera settling:
    /// stable no-input control, E input, then a persistent post-input observation.
    /// </summary>
    public static class InteractionResponseClassifier
    {
        public const float MaximumStablePositionDelta = 0.03f;

        public static InteractionResponseDecision Classify(
            InteractionResponseSample controlStart,
            InteractionResponseSample preInput,
            InteractionResponseSample postInput,
            InteractionResponseSample confirm,
            float maxNaturalJitter = 0.35f,
            float rejectedPenaltyThreshold = 2.2f)
        {
            var decision = new InteractionResponseDecision
            {
                Accepted = false,
                Reason = "missing_sample",
                MaximumPenaltyDiscontinuity = float.PositiveInfinity,
                StatusChanged = false,
                NearbyVisualChanged = false
            };

            if (controlStart == null || preInput == null ||
                postInput == null || confirm == null)
            {
                return decision;
            }

            if (!IsFinite(maxNaturalJitter) || maxNaturalJitter < 0f ||
                !IsFinite(rejectedPenaltyThreshold) || rejectedPenaltyThreshold <= 0f ||
                maxNaturalJitter >= rejectedPenaltyThreshold)
            {
                decision.Reason = "invalid_configuration";
                return decision;
            }

            if (!IsValidSample(controlStart) || !IsValidSample(preInput) ||
                !IsValidSample(postInput) || !IsValidSample(confirm))
            {
                decision.Reason = "invalid_sample";
                return decision;
            }

            decision.StatusChanged = !Same(preInput.Status, postInput.Status);
            decision.NearbyVisualChanged =
                !Same(preInput.NearbyVisual, postInput.NearbyVisual);

            float controlDiscontinuity = TimerDiscontinuity(controlStart, preInput);
            float inputDiscontinuity = TimerDiscontinuity(preInput, postInput);
            float confirmDiscontinuity = TimerDiscontinuity(postInput, confirm);
            float rawMaximumDiscontinuity = Math.Max(
                controlDiscontinuity,
                Math.Max(inputDiscontinuity, confirmDiscontinuity));
            decision.MaximumPenaltyDiscontinuity =
                rawMaximumDiscontinuity <= maxNaturalJitter
                    ? 0f
                    : rawMaximumDiscontinuity;

            int expectedProgress = controlStart.Progress;
            if (preInput.Progress != expectedProgress ||
                postInput.Progress != expectedProgress ||
                confirm.Progress != expectedProgress)
            {
                decision.Reason = "progress_changed";
                return decision;
            }

            if (rawMaximumDiscontinuity >= rejectedPenaltyThreshold)
            {
                decision.Reason = "rejected_penalty_detected";
                return decision;
            }

            if (!IsStableControl(controlStart, preInput, rejectedPenaltyThreshold))
            {
                decision.Reason = "unstable_control";
                return decision;
            }

            if (!Same(postInput.Status, confirm.Status) ||
                !Same(postInput.NearbyVisual, confirm.NearbyVisual) ||
                PositionDistance(postInput, confirm) > MaximumStablePositionDelta)
            {
                decision.Reason = "transient_post_input";
                return decision;
            }

            if (!decision.StatusChanged && !decision.NearbyVisualChanged)
            {
                decision.Reason = "no_causal_response";
                return decision;
            }

            decision.Accepted = true;
            decision.Reason = decision.StatusChanged
                ? decision.NearbyVisualChanged
                    ? "accepted_status_and_nearby_visual_change"
                    : "accepted_status_change"
                : "accepted_nearby_visual_change";
            return decision;
        }

        public static bool IsStableControl(
            InteractionResponseSample controlStart,
            InteractionResponseSample preInput,
            float rejectedPenaltyThreshold = 2.2f)
        {
            if (controlStart == null || preInput == null ||
                !IsFinite(rejectedPenaltyThreshold) || rejectedPenaltyThreshold <= 0f ||
                !IsValidSample(controlStart) || !IsValidSample(preInput))
            {
                return false;
            }

            return controlStart.Progress == preInput.Progress &&
                   Same(controlStart.Status, preInput.Status) &&
                   Same(controlStart.NearbyVisual, preInput.NearbyVisual) &&
                   PositionDistance(controlStart, preInput) <=
                       MaximumStablePositionDelta &&
                   TimerDiscontinuity(controlStart, preInput) <
                       rejectedPenaltyThreshold;
        }

        public static float TimerDiscontinuity(
            InteractionResponseSample before,
            InteractionResponseSample after)
        {
            if (before == null || after == null ||
                !IsValidSample(before) || !IsValidSample(after) ||
                after.Realtime < before.Realtime)
            {
                return float.PositiveInfinity;
            }

            float elapsed = after.Realtime - before.Realtime;
            return before.Timer - after.Timer - elapsed;
        }

        static bool IsValidSample(InteractionResponseSample sample) =>
            sample != null &&
            IsFinite(sample.Timer) &&
            IsFinite(sample.Realtime) &&
            IsFinite(sample.PositionX) &&
            IsFinite(sample.PositionY);

        static float PositionDistance(
            InteractionResponseSample first,
            InteractionResponseSample second)
        {
            double x = (double)first.PositionX - second.PositionX;
            double y = (double)first.PositionY - second.PositionY;
            return (float)Math.Sqrt(x * x + y * y);
        }

        static bool Same(string first, string second) =>
            string.Equals(first ?? string.Empty, second ?? string.Empty,
                StringComparison.Ordinal);

        static bool IsFinite(float value) =>
            !float.IsNaN(value) && !float.IsInfinity(value);
    }
}
