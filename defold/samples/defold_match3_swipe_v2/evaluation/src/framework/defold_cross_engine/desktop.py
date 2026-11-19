"""Bounded JSON-lines transport to the persistent native input helper."""
import json
import os
import select
import subprocess
import threading
from pathlib import Path
from framework.macos_evaluation.host import sha, stop_group

ROOT=Path(__file__).resolve().parent


class Desktop:
    def __init__(self):
        source=ROOT/'desktop.swift'
        cache=ROOT/'.cache'
        cache.mkdir(exist_ok=True)
        binary, receipt=cache/'desktop',cache/'desktop.sha256'
        digest=sha(source)
        if not binary.exists() or not receipt.exists() or receipt.read_text().strip()!=digest:
            result=subprocess.run(['/usr/bin/xcrun','swiftc','-O',str(source),'-o',str(binary)],
                capture_output=True,text=True,timeout=120,
                env={**os.environ,'CLANG_MODULE_CACHE_PATH':str(cache/'modules')})
            if result.returncode:raise RuntimeError(result.stderr)
            receipt.write_text(digest+'\n')
        self.process=subprocess.Popen([str(binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,start_new_session=True,bufsize=0)
        self.lock=threading.Lock()

    def call(self, operation, **values):
        with self.lock:
            self.process.stdin.write((json.dumps(dict(op=operation,**values))+'\n').encode())
            if not select.select([self.process.stdout],[],[],15)[0]:
                raise RuntimeError('NATIVE_HELPER_TIMEOUT')
            raw=self.process.stdout.readline()
            if not raw:raise RuntimeError('NATIVE_HELPER_EXITED')
            reply=json.loads(raw)
            if not reply.get('ok'):raise RuntimeError(reply.get('error','NATIVE_HELPER_FAILED'))
            return reply

    def close(self):
        self.process.stdin.close()
        try:self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:stop_group(self.process,grace=0)
        self.process.stdout.close();self.process.stderr.close()
