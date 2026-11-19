using System;
using System.Collections.Generic;
using System.Linq;
using OmniGame.Benchmark.ArrowEscape.V2;

namespace OmniGame.Benchmark.ArrowEscape.Trajectory
{
    internal static class TrajectoryFixtures
    {
        public static ArrowEscapeLevelSpec Resolve(string id)
        {
            switch (id)
            {
                case "clear_moves_1": return Clear(ArrowEscapeBudgetMode.Moves, 1, id);
                case "clear_moves_3": return Clear(ArrowEscapeBudgetMode.Moves, 3, id);
                case "clear_hearts_3": return Clear(ArrowEscapeBudgetMode.Hearts, 3, id);
                case "blocked_moves_1": return Blocked(ArrowEscapeBudgetMode.Moves, 1, id);
                case "blocked_moves_4": return Blocked(ArrowEscapeBudgetMode.Moves, 4, id);
                case "blocked_hearts_1": return Blocked(ArrowEscapeBudgetMode.Hearts, 1, id);
                case "chain_hearts_6": return Chain(ArrowEscapeBudgetMode.Hearts, 6, id);
                case "chain_moves_5": return Chain(ArrowEscapeBudgetMode.Moves, 5, id);
                case "and_left_first": return And(false, id);
                case "and_right_first": return And(true, id);
                case "hint_composition": return Hint(id);
                case "motion_right": return Motion(id, 5, 2, 1, 0, 3);
                case "motion_left": return Motion(id, 0, 3, -1, 0, 4);
                case "motion_up": return Motion(id, 3, 5, 0, 1, 2);
                case "motion_down": return Motion(id, 2, 0, 0, -1, 4);
                default: throw new ArgumentOutOfRangeException(nameof(id), id, "Unknown fixture.");
            }
        }

        internal static string[] LegalHintArrowIds(
            ArrowEscapeLevelSpec level,
            ArrowEscapeGameSnapshot snapshot)
        {
            if (level == null || snapshot == null ||
                snapshot.Phase != ArrowEscapeGamePhase.Playing ||
                level.Arrows == null || snapshot.Arrows == null)
            {
                return Array.Empty<string>();
            }

            var specs = level.Arrows
                .Where(spec => spec != null && !string.IsNullOrEmpty(spec.Id))
                .ToDictionary(spec => spec.Id, StringComparer.Ordinal);
            var result = new List<string>();
            foreach (ArrowEscapeArrowSnapshot candidate in snapshot.Arrows)
            {
                if (candidate == null || candidate.State != ArrowEscapeArrowState.Available ||
                    candidate.OccupiedCells == null || candidate.OccupiedCells.Length < 2 ||
                    !specs.ContainsKey(candidate.Id))
                {
                    continue;
                }

                ArrowEscapeGridCell head = candidate.OccupiedCells[0];
                ArrowEscapeGridCell neck = candidate.OccupiedCells[1];
                int dx = head.X - neck.X;
                int dy = head.Y - neck.Y;
                if (Math.Abs(dx) + Math.Abs(dy) != 1)
                {
                    continue;
                }

                bool blocked = false;
                for (int x = head.X + dx, y = head.Y + dy;
                     x >= 0 && x < level.Width && y >= 0 && y < level.Height;
                     x += dx, y += dy)
                {
                    foreach (ArrowEscapeArrowSnapshot other in snapshot.Arrows)
                    {
                        if (other == null || other.State == ArrowEscapeArrowState.Exited ||
                            string.Equals(other.Id, candidate.Id, StringComparison.Ordinal) ||
                            other.OccupiedCells == null)
                        {
                            continue;
                        }

                        if (other.OccupiedCells.Any(cell => cell.X == x && cell.Y == y))
                        {
                            blocked = true;
                            break;
                        }
                    }
                    if (blocked) break;
                }

                if (!blocked) result.Add(candidate.Id);
            }

            return result.OrderBy(id => id, StringComparer.Ordinal).ToArray();
        }

