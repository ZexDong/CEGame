#!/usr/bin/env python3
"""Fail closed if D1-D5 evaluator source can bypass normal player input."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


FORBIDDEN = {
    "teleport_or_direct_motion": [
        r"\bPivotTo\s*\(", r"\bMoveTo\s*\(",
        r"(?:\.|\[\s*[\"'])CFrame(?:[\"']\s*\])?\s*=(?!=)",
        r"(?:\.|\[\s*[\"'])Position(?:[\"']\s*\])?\s*=(?!=)",
        r"(?:\.|\[\s*[\"'])AssemblyLinearVelocity(?:[\"']\s*\])?\s*=(?!=)",
    ],
    "direct_state_mutation": [
        r"\bSetAttribute\s*\(", r"\.Health\s*=(?!=)", r"\.WalkSpeed\s*=(?!=)",
        r"\.JumpPower\s*=(?!=)", r"\.JumpHeight\s*=(?!=)", r"\.CanCollide\s*=(?!=)",
        r"\.Color\s*=(?!=)", r"\.Material\s*=(?!=)",
    ],
    "direct_business_call": [
        r"\bFireServer\s*\(", r"\bInvokeServer\s*\(", r"\bFire\s*\(", r"\bInvoke\s*\(",
        r"\brequire\s*\(", r"\bInputHoldBegin\s*\(", r"\bInputHoldEnd\s*\(",
        r"\bVirtualInputManager\b", r"\bVirtualUser\b",
    ],
    "image_or_model_judgment_d1_d5": [
        r"\bScreenshot\b", r"\bImageGrab\b", r"\bOpenAI\b", r"\bChatGPT\b",
    ],
    "absolute_candidate_coordinates": [r"CFrame\.new\s*\(\s*-?\d{2,}"],
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    findings = []
    records = []
    for path in args.sources:
        resolved = path.resolve()
        text = resolved.read_text(encoding="utf-8")
        records.append({"path": str(resolved), "sha256": sha256(resolved)})
        for category, patterns in FORBIDDEN.items():
            for pattern in patterns:
                for match in re.finditer(pattern, text):
                    findings.append({
                        "source": str(resolved), "line": text.count("\n", 0, match.start()) + 1,
                        "category": category, "pattern": pattern, "match": match.group(0),
                    })
        # Unit vectors and zero vectors are generic math, not candidate-world
        # coordinates. Flag only literal triples whose magnitude makes them a
        # plausible hard-coded world target.
        for match in re.finditer(
            r"Vector3\.new\s*\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)",
            text,
        ):
            values = [abs(float(value)) for value in match.groups()]
            if max(values) >= 10:
                findings.append({
                    "source": str(resolved), "line": text.count("\n", 0, match.start()) + 1,
                    "category": "absolute_candidate_coordinates", "pattern": "large literal Vector3.new",
                    "match": match.group(0),
                })
    report = {
        "schema_version": "dockline-dispatch-policy-v1",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "passed": not findings, "sources": records, "findings": findings,
        "declared_policy": {
            "only_os_virtual_input": True, "teleports": 0, "direct_business_calls": 0,
            "direct_state_mutations": 0, "screenshots_or_llm_used_for_d1_d5": False,
            "candidate_source_used_for_runtime_routing_or_scoring": False,
            "absolute_candidate_coordinates": 0,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "finding_count": len(findings), "output": str(args.output.resolve())}))
    return 0 if report["passed"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
