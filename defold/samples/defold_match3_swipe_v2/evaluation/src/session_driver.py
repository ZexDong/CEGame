"""Run the original campaign evaluator from a self-contained sample package."""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def read(path):
    return json.loads(Path(path).read_text())


def validate_package(evaluation):
    sample = evaluation.parent
    metadata = read(sample / "sample.json")
    rules = read(evaluation / "rules.json")
    coverage = read(evaluation / "coverage.json")
    sample_id = metadata["sample_id"]
    required = [
        sample / "input/GDD.md",
        sample / "input/INITIAL_AGENT_PROMPT.md",
        sample / "input/campaign.json",
        sample / "input/naming-tables.json",
        evaluation / "requirements.txt",
        evaluation / "score.schema.json",
        evaluation / "src/framework/defold_campaign_evaluation/run.py",
        evaluation / "src/framework/defold_campaign_playtest/session.py",
    ]
    missing = [str(path.relative_to(sample)) for path in required if not path.is_file()]
    if missing:
        raise ValueError("Missing packaged files: " + ", ".join(missing))
    if sample_id != rules.get("task_id") or sample_id != coverage.get("task_id"):
        raise ValueError("Sample, rules and coverage task IDs differ")
    if rules.get("status") != "frozen":
        raise ValueError("Rules are not frozen")
    dimensions = rules.get("dimensions")
    if dimensions != {"D1": 10, "D2": 30, "D3": 20, "D4": 20, "D5": 10, "D6": 10}:
        raise ValueError("Unexpected dimension maxima")
    return {
        "package_valid": True,
        "sample_id": sample_id,
        "check_count": len(rules.get("checks", [])),
        "engine_run": False,
        "nonvisual_max": 90,
        "D6": "not_run",
    }


def prepare_runtime(evaluation, runtime):
    sample = evaluation.parent
    sample_id = read(sample / "sample.json")["sample_id"]
    shutil.copytree(evaluation / "src/framework", runtime / "framework")
    task = runtime / "samples" / sample_id
    shutil.copytree(sample / "input", task / "input")
    task_evaluation = task / "evaluation"
    task_evaluation.mkdir(parents=True)
    shutil.copy2(evaluation / "rules.json", task_evaluation / "rules.json")
    shutil.copy2(evaluation / "coverage.json", task_evaluation / "coverage.json")

    lock_dir = runtime / ".locks"
    lock_dir.mkdir(parents=True)
    shared_lock = Path(tempfile.gettempdir()) / "vibe-gaming-defold-campaign-playtest.lock"
    shared_lock.touch(exist_ok=True)
    (lock_dir / "desktop-playtest.lock").symlink_to(shared_lock)
    return sample_id


def main(evaluation, argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args(argv)
    evaluation = Path(evaluation).resolve()
    try:
        validation = validate_package(evaluation)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"package_valid": False, "reason": str(error)}))
        return 2
    if args.validate_only:
        print(json.dumps(validation))
        return 0
    if args.project is None or args.output is None:
        parser.error("--project and --output are required unless --validate-only is used")
    if not args.project.is_absolute() or not args.output.is_absolute():
        parser.error("--project and --output must be absolute paths")
    project = args.project.resolve()
    output = args.output.resolve()
    sample = evaluation.parent
    if not project.is_dir() or output.exists():
        parser.error("project must exist and output must be a new directory")
    if project == output or project in output.parents or output in project.parents:
        parser.error("project and output must not overlap")
    if sample == output or sample in output.parents or output in sample.parents:
        parser.error("output must be outside the distributed sample")

    with tempfile.TemporaryDirectory(prefix="defold-campaign-evaluation-") as temporary:
        runtime = Path(temporary)
        sample_id = prepare_runtime(evaluation, runtime)
        command = [
            sys.executable,
            "-B",
            "-m",
            "framework.defold_campaign_evaluation.run",
            "--sample",
            sample_id,
            "--candidate",
            str(project),
            "--output",
            str(output),
        ]
        completed = subprocess.run(
            command,
            cwd=runtime,
            env={**os.environ, "PYTHONPATH": str(runtime), "PYTHONDONTWRITEBYTECODE": "1"},
        )
    return completed.returncode
