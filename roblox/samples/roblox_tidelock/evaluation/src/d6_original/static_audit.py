#!/usr/bin/env python3
"""Audit the immutable Tide Lock submission without playing or editing it."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def tree_hash(root: Path) -> tuple[str, list[dict[str, object]]]:
    records = []
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix()
        item_hash = sha256(path)
        records.append({"path": relative, "size": path.stat().st_size, "sha256": item_hash})
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(item_hash.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest().upper(), records


def checkpoint(status: str, detail: str, evidence: list[str]) -> dict[str, object]:
    return {"status": status, "detail": detail, "evidence": evidence}


def run(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command, cwd=cwd, capture_output=True, text=True,
        encoding="utf-8", errors="replace", check=False,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-zip", type=Path, required=True)
    parser.add_argument("--expected-zip-sha256", required=True,
                        help="SHA-256 recorded for the candidate ZIP being audited")
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--rojo", type=Path, required=True)
    parser.add_argument("--luau-compile", type=Path, required=True)
    parser.add_argument("--build-output", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    candidate_zip = args.candidate_zip.resolve()
    root = args.candidate_root.resolve()
    project = root / "project"
    place = root / "TideLockCandidate.rbxlx"
    report: dict[str, object] = {
        "schema_version": "tide-lock-static-v1",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "candidate_zip": str(candidate_zip),
        "candidate_zip_sha256": sha256(candidate_zip),
        "candidate_root": str(root),
        "checkpoints": {},
        "diagnostics": {},
    }
    checks: dict[str, dict[str, object]] = report["checkpoints"]  # type: ignore[assignment]

    tree_digest, files = tree_hash(root)
    report["candidate_tree_sha256"] = tree_digest
    report["files"] = files
    required = [
        "DEVELOPMENT_TRACE.txt", "RUN_REPORT.txt", "TideLockCandidate.rbxlx",
        "project/default.project.json", "project/build.ps1",
        "project/src/shared/TideLockSchema.luau",
        "project/src/server/TideLockServer.server.luau",
        "project/src/client/TideLockClient.client.luau",
    ]
    missing = [name for name in required if not (root / name).is_file()]
    expected_zip = args.expected_zip_sha256.strip().upper()
    zip_ok = report["candidate_zip_sha256"] == expected_zip
    unsafe = [item["path"] for item in files if "../" in str(item["path"]) or Path(str(item["path"])).is_absolute()]
    checks["d1.package_integrity"] = checkpoint(
        "pass" if zip_ok and not missing and not unsafe else "fail",
        f"zip_hash_match={zip_ok}; missing={missing}; unsafe_paths={unsafe}; files={len(files)}",
        ["candidate ZIP SHA-256", "extracted file inventory"],
    )

    compile_records = []
    compile_ok = True
    for source in sorted((project / "src").rglob("*.luau")):
        result = run([str(args.luau_compile.resolve()), str(source)])
        compile_records.append({
            "file": source.relative_to(root).as_posix(),
            "returncode": result.returncode,
            "stdout": (result.stdout or "")[-2000:],
            "stderr": (result.stderr or "")[-2000:],
        })
        compile_ok = compile_ok and result.returncode == 0
    report["diagnostics"]["luau_compile"] = compile_records  # type: ignore[index]
    checks["d1.source_compile"] = checkpoint(
        "pass" if compile_ok and len(compile_records) == 3 else "fail",
        f"compiled={len(compile_records)} expected=3 all_ok={compile_ok}",
        [item["file"] for item in compile_records],
    )

    args.build_output.parent.mkdir(parents=True, exist_ok=True)
    build = run([
        str(args.rojo.resolve()), "build", str((project / "default.project.json").resolve()),
        "-o", str(args.build_output.resolve()),
    ])
    build_ok = build.returncode == 0 and args.build_output.is_file()
    report["diagnostics"]["rojo_build"] = {  # type: ignore[index]
        "returncode": build.returncode, "stdout": build.stdout, "stderr": build.stderr,
        "output_sha256": sha256(args.build_output) if build_ok else None,
    }
    checks["d1.rojo_clean_build"] = checkpoint(
        "pass" if build_ok else "fail",
        f"returncode={build.returncode}; output_exists={args.build_output.is_file()}",
        ["Rojo stdout/stderr", str(args.build_output)],
    )

    place_ok = False
    source_match = False
    script_names: list[str] = []
    parse_detail = ""
    try:
        xml_root = ET.parse(place).getroot()
        embedded: dict[str, str] = {}
        for item in xml_root.iter("Item"):
            if item.attrib.get("class") not in {"ModuleScript", "Script", "LocalScript"}:
                continue
            properties = item.find("Properties")
            if properties is None:
                continue
            name = next((node.text or "" for node in properties.findall("string") if node.attrib.get("name") == "Name"), "")
            source = next((node.text or "" for node in properties.findall("string") if node.attrib.get("name") == "Source"), "")
            embedded[name] = source
        expected_sources = {
            "TideLockPublicSchema": project / "src/shared/TideLockSchema.luau",
            "TideLockServer": project / "src/server/TideLockServer.server.luau",
            "TideLockClient": project / "src/client/TideLockClient.client.luau",
        }
        script_names = sorted(embedded)
        source_match = set(embedded) == set(expected_sources) and all(
            embedded[name] == path.read_text(encoding="utf-8") for name, path in expected_sources.items()
        )
        place_ok = True
        parse_detail = f"scripts={script_names}; source_match={source_match}"
    except Exception as error:  # diagnostic only
        parse_detail = repr(error)
    checks["d1.delivered_place_integrity"] = checkpoint(
        "pass" if place_ok and source_match else "fail",
        parse_detail,
        [f"delivered_place_sha256={sha256(place)}" if place.is_file() else "delivered place missing"],
    )

    # This is completed by the desktop launcher after OpenPlaceSuccess and before F5.
    checks["d1.studio_open_smoke"] = checkpoint(
        "not_run", "awaiting no-gameplay-input Studio OpenPlaceSuccess smoke", []
    )

    private_patterns = re.compile(
        r"SignalCircuit|formal_suite|score_evidence|private_design|candidate_[AB]|scoring weights|private evaluation trajectories",
        re.IGNORECASE,
    )
    suspicious = []
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".txt", ".md", ".json", ".lua", ".luau", ".ps1"}:
            text = path.read_text(encoding="utf-8", errors="replace")
            for line_number, line in enumerate(text.splitlines(), 1):
                # A trace declaration such as "Private scorer: no" documents
                # non-access.  It is not private material and must not turn
                # a clean candidate audit into a false finding.
                if private_patterns.search(line) and "access" not in line and ": no" not in line:
                    suspicious.append({"path": path.relative_to(root).as_posix(), "line": line_number, "text": line[:300]})
    report["private_material_scan"] = {
        "passed": not suspicious,
        "findings": suspicious,
        "development_trace_claims_no_private_access": "Private scorer: no" in (root / "DEVELOPMENT_TRACE.txt").read_text(encoding="utf-8"),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.output.resolve()),
        "candidate_tree_sha256": tree_digest,
        "checkpoints": {key: value["status"] for key, value in checks.items()},
    }, ensure_ascii=False))
    return 0 if all(value["status"] in {"pass", "not_run"} for value in checks.values()) else 2


if __name__ == "__main__":
    raise SystemExit(main())
