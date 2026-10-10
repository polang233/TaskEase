"""Exercise one app instance across concurrent launches and executable copies.

Uses an isolated validation scope with fixture data. The app does not load user
rules in this mode. Every process launched here is tracked and stopped here.
"""
import argparse
import json
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('application', type=Path)
args = parser.parse_args()
app = args.application.resolve()
assert app.name == 'TaskEase.app' and app.is_dir()
scope = str(uuid.uuid4()).upper()
coordination = Path(tempfile.gettempdir()) / f'TaskEase.Validation.{scope}'
processes = []

def start(bundle):
    child = subprocess.Popen([str(bundle / 'Contents/MacOS/TaskEase'), '--instance-test-scope', scope],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    processes.append(child)
    return child

def owner(expected_pid):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        try:
            record = json.loads((coordination / 'application-owner.json').read_text())
            if record['ready'] and record['identity']['pid'] == expected_pid:
                return record
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    raise AssertionError('Application owner did not become ready')

try:
    with tempfile.TemporaryDirectory(prefix='taskease-copy-') as temporary:
        copied = Path(temporary) / 'TaskEase.app'
        shutil.copytree(app, copied, symlinks=True)
        first = start(app)
        owner(first.pid)
        duplicates = [start(app if index % 2 == 0 else copied) for index in range(4)]
        for child in duplicates:
            assert child.wait(timeout=8) == 0
        assert first.poll() is None
        assert sum(child.poll() is None for child in processes) == 1
        owner(first.pid)
        first.kill()
        first.wait(timeout=5)
        recovered = start(copied)
        owner(recovered.pid)
        assert recovered.poll() is None
        assert sum(child.poll() is None for child in processes) == 1
        print(json.dumps({'scope': 'isolated_application_fixture', 'passed': True,
                          'concurrentDuplicateCount': 4, 'instanceCountAfterDuplicates': 1,
                          'differentAppCopiesShareOneInstance': True, 'restartAfterCrash': True}, indent=2))
finally:
    for child in reversed(processes):
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=3)
    shutil.rmtree(coordination, ignore_errors=True)
