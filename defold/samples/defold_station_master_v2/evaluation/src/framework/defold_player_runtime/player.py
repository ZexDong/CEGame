#!/usr/bin/env python3
"""Defold Dashboard reader and the first discrete-key movement template.

This code knows only its documented public `player`/`movement_edge` cell contract and naming-table
control declaration. It never reads candidate-internal object names or a hard-coded route. The
macOS normal-input helper is a separate bottom layer.
"""

from __future__ import annotations

import argparse
import collections
import json
import math
import subprocess
import time
from pathlib import Path
from typing import Any, Callable


DIRECTION_DELTA = {
    "up_open": (0, 1, "up"),
    "down_open": (0, -1, "down"),
    "left_open": (-1, 0, "left"),
    "right_open": (1, 0, "right"),
}


class NormalInputError(RuntimeError):
    """The evaluator could not use its normal OS keyboard/mouse adapter."""


class DashboardConditionTimeout(RuntimeError):
    """A valid Dashboard never reached the requested condition before its deadline."""


class DashboardReader:
    """Incrementally read complete snapshots without rescanning a growing JSONL file."""

    def __init__(self, path: Path):
        self.path = path
        self.offset = 0
        self.buffer = ""
        self.latest: dict[str, Any] | None = None
        self.mtime_ns: int | None = None

    def poll_updates(self) -> list[dict[str, Any]]:
        """Return each newly completed snapshot once, in file order."""
        try:
            stat = self.path.stat()
        except FileNotFoundError:
            return []
        replaced_at_same_size = (
            stat.st_size == self.offset
            and self.mtime_ns is not None
            and stat.st_mtime_ns != self.mtime_ns
        )
        if stat.st_size < self.offset or replaced_at_same_size:
            self.offset = 0
            self.buffer = ""
            self.latest = None

        with self.path.open("r", encoding="utf-8") as source:
            source.seek(self.offset)
            chunk = source.read()
            self.offset = source.tell()
        try:
            self.mtime_ns = self.path.stat().st_mtime_ns
        except FileNotFoundError:
            self.mtime_ns = stat.st_mtime_ns
        if not chunk:
            return []

        complete = (self.buffer + chunk).split("\n")
        self.buffer = complete.pop()
        updates: list[dict[str, Any]] = []
        for line in complete:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict) and {
                "revision", "phase", "slots", "entities", "targets"
            } <= value.keys():
                self.latest = value
                updates.append(value)
        return updates

    def poll(self) -> dict[str, Any] | None:
        self.poll_updates()
        return self.latest

    def wait_until(
        self,
        predicate: Callable[[dict[str, Any]], bool],
        timeout_s: float,
    ) -> dict[str, Any]:
        deadline = time.monotonic() + timeout_s
        last = self.poll()
        while time.monotonic() < deadline:
            last = self.poll()
            if last is not None and predicate(last):
                return last
            time.sleep(0.03)
        raise DashboardConditionTimeout(
            f"dashboard condition was not reached within {timeout_s:.1f}s; last={last}"
        )


