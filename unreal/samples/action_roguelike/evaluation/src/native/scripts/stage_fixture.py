"""Build a private, audited source-instrumented runtime copy. Never edit input."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import shutil
import stat
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyze_fixture_adapter import analyze, source_path, code_only, read_source, DEFAULT_BINDINGS

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT.parents[2] / "engine/shared/unreal-fixture"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage(project: Path, destination: Path, binding_path: Path | None = None):
    project = project.resolve(strict=True)
    destination = destination.resolve()
    if destination.exists() or destination == project.parent or project.parent in destination.parents:
        raise ValueError("Fixture destination must be a fresh directory outside the candidate project")
    if any(part.lower() in ("input", "original") for part in destination.parts):
        raise ValueError("Fixture destination must be private, outside input/original")
    binding_path = binding_path or DEFAULT_BINDINGS
    binding, analysis = analyze(project, binding_path)
    ignored = {"Binaries", "Intermediate", "Saved", "DerivedDataCache", ".git", ".vs", "evaluation"}
    def ignore(directory, names):
        for name in names:
            item = Path(directory) / name
            if name not in ignored and (item.is_symlink() or getattr(item.lstat(), "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT):
                raise ValueError("Reparse point in fixture source")
        return [name for name in names if name in ignored]
    generated_names = ("AREvaluationFixture.cpp", "AREvaluationFixture.h", "ARCandidateAdapter.cpp", "ARCandidateAdapter.h", "UnrealFixtureCapabilities.cpp", "UnrealFixtureCapabilities.h")
    for name in generated_names:
        if (project.parent / "Source" / binding["module"] / name).exists():
            raise ValueError("FIXTURE_GENERATED_FILE_COLLISION: " + name)
    shutil.copytree(project.parent, destination, ignore=ignore)
    edits = []
    def write(relative, text, encoding="utf-8"):
        path = source_path(destination, relative)
        path.parent.mkdir(parents=True, exist_ok=True)
        before = digest(path) if path.exists() else None
        path.write_text(text, encoding=encoding, newline="\n")
        edits.append(dict(path=relative, before_sha256=before, after_sha256=digest(path)))
    module = binding["module"]
    for header in binding["headers"]:
        relative = f"Source/{module}/{header}"
        text, encoding = read_source(destination / relative)
        text = re.sub(r"GENERATED_BODY\s*\(\s*\)", "GENERATED_BODY()\n    friend struct FAREvaluationBinding;", text)
        write(relative, text, encoding)
    replacements = list(binding["damage_guards"])
    for change in replacements:
        relative = f"Source/{module}/{change['file']}"
        text, encoding = read_source(destination / relative)
        sites = list(re.finditer(change["pattern"], code_only(text)))
        count = len(sites)
        if count == 1:
            site = sites[0]
            patch = change.get("replacement", text[site.start():site.end()] + change.get("insertion", ""))
            text = text[:site.start()] + patch + text[site.end():]
        if count != 1:
            raise ValueError(f"FIXTURE_BINDING_DRIFT: {relative}: expected one guarded source site, found {count}")
        if '#include "AREvaluationFixture.h"' not in text:
            text = re.sub(r'(#include[^\n]+\n)', r'\1#include "AREvaluationFixture.h"\n', text, count=1)
        write(relative, text, encoding)
    template = (ROOT / "fixture/ARCandidateAdapter.cpp.in").read_text(encoding="utf-8")
    values = {"INCLUDES": "\n".join(f'#include "{h}"' for h in binding["headers"]), **binding["cpp"], "ADAPTER_ID": analysis["adapter_identity"]}
    for key, value in values.items():
        template = template.replace(f"@{key}@", value)
    if re.search(r"@[A-Z_]+@", template):
        raise ValueError("Unexpanded native fixture binding")
    write(f"Source/{module}/ARCandidateAdapter.cpp", template)
    for name in ("AREvaluationFixture.cpp", "AREvaluationFixture.h", "ARCandidateAdapter.h"):
        write(f"Source/{module}/{name}", (ROOT / "fixture" / name).read_text(encoding="utf-8"))
    for name in ("UnrealFixtureCapabilities.cpp", "UnrealFixtureCapabilities.h"):
        write(f"Source/{module}/{name}", (SHARED / name).read_text(encoding="utf-8"))
    write("FixtureAdapterAnalysis.json", json.dumps(analysis, indent=2) + "\n")
    # Keep dependencies explicit even for a candidate that manually serializes JSON.
    relative = f"Source/{module}/{module}.Build.cs"
    text = (destination / relative).read_text(encoding="utf-8-sig")
    dependencies = ["Json", "Slate", "SlateCore", "ApplicationCore"] + binding.get("additional_modules", [])
    if any(not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) for name in dependencies):
        raise ValueError("FIXTURE_MODULE_NAME_INVALID")
    dependency_code = ", ".join(json.dumps(name) for name in dict.fromkeys(dependencies))
    text, count = re.subn(r"(:\s*base\s*\(\s*\w+\s*\)\s*\{)", lambda m: m.group(0) + '\n        PrivateDependencyModuleNames.AddRange(new string[] { ' + dependency_code + ' });', text, count=1)
    if count != 1:
        raise ValueError("FIXTURE_BUILD_RULES_UNBOUND")
    write(relative, text)
    receipt = dict(version="ar-private-fixture-2.0.0", binding_id=binding["id"],
                   binding_sha256=digest(binding_path),
                   source_project=str(project), staged_project=str(destination / project.name),
                   source_sha256={f: digest(project.parent / f) for f in binding["source_sha256"]},
                   binding_source_hash_mode=binding.get("source_hash_mode", "exact_bytes"), edits=edits,
                   adapter_analysis=analysis,
                   layers={"engine": {"version": "ue-fixture-capabilities-1.0.0", "files": {p.name: digest(p) for p in SHARED.iterdir() if p.suffix in (".h", ".cpp")}},
                           "fixture": "ar-private-fixture-2.0.0", "adapter": analysis["adapter_identity"]},
                   validation_status="generated_requires_build_and_runtime_readback",
                   boundary="native precondition writes and player-damage guards only; no result or observer writes")
    (destination.parent / "fixture-stage.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--bindings", type=Path)
    args = parser.parse_args()
    print(json.dumps(stage(args.project, args.destination, args.bindings)))
