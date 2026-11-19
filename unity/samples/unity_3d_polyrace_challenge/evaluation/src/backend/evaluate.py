import argparse
import json
import subprocess
import sys
from pathlib import Path
sys.dont_write_bytecode = True
from session_core import Evaluation as CoreEvaluation
from coverage_common import CommonChecks
from coverage_polyrace import PolyRaceChecks
from format_score import emit

class Evaluation(CommonChecks, PolyRaceChecks, CoreEvaluation):
    pass

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--editor", required=True)
    parser.add_argument("--reuse-build", type=Path)
    parser.add_argument("--no-nunit", action="store_true")
    parser.add_argument("--case", action="append", help="Diagnostic subset only, never a final score")
    parser.add_argument("--review-d6", action="store_true")
    args = parser.parse_args()
    ev, out = Path(__file__).resolve().parent, args.output.resolve()
    evaluation = Evaluation(ev, args.project.resolve(), out, args.editor,
                            not args.no_nunit, args.reuse_build.resolve() if args.reuse_build else None)
    evaluation.only_cases = set(args.case or [])
    evaluation.run()
    result = emit(ev, out)
    if args.review_d6 and result["classification"] != "infrastructure_failure":
        if not json.loads((out/"automatic-score.json").read_text(encoding="utf-8"))["automatic_complete"]:
            raise SystemExit(3)
        subprocess.run([sys.executable, str(ev/"review_d6.py"), "--evaluation", str(out)], check=True)
        raise SystemExit(subprocess.run([sys.executable, str(ev/"merge_score.py"), "--evaluation", str(out)]).returncode)
    raise SystemExit(0 if result["evaluation_valid"] else 2 if result["classification"] == "infrastructure_failure" else 3)

if __name__ == "__main__":
    main()