def latest_snapshot(path: Path) -> dict[str, Any]:
    """Return the last complete JSON line; tolerate a writer appending the next line."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError as exc:
        raise RuntimeError(f"dashboard file does not exist: {path}") from exc
    for line in reversed(lines):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and {"revision", "phase", "slots", "entities", "targets"} <= value.keys():
            return value
    raise RuntimeError(f"dashboard file contains no complete snapshot: {path}")


def entities(snapshot: dict[str, Any], kind: str, state: str | None = None) -> list[dict[str, Any]]:
    return [
        entity
        for entity in snapshot["entities"]
        if entity.get("kind") == kind and (state is None or entity.get("state") == state)
    ]


def one_entity(snapshot: dict[str, Any], kind: str, state: str | None = None) -> dict[str, Any]:
    matches = entities(snapshot, kind, state)
    if len(matches) != 1:
        raise RuntimeError(f"selector kind={kind!r}, state={state!r} matched {len(matches)} entities")
    return matches[0]


def graph(snapshot: dict[str, Any]) -> dict[tuple[int, int], list[tuple[tuple[int, int], str]]]:
    result: dict[tuple[int, int], list[tuple[tuple[int, int], str]]] = collections.defaultdict(list)
    for edge in entities(snapshot, "movement_edge"):
        direction = DIRECTION_DELTA.get(edge["state"])
        if direction is None:
            continue
        x, y = edge["cell"]
        dx, dy, logical_key = direction
        result[(x, y)].append(((x + dx, y + dy), logical_key))
    return result


def shortest_key_path(snapshot: dict[str, Any], target_cell: tuple[int, int]) -> list[str]:
    start = tuple(one_entity(snapshot, "player")["cell"])
    if start == target_cell:
        return []
    route_graph = graph(snapshot)
    queue = collections.deque([start])
    previous: dict[tuple[int, int], tuple[tuple[int, int], str] | None] = {start: None}
    while queue:
        cell = queue.popleft()
        for neighbor, key in route_graph.get(cell, []):
            if neighbor in previous:
                continue
            previous[neighbor] = (cell, key)
            if neighbor == target_cell:
                queue.clear()
                break
            queue.append(neighbor)
    if target_cell not in previous:
        return []
    keys: list[str] = []
    cursor = target_cell
    while cursor != start:
        parent, key = previous[cursor]  # type: ignore[misc]
        keys.append(key)
        cursor = parent
    keys.reverse()
    return keys


def shortest_key_path_toward(
    snapshot: dict[str, Any], target_cell: tuple[int, int]
) -> list[str]:
    """Reach the target, or the closest currently reachable graph frontier.

    Some games expose temporary closed edges. A player must still walk to that
    gate before waiting for it to open; requiring a complete path to the final
    goal would deadlock at the start.
    """
    start = tuple(one_entity(snapshot, "player")["cell"])
    route_graph = graph(snapshot)
    queue = collections.deque([start])
    previous: dict[tuple[int, int], tuple[tuple[int, int], str] | None] = {start: None}
    while queue:
        cell = queue.popleft()
        for neighbor, key in route_graph.get(cell, []):
            if neighbor in previous:
                continue
            previous[neighbor] = (cell, key)
            queue.append(neighbor)
    destination = target_cell if target_cell in previous else min(
        previous,
        key=lambda cell: (
            abs(cell[0] - target_cell[0]) + abs(cell[1] - target_cell[1]),
            -cell[1],
            cell[0],
        ),
    )
    keys: list[str] = []
    cursor = destination
    while cursor != start:
        parent, key = previous[cursor]  # type: ignore[misc]
        keys.append(key)
        cursor = parent
    keys.reverse()
    return keys


def send_key(driver: Path, pid: int, physical_key: str) -> None:
    completed = subprocess.run(
        [str(driver), str(pid), "key", physical_key, "press"],
        text=True,
        capture_output=True,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
        raise NormalInputError(f"normal keyboard driver failed: {detail}")


def hold_key(driver: Path, pid: int, physical_key: str, seconds: float) -> None:
    completed = subprocess.run(
        [str(driver), str(pid), "key", physical_key, "hold", str(seconds)],
        text=True,
        capture_output=True,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
        raise NormalInputError(f"normal keyboard driver failed: {detail}")


def hold_two_keys(
    driver: Path,
    pid: int,
    first_key: str,
    second_key: str,
    seconds: float,
) -> None:
    completed = subprocess.run(
        [str(driver), str(pid), "dual_hold", first_key, second_key, str(seconds)],
        text=True,
        capture_output=True,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
        raise NormalInputError(f"normal keyboard driver failed: {detail}")


def driver_supported_keys(driver: Path) -> set[str]:
    completed = subprocess.run(
        [str(driver), "--keys"],
        text=True,
        capture_output=True,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
        raise NormalInputError(f"could not inspect normal keyboard driver keys: {detail}")
    result = {line.strip() for line in completed.stdout.splitlines() if line.strip()}
    if not result:
        raise NormalInputError("normal keyboard driver reported no supported keys")
    return result


def choose_physical_key(declared: Any, supported: set[str]) -> str:
    options = declared if isinstance(declared, list) else [declared]
    if not options or any(not isinstance(option, str) for option in options):
        raise NormalInputError(f"invalid naming-table key declaration: {declared!r}")
    for option in options:
        if option in supported:
            return option
    raise NormalInputError(
        f"none of the declared physical keys {options!r} are supported by the normal-input driver"
    )


def wait_for_revision(path: Path, old_revision: int, timeout_s: float) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        snapshot = latest_snapshot(path)
        if snapshot["revision"] > old_revision:
            return snapshot
        time.sleep(0.03)
    raise RuntimeError(f"dashboard revision did not advance within {timeout_s:.1f}s")


def wait_for_reader_revision(
    reader: DashboardReader,
    old_revision: int,
    timeout_s: float,
) -> dict[str, Any]:
    return reader.wait_until(lambda snapshot: snapshot["revision"] > old_revision, timeout_s)


def drive_discrete_edges(
    dashboard_path: Path,
    naming_path: Path,
    driver: Path,
    pid: int,
    target_kind: str,
    target_state: str | None,
    timeout_s: float,
    max_steps: int | None = None,
) -> None:
    naming = json.loads(naming_path.read_text(encoding="utf-8"))
    physical_keys = naming["controls"]["keys"]
    supported_keys = driver_supported_keys(driver)
    reader = DashboardReader(dashboard_path)
    first = reader.wait_until(lambda _: True, 2.0)
    first_player = one_entity(first, "player")
    first_targets = entities(first, target_kind, target_state)
    if not first_targets:
        raise RuntimeError(
            f"no cell entity matches kind={target_kind!r}, state={target_state!r}"
        )
    target = min(
        first_targets,
        key=lambda item: (
            abs(_cell(item)[0] - _cell(first_player)[0])
            + abs(_cell(item)[1] - _cell(first_player)[1]),
            str(item.get("id", "")),
        ),
    )
    target_id = str(target["id"])
    deadline = time.monotonic() + timeout_s
    steps_sent = 0

    while time.monotonic() < deadline:
        snapshot = reader.poll() or first
        if snapshot["phase"] in {"won", "lost"}:
            return
        if snapshot["phase"] not in {"playing", "paused"}:
            raise RuntimeError(f"cannot move while phase is {snapshot['phase']!r}")
        current_targets = [
            item for item in entities(snapshot, target_kind, target_state)
            if str(item.get("id")) == target_id
        ]
        if not current_targets:
            return
        target_cell = _cell(current_targets[0])
        player_cell = tuple(one_entity(snapshot, "player")["cell"])
        if player_cell == target_cell:
            return
        path = shortest_key_path_toward(snapshot, target_cell)
        if not path:
            # A temporary GDD-defined gate may remove the only edge. Observe until it opens.
            time.sleep(0.05)
            continue
        logical_key = path[0]
        before_cell = player_cell
        send_key(
            driver,
            pid,
            choose_physical_key(physical_keys[logical_key], supported_keys),
        )
        try:
            updated = reader.wait_until(
                lambda candidate: candidate["phase"] in {"won", "lost"}
                or tuple(one_entity(candidate, "player")["cell"]) != before_cell
                or not any(
                    str(item.get("id")) == target_id
                    for item in entities(candidate, target_kind, target_state)
                ),
                min(1.0, max(0.03, deadline - time.monotonic())),
            )
        except DashboardConditionTimeout:
            continue
        if updated["phase"] in {"won", "lost"}:
            return
        if not any(
            str(item.get("id")) == target_id
            for item in entities(updated, target_kind, target_state)
        ):
            return
        if tuple(one_entity(updated, "player")["cell"]) == before_cell:
            continue
        steps_sent += 1
        if max_steps is not None and steps_sent >= max_steps:
            return
    raise RuntimeError(f"timed out moving toward {target_kind!r}")


GRID_DIRECTIONS = (
    (0, 1, "up"),
    (0, -1, "down"),
    (-1, 0, "left"),
    (1, 0, "right"),
)


def _cell(entity: dict[str, Any]) -> tuple[int, int]:
    value = entity.get("cell")
    if not isinstance(value, list) or len(value) != 2:
        raise RuntimeError(f"entity {entity.get('id')!r} has no valid cell")
    return int(value[0]), int(value[1])


def _grid_bounds(naming: dict[str, Any]) -> tuple[int, int, int, int]:
    width = naming.get("level_width_cells")
    height = naming.get("level_height_cells")
    if (
        isinstance(width, bool)
        or not isinstance(width, int)
        or width < 1
        or isinstance(height, bool)
        or not isinstance(height, int)
        or height < 1
    ):
        raise RuntimeError(
            "grid navigation requires positive public level_width_cells and "
            "level_height_cells"
        )
    return 0, width - 1, 0, height - 1


def _grid_path_to_target(
    snapshot: dict[str, Any],
    naming: dict[str, Any],
    target_kind: str,
    target_state: str | None,
    action_key: str | None = None,
) -> tuple[list[str], dict[str, Any]] | None:
    player_cell = _cell(one_entity(snapshot, "player"))
    navigation = naming.get("controls", {}).get("navigation", {})
    blocking_kinds = set(navigation.get("blocking_kinds", []))
    hazard_kinds = set(navigation.get("hazard_kinds", []))
    approach_kinds = set(navigation.get("approach_kinds", []))
    blocked = {
        _cell(item)
        for item in snapshot.get("entities", [])
        if isinstance(item, dict)
        and item.get("kind") in blocking_kinds | hazard_kinds
        and isinstance(item.get("cell"), list)
    }
    blocked.discard(player_cell)
    min_x, max_x, min_y, max_y = _grid_bounds(naming)
    candidates = [
        item
        for item in entities(snapshot, target_kind, target_state)
        if item.get("visible") is not False and isinstance(item.get("cell"), list)
    ]
    if not candidates:
        return None

    goals: dict[tuple[int, int], dict[str, Any]] = {}
    for target in candidates:
        target_cell = _cell(target)
        if target_kind in approach_kinds or target_cell in blocked:
            for dx, dy, _ in GRID_DIRECTIONS:
                goal = target_cell[0] + dx, target_cell[1] + dy
                if min_x <= goal[0] <= max_x and min_y <= goal[1] <= max_y and goal not in blocked:
                    goals.setdefault(goal, target)
        else:
            goals.setdefault(target_cell, target)
    if not goals:
        return None
    if player_cell in goals and action_key != navigation.get("action_key"):
        return [], goals[player_cell]

    queue = collections.deque([player_cell])
    previous: dict[tuple[int, int], tuple[tuple[int, int], str] | None] = {player_cell: None}
    distance: dict[tuple[int, int], int] = {player_cell: 0}
    while queue:
        cell = queue.popleft()
        for dx, dy, logical_key in GRID_DIRECTIONS:
            neighbor = cell[0] + dx, cell[1] + dy
            if (
                neighbor in previous
                or neighbor in blocked
                or not (min_x <= neighbor[0] <= max_x and min_y <= neighbor[1] <= max_y)
            ):
                continue
            previous[neighbor] = (cell, logical_key)
            distance[neighbor] = distance[cell] + 1
            queue.append(neighbor)
    reachable_goals = [goal for goal in goals if goal in previous]
    if not reachable_goals:
        return None

    if action_key == navigation.get("action_key"):
        action_kinds = {target_kind} | {
            str(kind) for kind in navigation.get("action_fallback_kinds", [])
        }
        affected_cells = [
            _cell(item)
            for item in snapshot.get("entities", [])
            if isinstance(item, dict)
            and item.get("kind") in action_kinds
            and item.get("visible") is not False
            and isinstance(item.get("cell"), list)
        ]
        effect_distance = max(
            1,
            int(float(navigation.get("post_action_safe_distance_cells", 2))),
        )

        def action_utility(goal: tuple[int, int]) -> int:
            return sum(
                1
                for affected in affected_cells
                if abs(goal[0] - affected[0]) + abs(goal[1] - affected[1]) < effect_distance
            )

        reached = min(
            reachable_goals,
            key=lambda goal: (-action_utility(goal), distance[goal]),
        )
    else:
        reached = min(reachable_goals, key=distance.__getitem__)

    keys: list[str] = []
    cursor = reached
    while cursor != player_cell:
        parent, logical_key = previous[cursor]  # type: ignore[misc]
        keys.append(logical_key)
        cursor = parent
    keys.reverse()
    return keys, goals[reached]


def drive_discrete_grid(
    dashboard_path: Path,
    naming: dict[str, Any],
    driver: Path,
    pid: int,
    target_kind: str,
    target_state: str | None,
    timeout_s: float,
    action_key: str | None = None,
) -> None:
    declared_keys = naming["controls"].get("keys", {})
    supported_keys = driver_supported_keys(driver)
    reader = DashboardReader(dashboard_path)
    first = reader.wait_until(lambda _: True, 2.0)
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        snapshot = reader.poll() or first
        if snapshot["phase"] in {"won", "lost", "paused"}:
            return
        if snapshot["phase"] != "playing":
            raise RuntimeError(f"cannot move while phase is {snapshot['phase']!r}")
        route = _grid_path_to_target(
            snapshot, naming, target_kind, target_state, action_key
        )
        navigation = naming.get("controls", {}).get("navigation", {})
        if route is None and action_key == navigation.get("action_key"):
            for fallback_kind in navigation.get("action_fallback_kinds", []):
                route = _grid_path_to_target(
                    snapshot, naming, str(fallback_kind), None, action_key
                )
                if route is not None:
                    break
        if route is None:
            # The selected target may have been consumed or destroyed by the preceding action.
            return
        keys, _ = route
        if not keys:
            return
        logical_key = keys[0]
        try:
            physical_key = choose_physical_key(declared_keys[logical_key], supported_keys)
        except KeyError as exc:
            raise RuntimeError(f"naming tables are missing grid key {logical_key!r}") from exc
        before_cell = _cell(one_entity(snapshot, "player"))
        send_key(driver, pid, physical_key)
        step_deadline = min(deadline, time.monotonic() + 0.8)
        while time.monotonic() < step_deadline:
            updated = reader.poll()
            if updated is not None:
                if updated["phase"] in {"won", "lost", "paused"}:
                    return
                if _cell(one_entity(updated, "player")) != before_cell:
                    break
            time.sleep(0.03)
    raise RuntimeError(f"timed out moving toward {target_kind!r}")


def _grid_safe_route(
    snapshot: dict[str, Any],
    naming: dict[str, Any],
    avoid_kinds: set[str],
    minimum_distance: float,
) -> list[str] | None:
    player_cell = _cell(one_entity(snapshot, "player"))
    navigation = naming.get("controls", {}).get("navigation", {})
    blocked_kinds = set(navigation.get("blocking_kinds", [])) | set(
        navigation.get("hazard_kinds", [])
    )
    blocked = {
        _cell(item)
        for item in snapshot.get("entities", [])
        if isinstance(item, dict)
        and item.get("kind") in blocked_kinds
        and isinstance(item.get("cell"), list)
    }
    blocked.discard(player_cell)
    avoid_cells = [
        _cell(item)
        for item in snapshot.get("entities", [])
        if isinstance(item, dict)
        and item.get("kind") in avoid_kinds
        and isinstance(item.get("cell"), list)
    ]
    if not avoid_cells:
        return []
    min_x, max_x, min_y, max_y = _grid_bounds(naming)

    def safe(cell: tuple[int, int]) -> bool:
        return cell not in blocked and all(
            abs(cell[0] - hazard[0]) + abs(cell[1] - hazard[1]) >= minimum_distance
            for hazard in avoid_cells
        )

    queue = collections.deque([player_cell])
    previous: dict[tuple[int, int], tuple[tuple[int, int], str] | None] = {player_cell: None}
    reached: tuple[int, int] | None = player_cell if safe(player_cell) else None
    while queue and reached is None:
        cell = queue.popleft()
        for dx, dy, logical_key in GRID_DIRECTIONS:
            neighbor = cell[0] + dx, cell[1] + dy
            if (
                neighbor in previous
                or neighbor in blocked
                or not (min_x <= neighbor[0] <= max_x and min_y <= neighbor[1] <= max_y)
            ):
                continue
            previous[neighbor] = (cell, logical_key)
            if safe(neighbor):
                reached = neighbor
                break
            queue.append(neighbor)
    if reached is None:
        return None
    keys: list[str] = []
    cursor = reached
    while cursor != player_cell:
        parent, logical_key = previous[cursor]  # type: ignore[misc]
        keys.append(logical_key)
        cursor = parent
    keys.reverse()
    return keys


def retreat_discrete_grid(
    dashboard_path: Path,
    naming: dict[str, Any],
    driver: Path,
    pid: int,
    timeout_s: float,
) -> None:
    navigation = naming.get("controls", {}).get("navigation", {})
    avoid_kinds = set(navigation.get("post_action_avoid_kinds", []))
    minimum_distance = float(navigation.get("post_action_safe_distance_cells", 2))
    if not avoid_kinds:
        return
    declared_keys = naming["controls"].get("keys", {})
    supported_keys = driver_supported_keys(driver)
    reader = DashboardReader(dashboard_path)
    first = reader.wait_until(lambda _: True, 2.0)
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        snapshot = reader.poll() or first
        if snapshot["phase"] in {"won", "lost"}:
            return
        route = _grid_safe_route(snapshot, naming, avoid_kinds, minimum_distance)
        if route == []:
            return
        if route is None:
            time.sleep(0.03)
            continue
        before_cell = _cell(one_entity(snapshot, "player"))
        physical = choose_physical_key(declared_keys[route[0]], supported_keys)
        send_key(driver, pid, physical)
        step_deadline = min(deadline, time.monotonic() + 0.7)
        while time.monotonic() < step_deadline:
            updated = reader.poll()
            if updated is not None and _cell(one_entity(updated, "player")) != before_cell:
                break
            time.sleep(0.03)
    raise RuntimeError("timed out retreating from public grid hazards")


def continuous_axes(movement_template: str) -> list[tuple[int, str, str]]:
    if movement_template == "continuous_2d_keyboard":
        return [(0, "right", "left"), (1, "up", "down")]
    if movement_template == "continuous_world_3d_keyboard_with_pointer_ui":
        # The public coordinate space declares +z as "back"; Down moves toward +z.
        return [(0, "right", "left"), (2, "down", "up")]
    raise RuntimeError(f"unsupported continuous movement template {movement_template!r}")


def drive_platformer(
    dashboard_path: Path,
    naming: dict[str, Any],
    driver: Path,
    pid: int,
    target_kind: str,
    target_state: str | None,
    timeout_s: float,
) -> None:
    declared_keys = naming["controls"].get("keys", {})
    supported_keys = driver_supported_keys(driver)
    reader = DashboardReader(dashboard_path)
    first = reader.wait_until(lambda _: True, 2.0)
    target = nearest_position_entity(first, target_kind, target_state, [(0, "right", "left"), (1, "jump", "jump")])
    if target is None:
        raise RuntimeError(
            f"no visible platformer target matches kind={target_kind!r}, state={target_state!r}"
        )
    target_id = str(target["id"])
    deadline = time.monotonic() + timeout_s
    previous_distance: float | None = None
    stalled_steps = 0
    while time.monotonic() < deadline:
        snapshot = reader.poll() or first
        if snapshot["phase"] in {"won", "lost"}:
            return
        if snapshot["phase"] != "playing":
            raise RuntimeError(f"cannot move while phase is {snapshot['phase']!r}")
        player = one_entity(snapshot, "player")
        target = nearest_position_entity(
            snapshot,
            target_kind,
            target_state,
            [(0, "right", "left"), (1, "jump", "jump")],
            entity_id=target_id,
        )
        if target is None:
            return
        distance = position_distance(player, target, [(0, "right", "left"), (1, "jump", "jump")])
        # Platformer pickups, pads, exits, and hazards are contact-driven.  A broad
        # rectangle-surface tolerance would stop at the edge and never exercise the rule.
        if distance <= 8.0:
            return
        delta_x = float(target["position"][0]) - float(player["position"][0])
        delta_y = float(target["position"][1]) - float(player["position"][1])
        horizontal = "right" if delta_x >= 0 else "left"
        on_ground = snapshot.get("slots", {}).get("player_on_ground") == 1
        hazards = entities(snapshot, "spike")
        directional_spike_gaps = [
            abs(float(item["position"][0]) - float(player["position"][0]))
            for item in hazards
            if isinstance(item.get("position"), list)
            and (float(item["position"][0]) - float(player["position"][0])) * delta_x >= 0
            and abs(float(item["position"][1]) - float(player["position"][1])) < 55
        ]
        # One normal-input hold advances the player by roughly one short platform
        # stride.  Look farther than that stride so the next sample cannot arrive
        # only after contact with a public spike.
        spike_ahead = any(gap < 90 for gap in directional_spike_gaps)
        spike_near_route = any(gap < 180 for gap in directional_spike_gaps)
        deliberate_hazard = target_kind in {"spike", "echo"}
        should_jump = not deliberate_hazard and (
            delta_y > 18
            or spike_ahead
            or (on_ground and stalled_steps >= 2 and delta_y >= -18)
            or (
                on_ground
                and delta_y >= -18
                and abs(delta_x) > 45
                and not spike_near_route
            )
        )
        # Keep long strides for traversal, but trim them near a pickup or ledge.
        # Otherwise a single key hold can overshoot a narrow public platform and
        # make the controller oscillate forever around an otherwise reachable target.
        hold_seconds = min(0.24, max(0.08, abs(delta_x) / 440.0))
        horizontal_key = choose_physical_key(declared_keys[horizontal], supported_keys)
        if should_jump:
            jump_key = choose_physical_key(declared_keys["jump"], supported_keys)
            hold_two_keys(driver, pid, horizontal_key, jump_key, hold_seconds)
        else:
            hold_key(driver, pid, horizontal_key, hold_seconds)
        time.sleep(0.03)
        updated = reader.poll()
        if updated is None or updated.get("phase") != "playing":
            continue
        updated_player = one_entity(updated, "player")
        updated_target = nearest_position_entity(
            updated,
            target_kind,
            target_state,
            [(0, "right", "left"), (1, "jump", "jump")],
            entity_id=target_id,
        )
        if updated_target is None:
            return
        new_distance = position_distance(
            updated_player, updated_target, [(0, "right", "left"), (1, "jump", "jump")]
        )
        if previous_distance is not None and new_distance >= previous_distance - 1.0:
            stalled_steps += 1
        else:
            stalled_steps = 0
        previous_distance = new_distance
    raise RuntimeError(f"timed out moving toward {target_kind!r}")


def position_distance(
    first: dict[str, Any],
    second: dict[str, Any],
    axes: list[tuple[int, str, str]],
) -> float:
    return math.sqrt(
        sum(
            (float(first["position"][index]) - float(second["position"][index])) ** 2
            for index, _, _ in axes
        )
    )


def nearest_position_entity(
    snapshot: dict[str, Any],
    kind: str,
    state: str | None,
    axes: list[tuple[int, str, str]],
    entity_id: str | None = None,
) -> dict[str, Any] | None:
    player = one_entity(snapshot, "player")
    matches = [
        item
        for item in entities(snapshot, kind, state)
        if item.get("visible") is not False
        and isinstance(item.get("position"), list)
        and (entity_id is None or item.get("id") == entity_id)
    ]
    if not matches:
        return None
    return min(matches, key=lambda item: position_distance(player, item, axes))


def arrival_tolerance(
    player: dict[str, Any],
    target: dict[str, Any],
    axes: list[tuple[int, str, str]],
    movement_template: str,
) -> float:
    baseline = 8.0 if movement_template == "continuous_2d_keyboard" else 0.35
    player_size = player.get("size")
    target_size = target.get("size")
    extents: list[float] = []
    if isinstance(player_size, list) and isinstance(target_size, list):
        for index, _, _ in axes:
            if index < len(player_size) and index < len(target_size):
                extents.append((float(player_size[index]) + float(target_size[index])) / 2)
    return max([baseline, *extents])


def toward_key(
    player: dict[str, Any],
    target: dict[str, Any],
    axes: list[tuple[int, str, str]],
) -> tuple[str, int]:
    candidates: list[tuple[float, str, int]] = []
    for index, positive, negative in axes:
        delta = float(target["position"][index]) - float(player["position"][index])
        candidates.append((abs(delta), positive if delta >= 0 else negative, index))
    _, key, index = max(candidates)
    return key, index


def perpendicular_detour_keys(
    primary_axis: int,
    axes: list[tuple[int, str, str]],
    player: dict[str, Any],
    target: dict[str, Any],
) -> list[str]:
    for index, positive, negative in axes:
        if index == primary_axis:
            continue
        delta = float(target["position"][index]) - float(player["position"][index])
        preferred = positive if delta >= 0 else negative
        other = negative if preferred == positive else positive
        return [preferred, other]
    return []


def continuous_aabb_key_route(
    snapshot: dict[str, Any],
    naming: dict[str, Any],
    target: dict[str, Any],
    axes: list[tuple[int, str, str]],
    grid_step: float,
    clearance: float,
) -> list[str] | None:
    """Plan a four-direction route from public 2D or 3D AABBs.

    The grid is rebuilt from the latest Dashboard snapshot.  It contains no
    game-specific coordinates: obstacle kinds come from naming tables and all
    positions and sizes come from the public read-only contract.
    """
    if len(axes) != 2:
        return None
    first_axis, first_positive, first_negative = axes[0]
    second_axis, second_positive, second_negative = axes[1]
    required_dimensions = max(first_axis, second_axis) + 1
    player = one_entity(snapshot, "player")
    player_position = player.get("position")
    target_position = target.get("position")
    if (
        not isinstance(player_position, list)
        or len(player_position) < required_dimensions
        or not isinstance(target_position, list)
        or len(target_position) < required_dimensions
    ):
        return None
    navigation = naming.get("controls", {}).get("navigation", {})
    blocking_kinds = set(navigation.get("blocking_kinds", []))
    hazard_kinds = set(navigation.get("hazard_kinds", []))
    obstacle_kinds = blocking_kinds | hazard_kinds
    if not obstacle_kinds:
        return None
    obstacles = [
        item
        for item in snapshot.get("entities", [])
        if isinstance(item, dict)
        and item.get("kind") in obstacle_kinds
        and item.get("visible") is not False
        and (item.get("kind") not in hazard_kinds or item.get("state") not in {"dormant", "stopped"})
        and isinstance(item.get("position"), list)
        and len(item["position"]) >= required_dimensions
        and isinstance(item.get("size"), list)
        and len(item["size"]) >= required_dimensions
    ]
    if not obstacles:
        return None

    start_first = float(player_position[first_axis])
    start_second = float(player_position[second_axis])
    goal_first = float(target_position[first_axis])
    goal_second = float(target_position[second_axis])
    player_size = player.get("size")
    player_half_first = (
        float(player_size[first_axis]) * 0.5
        if isinstance(player_size, list) and len(player_size) >= required_dimensions
        else 0.5
    )
    player_half_second = (
        float(player_size[second_axis]) * 0.5
        if isinstance(player_size, list) and len(player_size) >= required_dimensions
        else 0.5
    )

    obstacle_boxes: list[tuple[float, float, float, float]] = []
    first_values = [start_first, goal_first]
    second_values = [start_second, goal_second]
    approach_kinds = set(navigation.get("approach_kinds", []))
    approaching = target.get("kind") in approach_kinds
    for obstacle in obstacles:
        if obstacle.get("id") == target.get("id"):
            continue
        position = obstacle["position"]
        size = obstacle["size"]
        center_first = float(position[first_axis])
        center_second = float(position[second_axis])
        raw_half_first = float(size[first_axis]) * 0.5
        raw_half_second = float(size[second_axis]) * 0.5
        if (
            approaching
            and abs(goal_first - center_first) <= raw_half_first
            and abs(goal_second - center_second) <= raw_half_second
        ):
            # Interactive furniture is both a target and a physical blocker.
            # Its public *_nearby state terminates the approach before overlap.
            continue
        hazard_clearance = grid_step * 2 if obstacle.get("kind") in hazard_kinds else 0.0
        half_first = raw_half_first + player_half_first + clearance + hazard_clearance
        half_second = raw_half_second + player_half_second + clearance + hazard_clearance
        box = (
            center_first - half_first,
            center_first + half_first,
            center_second - half_second,
            center_second + half_second,
        )
        obstacle_boxes.append(box)
        first_values.extend(box[:2])
        second_values.extend(box[2:])

    padding = grid_step * 2
    min_cell_first = math.floor((min(first_values) - padding - start_first) / grid_step)
    max_cell_first = math.ceil((max(first_values) + padding - start_first) / grid_step)
    min_cell_second = math.floor((min(second_values) - padding - start_second) / grid_step)
    max_cell_second = math.ceil((max(second_values) + padding - start_second) / grid_step)

    def cell_for(first: float, second: float) -> tuple[int, int]:
        return round((first - start_first) / grid_step), round((second - start_second) / grid_step)

    def point_for(cell: tuple[int, int]) -> tuple[float, float]:
        return start_first + cell[0] * grid_step, start_second + cell[1] * grid_step

    def blocked(cell: tuple[int, int]) -> bool:
        first, second = point_for(cell)
        return any(
            low_first < first < high_first and low_second < second < high_second
            for low_first, high_first, low_second, high_second in obstacle_boxes
        )

    start = (0, 0)
    goal = cell_for(goal_first, goal_second)
    if start == goal:
        return []
    blocked_cells = {
        (first, second)
        for first in range(min_cell_first, max_cell_first + 1)
        for second in range(min_cell_second, max_cell_second + 1)
        if blocked((first, second))
    }
    blocked_cells.discard(start)
    if goal in blocked_cells:
        return None

    directions = (
        (1, 0, first_positive),
        (-1, 0, first_negative),
        (0, 1, second_positive),
        (0, -1, second_negative),
    )
    queue = collections.deque([start])
    previous: dict[tuple[int, int], tuple[tuple[int, int], str] | None] = {start: None}
    while queue and goal not in previous:
        cell = queue.popleft()
        ordered = sorted(
            directions,
            key=lambda item: abs(cell[0] + item[0] - goal[0]) + abs(cell[1] + item[1] - goal[1]),
        )
        for dx, dz, key in ordered:
            neighbor = cell[0] + dx, cell[1] + dz
            if (
                neighbor in previous
                or neighbor in blocked_cells
                or not (
                    min_cell_first <= neighbor[0] <= max_cell_first
                    and min_cell_second <= neighbor[1] <= max_cell_second
                )
            ):
                continue
            previous[neighbor] = (cell, key)
            queue.append(neighbor)
    if goal not in previous:
        return None
    keys: list[str] = []
    cursor = goal
    while cursor != start:
        parent, key = previous[cursor]  # type: ignore[misc]
        keys.append(key)
        cursor = parent
    keys.reverse()
    return keys


def drive_continuous(
    dashboard_path: Path,
    naming: dict[str, Any],
    driver: Path,
    pid: int,
    target_kind: str,
    target_state: str | None,
    timeout_s: float,
) -> None:
    movement_template = naming["controls"]["movement_template"]
    axes = continuous_axes(movement_template)
    declared_keys = naming["controls"].get("keys", {})
    supported_keys = driver_supported_keys(driver)
    reader = DashboardReader(dashboard_path)
    first = reader.wait_until(lambda _: True, 2.0)
    target = nearest_position_entity(first, target_kind, target_state, axes)
    if target is None:
        explore_kind = naming.get("controls", {}).get("navigation", {}).get("explore_via_kind")
        if isinstance(explore_kind, str) and explore_kind and explore_kind != target_kind:
            started = time.monotonic()
            drive_continuous(
                dashboard_path,
                naming,
                driver,
                pid,
                explore_kind,
                "open",
                timeout_s,
            )
            remaining = timeout_s - (time.monotonic() - started)
            if remaining <= 0:
                raise RuntimeError(f"timed out exploring toward {target_kind!r}")
            drive_continuous(
                dashboard_path,
                naming,
                driver,
                pid,
                target_kind,
                target_state,
                remaining,
            )
            return
        raise RuntimeError(
            f"no visible position entity matches kind={target_kind!r}, state={target_state!r}"
        )
    target_id = str(target["id"])
    deadline = time.monotonic() + timeout_s
    step_seconds = 0.08 if movement_template == "continuous_world_3d_keyboard_with_pointer_ui" else 0.12
    detour_key: str | None = None
    detour_remaining = 0
    detour_flip = False
    navigation = naming.get("controls", {}).get("navigation", {})
    contact_kinds = set(navigation.get("contact_kinds", []))
    approach_kinds = set(navigation.get("approach_kinds", []))
    hazard_kinds = set(navigation.get("hazard_kinds", []))

    while time.monotonic() < deadline:
        snapshot = reader.poll() or first
        if snapshot["phase"] in {"won", "lost"}:
            return
        if snapshot["phase"] != "playing":
            raise RuntimeError(f"cannot move while phase is {snapshot['phase']!r}")
        player = one_entity(snapshot, "player")
        target = nearest_position_entity(
            snapshot, target_kind, target_state, axes, entity_id=target_id
        )
        if target is None:
            # A pickup, room portal, or equivalent target normally disappears or changes state
            # when reached.  The player never guesses a hidden replacement target.
            return
        if target_kind in approach_kinds and str(target.get("state", "")).endswith("_nearby"):
            return
        before_distance = position_distance(player, target, axes)
        tolerance = (
            4.0 if movement_template == "continuous_2d_keyboard" else 0.12
        ) if target_kind in contact_kinds else arrival_tolerance(
            player, target, axes, movement_template
        )
        if before_distance <= tolerance:
            return

        if movement_template == "continuous_world_3d_keyboard_with_pointer_ui":
            public_route = continuous_aabb_key_route(
                snapshot, naming, target, axes, grid_step=0.65, clearance=0.08
            )
        else:
            public_route = continuous_aabb_key_route(
                snapshot, naming, target, axes, grid_step=18.0, clearance=1.0
            )

        if target_kind not in hazard_kinds and hazard_kinds and not public_route:
            hazards = [
                item
                for item in snapshot.get("entities", [])
                if item.get("kind") in hazard_kinds
                and item.get("visible") is not False
                and isinstance(item.get("position"), list)
                and item.get("state") not in {"dormant", "stopped"}
            ]
            if hazards:
                hazard = min(hazards, key=lambda item: position_distance(player, item, axes))
                hazard_distance = position_distance(player, hazard, axes)
                safety_distance = 90.0 if movement_template == "continuous_2d_keyboard" else 1.5
                if hazard_distance < safety_distance:
                    away_candidates: list[tuple[float, str]] = []
                    for index, positive, negative in axes:
                        delta = float(player["position"][index]) - float(hazard["position"][index])
                        away_candidates.append((abs(delta), positive if delta >= 0 else negative))
                    _, away_key = max(away_candidates)
                    physical = choose_physical_key(declared_keys[away_key], supported_keys)
                    hold_key(driver, pid, physical, step_seconds)
                    time.sleep(0.03)
                    reader.poll()
                    continue

        primary_key, primary_axis = toward_key(player, target, axes)
        if public_route:
            key = public_route[0]
        else:
            key = detour_key if detour_remaining > 0 and detour_key else primary_key
        before_revision = int(snapshot["revision"])
        try:
            physical = choose_physical_key(declared_keys[key], supported_keys)
        except KeyError as exc:
            raise RuntimeError(f"naming tables are missing logical movement key {key!r}") from exc
        hold_key(driver, pid, physical, step_seconds)
        updated = wait_for_reader_revision(reader, before_revision, 1.2)
        updated_player = one_entity(updated, "player")
        updated_target = nearest_position_entity(
            updated, target_kind, target_state, axes, entity_id=target_id
        )
        if updated_target is None:
            return
        after_distance = position_distance(updated_player, updated_target, axes)
        position_changed = any(
            abs(float(updated_player["position"][index]) - float(player["position"][index])) > 1e-4
            for index, _, _ in axes
        )

        if public_route:
            continue

        if detour_remaining > 0:
            detour_remaining -= 1
            if not position_changed:
                detour_remaining = 0
                detour_key = None
                detour_flip = not detour_flip
            elif detour_remaining == 0:
                detour_key = None
            continue

        progress_epsilon = 0.5 if movement_template == "continuous_2d_keyboard" else 0.02
        if not position_changed or after_distance >= before_distance - progress_epsilon:
            alternatives = perpendicular_detour_keys(
                primary_axis, axes, updated_player, updated_target
            )
            if alternatives:
                detour_key = alternatives[1 if detour_flip else 0]
                detour_flip = not detour_flip
                detour_remaining = 8
    raise RuntimeError(f"timed out moving toward {target_kind!r}")


def drive_to(
    dashboard_path: Path,
    naming_path: Path,
    driver: Path,
    pid: int,
    target_kind: str,
    target_state: str | None,
    timeout_s: float,
    action_key: str | None = None,
    max_steps: int | None = None,
) -> None:
    naming = json.loads(naming_path.read_text(encoding="utf-8"))
    movement_template = naming.get("controls", {}).get("movement_template")
    if movement_template == "discrete_keys":
        drive_discrete_edges(
            dashboard_path,
            naming_path,
            driver,
            pid,
            target_kind,
            target_state,
            timeout_s,
            max_steps,
        )
        return
    if movement_template == "discrete_keys_with_hold_repeat":
        drive_discrete_grid(
            dashboard_path,
            naming,
            driver,
            pid,
            target_kind,
            target_state,
            timeout_s,
            action_key,
        )
        return
    if movement_template == "continuous_platformer":
        drive_platformer(
            dashboard_path,
            naming,
            driver,
            pid,
            target_kind,
            target_state,
            timeout_s,
        )
        return
    if movement_template in {
        "continuous_2d_keyboard",
        "continuous_world_3d_keyboard_with_pointer_ui",
    }:
        drive_continuous(
            dashboard_path,
            naming,
            driver,
            pid,
            target_kind,
            target_state,
            timeout_s,
        )
        return
    raise RuntimeError(f"unsupported movement template {movement_template!r}")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    inspect_parser = sub.add_parser("inspect")
    inspect_parser.add_argument("dashboard", type=Path)

    plan_parser = sub.add_parser("plan")
    plan_parser.add_argument("dashboard", type=Path)
    plan_parser.add_argument("target_kind")
    plan_parser.add_argument("--state")

    drive_parser = sub.add_parser("drive")
    drive_parser.add_argument("dashboard", type=Path)
    drive_parser.add_argument("naming_tables", type=Path)
    drive_parser.add_argument("key_driver", type=Path)
    drive_parser.add_argument("pid", type=int)
    drive_parser.add_argument("target_kind")
    drive_parser.add_argument("--state")
    drive_parser.add_argument("--timeout", type=float, default=30)

    args = parser.parse_args()
    if args.command == "inspect":
        print(json.dumps(latest_snapshot(args.dashboard), indent=2, sort_keys=True))
    elif args.command == "plan":
        snapshot = latest_snapshot(args.dashboard)
        target = tuple(one_entity(snapshot, args.target_kind, args.state)["cell"])
        print(json.dumps(shortest_key_path(snapshot, target)))
    elif args.command == "drive":
        drive_to(
            args.dashboard,
            args.naming_tables,
            args.key_driver,
            args.pid,
            args.target_kind,
            args.state,
            args.timeout,
        )


if __name__ == "__main__":
    main()
