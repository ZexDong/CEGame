using System;
using System.Collections.Generic;
using UnityEngine;

namespace GameCreate.Evaluation
{
    // This lease prevents the registered adapter from writing after setup.
    // It is not an OS sandbox: adapter source review, hash binding and mutation
    // calibration are still required before it can produce official scores.
    public sealed class PreparedStateSession : IDisposable
    {
        public enum Stage { Preparing, Ready, Acting, Closed }
        public Stage CurrentStage { get; private set; } = Stage.Preparing;
        public string StateId { get; }
        public string AttemptId { get; } = Guid.NewGuid().ToString("N");
        public int SetupWriteCount { get; private set; }
        public int RejectedLateWrites { get; private set; }
        public int ActionStartFrame { get; private set; } = -1;
        public IReadOnlyList<string> Preconditions => preconditions.AsReadOnly();
        readonly List<string> preconditions = new List<string>();
        readonly float deadline;

        public PreparedStateSession(string stateId, float timeoutSeconds)
        {
            if (string.IsNullOrWhiteSpace(stateId) || float.IsNaN(timeoutSeconds) ||
                float.IsInfinity(timeoutSeconds) || timeoutSeconds <= 0)
                throw new ArgumentException("State preparation needs an id and a finite positive budget.");
            StateId = stateId;
            deadline = Time.realtimeSinceStartup + timeoutSeconds;
        }

        public void ApplySetup(Action candidateOwnedInitialization)
        {
            if (CurrentStage != Stage.Preparing)
            {
                RejectedLateWrites++;
                throw new InvalidOperationException("State preparation is sealed; cannot modify the tested action.");
            }
            if (Time.realtimeSinceStartup > deadline)
                throw new TimeoutException("SETUP_FAILED: state preparation budget exhausted.");
            if (candidateOwnedInitialization == null) throw new ArgumentNullException(nameof(candidateOwnedInitialization));
            try
            {
                candidateOwnedInitialization();
                SetupWriteCount++;
                if (Time.realtimeSinceStartup > deadline)
                    throw new TimeoutException("SETUP_FAILED: initialization exceeded its budget.");
            }
            catch
            {
                CurrentStage = Stage.Closed;
                throw;
            }
        }

        public void VerifyPrecondition(string evidenceId, Func<bool> independentObservation)
        {
            if (CurrentStage != Stage.Preparing || Time.realtimeSinceStartup > deadline)
                throw new InvalidOperationException("State cannot be verified outside its preparation window.");
            if (string.IsNullOrWhiteSpace(evidenceId) || independentObservation == null)
                throw new ArgumentException("Precondition needs independent evidence.");
            try
            {
                if (!independentObservation())
                    throw new InvalidOperationException("SETUP_FAILED: " + evidenceId);
            }
            catch
            {
                CurrentStage = Stage.Closed;
                throw;
            }
            if (!preconditions.Contains(evidenceId)) preconditions.Add(evidenceId);
        }

        public void SealPreparation()
        {
            if (CurrentStage != Stage.Preparing || preconditions.Count == 0 || Time.realtimeSinceStartup > deadline)
                throw new InvalidOperationException("Cannot seal an unverified state.");
            CurrentStage = Stage.Ready;
        }

        public void BeginScoredActions()
        {
            if (CurrentStage != Stage.Ready) throw new InvalidOperationException("Actions require a verified state.");
            CurrentStage = Stage.Acting;
            ActionStartFrame = Time.frameCount;
        }

        public void Dispose() { CurrentStage = Stage.Closed; }
    }
}
