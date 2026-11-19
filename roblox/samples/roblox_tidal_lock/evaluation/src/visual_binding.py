"""Bind externally obtained D6 evidence to a candidate and the frozen protocol.

This validates recorded artifacts, not the identity of a remote service. Operators
must retain actual provider response metadata. A numeric score alone is not evidence.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import shutil


SKIP = {".git", "__pycache__", "Library", "Temp", "Logs", ".godot", "Binaries",
        "Intermediate", "Saved", "DerivedDataCache"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def candidate_digest(source):
    source = Path(source).resolve()
    if source.is_file():
        return sha(source)
    if not source.is_dir():
        raise ValueError("Candidate does not exist")
    files = {}
    for path in sorted(source.rglob("*")):
        if any(part in SKIP for part in path.relative_to(source).parts):
            continue
        if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
            raise ValueError("Linked candidate paths are unsupported")
        if path.is_file():
            files[path.relative_to(source).as_posix()] = sha(path)
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def validate_visual(document, evaluation, candidate, output):
    """Read an external visual JSON plus its result-relative evidence closure."""
    document, evaluation, output = Path(document).resolve(), Path(evaluation), Path(output)
    value = json.loads(document.read_text(encoding="utf-8-sig"))
    protocol = json.loads((evaluation / "d6/protocol.json").read_text(encoding="utf-8-sig"))
    scores = value.get("round_scores")
    if not isinstance(scores, list) or len(scores) != 3 or any(
        type(x) not in (int, float) or not math.isfinite(x) or not 0 <= x <= 10 for x in scores
    ):
        raise ValueError("D6 requires three finite round_scores in [0,10]")
    total = value.get("final_score")
    mean = round(sum(round(x, 1) for x in scores) / 3, 1)
    if type(total) not in (int, float) or not math.isfinite(total) or abs(total - mean) > 1e-6:
        raise ValueError("D6 final_score must equal the fixed three-round mean")
    expected = {
        "candidate_sha256": candidate_digest(candidate),
        "prompt_sha256": sha(evaluation / "d6" / protocol.get("prompt", "prompt.txt")),
        "reference_sha256": sha(evaluation / "d6" / protocol["reference_image"]["path"]),
        "reviewer_model": protocol["reviewer_model"],
    }
    binding = value.get("binding", {})
    if any(binding.get(k) != v for k, v in expected.items()):
        raise ValueError("D6 candidate/prompt/reference/reviewer binding is absent or mismatched")
    screenshots = value.get("screenshots", [])
    responses = value.get("responses", [])
    if len(screenshots) != protocol["candidate_images_per_round"] or len(responses) != 3:
        raise ValueError("D6 requires four screenshot records and three provider response records")
    image_hashes = [item.get("sha256") if isinstance(item, dict) else None for item in screenshots]
    if any(not isinstance(h, str) for h in image_hashes) or len(set(image_hashes)) != len(image_hashes):
        raise ValueError("D6 needs four distinct captured state images")
    destination = output / "evidence" / "visual-artifacts"
    destination.mkdir(parents=True, exist_ok=True)
    root = document.parent
    for index, record in enumerate(screenshots + responses):
        if not isinstance(record, dict) or not isinstance(record.get("path"), str):
            raise ValueError("D6 artifact record requires path and sha256")
        rel = Path(record["path"])
        if rel.is_absolute() or ".." in rel.parts:
            raise ValueError("D6 artifact paths must be relative to the visual JSON")
        path = (root / rel).resolve()
        if not path.is_relative_to(root) or not path.is_file() or not path.stat().st_size:
            raise ValueError("Missing/escaped D6 evidence file")
        if sha(path) != record.get("sha256"):
            raise ValueError("D6 artifact hash mismatch")
        if index >= len(screenshots):
            round_index = index - len(screenshots)
            response = json.loads(path.read_text(encoding="utf-8-sig"))
            # Provider envelopes can be retained separately; this is the parsed,
            # unchanged five-criterion answer alongside its real response ID.
            criteria = response.get("criteria")
            if not isinstance(criteria, list) or len(criteria) != 5 or any(
                type(x) not in (int, float) or not math.isfinite(x) or not 0 <= x <= 2 for x in criteria
            ):
                raise ValueError("D6 response needs five numeric criteria in [0,2]")
            if round(sum(criteria), 1) != round(scores[round_index], 1):
                raise ValueError("D6 response criteria do not sum to its round score")
            if not response.get("response_id") or response.get("model") != expected["reviewer_model"]:
                raise ValueError("D6 response needs actual response_id and recorded model")
            if response.get("image_sha256") != image_hashes or response.get("binding") != expected:
                raise ValueError("D6 response is not bound to these images/candidate/protocol")
        copied = destination / (str(index) + "-" + path.name)
        shutil.copyfile(path, copied)
        record["path"] = copied.relative_to(output).as_posix()
    value["binding"] = expected
    target = output / "evidence/visual.json"
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return value
