using System;
using UnityEngine;

namespace OmniGame.Benchmark.ArrowEscape.V2
{
    public enum ArrowEscapeBudgetMode
    {
        Moves = 0,
        Hearts = 1
    }

    public enum ArrowEscapeGamePhase
    {
        NotReady = 0,
        Playing = 1,
        Won = 2,
        Lost = 3
    }

    public enum ArrowEscapeArrowState
    {
        Available = 0,
        Locked = 1,
        Moving = 2,
        Exited = 3
    }

    public enum ArrowEscapeSelectionOutcome
    {
        Ignored = 0,
        StartedExit = 1,
        Blocked = 2,
        Locked = 3
    }

    public enum ArrowEscapeInputSource
    {
        None = 0,
        PlayerPointer = 1
    }

    public enum ArrowEscapeVisibleTargetKind
    {
        Arrow = 0,
        Hint = 1,
        Restart = 2,
        NextLevel = 3
    }

    [Serializable]
    public struct ArrowEscapeGridCell : IEquatable<ArrowEscapeGridCell>
    {
        public int X;
        public int Y;

        public ArrowEscapeGridCell(int x, int y)
        {
            X = x;
            Y = y;
        }

        public bool Equals(ArrowEscapeGridCell other) => X == other.X && Y == other.Y;
        public override bool Equals(object obj) => obj is ArrowEscapeGridCell other && Equals(other);
        public override int GetHashCode() => (X * 397) ^ Y;
        public override string ToString() => $"({X},{Y})";
    }

    [Serializable]
    public sealed class ArrowEscapeArrowSpec
    {
        public string Id;
        public ArrowEscapeGridCell[] Path = Array.Empty<ArrowEscapeGridCell>();
        public Color Color = Color.white;
        public string[] PrerequisiteIds = Array.Empty<string>();

        public ArrowEscapeArrowSpec()
        {
        }

        public ArrowEscapeArrowSpec(
            string id,
            ArrowEscapeGridCell[] path,
            string[] prerequisiteIds = null,
            Color? color = null)
        {
            Id = id;
            Path = path ?? Array.Empty<ArrowEscapeGridCell>();
            PrerequisiteIds = prerequisiteIds ?? Array.Empty<string>();
            Color = color ?? Color.white;
        }
    }

    [Serializable]
    public sealed class ArrowEscapeLevelSpec
    {
        public string LevelId;
        public int Width;
        public int Height;
        public ArrowEscapeBudgetMode BudgetMode;
        public int InitialBudget;
        public ArrowEscapeArrowSpec[] Arrows = Array.Empty<ArrowEscapeArrowSpec>();

        public ArrowEscapeLevelSpec()
        {
        }

        public ArrowEscapeLevelSpec(
            string levelId,
            int width,
            int height,
            ArrowEscapeBudgetMode budgetMode,
            int initialBudget,
            ArrowEscapeArrowSpec[] arrows)
        {
            LevelId = levelId;
            Width = width;
            Height = height;
            BudgetMode = budgetMode;
            InitialBudget = initialBudget;
            Arrows = arrows ?? Array.Empty<ArrowEscapeArrowSpec>();
        }
    }

    [Serializable]
    public sealed class ArrowEscapeLoadResult
    {
        public bool Accepted;
        public string[] ValidationErrors = Array.Empty<string>();

        public static ArrowEscapeLoadResult Success() => new ArrowEscapeLoadResult { Accepted = true };

        public static ArrowEscapeLoadResult Rejected(params string[] errors) =>
            new ArrowEscapeLoadResult
            {
                Accepted = false,
                ValidationErrors = errors ?? Array.Empty<string>()
            };
    }

    [Serializable]
    public sealed class ArrowEscapeSelectionResult
    {
        public string ArrowId;
        public ArrowEscapeSelectionOutcome Outcome;
        public int BudgetBefore;
        public int BudgetAfter;
    }

    [Serializable]
    public sealed class ArrowEscapeArrowSnapshot
    {
        public string Id;
        public ArrowEscapeArrowState State;
        public bool HasKeyBadge;
        public bool HasLockBadge;
        public ArrowEscapeGridCell[] OccupiedCells = Array.Empty<ArrowEscapeGridCell>();
    }

    /// <summary>
    /// Read-only semantic locator for one player-visible input target.
    /// ScreenRect uses Unity screen coordinates (origin at bottom-left) in the
    /// current 1280 x 720 game view. It locates normal input; it is not an
    /// action callback and does not report a gameplay verdict. A read-only
    /// consumer must match it to independently discoverable visible GameObject
    /// geometry; the Rect or VisualState alone is never evidence.
    /// Interactable means that a complete normal player click is currently a
    /// valid attempt/action on that target. Therefore a blocked or dependency-
    /// locked arrow is still Interactable during Playing (the attempt must reach
    /// the game and produce the required cost/feedback); a Moving/Exited arrow or
    /// an arrow after Won/Lost is not. This flag is read-only metadata and never
    /// authorizes action invocation by a read-only consumer.
    /// </summary>
    [Serializable]
    public sealed class ArrowEscapeVisibleTargetSnapshot
    {
        public string Id;
        public ArrowEscapeVisibleTargetKind Kind;
        public Rect ScreenRect;
        public bool Visible;
        public bool Interactable;
        public string VisualState;
    }

    [Serializable]
    public sealed class ArrowEscapeGameSnapshot
    {
        public string LevelId;
        public ArrowEscapeGamePhase Phase;
        public ArrowEscapeBudgetMode BudgetMode;
        public int InitialBudget;
        public int RemainingBudget;
        public string LastSelectedArrowId;
        public ArrowEscapeSelectionOutcome LastSelectionOutcome;
        public ArrowEscapeInputSource LastInputSource;
        public string LastHintArrowId;
        public bool CompletedUiVisible;
        public bool FailedUiVisible;
        public int StateRevision;
        public ArrowEscapeArrowSnapshot[] Arrows = Array.Empty<ArrowEscapeArrowSnapshot>();
        public ArrowEscapeVisibleTargetSnapshot[] VisibleTargets =
            Array.Empty<ArrowEscapeVisibleTargetSnapshot>();

        public ArrowEscapeArrowSnapshot FindArrow(string id)
        {
            if (Arrows == null)
            {
                return null;
            }

            foreach (ArrowEscapeArrowSnapshot arrow in Arrows)
            {
                if (arrow != null && string.Equals(arrow.Id, id, StringComparison.Ordinal))
                {
                    return arrow;
                }
            }

            return null;
        }
    }
}
