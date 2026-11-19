"""Check the public delivery contract and frozen non-project file integrity only."""
from pathlib import Path
import argparse, json, sys
sys.dont_write_bytecode=True
def main():
 p=argparse.ArgumentParser();p.add_argument('--input-root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--allow-project-changes',action='store_true');a=p.parse_args()
 root=a.input_root.resolve();errors=[]








 for path in root.rglob('*'):
  if path.is_symlink():errors.append('Linked file: '+path.relative_to(root).as_posix())
  if not path.is_file():continue
  rel=path.relative_to(root).as_posix()
  if '__pycache__' in path.parts:errors.append('Generated cache: '+rel)

 entries=list((root/'starter-project').glob('*.uproject'))
 if len(entries)!=1:errors.append('Exactly one project descriptor is required')
 else:
  try:json.loads(entries[0].read_text(encoding='utf-8-sig'))
  except ValueError:errors.append('Invalid project descriptor JSON')
 print(json.dumps({'status':'failed' if errors else 'passed','gameplay_verified':False,'errors':errors},indent=2));return bool(errors)
if __name__=='__main__':raise SystemExit(main())
