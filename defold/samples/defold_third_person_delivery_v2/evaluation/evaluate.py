"""Evaluate a Defold candidate and emit an evidence-bound D1-D6 report."""
from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
import platform
import sys
import uuid
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "src"))
sys.path.insert(0, str(HERE))
from score_adapter import convert
from validate_score import validate
from visual_review import apply_review, capture_inventory, reference_binding

EXCLUDED = {".git", ".internal", ".cache", "__pycache__", "build", ".pytest_cache"}


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=True, allow_nan=False) + "\n", encoding="utf-8")


def binding(root):
    root = Path(root).resolve()
    files = {}
    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED)
        for name in dirs + names:
            path = Path(directory) / name
            if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
                raise ValueError("Submitted projects must not contain linked paths.")
        for name in sorted(names):
            path = Path(directory) / name
            files[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def native_preflight(meta):
    module = importlib.import_module(meta["evaluation"]["native_entry"])
    if meta["evaluation"]["native_entry"] == "runner":
        return module.validate_package(HERE, dict(os.environ, PYTHONPATH=str(HERE / "src"),
                                                 PYTHONDONTWRITEBYTECODE="1"))
    return module.validate_package(HERE)


def external_output(project, output):
    if project == output or project in output.parents or output in project.parents:
        raise ValueError("Project and output directories must not overlap.")
    # Protect the engine/distribution root, including sibling samples.
    distribution = next((parent for parent in HERE.parents if parent.name == "opensource"), HERE.parents[2])
    if distribution == output or distribution in output.parents or output in distribution.parents:
        raise ValueError("Output must be outside the distributed engine package.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--phase", choices=("collect", "finalize"), default="collect")
    parser.add_argument("--d6-review", type=Path, help="Three-round visual review JSON; see evaluation/d6/protocol.json")
    args = parser.parse_args()
    meta = read(HERE.parent / "sample.json")
    if args.project is None or args.output is None or not args.project.is_absolute() or not args.output.is_absolute():
        parser.error("--project and --output must be absolute paths")
    project, output = args.project.resolve(), args.output.resolve()
    try:
        external_output(project, output)
        if not project.is_dir():
            raise ValueError("Candidate directory does not exist.")
        if args.phase == "collect":
            if output.exists():
                raise ValueError("Collection output must be a new directory.")
        elif not (output / "evidence/binding.json").is_file():
            raise ValueError("Finalization requires an existing collection directory.")
        if args.phase == "finalize" and args.d6_review is None:
            raise ValueError("Finalization requires --d6-review.")
        identity = binding(project)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    infrastructure, reason = False, ""
    if args.phase == "collect":
        output.mkdir(parents=True)
        write(output / "evidence/binding.json", {
            "sample_id": meta["sample_id"], "run_id": uuid.uuid4().hex,
            "candidate_sha256": identity, "references": reference_binding(HERE.parent),
            "evaluator_version": meta["evaluation"]["version"],
        })
        try:
            native_preflight(meta)
            if platform.system() != "Darwin" or platform.machine() != "arm64":
                raise RuntimeError("Dynamic Defold evaluation requires the macOS arm64 toolchain specified in the engine README.")
            module = importlib.import_module(meta["evaluation"]["native_entry"])
            code = module.main(HERE, ["--project", str(project), "--output", str(output / "native")])
            infrastructure = code == 2
            if binding(project) != identity:
                raise RuntimeError("Candidate source changed during collection.")
        except (OSError, ValueError, RuntimeError, KeyError, ImportError) as error:
            infrastructure, reason = True, str(error)
            write(output / "evidence/collection-error.json", {"reason": reason})
        write(output / "evidence/visual-captures.json", capture_inventory(output))
    else:
        receipt = read(output / "evidence/binding.json")
        if (receipt["candidate_sha256"] != identity or receipt["sample_id"] != meta["sample_id"]
                or receipt["evaluator_version"] != meta["evaluation"]["version"]
                or receipt["references"] != reference_binding(HERE.parent)):
            parser.error("Candidate, evaluator or reference identity differs from the collection.")
        previous = read(output / "score.json")
        native_path = output / "native/score.json"
        native_status = read(native_path).get("evaluation_status") if native_path.is_file() else None
        infrastructure = native_status in {None, "infrastructure_invalid", "evaluator_invalid"}
        reason = previous["reason"] if infrastructure else ""
    try:
        result = convert(HERE, output, meta, reason, infrastructure)
        if args.d6_review is not None:
            if infrastructure:
                raise ValueError("Visual review cannot finalize an infrastructure failure.")
            apply_review(result, args.d6_review.resolve(), HERE.parent, output)
        validate(result, output, check_evidence=True)
    except (OSError, ValueError, KeyError, TypeError) as error:
        result = convert(HERE, output, meta, "Result or visual review rejected: " + str(error), True)
        write(output / "evidence/result-error.json", {"reason": str(error)})
        validate(result, output, check_evidence=True)
    write(output / "score.json", result)
    print(json.dumps({"classification": result["classification"], "final_score": result["final_score"],
                      "score": str(output / "score.json")}))
    return 2 if result["classification"] == "infrastructure_failure" else 0 if result["evaluation_valid"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
