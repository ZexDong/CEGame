"""Unified read-only state and flow interface across all five benchmark engines."""
import argparse
import json
from collections import deque
from copy import deepcopy
from pathlib import Path


def _extract_snapshot(record):
    if not isinstance(record, dict):
        return record
    if record.get("protocol") == "godot-checkpoint-driver/v1":
        observations = record.get("observations") or []
        if observations:
            return observations[-1].get("state", {}).get("snapshot")
        events = record.get("events") or []
        if events:
            return events[-1].get("after", {}).get("snapshot")
        return None
    if isinstance(record.get("save"), dict) and record["save"].get("contract") == "game-session/v1":
        return record["save"]
    for key in ("snapshot", "state", "game_state"):
        if isinstance(record.get(key), dict) and "slots" not in record:
            return record[key]
    return record


class OmniState:
    def __init__(self, capture):
        self._capture = capture

    def Get(self, key):
        state = self._capture()
        if not isinstance(state, dict):
            raise ValueError("No public snapshot is available")
        if key in state:
            return deepcopy(state[key])
        if key in (state.get("slots") or {}):
            return deepcopy(state["slots"][key])
        for container in ("snapshot", "state", "game_state"):
            nested = state.get(container)
            if isinstance(nested, dict) and key in nested:
                return deepcopy(nested[key])
        values = state.get("values")
        if isinstance(values, list):
            matches = [row["value"] for row in values
                       if isinstance(row, dict) and row.get("name") == key and "value" in row]
            if len(matches) > 1:
                raise ValueError(f"Duplicate public state field {key}")
            if matches:
                return deepcopy(matches[0])
        value = state
        for part in key.split("."):
            if not isinstance(value, dict) or part not in value:
                raise KeyError(key)
            value = value[part]
        return deepcopy(value)

    @classmethod
    def from_file(cls, path):
        path = Path(path)

        def capture():
            with path.open(encoding="utf-8-sig") as stream:
                if path.suffix.lower() == ".jsonl":
                    last = deque((line for line in stream if line.strip()), maxlen=1)
                    record = json.loads(last[0]) if last else None
                else:
                    record = json.load(stream)
            return _extract_snapshot(record)

        return cls(capture)


class OmniFlow:
    def __init__(self, *, load_state=None, restart=None):
        self._load_state = load_state
        self._restart = restart

    def LoadState(self, state_id):
        if self._load_state is None:
            raise NotImplementedError("This session has no legal state-loading operation")
        return self._load_state(state_id)

    def Restart(self):
        if self._restart is None:
            raise NotImplementedError("This session has no restart operation")
        return self._restart()


def _callable_capture(source):
    if callable(source):
        return source
    if isinstance(source, (str, Path)):
        return OmniState.from_file(source)._capture
    if hasattr(source, "capture") and callable(source.capture):
        return source.capture
    if hasattr(source, "state") and callable(source.state):
        return source.state
    raise TypeError("Expected a snapshot path, callable, or session object with capture()/state()")


def _resolve_load_state(source, load_state):
    if load_state is not None:
        return load_state
    for attr in ("load_state", "LoadState", "load_entry", "open_entry", "open"):
        fn = getattr(source, attr, None)
        if callable(fn):
            return fn
    return None


def _resolve_restart(source, restart):
    if restart is not None:
        return restart
    for attr in ("restart", "Restart", "reset"):
        fn = getattr(source, attr, None)
        if callable(fn):
            return fn
    return None


def unity_session(evaluation, seed=0):
    """Bind an active game-session/v1 evaluator with the player command transport."""
    def capture():
        return evaluation.validate(evaluation.p.call("observe", seconds=0))

    def load(state_id):
        if state_id not in evaluation.model["entries"]:
            raise ValueError(f"Unknown public entry {state_id}")
        state = evaluation.validate(evaluation.p.call("open", entry=state_id, seed=seed, seconds=0))
        if state["entryId"] != state_id:
            raise ValueError("The game opened a different entry")
        return state

    def restart():
        evaluation.restart()
        return capture()

    return OmniState(capture), OmniFlow(load_state=load, restart=restart)


def defold_campaign(session, *, load_state=None, restart=None):
    """Bind a Defold Dashboard session and its published flow controls."""
    def default_restart():
        serial = session.state()["slots"]["run_serial"]
        session.press("restart")
        return session.wait(lambda v: v["phase"] == "playing" and v["slots"]["run_serial"] == serial + 1)

    return (
        OmniState(_callable_capture(session)),
        OmniFlow(load_state=_resolve_load_state(session, load_state),
                 restart=restart if restart is not None else default_restart),
    )


def godot_session(source, *, load_state=None, restart=None):
    """Bind a Godot read-only dashboard capture or active session."""
    return (
        OmniState(_callable_capture(source)),
        OmniFlow(load_state=_resolve_load_state(source, load_state),
                 restart=_resolve_restart(source, restart)),
    )


def roblox_session(source, *, load_state=None, restart=None):
    """Bind a Roblox read-only state provider or active session."""
    return (
        OmniState(_callable_capture(source)),
        OmniFlow(load_state=_resolve_load_state(source, load_state),
                 restart=_resolve_restart(source, restart)),
    )


def unreal_session(source, *, load_state=None, restart=None):
    """Bind an Unreal read-only observation snapshot or active session."""
    return (
        OmniState(_callable_capture(source)),
        OmniFlow(load_state=_resolve_load_state(source, load_state),
                 restart=_resolve_restart(source, restart)),
    )


def bind_session(engine, target, **kwargs):
    """Return an (OmniState, OmniFlow) pair for any supported benchmark engine."""
    key = str(engine).strip().lower()
    adapters = {
        "unity": unity_session,
        "defold": defold_campaign,
        "godot": godot_session,
        "roblox": roblox_session,
        "unreal": unreal_session,
    }
    if key not in adapters:
        raise ValueError(f"Unsupported engine: {engine}")
    return adapters[key](target, **kwargs)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Read one key from a native JSON or JSONL state snapshot.")
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("key")
    args = parser.parse_args()
    print(json.dumps(OmniState.from_file(args.snapshot).Get(args.key), ensure_ascii=True, allow_nan=False))
