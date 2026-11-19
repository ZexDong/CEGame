#!/usr/bin/env python3
"""Reactor Relay Protocol evaluator following the D1-D6 checkpoint pipeline.

The static phase inspects the delivered rbxlx/source package.  The dynamic
phase replays a JSONL evidence trace produced by player_runtime.py and
evaluates the assertions from checkpoint-script.json.  Missing evidence is
reported as unevaluated, never silently converted to a candidate failure.
"""

from __future__ import annotations

import argparse
import ast
import json
import math
import re
import sys
import tempfile
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any
import xml.etree.ElementTree as ET


DIM_MAX = {"D1": 10.0, "D2": 30.0, "D3": 20.0, "D4": 20.0, "D5": 10.0, "D6": 10.0}
PHASES = {"not_ready", "menu", "cycle", "preview", "sequence", "won", "lost"}


class AttrDict(dict):
    def __getattr__(self, name: str) -> Any:
        try:
            return self[name]
        except KeyError as exc:
            raise AttributeError(name) from exc


def wrap(value: Any) -> Any:
    if isinstance(value, dict):
        return AttrDict({k: wrap(v) for k, v in value.items()})
    if isinstance(value, list):
        return [wrap(v) for v in value]
    return value


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def extract_rbxlx_sources(path: Path) -> dict[str, str]:
    root = ET.parse(path).getroot()
    found: dict[str, str] = {}

    def walk(item: ET.Element, prefix: str = "") -> None:
        if item.tag != "Item":
            return
        props = item.find("Properties")
        name = "unnamed"
        source = None
        if props is not None:
            for node in props:
                if node.attrib.get("name") == "Name":
                    name = node.text or name
                elif node.attrib.get("name") == "Source":
                    source = node.text or ""
        current = f"{prefix}/{name}" if prefix else name
        if source is not None:
            found[current] = source
        for child in item.findall("Item"):
            walk(child, current)

    for item in root.findall("Item"):
        walk(item)
    return found


def static_checks(game: Path, source_zip: Path | None, naming: dict[str, Any]) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []

    def add(cid: str, passed: bool, evidence: str) -> None:
        checks.append({"id": cid, "dim": "D1", "status": "pass" if passed else "fail", "evidence": evidence})

    sources: dict[str, str] = {}
    try:
        sources = extract_rbxlx_sources(game)
        add("STATIC-artifact-readable", True, f"rbxlx XML parsed; {len(sources)} embedded scripts found")
    except Exception as exc:
        add("STATIC-artifact-readable", False, f"cannot parse rbxlx: {exc}")
        for cid in ("STATIC-entry-structure", "STATIC-source-sanity", "STATIC-source-match", "STATIC-dashboard"):
            add(cid, False, "blocked by unreadable artifact")
        return checks

    required_paths = {"ReplicatedStorage/ReactorRelayPublicSchema", "StarterPlayer/StarterPlayerScripts/ReactorRelay"}
    missing = sorted(required_paths - sources.keys())
    add("STATIC-entry-structure", not missing, "required Roblox services/scripts present" if not missing else f"missing: {missing}")

    client = sources.get("StarterPlayer/StarterPlayerScripts/ReactorRelay", "")
    schema = sources.get("ReplicatedStorage/ReactorRelayPublicSchema", "")
    source_ok = all(token in client for token in ("ScreenGui", "Activated:Connect", "RR_Ready", "Schema.Tags.GameState", "Schema.Tags.Control", "Schema.Tags.HUDField")) and all(
        token in schema for token in ("CycleTargets", "FinalSequence", "LogicalLayout")
    ) and any(
        version in schema for version in ("reactor-relay-v1", "reactor-relay-v2-hard")
    )
    debug_markers = [m for m in ("cheat", "one_click_win", "debug_button") if m.lower() in client.lower()]
    add("STATIC-source-sanity", source_ok and not debug_markers,
        "entry scripts contain GUI/input/state wiring and no obvious cheat/debug marker" if source_ok and not debug_markers
        else f"missing expected wiring or debug markers present: {debug_markers}")

    if source_zip is None:
        add("STATIC-source-match", False, "source zip not supplied")
    else:
        try:
            with zipfile.ZipFile(source_zip) as zf:
                candidates = {Path(n).name: zf.read(n).decode("utf-8") for n in zf.namelist() if n.endswith((".lua", ".luau"))}
            pairs = {
                "ReactorRelay.client.luau": "StarterPlayer/StarterPlayerScripts/ReactorRelay",
                "ReactorRelaySchema.luau": "ReplicatedStorage/ReactorRelayPublicSchema",
            }
            normalize = lambda value: value.replace("\r\n", "\n").strip()
            mismatched = [name for name, key in pairs.items() if normalize(candidates.get(name, "")) != normalize(sources.get(key, ""))]
            add("STATIC-source-match", not mismatched, "source archive exactly matches embedded scripts" if not mismatched else f"mismatched: {mismatched}")
        except Exception as exc:
            add("STATIC-source-match", False, f"cannot compare source archive: {exc}")

    control_ids = {row["kind"] for row in naming["targets"]}
    missing_controls = sorted(cid for cid in control_ids if cid not in client)
    required_attrs = {"RR_Revision","RR_Phase","RR_Cycle","RR_Integrity","RR_Faults","RR_UnallocatedPower","RR_UnallocatedCoolant","RR_ScanCharges","RR_PurgeAvailable","RR_SelectedBay","RR_IncidentId","RR_SequenceIndex"}
    missing_attrs = sorted(attr for attr in required_attrs if attr not in client)
    contract_ok = not missing_controls and not missing_attrs and "CollectionService:AddTag" in client
    detail = "public tags, Attributes, and 19 control IDs are present" if contract_ok else f"missing controls={missing_controls}; missing attributes={missing_attrs}"
    add("STATIC-public-contract", contract_ok, detail)
    return checks


