"""Collect a Godot candidate and aggregate evidence-backed checkpoint reviews."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

MAXIMA = {"D1": 10, "D2": 30, "D3": 20, "D4": 20, "D5": 10, "D6": 10}
EXCLUDES = {".godot", ".git", "__pycache__", ".pytest_cache"}
VERSION = "godot-public-2"


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
                    encoding="utf-8")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_id(output):
    return "godot-" + hashlib.sha256(str(output).encode("utf-8")).hexdigest()[:20]


def inside(root, relative):
    root = Path(root).resolve()
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        raise ValueError("Evidence path escapes output")
    return path


def tree_hashes(root):
    result = {}
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDES)
        for name in dirs + names:
            path = Path(directory) / name
            if path.is_symlink() or not path.resolve().is_relative_to(root):
                raise ValueError("Linked candidate paths are unsupported")
        for name in sorted(names):
            path = Path(directory) / name
            if path.suffix not in {".pyc", ".pyo"}:
                result[path.relative_to(root).as_posix()] = digest(path)
    return result


def bindings(evaluation):
    files = [evaluation.parent / "sample.json"]
    files += [p for p in evaluation.rglob("*") if p.is_file()
              and "__pycache__" not in p.parts and p.suffix not in {".pyc", ".pyo"}]
    return {p.relative_to(evaluation.parent).as_posix(): digest(p) for p in sorted(files)}


def run_process(command, output, label, timeout):
    receipt = {"command": command, "exit_code": None, "timed_out": False}
    stdout, stderr = output / (label + ".stdout.txt"), output / (label + ".stderr.txt")
    with stdout.open("wb") as out, stderr.open("wb") as err:
        process = subprocess.Popen(command, stdout=out, stderr=err)
        receipt["pid"] = process.pid
        try:
            receipt["exit_code"] = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            receipt["exit_code"] = process.wait()
            receipt["timed_out"] = True
    receipt["stdout"] = stdout.name
    receipt["stderr"] = stderr.name
    write(output / (label + ".process.json"), receipt)
    return receipt


def check_row(definition, status, score, evidence, reason):
    return {"id": definition["id"], "requirement_ids": definition["requirement_ids"],
            "dimension": definition["dimension"], "max_score": definition["max_score"],
            "status": status, "score": score, "reason": reason, "blocked_by": [],
            "evidence": evidence}


def summarize(meta, run_id, checks, reason, infrastructure=False):
    dimensions = {}
    for dim, maximum in MAXIMA.items():
        rows = [r for r in checks if r["dimension"] == dim]
        complete = bool(rows) and all(r["score"] is not None for r in rows)
        dimensions[dim] = {
            "score": round(sum(r["score"] for r in rows), 6) if complete else None,
            "max_score": maximum,
            "status": "complete" if complete else ("invalid" if infrastructure else "incomplete"),
            "evidence": sorted({p for r in rows for p in r["evidence"]}),
        }
    complete = all(d["status"] == "complete" for d in dimensions.values())
    return {"schema_version": "2.1", "sample_id": meta["sample_id"],
            "sample_version": meta["sample_version"], "evaluator_version": VERSION,
            "run_id": run_id, "evaluation_valid": complete,
            "classification": "scored" if complete else (
                "infrastructure_failure" if infrastructure else "incomplete"),
            "coverage_status": "not_reviewed", "reason": "" if complete else reason,
            "dimensions": dimensions, "checks": checks, "coverage_evidence": [],
            "final_score": round(sum(d["score"] for d in dimensions.values()), 6)
                           if complete else None, "max_score": 100}


def _engine_errors(output, receipts):
    text = "\n".join((output / r[k]).read_text(encoding="utf-8", errors="replace")
                     for r in receipts for k in ("stdout", "stderr"))
    return bool(re.search(r"Parse Error|SCRIPT ERROR|Failed loading resource|Failed to load script",
                          text))


def collect(evaluation, meta, args, output):
    source = args.project.resolve()
    if not (source / "project.godot").is_file():
        if (source / "sp/project.godot").is_file():
            source /= "sp"
        else:
            raise ValueError("--project must contain project.godot (or sp/project.godot)")
    exe = args.godot or os.environ.get("GODOT_EXE") or shutil.which("godot")
    if not exe or not Path(exe).is_file():
        raise ValueError("Set GODOT_EXE or --godot to an installed Godot console executable")
    before = tree_hashes(source)
    project = output / "project"
    for rel in before:
        dest = inside(project, rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / rel, dest)
    project_file = project / "project.godot"
    text = project_file.read_text(encoding="utf-8-sig")
    text = re.sub(r"(?m)^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n?", "", text)
    text = text.replace("[application]", '[application]\nconfig/use_custom_user_dir=true\n'
                        'config/custom_user_dir_name="GameCreate/' + uuid.uuid4().hex + '"', 1)
    project_file.write_text(text, encoding="utf-8")
    evidence = output / "evidence"
    native = evidence / "native"
    native.mkdir(parents=True)
    version = run_process([str(exe), "--version"], native, "engine-version", 30)
    if version["exit_code"] != 0 or version["timed_out"]:
        raise ValueError("Godot version query failed")
    prefix = [str(exe), "--path", str(project), "--rendering-method", "gl_compatibility"]
    imported = run_process(prefix + ["--headless", "--editor", "--import", "--quit"],
                           native, "import", args.timeout)
    receipts, reports = [imported], []
    data = load(evaluation / "checkpoint-script.json")
    trajectories = data["trajectories"]
    if args.trajectory:
        trajectories = [t for t in trajectories if t["id"] == args.trajectory]
        if not trajectories:
            raise ValueError("Unknown trajectory")
    if imported["exit_code"] == 0 and not _engine_errors(native, receipts):
        if args.interactive_seconds:
            trajectories = trajectories[:1]
        for trajectory in trajectories:
            reopen = [i for i, s in enumerate(trajectory["steps"]) if s.get("do") == "reopen"]
            cuts = [0] + reopen + [len(trajectory["steps"])]
            for part, (start, stop) in enumerate(zip(cuts, cuts[1:])):
                label = trajectory["id"] + "-part" + str(part)
                report = native / (label + ".json")
                command = prefix + (["--headless"] if args.headless else []) + [
                    "--script", str(evaluation / "src/collector.gd"), "--",
                    "--evaluation", str(evaluation), "--output", str(report),
                    "--trajectory", trajectory["id"], "--start-step", str(start),
                    "--stop-step", str(stop), "--reopen-verified", "true" if part else "false"]
                if args.interactive_seconds:
                    command += ["--interactive-seconds", str(args.interactive_seconds)]
                receipt = run_process(command, native, label, args.timeout)
                receipts.append(receipt)
                if report.is_file():
                    reports.append(report.relative_to(output).as_posix())
    write(evidence / "source-integrity.json", {
        "unchanged": before == tree_hashes(source), "source_files": before})
    transcripts = []
    for rel in reports:
        value = load(output / rel)
        if isinstance(value, dict):
            transcripts.extend(value.get("observations", []))
            transcripts.extend({"state": e.get("after", {})} for e in value.get("events", []))
    snapshots = [v.get("state", {}).get("snapshot", {}) for v in transcripts]
    snapshots = [s for s in snapshots if s]
    names = load(evaluation.parent / meta["input"]["starter_project"] / "benchmark/naming-tables.json")
    required_slots = names.get("slots", [])
    well_formed = any(
        s.get("phase") in {"menu", "playing", "paused", "won", "lost"}
        and type(s.get("revision")) in (int, float)
        and isinstance(s.get("slots"), dict)
        and all(type(s["slots"].get(k)) in (int, float) for k in required_slots)
        and isinstance(s.get("entities"), list) and isinstance(s.get("targets"), list)
        for s in snapshots)
    images = sorted(p.relative_to(output).as_posix() for p in native.glob("*.png"))
    write(evidence / "runtime-summary.json", {
        "reports": reports, "snapshots": len(snapshots), "images": images,
        "dashboard_well_formed": well_formed,
        "engine_version": (native / version["stdout"]).read_text(encoding="utf-8", errors="replace").strip(),
        "engine_error": _engine_errors(native, receipts),
        "processes": receipts, "headless": args.headless})
    # D1 tests use only current import/runtime observations; other dimensions
    # require requirement-level observations, never inferred from "phase ready".
    definitions = load(evaluation / "rules.json")["checks"]
    d1_ok = [
        imported["exit_code"] == 0 and not imported["timed_out"],
        bool(reports) and all(r["exit_code"] == 0 and not r["timed_out"] for r in receipts[1:]),
        not _engine_errors(native, receipts),
        bool(snapshots),
        well_formed,
    ]
    checks, d1_index = [], 0
    for definition in definitions:
        if definition["dimension"] == "D1":
            passed = d1_ok[d1_index]
            d1_index += 1
            checks.append(check_row(definition, "pass" if passed else "fail",
                                    definition["max_score"] if passed else 0,
                                    ["evidence/runtime-summary.json"],
                                    definition["description"] + (": observed" if passed else ": not demonstrated")))
        else:
            checks.append(check_row(definition, "inconclusive_evaluator", None,
                                    ["evidence/runtime-summary.json"],
                                    "Requires review of the named requirement and collected evidence"))
    write(evidence / "initial-checks.json", checks)
    write(output / "review-template.json", {
        "protocol": "godot-evidence-review/v1", "sample_id": meta["sample_id"],
        "run_id": run_id(output), "bundle_hash": digest(evidence / "bindings.json"),
        "collection_hash": None, "reviewer": "",
        "checks": [{"id": r["id"], "verdict": None, "reason": "",
                    "requirements": [{"id": k, "verdict": None, "evidence": [], "reason": ""}
                                     for k in r["requirement_ids"]]}
                   for r in checks if r["dimension"] != "D1"],
    })
    # Seal only observed evidence, excluding mutable review and score documents.
    seal = {p.relative_to(output).as_posix(): digest(p) for p in evidence.rglob("*") if p.is_file()}
    write(evidence / "collection-manifest.json", seal)
    template = load(output / "review-template.json")
    template["collection_hash"] = digest(evidence / "collection-manifest.json")
    write(output / "review-template.json", template)
    return summarize(meta, run_id(output), checks, "Collection finished; complete the evidence review")


def finalize(evaluation, meta, args, output):
    evidence = output / "evidence"
    if load(evidence / "bindings.json") != bindings(evaluation):
        raise ValueError("Evaluator or input changed after collection")
    seal = load(evidence / "collection-manifest.json")
    for rel, expected in seal.items():
        if digest(inside(output, rel)) != expected:
            raise ValueError("Collected evidence changed: " + rel)
    if not load(evidence / "source-integrity.json")["unchanged"]:
        raise ValueError("Submitted source changed during collection")
    runtime = load(evidence / "runtime-summary.json")
    if not args.review:
        raise ValueError("--review is required for finalize")
    review = load(args.review)
    if (review.get("protocol") != "godot-evidence-review/v1"
            or review.get("sample_id") != meta["sample_id"]
            or review.get("run_id") != run_id(output)
            or review.get("bundle_hash") != digest(evidence / "bindings.json")
            or review.get("collection_hash") != digest(evidence / "collection-manifest.json")
            or not str(review.get("reviewer", "")).strip()):
        raise ValueError("Review does not identify this collection/evaluator/reviewer")
    checks = load(evidence / "initial-checks.json")
    expected = {r["id"] for r in checks if r["dimension"] != "D1"}
    rows = review.get("checks", [])
    if len(rows) != len(expected) or {r["id"] for r in rows} != expected:
        raise ValueError("Review checkpoint set differs from rules")
    reviewed = {r["id"]: r for r in rows}
    for row in checks:
        if row["dimension"] == "D1":
            continue
        supplied = reviewed[row["id"]]
        atoms = supplied.get("requirements", [])
        if (len(atoms) != len(row["requirement_ids"])
                or {r["id"] for r in atoms} != set(row["requirement_ids"])):
            raise ValueError("Review requirement inventory mismatch: " + row["id"])
        references = set()
        verdicts = []
        for atom in atoms:
            verdict = atom.get("verdict")
            if verdict not in {"pass", "fail", "inconclusive"} or not atom.get("reason", "").strip():
                raise ValueError("Every reviewed requirement needs a verdict and reason")
            refs = atom.get("evidence", [])
            if not refs:
                raise ValueError("Every reviewed requirement needs evidence")
            for ref in refs:
                file = ref.split("#", 1)[0]
                if file not in seal:
                    raise ValueError("Review must cite sealed collected evidence: " + file)
                if row["dimension"] == "D6" and not file.endswith(".png"):
                    raise ValueError("D6 requires rendered images")
                if row["dimension"] in {"D2", "D3", "D4", "D5"} and not (
                        file.endswith(".png") or (file in runtime["reports"])):
                    raise ValueError("Gameplay review must cite a runtime transcript or image")
                references.add(ref)
            verdicts.append(verdict)
        if not supplied.get("reason", "").strip():
            raise ValueError("Every reviewed checkpoint needs a reason")
        if "inconclusive" in verdicts:
            status, value = "inconclusive_evaluator", None
        else:
            fraction = verdicts.count("pass") / len(verdicts)
            value = round(row["max_score"] * fraction, 6)
            status = "pass" if fraction == 1 else ("partial" if fraction else "fail")
        if supplied.get("verdict") != ("inconclusive" if value is None else
                                       "pass" if status == "pass" else
                                       "fail" if status == "fail" else "partial"):
            raise ValueError("Checkpoint verdict contradicts its requirement reviews")
        row.update(status=status, score=value, reason=supplied["reason"],
                   evidence=sorted(references) + ["review.json"])
    if not runtime["dashboard_well_formed"] and any(
            row["score"] is not None and row["score"] > 0
            for row in checks if row["dimension"] in {"D2", "D3", "D4"}):
        raise ValueError("Positive gameplay scores require the public dashboard observations")
    write(output / "review.json", review)
    return summarize(meta, run_id(output), checks, "Some requirements remain inconclusive")


def main(evaluation=None):
    evaluation = Path(evaluation or Path(__file__).resolve().parents[1]).resolve()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--phase", choices=["run", "collect", "finalize"], default="run")
    parser.add_argument("--review", type=Path)
    parser.add_argument("--trajectory")
    parser.add_argument("--interactive-seconds", type=int, default=0,
                        help="Collect a human-played session through normal input")
    parser.add_argument("--headless", action="store_true", help="No visual evidence; D6 remains pending")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.output is None or not args.output.is_absolute():
        parser.error("--output must be an absolute path")
    output = args.output.resolve()
    public_root = evaluation.parent
    for ancestor in evaluation.parents:
        if all((ancestor / e).is_dir() for e in ["unity", "godot", "roblox", "unreal"]):
            public_root = ancestor
            break
    if output.is_relative_to(public_root):
        parser.error("Output must be outside the public package")
    if args.interactive_seconds < 0 or args.interactive_seconds >= args.timeout:
        parser.error("--interactive-seconds must be nonnegative and shorter than --timeout")
    if args.phase != "finalize":
        if args.project is None or not args.project.is_absolute():
            parser.error("--project must be an absolute path")
        if output.exists() or output.is_relative_to(args.project.resolve()):
            parser.error("Use a new output directory outside the candidate")
        output.mkdir(parents=True)
        (output / "evidence").mkdir()
        write(output / "evidence/bindings.json", bindings(evaluation))
    elif not output.is_dir():
        parser.error("Finalize requires the existing collection directory")
    meta = load(evaluation.parent / "sample.json")
    try:
        result = (finalize(evaluation, meta, args, output) if args.phase == "finalize"
                  else collect(evaluation, meta, args, output))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        write(output / "evidence/error.json", {"error": str(exc)})
        definitions = load(evaluation / "rules.json")["checks"]
        checks = [check_row(d, "inconclusive_evaluator", None, ["evidence/error.json"], str(exc))
                  for d in definitions]
        result = summarize(meta, run_id(output), checks, str(exc), infrastructure=True)
    from validate_score import validate
    validate(result, output, check_evidence=True)
    write(output / "score.json", result)
    print(json.dumps({"classification": result["classification"],
                      "final_score": result["final_score"], "reason": result["reason"]}))
    return 0 if result["evaluation_valid"] else (2 if result["classification"] == "infrastructure_failure" else 3)


if __name__ == "__main__":
    raise SystemExit(main())
