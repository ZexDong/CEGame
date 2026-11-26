"""Check a task input or export a complete, independent generation input."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.dont_write_bytecode = True
INPUT = Path(__file__).resolve().parents[1]
ARCHIVE = "tools/catalog/UNREAL_ENGINE_5_7_4_INTERFACE_CATALOG.jsonl.gz"
ARCHIVE_SHA256 = "750f1bd26572c5f4d3e5c2afe7fce14d5d7c76aad4ee806151ced72924a6dfd0"


def catalog_path(root):
    root = root.resolve()
    path = root / ARCHIVE
    if not path.exists() and root == INPUT and INPUT.parent.parent.name == "samples":
        path = INPUT.parent.parent / "bomber/input" / ARCHIVE
    if not path.is_file():
        raise FileNotFoundError("Missing interface catalog. Export a complete input from the release checkout.")
    if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise ValueError("Interface catalog does not match the frozen SHA-256.")
    return path


def export_input(root, destination, archive):
    destination = destination.resolve()
    package_root = INPUT.parents[3] if INPUT.parent.parent.name == "samples" else INPUT
    if destination.is_relative_to(package_root) or destination.is_relative_to(root) or destination.exists():
        raise ValueError("Choose a new destination outside the input and release directories.")
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        copy = Path(temporary) / "input"
        shutil.copytree(root, copy)
        if not (copy / ARCHIVE).exists():
            shutil.copyfile(archive, copy / ARCHIVE)
        catalog_path(copy)
        copy.rename(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", type=Path, default=INPUT)
    parser.add_argument("--allow-project-changes", action="store_true")
    parser.add_argument("--export-input", type=Path, metavar="DIRECTORY")
    args = parser.parse_args()
    root = args.input_root.resolve()
    errors = []
    try:
        for path in root.rglob("*"):
            if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
                errors.append("Linked path: " + path.relative_to(root).as_posix())
            if path.name == "__pycache__":
                errors.append("Generated cache: " + path.relative_to(root).as_posix())
        entries = list((root / "starter-project").glob("*.uproject"))
        if len(entries) != 1:
            errors.append("Exactly one project descriptor is required")
        else:
            json.loads(entries[0].read_text(encoding="utf-8-sig"))
        archive = catalog_path(root)
        if args.export_input and not errors:
            export_input(root, args.export_input, archive)
    except (OSError, ValueError, shutil.Error) as error:
        errors.append(str(error))
    print(json.dumps({"status": "failed" if errors else "passed", "gameplay_verified": False, "errors": errors}))
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