def validate_snapshot(snapshot: dict[str, Any], naming: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not isinstance(snapshot.get("revision"), int) or snapshot.get("revision", -1) < 0:
        errors.append("revision must be a non-negative integer")
    if snapshot.get("phase") not in PHASES:
        errors.append("phase is invalid")
    slots = snapshot.get("slots")
    if not isinstance(slots, dict):
        errors.append("slots must be an object")
        slots = {}
    for name in naming["slots"]:
        if name not in slots or not isinstance(slots.get(name), (int, float)):
            errors.append(f"slot {name} missing/non-numeric")
    entities = snapshot.get("entities")
    if not isinstance(entities, list):
        errors.append("entities must be an array")
        entities = []
    entity_map = {e.get("kind"): e for e in entities if isinstance(e, dict)}
    for row in naming["entities"]:
        item = entity_map.get(row["kind"])
        if item is None:
            errors.append(f"entity {row['kind']} missing")
        elif item.get("state") not in row["states"]:
            errors.append(f"entity {row['kind']} state {item.get('state')!r} invalid")
    targets = snapshot.get("targets")
    if not isinstance(targets, list):
        errors.append("targets must be an array")
        targets = []
    target_map = {t.get("kind"): t for t in targets if isinstance(t, dict)}
    for row in naming["targets"]:
        item = target_map.get(row["kind"])
        if item is None:
            errors.append(f"target {row['kind']} missing")
            continue
        rect = item.get("rect")
        if not isinstance(rect, list) or len(rect) != 4 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in rect):
            errors.append(f"target {row['kind']} rect invalid")
        if not isinstance(item.get("visible"), bool) or not isinstance(item.get("interactable"), bool):
            errors.append(f"target {row['kind']} visibility flags invalid")
    extra = set(snapshot) - {"revision", "phase", "slots", "entities", "targets"}
    if extra:
        errors.append(f"unexpected top-level fields: {sorted(extra)}")
    return errors


ALLOWED_AST = (
    ast.Expression, ast.BoolOp, ast.BinOp, ast.UnaryOp, ast.Compare, ast.Call,
    ast.Name, ast.Load, ast.Attribute, ast.Constant, ast.And, ast.Or, ast.Not,
    ast.Eq, ast.NotEq, ast.Lt, ast.LtE, ast.Gt, ast.GtE, ast.Add, ast.Sub,
    ast.Mult, ast.Div, ast.USub,
)


def eval_assertion(expr: str, snapshot: dict[str, Any], saved: dict[str, Any], visual_changes: dict[str, bool]) -> bool:
    tree = ast.parse(expr, mode="eval")
    for node in ast.walk(tree):
        if not isinstance(node, ALLOWED_AST):
            raise ValueError(f"unsupported assertion syntax: {type(node).__name__}")
        if isinstance(node, ast.Call) and (not isinstance(node.func, ast.Name) or node.func.id not in {
            "entity", "target", "all_targets_visible", "visible_change_since"
        }):
            raise ValueError("unsupported assertion function")
    snap = wrap(snapshot)
    entities = {e["kind"]: wrap(e) for e in snapshot.get("entities", [])}
    targets = {t["kind"]: wrap(t) for t in snapshot.get("targets", [])}

    def entity(kind: str) -> Any:
        return entities.get(kind, AttrDict(state="__missing__"))

    def target(kind: str) -> Any:
        return targets.get(kind, AttrDict(visible=False, interactable=False, rect=[0, 0, 0, 0]))

    def all_targets_visible(*kinds: str) -> bool:
        # Presence/layout checks must not fail merely because a correctly
        # unavailable control (for example Commit before all bays lock) is disabled.
        return all(target(k).visible for k in kinds)

    env: dict[str, Any] = {
        "phase": snap.get("phase"), "revision": snap.get("revision"), "slots": snap.get("slots", AttrDict()),
        "entity": entity, "target": target, "all_targets_visible": all_targets_visible,
        "visible_change_since": lambda name: bool(visual_changes.get(name, False)),
    }
    env.update({name: wrap(value) for name, value in saved.items()})
    return bool(eval(compile(tree, "<checkpoint>", "eval"), {"__builtins__": {}}, env))


