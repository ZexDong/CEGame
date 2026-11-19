"""Compile and verify the separately archived user submission before Studio."""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent


def verify_inputs():
    manifest = json.loads((ROOT / 'candidate_sha256.json').read_text(encoding='utf-8'))
    for relative, expected in manifest['files'].items():
        path = ROOT / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'Input integrity mismatch: {relative}. Prepare a new evaluation for a changed submission.')
    archive = ROOT / 'input/SkylineSwitchyard-project.zip'
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            if entry.is_dir() or entry.filename.endswith(('\\', '/')):
                continue
            relative = entry.filename.replace('\\', '/')
            if relative.startswith('/') or '..' in Path(relative).parts:
                raise RuntimeError('Unsafe archive entry')
            if package.read(entry) != (ROOT / 'candidate' / relative).read_bytes():
                raise RuntimeError(f'Source differs from supplied ZIP: {relative}')
    # Also compare against the actual user archive, not only the convenience ZIP.
    with zipfile.ZipFile(ROOT / 'input/SkylineSwitchyard_FULL_PACKAGE.zip') as original:
        for path in (ROOT / 'candidate/project').rglob('*'):
            if path.is_file():
                relative = path.relative_to(ROOT / 'candidate').as_posix()
                if original.read('SkylineSwitchyard/' + relative) != path.read_bytes():
                    raise RuntimeError('Project differs from original full package: ' + relative)
        if original.read('SkylineSwitchyard/SkylineSwitchyard.rbxlx') != (ROOT / 'candidate/SkylineSwitchyard.rbxlx').read_bytes():
            raise RuntimeError('Place differs from original full package')
    # Supplied place must contain exactly the submitted script source texts.
    document = ET.parse(ROOT / 'candidate/SkylineSwitchyard.rbxlx')
    embedded = Counter(p.text.replace('\r\n', '\n') for p in document.findall(".//Properties/*[@name='Source']") if p.text)
    source = Counter(p.read_text(encoding='utf-8') for p in (ROOT / 'candidate/project/src').rglob('*.luau'))
    if embedded != source:
        raise RuntimeError('Supplied Place source does not match supplied ZIP')


def preflight() -> bool:
    output = ROOT / 'evidence' / datetime.now(timezone(timedelta(hours=8))).strftime('preflight_%Y%m%d_%H%M%S_%f')
    output.mkdir(parents=True)
    results = []
    error = None
    try:
        verify_inputs()
        for folder in ['candidate/project/src', 'runtime']:
            for path in sorted((ROOT / folder).rglob('*.luau')):
                result = subprocess.run([str(ROOT / 'tools/luau-compile.exe'), '--null', str(path)],
                                        capture_output=True, text=True, encoding='utf-8', errors='replace')
                results.append({'file': str(path.relative_to(ROOT)).replace('\\', '/'),
                                'exit_code': result.returncode,
                                'output': result.stdout + result.stderr,
                                'ownership': 'candidate' if folder.startswith('candidate') else 'evaluator'})
    except Exception as exc:
        error = str(exc)
    failed = [r for r in results if r['exit_code']]
    candidate_failed = [r for r in failed if r['ownership'] == 'candidate']
    evaluator_failed = [r for r in failed if r['ownership'] == 'evaluator']
    passed = not failed and error is None
    report = {
        'status': 'PREFLIGHT_PASS' if passed else ('CANDIDATE_COMPILE_BLOCKED' if candidate_failed and not evaluator_failed and error is None else 'PREFLIGHT_ERROR'),
        'source_integrity': 'PASS' if error is None else 'ERROR',
        'error': error, 'checks': results,
        'submission_kind': 'USER_SUPPLIED_FULL_PACKAGE_20261026',
        'studio_play_executed': False,
        'automatic_score': None,
        'note': 'New user-supplied project and Place. Compilation is not a gameplay score; this runner never patches code during evaluation.'
    }
    (output / 'preflight.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    if not passed:
        rules = json.loads((ROOT / 'rules.json').read_text(encoding='utf-8'))
        score = {
            'benchmark_id': rules['benchmark_id'], 'evaluation_status': report['status'],
            'completed': False, 'assessment_complete': False, 'automatic_score': None,
            'automatic_score_maximum': 90, 'manual_visual_score_maximum': 10,
            'studio_play_executed': False, 'runner_error': error,
            'checks': {},
            'dimensions': {k: {'status': 'NOT_EVALUATED' if k != 'D6' else 'MANUAL_REVIEW_REQUIRED', 'maximum': v['maximum_score']}
                           for k, v in rules['dimensions'].items()},
            'unresolved_checks': [c['id'] for v in rules['dimensions'].values() for c in v.get('checks', [])],
            'note': 'No runtime score: compilation or input verification blocked the run. This is not a 0/90 result.'
        }
        (output / 'score.json').write_text(json.dumps(score, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Preflight evidence: {output}', flush=True)
    if error:
        print('Preflight error:', error, flush=True)
    for result in failed:
        print(f"COMPILE FAILED [{result['ownership']}]: {result['file']}\n{result['output']}", flush=True)
    if passed:
        print('Preflight PASS. Compilation alone does not establish gameplay correctness.', flush=True)
    else:
        print('Run blocked before Studio Play. No gameplay score; see preflight.json and score.json.', flush=True)
    return passed


if __name__ == '__main__':
    raise SystemExit(0 if preflight() else 2)
