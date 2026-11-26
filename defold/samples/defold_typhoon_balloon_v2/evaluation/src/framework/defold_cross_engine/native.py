"""Defold build and PID-bound launch; no gameplay or scoring knowledge."""
import configparser
import os
import shutil
import subprocess
import time
import uuid
from pathlib import Path

from framework.macos_evaluation.host import binding, load, run_process, write

def defold_build_tools():
    packages = os.environ.get("DEFOLD_PACKAGES")

    def tool(variable, pattern):
        explicit = os.environ.get(variable)
        if explicit and Path(explicit).is_file():
            return Path(explicit).resolve()
        matches = sorted(Path(packages).glob(pattern)) if packages and not explicit else []
        if len(matches) == 1 and matches[0].is_file():
            return matches[0].resolve()
        raise RuntimeError(f"Set {variable} to the installed tool, or select a unique match via DEFOLD_PACKAGES")

    return tool("DEFOLD_JAVA", "jdk*/bin/java"), tool("DEFOLD_BOB_JAR", "defold-*.jar")


EXCLUDED = {'build', '.internal', '.git', '.venv', '__pycache__', '.DS_Store', 'game-state.json'}


def project_path(candidate):
    candidate = Path(candidate).resolve()
    options = [p for p in (candidate, candidate/'project', candidate/'starter_project')
               if (p/'game.project').is_file()]
    if len(options) != 1:
        raise ValueError('DEFOLD_PROJECT_MISSING_OR_AMBIGUOUS')
    return options[0]


def stage_build(candidate, output, timeout=600):
    candidate, output = Path(candidate).resolve(), Path(output).resolve()
    if candidate.is_relative_to(output) or output.is_relative_to(candidate):
        raise ValueError('SOURCE_RUN_OVERLAP')
    source = project_path(candidate)
    before = binding(candidate, EXCLUDED)
    write(output/'candidate-identity.json', before)
    config = configparser.ConfigParser(interpolation=None)
    config.read(source/'game.project')
    if config.has_option('project', 'dependencies'):
        raise ValueError('UNDECLARED_NETWORK_DEPENDENCIES')
    work = output/'work/project'
    shutil.copytree(source, work, ignore=shutil.ignore_patterns(*EXCLUDED))
    java, bob = defold_build_tools()
    command = [java, '-Dcom.google.protobuf.use_unsafe_pre22_gencode=true', '-cp', bob,
               'com.dynamo.bob.Bob', '--root', work, '--platform', 'arm64-macos',
               '--variant', 'debug', '--archive', 'build', 'bundle']
    receipt = run_process(command, work, output, 'build', timeout)
    write(output/'candidate-source-verification.json', dict(
        source_unchanged=binding(candidate, EXCLUDED)==before,
        candidate_identity_sha256=before['sha256']))
    if receipt['exit_code']:
        return before, receipt, None
    binaries = list((work/'build/default').glob('*.app/Contents/MacOS/*'))
    binaries = [p for p in binaries if p.is_file() and os.access(p, os.X_OK)]
    if len(binaries) != 1:
        raise ValueError('DEFOLD_BUNDLE_AMBIGUOUS')
    return before, receipt, binaries[0]


def start_player(player, values):
    """Used by a normal-input host. State file is output-only, never a command."""
    readiness = player.desktop.call('check')
    if readiness.get('session_locked', True):
        raise RuntimeError('MACOS_SESSION_LOCKED')
    if not all(readiness.get(key) for key in ('accessibility', 'input', 'screen_recording')):
        raise RuntimeError('MACOS_NATIVE_PERMISSIONS_REQUIRED')
    player.start_values = values
    token = uuid.uuid4().hex
    game = player.root/'state/game-state.json'
    if game.exists():
        game.unlink()  # Exact observer output owned by this run.
    executable = Path(values['executable']).resolve()
    player.log = (player.root/'logs'/('defold-'+token+'.log')).open('wb')
    # exec preserves the shell PID, binding the public envelope to the real process.
    command = ['/bin/sh', '-c',
               'exec "$1" "--config=benchmark.process_id=$$" '
               '"--config=benchmark.state_path=$2" "--config=benchmark.process_token=$3"',
               'defold-player', str(executable), str(game), token]
    player.process = subprocess.Popen(command, cwd=executable.parent,
        stdout=player.log, stderr=subprocess.STDOUT, start_new_session=True)
    if player.budget:
        player.budget.processes.append(player.process)
    player.had_session = True
    player.watchdog_fault = None
    player.session = dict(process_id=player.process.pid, process_token=token,
                          session=token, host_platform='macos')
    deadline = time.monotonic()+30
    while time.monotonic()<deadline:
        if player.budget:
            player.budget.check()
        if player.process.poll() is not None:
            raise RuntimeError('PROCESS_EXITED_DURING_START')
        try:
            state = load(game)
            if state.get('process_id') == player.process.pid and state.get('process_token') == token:
                player.desktop.call('window', pid=player.process.pid)
                player.desktop.call('focus', pid=player.process.pid, activate=True)
                return dict(player.session)
        except (OSError, ValueError):
            pass
        except RuntimeError as error:
            if str(error) != 'WINDOW_NOT_FOUND':
                raise
        time.sleep(.05)
    raise RuntimeError('FIRST_FRAME_TIMEOUT')
