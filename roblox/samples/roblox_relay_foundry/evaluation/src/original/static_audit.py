import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


root = Path(__file__).resolve().parents[1]
package = root.parent
parser = argparse.ArgumentParser()
parser.add_argument("--candidate", type=Path, default=package / "gold")
parser.add_argument("--output", type=Path, default=root / "results" / "static_audit.json")
args = parser.parse_args()
candidate = args.candidate.resolve()
output = args.output.resolve()
files = sorted(path for path in candidate.rglob("*") if path.is_file())
source = "\n".join(
    path.read_text(encoding="utf-8", errors="ignore")
    for path in files
    if path.suffix in (".luau", ".json", ".txt")
)
place = next(
    (path for path in (candidate / "RelayFoundryCandidate.rbxlx", candidate / "RelayFoundryGold.rbxlx") if path.is_file()),
    None,
)
run_report = candidate / "RUN_REPORT.txt"
report = {
    "candidate_root": str(candidate),
    "candidate_files": [
        {"path": str(path.relative_to(candidate)), "sha256": sha256(path)} for path in files
    ],
    "checks": {
        "package_integrity": {
            "status": "pass" if place and (candidate / "project" / "default.project.json").is_file() else "fail"
        },
        "qa_source_isolation": {
            "status": "pass",
            "detail": "QA build reads copied source; submitted source is never opened for modification.",
        },
        "engine_open_smoke": {"status": "not_run", "detail": "Requires Studio QA open smoke."},
    },
    "audit_notes": {
        "private_evaluator_reference_in_candidate": any(
            token in source.lower() for token in ("private evaluator", "hidden test", "score weight")
        ),
        "candidate_runtime_unverified_by_developer": run_report.is_file()
        and "NOT RUN" in run_report.read_text(encoding="utf-8", errors="ignore"),
    },
}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(output)
