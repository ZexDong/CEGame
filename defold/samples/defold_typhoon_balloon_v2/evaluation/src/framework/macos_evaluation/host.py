"""Bounded owned processes, immutable staging and native desktop operations."""
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load(path):
    def pairs(rows):
        result = {}
        for key, value in rows:
            if key in result:
                raise ValueError('DUPLICATE_JSON_KEY:' + key)
            result[key] = value
        return result
    def invalid(value):
        raise ValueError('NONFINITE_JSON:' + value)
    return json.loads(Path(path).read_text(encoding='utf-8-sig'),
                      object_pairs_hook=pairs, parse_constant=invalid)


def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(data, stream, indent=2, ensure_ascii=False, allow_nan=False)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def sha(path):
    with Path(path).open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256')
    return digest.hexdigest()


def binding(root, excluded=()):
    root = Path(root).resolve()
    if not root.is_dir():
        raise ValueError('SOURCE_DIRECTORY_MISSING:' + str(root))
    rows = []
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in excluded)
        for name in dirs + sorted(files):
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError('SOURCE_SYMLINK_NOT_ALLOWED:' + str(path))
        for name in sorted(files):
            path = Path(directory) / name
            rows.append(dict(path=path.relative_to(root).as_posix(),
                             bytes=path.stat().st_size, sha256=sha(path)))
    rows.sort(key=lambda row: row['path'])
    digest = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()
    return dict(sha256=digest, file_count=len(rows), files=rows)


def overlap(left, right):
    left, right = Path(left).resolve(), Path(right).resolve()
    return left.is_relative_to(right) or right.is_relative_to(left)


def group_alive(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False


def stop_group(process, grace=5):
    """Only accept a Popen launched with start_new_session=True by this host."""
    pid = process.pid
    if group_alive(pid):
        os.killpg(pid, signal.SIGTERM)
    deadline = time.monotonic() + grace
    while group_alive(pid) and time.monotonic() < deadline:
        process.poll()  # Reap the leader; zombies must not masquerade as survivors.
        time.sleep(.03)
    if group_alive(pid):
        os.killpg(pid, signal.SIGKILL)
    process.wait(timeout=10)
    deadline = time.monotonic() + 3
    while group_alive(pid) and time.monotonic() < deadline:
        time.sleep(.03)
    return dict(process_exited=process.poll() is not None,
                owned_process_group_empty=not group_alive(pid))


def run_process(command, cwd, output, name, timeout, env=None):
    output = Path(output)
    started = time.monotonic()
    with (output / (name + '.stdout.log')).open('wb') as stdout, \
         (output / (name + '.stderr.log')).open('wb') as stderr:
        process = subprocess.Popen([str(x) for x in command], cwd=cwd, env=env,
                                   stdout=stdout, stderr=stderr, start_new_session=True)
        timed_out = False
        try:
            process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            timed_out = True
        finally:
            cleanup = stop_group(process, grace=0 if timed_out else 3)
    receipt = dict(command=[str(x) for x in command], process_id=process.pid,
                   exit_code=124 if timed_out else process.returncode, timed_out=timed_out,
                   elapsed_seconds=round(time.monotonic() - started, 3), **cleanup)
    write(output / (name + '-host.json'), receipt)
    if not all(cleanup.values()):
        raise RuntimeError('OWNED_PROCESS_CLEANUP_UNVERIFIED:' + name)
    return receipt


def native_binary():
    if sys.platform != 'darwin':
        raise RuntimeError('MACOS_REQUIRED')
    source = ROOT / 'desktop.swift'
    # Stable path for macOS privacy consent; the source hash prevents stale use.
    cache = ROOT / '.cache'
    cache.mkdir(exist_ok=True)
    binary, receipt = cache / 'desktop', cache / 'source.sha256'
    digest = sha(source)
    if not binary.is_file() or not receipt.is_file() or receipt.read_text().strip() != digest:
        result = subprocess.run(['/usr/bin/xcrun', 'swiftc', '-O', str(source), '-o', str(binary)],
                                capture_output=True, text=True, timeout=120,
                                env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(cache / 'modules')})
        if result.returncode:
            raise RuntimeError('NATIVE_HELPER_COMPILE_FAILED:' + result.stderr)
        receipt.write_text(digest + '\n')
    return binary


class Desktop:
    def __init__(self):
        self.binary = native_binary()
        self.lock = threading.Lock()

    def call(self, operation, **values):
        with self.lock:
            result = subprocess.run([str(self.binary)], input=json.dumps(dict(op=operation, **values)),
                                    text=True, capture_output=True, timeout=15)
        try:
            value = json.loads(result.stdout)
        except ValueError:
            raise RuntimeError('NATIVE_HELPER_PROTOCOL_INVALID:' + result.stderr) from None
        if result.returncode or not value.get('ok'):
            raise RuntimeError(value.get('error', 'NATIVE_HELPER_FAILED'))
        return value


def capabilities():
    return Desktop().call('check')
