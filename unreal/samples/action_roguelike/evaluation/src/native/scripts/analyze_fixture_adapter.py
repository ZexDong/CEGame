"""Resolve reviewed semantic mappings against candidate C++ source evidence.

This is intentionally a conservative source analyzer, not a C++ compiler or a
semantic-name guesser. Compilation and independent runtime observation remain
mandatory. New storage models need a reviewed private mapping profile.
"""
from __future__ import annotations

import hashlib
import json
import re
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BINDINGS = ROOT / "adapters/source-bindings.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_source(path):
    data = path.read_bytes()
    try:
        return data.decode("utf-8-sig"), "utf-8-sig" if data.startswith(b"\xef\xbb\xbf") else "utf-8"
    except UnicodeDecodeError:
        # Analyze ASCII C++ tokens while preserving legacy comment bytes on
        # write. Never silently replace an undecodable byte in candidate source.
        return data.decode("latin-1"), "latin-1"


def source_path(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("FIXTURE_BINDING_PATH_ESCAPE")
    for item in (path, *path.parents):
        if item == root:
            break
        if item.is_symlink() or (item.exists() and getattr(item.lstat(), "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT):
            raise ValueError("FIXTURE_BINDING_REPARSE_POINT")
    return path


def code_only(text):
    # Preserve offsets/newlines for auditable patch locations. Literal/comment
    # contents cannot supply a class, declaration or damage-entry anchor.
    pattern = r'R"([^ ()\\\t\r\n]{0,16})\(.*?\)\1"|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/'
    return re.sub(pattern, lambda m: re.sub(r"[^\n]", " ", m.group()), text, flags=re.S)


def class_body(text, name):
    match = re.search(r"\bclass\s+(?:\w+_API\s+)?" + re.escape(name) + r"\s*:[^{;]+\{", text)
    if not match:
        return None
    depth = 1
    for index in range(match.end(), len(text)):
        depth += (text[index] == "{") - (text[index] == "}")
        if depth == 0:
            return text[match.end():index]
    return None


def analyze(project: Path, binding_path: Path | None = None):
    project = project.resolve(strict=True)
    root = project.parent
    binding_path = binding_path or DEFAULT_BINDINGS
    profiles = json.loads(binding_path.read_text(encoding="utf-8"))
    matches, rejected = [], []
    for profile in profiles["bindings"]:
        evidence, errors = [], []
        module_root = f"Source/{profile['module']}"
        sources = {}
        for relative in profile["source_sha256"]:
            path = source_path(root, relative)
            if path.is_file():
                sources[relative] = code_only(read_source(path)[0])
            else:
                errors.append(f"missing source: {relative}")
        headers = "\n".join(sources.get(f"{module_root}/{h}", "") for h in profile["headers"])
        for alias, class_name in (("P", profile["cpp"]["PLAYER"]), ("G", profile["cpp"]["GAMEMODE"])):
            body = class_body(headers, class_name)
            if body is None or not re.search(r"\bGENERATED_BODY\s*\(\s*\)", body):
                errors.append(f"missing native class: {class_name}")
                continue
            evidence.append({"kind": "class", "name": class_name})
            for member in profile.get("required_members", {}).get(alias, []):
                declarations = re.findall(r"\b(?:float|double|int32|int|bool)\s+([^;{}()]+);", body)
                declaration = any(re.search(r"(?:^|,)\s*" + re.escape(member) + r"\s*(?:=|$)", d) for d in declarations)
                if not declaration:
                    errors.append(f"missing scalar declaration: {class_name}::{member}")
                else:
                    evidence.append({"kind": "member", "class": class_name, "name": member})
        for anchor in profile.get("source_anchors", []) + profile["damage_guards"]:
            relative = f"{module_root}/{anchor['file']}"
            sites = list(re.finditer(anchor["pattern"], sources.get(relative, "")))
            if len(sites) != 1:
                errors.append(f"ambiguous/missing source anchor: {relative}")
            else:
                evidence.append({"kind": "source_anchor", "path": relative,
                                 "line": sources[relative].count("\n", 0, sites[0].start()) + 1})
        if errors:
            rejected.append({"id": profile["id"], "reasons": errors})
            continue
        hashes = {f: digest(source_path(root, f)) for f in sources}
        exact = all(hashlib.sha256(source_path(root, f).read_bytes().replace(b"\r\n", b"\n")
                    if profile.get("source_hash_mode") == "utf8_lf" else source_path(root, f).read_bytes()).hexdigest() == sha
                    for f, sha in profile["source_sha256"].items())
        if profile.get("observation_units") and not exact:
            rejected.append({"id": profile["id"], "reasons": ["unit mapping requires exact audited source hashes"]})
            continue
        matches.append((profile, {"profile_id": profile["id"], "selection": "audited_source_hash" if exact else "source_structure",
                                  "source_sha256": hashes, "evidence": evidence,
                                  "runtime_write_readback_required": True,
                                  "independent_observation_required": True}))
    if len(matches) != 1:
        raise ValueError("FIXTURE_BINDING_UNAVAILABLE: expected one source-supported semantic mapping; "
                         + json.dumps({"matches": [b[0]["id"] for b in matches], "rejected": rejected}))
    binding, report = matches[0]
    report["binding_sha256"] = digest(binding_path)
    report["adapter_identity"] = binding["id"] + ":" + hashlib.sha256(json.dumps(
        {"profile": binding, "sources": report["source_sha256"]}, sort_keys=True).encode()).hexdigest()
    return binding, report
