using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace OmniGame.Benchmark.SignCircuit.Contract
{
    /// <summary>
    /// A public, implementation-neutral observation snapshot. It contains no
    /// gameplay verdict and exposes no method that changes gameplay.
    /// </summary>
    [Serializable]
    public struct SignCircuitSnapshot
    {
        public const int CurrentSchemaVersion = 2;

        public int schemaVersion;
        public string scene;
        public string phase;
        public int progress;
        public float remainingSeconds;
        public int targetSignMask;
        public int acceptedCheckpointMask;
        public bool gateOpen;
        public bool interactionAvailable;
        public bool hudVisible;
        public bool pauseVisible;
        public bool successVisible;
        public bool failureVisible;
        public bool hasBestTime;
        public float bestTimeSeconds;
        public Vector2 playerPosition;
        public string statusText;
        public string feedback;
    }

    [Serializable]
    public struct SignCircuitActionTarget
    {
        public string id;
        public Rect screenRect;
        public bool visible;
        public bool interactable;
        public string label;
    }

    /// <summary>
    /// Public semantic locator for a player-visible, read-only UI surface.
    /// The rectangle only identifies where the real UI should be observed; it
    /// is never accepted as proof of text, state, visibility, or correctness.
    /// </summary>
    [Serializable]
    public struct SignCircuitObservationTarget
    {
        public string id;
        public Rect screenRect;
        public bool visible;
    }

    /// <summary>
    /// Candidate gameplay publishes observations; public read-only consumers only read
    /// them. Publication must mirror the real visible state and must never be
    /// used to trigger an action or declare a gameplay result.
    /// </summary>
    public static class SignCircuitProbePublisher
    {
        public static void Publish(
            SignCircuitSnapshot snapshot,
            IReadOnlyList<SignCircuitActionTarget> actionTargets = null,
            IReadOnlyList<SignCircuitObservationTarget> observationTargets = null)
        {
            SignCircuitProbeStorage.Publish(snapshot, actionTargets, observationTargets);
        }
    }

    /// <summary>Read-only side used by public smoke checks and other read-only consumers.</summary>
    public static class SignCircuitProbeReader
    {
        public static bool TryRead(out SignCircuitSnapshot snapshot) =>
            SignCircuitProbeStorage.TryRead(out snapshot);

        public static bool TryGetActionTarget(
            string id,
            out SignCircuitActionTarget target) =>
            SignCircuitProbeStorage.TryGetActionTarget(id, out target);

        public static bool TryGetObservationTarget(
            string id,
            out SignCircuitObservationTarget target) =>
            SignCircuitProbeStorage.TryGetObservationTarget(id, out target);

        public static int LastPublishedFrame => SignCircuitProbeStorage.LastPublishedFrame;
    }

    internal static class SignCircuitProbeStorage
    {
        static SignCircuitSnapshot current;
        static SignCircuitActionTarget[] targets = Array.Empty<SignCircuitActionTarget>();
        static SignCircuitObservationTarget[] observationTargets =
            Array.Empty<SignCircuitObservationTarget>();
        static int frame = -100000;
        static int sceneHandle = int.MinValue;

        public static int LastPublishedFrame => frame;

        public static void Publish(
            SignCircuitSnapshot snapshot,
            IReadOnlyList<SignCircuitActionTarget> actionTargets,
            IReadOnlyList<SignCircuitObservationTarget> publishedObservationTargets)
        {
            snapshot.schemaVersion = SignCircuitSnapshot.CurrentSchemaVersion;
            current = snapshot;
            frame = Time.frameCount;
            sceneHandle = SceneManager.GetActiveScene().handle;

            if (actionTargets == null || actionTargets.Count == 0)
            {
                targets = Array.Empty<SignCircuitActionTarget>();
            }
            else
            {
                targets = new SignCircuitActionTarget[actionTargets.Count];
                for (int index = 0; index < actionTargets.Count; index++)
                {
                    targets[index] = actionTargets[index];
                }
            }

            if (publishedObservationTargets == null ||
                publishedObservationTargets.Count == 0)
            {
                observationTargets = Array.Empty<SignCircuitObservationTarget>();
            }
            else
            {
                observationTargets =
                    new SignCircuitObservationTarget[publishedObservationTargets.Count];
                for (int index = 0; index < publishedObservationTargets.Count; index++)
                {
                    observationTargets[index] = publishedObservationTargets[index];
                }
            }
        }

        public static bool TryRead(out SignCircuitSnapshot snapshot)
        {
            snapshot = current;
            if (frame < 0 || Time.frameCount - frame > 5 ||
                sceneHandle != SceneManager.GetActiveScene().handle ||
                current.schemaVersion != SignCircuitSnapshot.CurrentSchemaVersion ||
                string.IsNullOrWhiteSpace(current.scene) ||
                string.IsNullOrWhiteSpace(current.phase))
            {
                return false;
            }

            return current.progress >= 0 && current.progress <= 3 &&
                   IsFinite(current.remainingSeconds) &&
                   IsFinite(current.playerPosition.x) &&
                   IsFinite(current.playerPosition.y);
        }

        public static bool TryGetActionTarget(
            string id,
            out SignCircuitActionTarget target)
        {
            target = default;
            if (!TryRead(out _) || string.IsNullOrWhiteSpace(id)) return false;
            bool found = false;
            foreach (SignCircuitActionTarget candidate in targets)
            {
                if (string.Equals(candidate.id, id, StringComparison.OrdinalIgnoreCase))
                {
                    // A semantic id is a contract key, not a best-effort label.
                    // Reject ambiguity instead of silently trusting the first
                    // candidate-published rectangle.
                    if (found)
                    {
                        target = default;
                        return false;
                    }
                    target = candidate;
                    found = true;
                }
            }
            return found && IsFinite(target.screenRect);
        }

        public static bool TryGetObservationTarget(
            string id,
            out SignCircuitObservationTarget target)
        {
            target = default;
            if (!TryRead(out _) || string.IsNullOrWhiteSpace(id)) return false;
            bool found = false;
            foreach (SignCircuitObservationTarget candidate in observationTargets)
            {
                if (string.Equals(candidate.id, id, StringComparison.OrdinalIgnoreCase))
                {
                    if (found)
                    {
                        target = default;
                        return false;
                    }
                    target = candidate;
                    found = true;
                }
            }
            return found && IsFinite(target.screenRect);
        }

        static bool IsFinite(Rect rect) =>
            IsFinite(rect.x) && IsFinite(rect.y) &&
            IsFinite(rect.width) && IsFinite(rect.height) &&
            rect.width >= 0f && rect.height >= 0f;

        static bool IsFinite(float value) =>
            !float.IsNaN(value) && !float.IsInfinity(value);
    }
}