        internal static IEnumerable<KeyValuePair<string, ArrowEscapeLevelSpec>>
            InvalidValidationCases()
        {
            yield return new KeyValuePair<string, ArrowEscapeLevelSpec>(
                "empty_level_id",
                Level(string.Empty, ArrowEscapeBudgetMode.Moves, 3,
                    Arrow("valid_a", Cells((1, 1), (0, 1)))));
            yield return new KeyValuePair<string, ArrowEscapeLevelSpec>(
                "empty_arrows",
                Level("empty_arrows", ArrowEscapeBudgetMode.Moves, 3));
            yield return new KeyValuePair<string, ArrowEscapeLevelSpec>(
                "null_arrow",
                Level("null_arrow", ArrowEscapeBudgetMode.Moves, 3,
                    (ArrowEscapeArrowSpec)null));
            yield return new KeyValuePair<string, ArrowEscapeLevelSpec>(
                "dependency_cycle",
                Level("dependency_cycle", ArrowEscapeBudgetMode.Moves, 3,
                    Arrow("cycle_a", Cells((1, 0), (0, 0)), "cycle_b"),
                    Arrow("cycle_b", Cells((1, 2), (0, 2)), "cycle_a")));
        }

        private static ArrowEscapeLevelSpec Clear(
            ArrowEscapeBudgetMode mode, int budget, string id) =>
            Level(id, mode, budget, Arrow("clear_a", Cells((1, 1), (0, 1))));

        private static ArrowEscapeLevelSpec Blocked(
            ArrowEscapeBudgetMode mode, int budget, string id) =>
            Level(id, mode, budget,
                Arrow("blocked_a", Cells((1, 1), (0, 1))),
                Arrow("wall_b", Cells((2, 1), (2, 2))));

        private static ArrowEscapeLevelSpec Chain(
            ArrowEscapeBudgetMode mode, int budget, string id) =>
            Level(id, mode, budget,
                Arrow("key_a", Cells((1, 0), (0, 0))),
                Arrow("lock_b", Cells((1, 2), (0, 2)), "key_a"),
                Arrow("lock_c", Cells((1, 4), (0, 4)), "lock_b"));

        private static ArrowEscapeLevelSpec And(bool reverse, string id)
        {
            string[] prerequisites = reverse
                ? new[] { "key_right", "key_left" }
                : new[] { "key_left", "key_right" };
            return Level(id, ArrowEscapeBudgetMode.Hearts, 6,
                Arrow("key_left", Cells((1, 0), (0, 0))),
                Arrow("key_right", Cells((1, 2), (0, 2))),
                Arrow("multi_lock", Cells((1, 4), (0, 4)), prerequisites));
        }

        private static ArrowEscapeLevelSpec Hint(string id) =>
            Level(id, ArrowEscapeBudgetMode.Hearts, 4,
                Arrow("only_clear", Cells((1, 0), (0, 0))),
                Arrow("blocked", Cells((1, 2), (0, 2))),
                Arrow("blocker", Cells((2, 2), (2, 3))),
                Arrow("locked", Cells((1, 4), (0, 4)), "only_clear"));

        private static ArrowEscapeLevelSpec Motion(
            string id, int headX, int headY, int dx, int dy, int length)
        {
            var cells = new ArrowEscapeGridCell[length];
            for (int index = 0; index < length; index++)
            {
                cells[index] = new ArrowEscapeGridCell(headX - dx * index, headY - dy * index);
            }
            return Level(id, ArrowEscapeBudgetMode.Hearts, 5, Arrow("motion_a", cells));
        }

        private static ArrowEscapeLevelSpec Level(
            string id, ArrowEscapeBudgetMode mode, int budget, params ArrowEscapeArrowSpec[] arrows) =>
            new ArrowEscapeLevelSpec(id, 6, 6, mode, budget, arrows);

        private static ArrowEscapeArrowSpec Arrow(
            string id, ArrowEscapeGridCell[] path, params string[] prerequisites) =>
            new ArrowEscapeArrowSpec(id, path, prerequisites ?? Array.Empty<string>());

        private static ArrowEscapeGridCell[] Cells(params (int x, int y)[] values)
        {
            var result = new List<ArrowEscapeGridCell>(values.Length);
            foreach ((int x, int y) in values)
            {
                result.Add(new ArrowEscapeGridCell(x, y));
            }
            return result.ToArray();
        }
    }
}
