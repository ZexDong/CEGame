"""Portable entry point for the minimal Unity distribution.

Only a private workspace receives evaluator injection. The submitted project and
the distributed input are never evaluated in place.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
import uuid

sys.dont_write_bytecode = True
MAXIMA = dict(zip(("D1", "D2", "D3", "D4", "D5", "D6"), (10, 30, 20, 20, 10, 10)))
SKIP = {".git", "Library", "Temp", "TempHost", "Logs", "UserSettings",
        "obj", "bin", ".vs", "__pycache__"}


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def tree(root):
    result = {}
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP)
        for name in sorted(files):
            p = Path(directory) / name
            if p.is_symlink():
                raise ValueError("Symbolic links are not accepted")
            result[p.relative_to(root).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


def copy(source, destination):
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(*SKIP))


def native_output(runtime):
    # Signs accepts only tmp/, while other native runners accept tmp/ or runs/.
    # The common denominator avoids weakening any native boundary check.
    return runtime / "tmp" / "measurement"


def validate_output(result, ev, out):
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "portable_score_validator", ev / "validate_score.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.validate(result, out, require_final=result["evaluation_valid"],
                    check_evidence=True)


def dimensions(native):
    values = native.get("dimensions", {})
    if isinstance(values, list):
        values = {x["id"]: x for x in values}
    result = {}
    for dimension in MAXIMA:
        v = values.get(dimension, native.get(dimension))
        result[dimension] = v.get("score") if isinstance(v, dict) else v
    return result


def normalize(native, sample, evidence, failure=None):
    """Preserve native dimension aggregates, never manufacture leaf observations.

    Legacy backends have different checkpoint granularity/rounding. Their exact
    checkpoints remain in the bound native document; these six adapter checks
    are explicitly dimension aggregates, not invented additional gameplay tests.
    """
    values = dimensions(native)
    valid = bool(native.get("evaluation_valid", native.get("valid_score",
                 native.get("scoring_execution_valid", False)))) and not failure
    checks = []
    dims = {}
    for dimension, maximum in MAXIMA.items():
        value = values[dimension]
        if not valid:
            value = None
        if value is not None:
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError("Non-numeric native dimension")
            if not 0 <= value <= maximum:
                raise ValueError("Native dimension outside fixed maximum")
            value = round(value, 6)
        state = "inconclusive_evaluator" if value is None else (
            "pass" if value == maximum else "fail" if value == 0 else "partial")
        checks.append(dict(
            id=dimension.lower() + ".native_dimension_aggregate",
            requirement_ids=sample["dimension_requirements"].get(dimension, ["DELIVERY"]),
            dimension=dimension, max_score=maximum, score=value, status=state,
            blocked_by=[], reason=(
                "Native backend dimension aggregate; exact requirement checkpoints, "
                "failure/blocking attribution and historical rounding are in the bound "
                "native evidence. This adapter adds no gameplay credit or score cap."),
            evidence=[evidence]))
        dims[dimension] = dict(score=value, max_score=maximum,
                               status="complete" if value is not None else "incomplete",
                               evidence=[evidence])
    # A conversion cannot promote historical qualification or incomplete D6.
    qualified = sample.get("coverage_status") == "qualified"
    complete = valid and all(x["score"] is not None for x in dims.values())
    any_failure = any(x["score"] is not None and x["score"] < x["max_score"] for x in checks)
    return dict(
        schema_version="2.1", sample_id=sample["sample_id"],
        sample_version=sample["sample_version"],
        evaluator_version=sample["evaluator_version"], run_id="evaluation-" + uuid.uuid4().hex[:12],
        evaluation_valid=complete,
        classification=("candidate_failure" if any_failure else "scored") if complete else
                       ("infrastructure_failure" if failure or not valid else "incomplete"),
        coverage_status="qualified" if qualified else "not_reviewed",
        coverage_evidence=["evaluator-binding.json"],
        reason=failure or ("Native measurement is incomplete; "
                           "missing D6 remains null." if not complete else
                           "All six native dimension observations are complete. Coverage labels are informational."),
        dimensions=dims, checks=checks,
        final_score=round(sum(x["score"] for x in dims.values()), 6) if complete else None,
        max_score=100,
        extensions=dict(native_evidence=evidence, legacy_conversion=True,
                        dimension_aggregation="Preserve the backend's exact dimension totals",
                        qualification_scope="Current run evidence and fixed evaluator/input bindings"))


def run(args):
    sample_root = Path(__file__).resolve().parents[1]
    ev = sample_root / "evaluation"
    sample = load(sample_root / "sample.json")
    if not args.output:
        raise ValueError("--output is required")
    out = Path(args.output).resolve()
    if out == sample_root or sample_root in out.parents:
        raise ValueError("Do not create results inside the public sample")
    if args.project:
        project_boundary = Path(args.project).resolve()
        if out == project_boundary or project_boundary in out.parents:
            raise ValueError("Output must not be inside the submitted project")
    if out.exists():
        raise ValueError("Output must be a new directory")
    out.mkdir(parents=True)
    if args.import_native:
        # Evidence-only conversion is deliberately named and never called a rerun.
        p = Path(args.import_native).resolve()
        shutil.copy2(p, out / "native-score.json")
        write(out / "evaluator-binding.json", dict(
            operation="retained_evidence_format_conversion_not_game_execution",
            native_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
            source_evaluator_version=load(p).get("evaluator_revision"),
            qualification_scope="Current run evidence and fixed evaluator/input bindings"))
        result = normalize(load(p), sample, "native-score.json")
        # Imported numbers are a format conversion, not a new candidate run.
        # Keep the original document, but do not certify an unbound score.
        result.update(evaluation_valid=False, classification="incomplete", final_score=None,
                      reason="Retained native evidence conversion only; no fresh candidate/build/runtime binding was verified.")
        result["extensions"]["operation"] = "retained_evidence_conversion_not_fresh_execution"
        validate_output(result, ev, out)
        write(out / "score.json", result)
        return 0 if result["evaluation_valid"] else 3
    if not args.project:
        raise ValueError("--project is required")
    project = Path(args.project).resolve()
    if project == sample_root / "input" or (sample_root / "input") in project.parents:
        raise ValueError("Do not evaluate the published input in place")
    failure = None
    (out / "execution.log").touch()
    try:
        write(out / "evaluator-binding.json", dict(
            operation="preparing_not_yet_executed",
            adapter_version=sample["evaluator_version"]))
        before = tree(project)
        runtime = out / "workspace"
        backend_source = sample_root / sample["backend_directory"]
        backend = runtime / "demos" / sample["sample_id"] / "evaluation"
        native_ev = backend / sample["native_subdirectory"] if sample.get("native_subdirectory") else backend
        copy(backend_source, native_ev)
        backend.parent.mkdir(parents=True, exist_ok=True)
        copy(sample_root / "input", backend.parent / "input")
        if (native_ev / "parent-reference").exists():
            copy(native_ev / "parent-reference", backend / "reference")
        support = ev / "support"
        if support.exists():
            for child in support.iterdir():
                if child.is_dir():
                    copy(child, runtime / child.name)
                else:
                    shutil.copy2(child, runtime / child.name)
        candidate = runtime / "tmp" / "candidate"
        copy(project, candidate)
        (runtime / "runs").mkdir(parents=True)
        native_out = native_output(runtime)
        entry = native_ev / sample["native_entry"]
        args_list = []
        if entry.suffix == ".py":
            args_list = [sys.executable, "-B", str(entry), "--project", str(candidate),
                         "--output", str(native_out), "--editor", args.editor]
            if args.review_d6:
                args_list.append("--review-d6")
        else:
            args_list = [args.powershell, "-NoLogo", "-NoProfile", "-File", str(entry)]
            args_list += [sample["native_project_argument"], str(candidate),
                          sample["native_output_argument"], str(native_out)]
            if sample.get("accepts_engine_arguments", True):
                args_list += ["-UnityEditorPath", args.editor, "-UnityCliPath", args.unity_cli]
        write(out / "evaluator-binding.json", dict(
            operation="fresh_native_backend_execution", argv=args_list,
            adapter_version=sample["evaluator_version"],
            candidate_before=before, backend=tree(backend_source),

            qualification_scope="Current run evidence and fixed evaluator/input bindings"))
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["GAMECREATE_PYTHON"] = sys.executable
        env["UNITY_EDITOR"] = args.editor
        env["UNITY_CLI"] = args.unity_cli
        if entry.suffix == ".py" and args.reuse_build:
            args_list += ["--reuse-build", str(Path(args.reuse_build).resolve())]
        # Record the actual argv, including explicitly requested bound build reuse.
        binding = load(out / "evaluator-binding.json")
        binding["argv"] = args_list
        write(out / "evaluator-binding.json", binding)
        with (out / "execution.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(args_list, stdout=log, stderr=subprocess.STDOUT, env=env)
            code = process.wait(timeout=args.timeout)
        write(out / "process.json", dict(pid=process.pid, exit_code=code, argv=args_list))
        native_path = native_out / "score.json"
        if not native_path.exists():
            raise RuntimeError("Native evaluator did not produce score.json; see execution.log")
        native = load(native_path)
        if code not in (0, 3):
            raise RuntimeError("Native evaluator failed with exit code " + str(code))
        if entry.suffix == ".py" and args.reuse_visual_evaluation:
            with (out / "visual-merge.log").open("w", encoding="utf-8") as log:
                merged = subprocess.run(
                    [sys.executable, "-B", str(native_ev / "merge_score.py"),
                     "--evaluation", str(native_out), "--reuse-visual-evaluation",
                     str(Path(args.reuse_visual_evaluation).resolve())],
                    stdout=log, stderr=subprocess.STDOUT, env=env)
            if merged.returncode:
                raise RuntimeError("Bound visual evidence reuse failed; see visual-merge.log")
            native = load(native_path)
        if entry.suffix == ".py" and native.get("schema_version") == "2.0":
            # Preserve the exact detailed native v2 checks, rebasing evidence only.
            result = native
            prefix = native_out.relative_to(out).as_posix() + "/"
            for d in result["dimensions"].values():
                d["evidence"] = [prefix + p for p in d.get("evidence", [])]
            for c in result["checks"]:
                c["evidence"] = [prefix + p for p in c.get("evidence", [])]
            result["coverage_evidence"] = [prefix + p for p in result.get("coverage_evidence", [])]
        else:
            result = normalize(native, sample, native_path.relative_to(out).as_posix())
        if tree(project) != before:
            raise RuntimeError("Submitted project changed during measurement")
    except Exception:
        if "process" in locals() and process.poll() is None:
            process.kill()
            process.wait()
        failure = traceback.format_exc()
        with (out / "execution.log").open("a", encoding="utf-8") as log:
            log.write("\n" + failure)
        result = normalize({}, sample, "execution.log", failure)
    validate_output(result, ev, out)
    write(out / "score.json", result)
    print(json.dumps(dict(evaluation_valid=result["evaluation_valid"],
                          classification=result["classification"],
                          final_score=result["final_score"])))
    return 0 if result["evaluation_valid"] else 2 if failure else 3


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project")
    parser.add_argument("--output")
    parser.add_argument("--import-native", help="Evidence conversion only; not a fresh run")
    parser.add_argument("--editor", default=os.environ.get("UNITY_EDITOR", "Unity.exe"))
    parser.add_argument("--unity-cli", default=os.environ.get("UNITY_CLI", "unity.exe"))
    parser.add_argument("--powershell", default=os.environ.get("POWERSHELL", "pwsh"))
    parser.add_argument("--review-d6", action="store_true")
    parser.add_argument("--reuse-build", help="Modern backend only; source and host hashes must match")
    parser.add_argument("--reuse-visual-evaluation", help="Modern backend only; same candidate and fixed image/protocol")
    parser.add_argument("--timeout", type=int, default=7200)
    return run(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
