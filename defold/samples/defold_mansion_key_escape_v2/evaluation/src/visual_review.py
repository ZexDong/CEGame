"""Validate candidate-bound visual judge responses and aggregate D6."""
from __future__ import annotations

import hashlib
import json
import math
import re
import statistics
from pathlib import Path

CRITERIA = ("scene_completeness", "composition", "scale_and_layering", "style_and_color", "overall_finish")


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inside(root, relative):
    if not isinstance(relative, str) or "\\" in relative or ":" in relative:
        raise ValueError("Expected a result-relative path using forward slashes.")
    path = (root / relative).resolve()
    if path == root or root not in path.parents or not path.is_file():
        raise ValueError("Missing or escaped evidence: " + relative)
    return path


def reference_binding(sample):
    protocol = read(sample / "evaluation/d6/protocol.json")
    paths = ["evaluation/d6/protocol.json", "evaluation/d6/prompt.txt"] + protocol["references"]
    return {rel: sha(inside(sample, rel)) for rel in paths}


def capture_inventory(output):
    rows = {}
    native = output / "native"
    for path in sorted(native.rglob("*.png")):
        rel = path.relative_to(output).as_posix()
        if not (rel.startswith("native/checkpoint/trajectories/") or rel.startswith("native/playtest/captures/")):
            continue
        data = path.read_bytes()
        if len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n":
            rows[rel] = {"sha256": sha(path), "width": int.from_bytes(data[16:20], "big"),
                         "height": int.from_bytes(data[20:24], "big")}
    return rows


def apply_review(result, review_path, sample, output):
    review = read(review_path)
    binding = read(output / "evidence/binding.json")
    protocol = read(sample / "evaluation/d6/protocol.json")
    if (review.get("candidate_sha256") != binding["candidate_sha256"]
            or review.get("reference_hashes") != binding["references"]):
        raise ValueError("D6 candidate/reference identity mismatch.")
    if review.get("model") != protocol["judge_model"] or review.get("settings") != protocol["judge_settings"]:
        raise ValueError("D6 judge model/settings differ from the fixed protocol.")
    states = review.get("states", {})
    if not isinstance(states, dict) or set(states) != set(protocol["states"]) or any(
            not re.fullmatch(r"[A-Za-z0-9_.-]+", label) for label in states):
        raise ValueError("D6 must cover exactly the states registered in the protocol.")
    inventory = read(output / "evidence/visual-captures.json")
    current = capture_inventory(output)
    if inventory != current:
        raise ValueError("Collected visual evidence changed after collection.")
    images = []
    for row in states.values():
        rel = row.get("image")
        if rel not in inventory or row.get("sha256") != inventory[rel]["sha256"]:
            raise ValueError("D6 screenshot is not bound to the native collection.")
        images.append(rel)
    if len(set(images)) != len(images):
        raise ValueError("D6 states must use different native captures.")
    rounds = review.get("rounds")
    if not isinstance(rounds, list) or len(rounds) != 3:
        raise ValueError("D6 requires three independent rounds.")
    used_requests, raw_files, observed = set(), [], {key: [] for key in states}
    for round_ in rounds:
        if set(round_) != set(states):
            raise ValueError("Each D6 round must cover the same state set.")
        for state, response in round_.items():
            request = response.get("request_id")
            if not isinstance(request, str) or not request or request in used_requests:
                raise ValueError("D6 responses must have unique request IDs.")
            used_requests.add(request)
            raw = inside(output, response["raw_response"])
            if sha(raw) != response["raw_response_sha256"]:
                raise ValueError("D6 response digest mismatch.")
            payload = read(raw)
            if (payload.get("request_id") != request or payload.get("model") != review["model"]
                    or payload.get("state") != state
                    or payload.get("candidate_sha256") != binding["candidate_sha256"]
                    or payload.get("image_sha256") != states[state]["sha256"]
                    or payload.get("reference_hashes") != binding["references"]
                    or not payload.get("rationale") or not payload.get("raw_provider_response")):
                raise ValueError("D6 raw response receipt lacks matching identity or provider evidence.")
            scores = payload.get("scores", {})
            if set(scores) != set(CRITERIA):
                raise ValueError("D6 rubric must contain all five criteria.")
            for key, score in scores.items():
                if type(score) not in (int, float) or not math.isfinite(score) or score not in (0, .5, 1, 1.5, 2):
                    raise ValueError("D6 criterion scores must be 0..2 in half-point steps.")
            observed[state].append(sum(scores.values()))
            raw_files.append(response["raw_response"])
    destination = output / "evidence/d6-review.json"
    destination.write_text(json.dumps(review, indent=2) + "\n", encoding="utf-8")
    # Each registered state is a leaf. Its credit is the median of three totals.
    used = 0
    for i, key in enumerate(states):
        maximum = round(10 - used, 6) if i == len(states) - 1 else round(10 / len(states), 6)
        used += maximum
        ratio = statistics.median(observed[key]) / 10
        points = round(maximum * ratio, 6)
        state = "pass" if points == maximum else "fail" if points == 0 else "partial"
        result["checks"].append({
            "id": "D6-" + key, "requirement_ids": ["D6-PRESENTATION"],
            "dimension": "D6", "max_score": maximum, "score": points,
            "status": state, "reason": "Median of three independent five-item judge totals for this state.",
            "blocked_by": [], "evidence": ["evidence/d6-review.json"] + images + sorted(set(raw_files)),
        })
    evidence = ["evidence/d6-review.json"] + images + sorted(set(raw_files))
    result["dimensions"]["D6"] = {"max_score": 10, "score": round(sum(c["score"] for c in result["checks"]
                                                       if c["dimension"] == "D6"), 6),
                                  "status": "complete", "evidence": evidence}
    if all(d["status"] == "complete" for d in result["dimensions"].values()):
        result.update(evaluation_valid=True, classification="scored", reason="All six dimensions have resolved evidence.",
                      final_score=round(sum(d["score"] for d in result["dimensions"].values()), 6))
