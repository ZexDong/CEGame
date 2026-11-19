#!/usr/bin/env python3
"""Static-only D1 audit for the unchanged Deep Relay submission."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from datetime import datetime, timezone
from pathlib import Path


EXPECTED = {
    "project/default.project.json",
    "project/src/shared/DeepRelaySchema.luau",
    "project/src/server/DeepRelayServer.server.luau",
    "project/src/client/DeepRelayClient.client.luau",
}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest().upper()


def evidence(path: Path, root: Path) -> list[dict]:
    return [{"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": digest(path)}]


def checkpoint(status: str, detail: str, files: list[dict]) -> dict:
    return {"status": status, "detail": detail, "evidence": files, "trace_ids": []}


def run_capture(command: list[str], cwd: Path) -> tuple[int, str]:
    completed = subprocess.run(command, cwd=cwd, text=True, encoding="utf-8", errors="replace", capture_output=True)
    return completed.returncode, completed.stdout + completed.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    original = root / "candidate" / "original"
    source = root / "candidate" / "source" / "project"
    place = original / "DeepRelayCandidate.rbxlx"
    package = original / "DeepRelayCandidate_project.zip"
    rojo = root / "tools" / "rojo.exe"
    compiler = root / "tools" / "luau-compile.exe"
    audit_dir = root / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)
    for required in (place, package, rojo, compiler, source / "default.project.json"):
        if not required.is_file():
            raise FileNotFoundError(f"required input missing: {required}")

    checkpoints: dict[str, dict] = {}
    previous_smoke = None
    previous_results = audit_dir / "static_results.json"
    if previous_results.is_file():
        try:
            previous = json.loads(previous_results.read_text(encoding="utf-8"))
            smoke = previous.get("checkpoints", {}).get("d1.studio_open_smoke")
            evidence_ok = isinstance(smoke, dict) and smoke.get("status") == "pass" and all(
                (root / record["file"]).is_file() and digest(root / record["file"]) == record["sha256"]
                for record in smoke.get("evidence", [])
            )
            if previous.get("candidate_place_sha256") == digest(place) and evidence_ok:
                previous_smoke = smoke
        except (OSError, ValueError, KeyError, TypeError):
            previous_smoke = None
    with zipfile.ZipFile(package) as archive:
        names = {name.replace("\\", "/") for name in archive.namelist() if not name.endswith("/")}
        unsafe = [name for name in names if name.startswith(("/", "\\")) or ".." in Path(name).parts]
        extracted_mismatches = []
        for name in sorted(EXPECTED & names):
            extracted = source.parent / name
            if not extracted.is_file() or hashlib.sha256(archive.read(name)).digest() != hashlib.sha256(extracted.read_bytes()).digest():
                extracted_mismatches.append(name)
        package_ok = EXPECTED.issubset(names) and not unsafe and archive.testzip() is None and not extracted_mismatches
        inventory = {"entries": sorted(names), "missing_expected": sorted(EXPECTED - names), "unsafe": unsafe, "extracted_source_mismatches": extracted_mismatches}
    inventory_path = audit_dir / "package_inventory.json"
    inventory_path.write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checkpoints["d1.package_integrity"] = checkpoint(
        "pass" if package_ok else "fail",
        "Source ZIP is readable, traversal-safe and contains the complete Rojo project." if package_ok else "Source ZIP is incomplete or unsafe.",
        evidence(package, root) + evidence(inventory_path, root),
    )

    compile_records = []
    compile_ok = True
    for script in sorted((source / "src").rglob("*.luau")):
        code, output = run_capture([str(compiler), str(script)], root)
        compile_records.append({"file": str(script.relative_to(root)).replace("\\", "/"), "exit_code": code, "diagnostic_tail": output[-2000:] if code else ""})
        compile_ok = compile_ok and code == 0
    compile_log = audit_dir / "luau_compile.json"
    compile_log.write_text(json.dumps(compile_records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checkpoints["d1.source_compile"] = checkpoint(
        "pass" if compile_ok and len(compile_records) == 3 else "fail",
        f"Luau compiler checked {len(compile_records)} submitted scripts.", evidence(compile_log, root),
    )

    with tempfile.TemporaryDirectory(prefix="deeprelay_clean_build_") as temp_name:
        temp = Path(temp_name)
        with zipfile.ZipFile(package) as archive:
            archive.extractall(temp)
        clean_output = audit_dir / "DeepRelay_clean_build.rbxlx"
        code, output = run_capture([str(rojo), "build", str(temp / "project" / "default.project.json"), "-o", str(clean_output)], root)
    build_log = audit_dir / "rojo_clean_build.log"
    build_log.write_text(output, encoding="utf-8")
    build_ok = code == 0 and clean_output.is_file() and clean_output.stat().st_size > 0
    checkpoints["d1.rojo_clean_build"] = checkpoint(
        "pass" if build_ok else "fail", "A clean extraction was rebuilt with bundled Rojo." if build_ok else "Clean Rojo build failed.",
        evidence(build_log, root) + (evidence(clean_output, root) if clean_output.exists() else []),
    )

    try:
        tree = ET.parse(place)
        items = tree.getroot().findall(".//Item")
        classes = [item.attrib.get("class", "") for item in items]
        place_ok = place.stat().st_size > 0 and classes.count("Script") >= 1 and classes.count("LocalScript") >= 1 and classes.count("ModuleScript") >= 1
        place_detail = f"Delivered XML place parsed with {len(items)} Items and all three script classes."
    except (ET.ParseError, OSError) as error:
        place_ok = False
        place_detail = f"Delivered place XML parse failed: {error}"
    place_report = audit_dir / "delivered_place_audit.json"
    place_report.write_text(json.dumps({"parsed": place_ok, "detail": place_detail}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checkpoints["d1.delivered_place_integrity"] = checkpoint(
        "pass" if place_ok else "fail", place_detail, evidence(place, root) + evidence(place_report, root),
    )
    checkpoints["d1.studio_open_smoke"] = previous_smoke or checkpoint(
        "not_run", "The no-input Studio OpenPlaceSuccess smoke has not run yet.", [],
    )

    hash_records = []
    for path in sorted([place, package, *source.rglob("*")]):
        if path.is_file():
            hash_records.append({"file": str(path.relative_to(root)).replace("\\", "/"), "sha256": digest(path), "bytes": path.stat().st_size})
    hashes = audit_dir / "hashes.json"
    hashes.write_text(json.dumps({"schema_version": "deep-relay-hashes-v1", "files": hash_records}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result = {
        "schema_version": "deep-relay-static-v1",
        "audited_at_utc": datetime.now(timezone.utc).isoformat(),
        "candidate_place_sha256": digest(place),
        "candidate_zip_sha256": digest(package),
        "checkpoints": checkpoints,
        "hash_manifest": str(hashes.relative_to(root)).replace("\\", "/"),
    }
    output = audit_dir / "static_results.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed_before_smoke": all(value["status"] == "pass" for key, value in checkpoints.items() if key != "d1.studio_open_smoke"), "output": str(output)}, ensure_ascii=False))
    return 0 if all(value["status"] == "pass" for key, value in checkpoints.items() if key != "d1.studio_open_smoke") else 2


if __name__ == "__main__":
    raise SystemExit(main())