def load_trace(path: Path) -> dict[tuple[str, int], dict[str, Any]]:
    records: dict[tuple[str, int], dict[str, Any]] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            key = (row["trajectory"], int(row["step"]))
            if key in records:
                raise ValueError(f"duplicate trace record {key} at line {line_no}")
            records[key] = row
    return records


def dynamic_checks(script: dict[str, Any], naming: dict[str, Any], trace_path: Path | None) -> tuple[list[dict[str, Any]], list[str]]:
    results: list[dict[str, Any]] = []
    trace_errors: list[str] = []
    records = load_trace(trace_path) if trace_path else {}
    for traj in script["trajectories"]:
        saved: dict[str, Any] = {}
        visual_changes: dict[str, bool] = {}
        blocked = False
        tool_blocked = False
        for index, step in enumerate(traj["steps"]):
            record = records.get((traj["id"], index))
            snapshot = record.get("snapshot") if record else None
            if snapshot is not None:
                errors = validate_snapshot(snapshot, naming)
                if errors:
                    trace_errors.extend(f"{traj['id']} step {index}: {e}" for e in errors)
            if step.get("do") == "snapshot" and snapshot is not None:
                saved[step["save_as"]] = snapshot
                visual_changes.update(record.get("visual_changes", {}))
            check = step.get("check")
            if not check:
                if record and record.get("runtime_error"):
                    tool_blocked = True
                continue
            base = {"id": check["id"], "source": check["source"], "dim": check["dim"], "trajectory": traj["id"], "step": index, "assert": check["assert"]}
            if trace_path is None:
                results.append({**base, "status": "unevaluated", "evidence": "dynamic trace not supplied"})
                continue
            if record and record.get("runtime_error"):
                tool_blocked = True
            if tool_blocked:
                results.append({**base, "status": "evaluator_error", "evidence": record.get("evidence", "runtime player error") if record else "prior runtime player error"})
                continue
            if blocked or snapshot is None:
                results.append({**base, "status": "unable_to_continue", "evidence": "prior action failed or snapshot missing"})
                blocked = True
                continue
            visual_changes.update(record.get("visual_changes", {}))
            try:
                passed = eval_assertion(check["assert"], snapshot, saved, visual_changes)
                results.append({**base, "status": "pass" if passed else "fail", "evidence": record.get("evidence", "runtime snapshot")})
            except Exception as exc:
                results.append({**base, "status": "evaluator_error", "evidence": str(exc)})
    return results, trace_errors


def score_dimension(dim: str, checks: list[dict[str, Any]]) -> dict[str, Any]:
    relevant = [c for c in checks if c["dim"] == dim]
    if not relevant:
        return {"max": DIM_MAX[dim], "score": None, "passed": 0, "total": 0, "status": "not_evaluated"}
    evaluable = [c for c in relevant if c["status"] not in {"unevaluated", "evaluator_error"}]
    if len(evaluable) != len(relevant):
        return {"max": DIM_MAX[dim], "score": None, "passed": sum(c["status"] == "pass" for c in evaluable),
                "total": len(relevant), "status": "incomplete_evidence"}
    passed = sum(c["status"] == "pass" for c in relevant)
    score = round(DIM_MAX[dim] * passed / len(relevant), 2)
    return {"max": DIM_MAX[dim], "score": score, "passed": passed, "total": len(relevant), "status": "scored"}


