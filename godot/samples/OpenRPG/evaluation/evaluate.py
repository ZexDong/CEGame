"""Godot evaluation entry."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "src"))
from runtime import main
if __name__ == "__main__":
    raise SystemExit(main(HERE))
