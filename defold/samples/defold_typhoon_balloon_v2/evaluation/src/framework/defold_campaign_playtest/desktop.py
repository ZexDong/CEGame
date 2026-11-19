"""New native capabilities, reusing the existing bounded JSON transport."""
import os
import subprocess
import threading
from pathlib import Path
from framework.defold_cross_engine.desktop import Desktop
from framework.macos_evaluation.host import sha


class EvaluatorDesktop(Desktop):
    def __init__(self):
        root=Path(__file__).resolve().parent
        source=root/'desktop.swift'
        cache=root/'.cache';cache.mkdir(exist_ok=True)
        binary=cache/'desktop'; receipt=cache/'source.sha256'
        digest=sha(source)
        if not binary.is_file() or not receipt.is_file() or receipt.read_text().strip()!=digest:
            result=subprocess.run(['/usr/bin/xcrun','swiftc','-O',str(source),'-o',str(binary)],
                capture_output=True,text=True,timeout=120,
                env={**os.environ,'CLANG_MODULE_CACHE_PATH':str(cache/'modules')})
            if result.returncode: raise RuntimeError(result.stderr)
            receipt.write_text(digest+'\n')
        self.process=subprocess.Popen([str(binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,start_new_session=True,bufsize=0)
        self.lock=threading.Lock()