def main(argv: list[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True, help="candidate ReactorRelayCandidate.rbxlx")
    parser.add_argument("--source-zip", type=Path, help="candidate source archive")
    parser.add_argument("--trace", type=Path, help="JSONL trace from player_runtime.py")
    parser.add_argument("--candidate-runtime-failure", type=Path, help="conclusive candidate-side Studio runtime error evidence")
    parser.add_argument("--original-runtime-failure", type=Path, help="syntax/runtime failure from the frozen original delivery")
    parser.add_argument("--baseline", type=Path, help="prior report whose completed checks are retained during incremental retry")
    parser.add_argument("--finalize-incomplete-as-fail", action="store_true", help="convert remaining D2-D5 evaluator errors to scored failures")
    parser.add_argument("--script", type=Path, default=here / "checkpoint-script.json")
    parser.add_argument("--d6", type=float, choices=[x / 2 for x in range(21)], help="independent visual score 0-10 in 0.5 increments")
    parser.add_argument("--out", type=Path, default=here / "evaluation-report.json")
    args = parser.parse_args(argv)

    script = load_json(args.script.resolve())
    naming = load_json(here / "naming-tables.json")
    static = static_checks(args.game.resolve(), args.source_zip.resolve() if args.source_zip else None, naming)
    dynamic, trace_errors = dynamic_checks(script, naming, args.trace.resolve() if args.trace else None)
    all_checks = static + dynamic
    original_failure = args.original_runtime_failure.resolve() if args.original_runtime_failure else None
    if original_failure and original_failure.exists():
        original_text = original_failure.read_text(encoding="utf-8", errors="replace").strip()
        for check in all_checks:
            if check.get("id") == "STATIC-source-sanity":
                check["status"] = "fail"
                check["evidence"] = "Frozen original delivery failed Luau parsing; repaired QA copy used only for downstream testing: " + original_text
    runtime_failure = args.candidate_runtime_failure.resolve() if args.candidate_runtime_failure else None
    runtime_failure_text = runtime_failure.read_text(encoding="utf-8", errors="replace").strip() if runtime_failure else ""
    if runtime_failure or args.trace:
        all_checks.append({
            "id": "STATIC-runtime-load", "dim": "D1",
            "status": "fail" if runtime_failure else "pass",
            "evidence": runtime_failure_text if runtime_failure else "Studio Play reached the public Ready contract",
        })
    if runtime_failure:
        for check in all_checks:
            if check.get("dim") in {"D2", "D3", "D4", "D5"}:
                check["status"] = "fail"
                check["evidence"] = "candidate gameplay did not initialize: " + runtime_failure_text
    if args.baseline and args.baseline.exists():
        baseline_report = load_json(args.baseline.resolve())
        merged = {c["id"]: c for c in baseline_report.get("checks", [])}
        for check in all_checks:
            merged[check["id"]] = check
        all_checks = list(merged.values())
    if args.finalize_incomplete_as_fail:
        for check in all_checks:
            if check.get("dim") in {"D2", "D3", "D4", "D5"} and check.get("status") in {
                "evaluator_error", "unevaluated", "unable_to_continue"
            }:
                prior_status = check["status"]
                check["status"] = "fail"
                check["evidence"] = f"Finalized as failure after incremental retry ({prior_status}): " + check.get("evidence", "no complete evidence")
    dims = {d: score_dimension(d, all_checks) for d in ("D1", "D2", "D3", "D4", "D5")}
    dims["D6"] = {"max": 10.0, "score": args.d6, "status": "provisional_no_reference" if args.d6 is not None else "not_evaluated",
                  "note": "Independent three-state candidate visual review; no frozen Gold/reference image was supplied." if args.d6 is not None else "D6 must come from the frozen reference-vs-candidate visual protocol"}
    numeric = [dims[d]["score"] for d in DIM_MAX if dims[d].get("score") is not None]
    complete = all(dims[d].get("score") is not None for d in DIM_MAX)
    report = {
        "schema_version": 1,
        "game": "reactor_relay_protocol",
        "candidate": str(args.game.resolve()),
        "source_zip": str(args.source_zip.resolve()) if args.source_zip else None,
        "trace": str(args.trace.resolve()) if args.trace else None,
        "dimensions": dims,
        "total": round(sum(numeric), 2) if complete else None,
        "available_points": round(sum(numeric), 2),
        "complete": complete,
        "checks": all_checks,
        "trace_errors": trace_errors,
        "limitations": [
            "D2-D5 require a real-input runtime trace; absent trace is unevaluated, not failed.",
            "D6 is independent and requires a frozen reference screenshot set, which is not included in the supplied files.",
            "Requirement IDs were reconstructed from the delivered README/runtime because the original GDD was not supplied."
        ]
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(args.out.resolve()), "dimensions": dims, "total": report["total"]}, ensure_ascii=False, indent=2))
    return 0 if not any(c["status"] == "evaluator_error" for c in all_checks) else 2


if __name__ == "__main__":
    raise SystemExit(main())
