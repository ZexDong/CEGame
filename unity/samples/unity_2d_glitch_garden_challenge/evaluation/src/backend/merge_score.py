"""Validate fixed visual evidence and emit the same score/v2 as every engine."""
import argparse
import json
import re
import shutil
from pathlib import Path
from format_score import emit, load, sha

KEYS = ["Scene completeness and asset assembly", "Composition and layout", "Scale, hierarchy, and clarity", "Style and color consistency", "Overall polish"]

def verified_visual(ev, folder):
    value = load(folder / "d6.json")
    if value["reference_sha256"] != sha(ev / "reference.png"):
        raise ValueError("Visual reference differs")
    if value["status"] == "no_candidate_frame_product_blocked":
        automatic = load(folder / "automatic-score.json")
        rows = {r["id"]: r["state"] for r in automatic["leaves"]}
        if automatic.get("infrastructure_error") or value["score"] != 0 or value.get("model_call") is not False:
            raise ValueError("A provider failure is not a candidate visual zero")
        if (folder / "main-play.png").exists() or not any(
                rows.get(key) == "FAIL_OBSERVED" for key in ["d1.import", "d1.scene"]):
            raise ValueError("No-frame zero lacks independently verified compile/scene defect")
        if not (folder / "build.log").is_file():
            raise ValueError("No raw compile/scene evidence")
        return value
    if value["status"] != "reviewed":
        raise ValueError("A no-frame result must be independently adjudicated, not cached as a review")
    if value["model"] != "gpt-5.6-sol" or value["rounds"] != 1:
        raise ValueError("Wrong visual review protocol")
    if value["candidate_sha256"] != sha(folder / "main-play.png") or value["raw_response_sha256"] != sha(folder / "d6-response.json"):
        raise ValueError("Visual image/response binding mismatch")
    raw = load(folder / "d6-response.json")
    if raw.get("model") and raw["model"] != "gpt-5.6-sol":
        raise ValueError("Unexpected actual visual-review model")
    output = "\n".join(c.get("text", "") for item in raw.get("output", [])
                       for c in item.get("content", []) if c.get("type") == "output_text")
    parsed = {}
    for key in KEYS:
        match = re.search(re.escape(key) + r"[::]\s*([0-9.]+)\s*/\s*2", output)
        if not match or float(match[1]) not in [0, .5, 1, 1.5, 2]:
            raise ValueError("Unparseable frozen visual rubric")
        parsed[key] = float(match[1])
    if parsed != value["categories"] or sum(parsed.values()) != value["score"]:
        raise ValueError("Visual categories differ from raw response")
    return value

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evaluation", required=True, type=Path)
    parser.add_argument("--reuse-visual-evaluation", type=Path)
    args = parser.parse_args()
    ev, out = Path(__file__).resolve().parent, args.evaluation.resolve()
    binding = load(out / "binding.json")
    from session_core import evaluator_digest
    bound = {r["path"]: r["sha256"] for r in binding["evaluator"]}
    if any(bound.get(r["path"]) != r["sha256"] for r in evaluator_digest(ev)):
        raise ValueError("An evaluation dependency changed after runtime execution")
    if args.reuse_visual_evaluation:
        previous = args.reuse_visual_evaluation.resolve()
        prior = load(previous / "binding.json")
        if prior["candidate"] != binding["candidate"]:
            raise ValueError("Cached D6 belongs to a different candidate")
        prior_files = {r["path"]: r["sha256"] for r in prior["evaluator"]}
        for filename in ["reference.png", "d6-prompt.txt"]:
            if prior_files.get(filename) != sha(ev / filename):
                raise ValueError("Cached visual protocol is not unchanged")
        value = verified_visual(ev, previous)
        folder = out / "visual-reused"
        folder.mkdir(exist_ok=False)
        for filename in ["d6.json", "main-play.png", "main-play-state.json",
                         "d6-response.json", "d6-review.txt", "d6-request-binding.json"]:
            if (previous / filename).exists():
                shutil.copyfile(previous / filename, folder / filename)
        (folder / "reuse-binding.json").write_text(json.dumps(dict(
            source_evaluation=previous.name, candidate_hashes_identical=True,
            reference_and_prompt_identical=True, new_api_calls=0,
            rationale="Same immutable candidate and predeclared single-state visual protocol; no cherry-picked second review.",
            source_binding_sha256=sha(previous / "binding.json")), indent=2), encoding="utf-8")
        if value["status"] == "reviewed":
            files = ["d6.json", "main-play.png", "d6-response.json", "reuse-binding.json"]
        else:
            files = ["d6.json", "reuse-binding.json"]
        visual = dict(score=value["score"], reused=True,
            evidence=["visual-reused/" + f for f in files] + (
                ["automatic-score.json", "build.log"] if value["status"] != "reviewed" else []))
    else:
        value = verified_visual(ev, out)
        visual = dict(score=value["score"], reused=False,
                      evidence=["d6.json", "main-play.png", "d6-response.json"] if value["status"] == "reviewed"
                               else ["d6.json", "automatic-score.json", "build.log"])
    result = emit(ev, out, visual)
    print(json.dumps({d: v["score"] for d, v in result["dimensions"].items()}))
    raise SystemExit(0 if result["evaluation_valid"] else 3)

if __name__ == "__main__":
    main()
