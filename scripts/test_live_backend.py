#!/usr/bin/env python3
"""Boot a disposable real backend/provider, run the native test, then clean up."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

project = Path(__file__).resolve().parent.parent
backend = project.parent / 'mukai'
runner = backend / 'node_modules' / '.bin' / 'tsx'
if not runner.exists():
    sys.exit('Install the sibling Mukai backend dependencies first (npm ci).')
with tempfile.TemporaryDirectory(prefix='mukai-native-test-') as directory:
    metadata = Path(directory) / 'connection.json'
    environment = dict(os.environ, MUKAI_FIXTURE_METADATA=str(metadata))
    with (Path(directory) / 'backend.log').open('w+') as log:
        fixture = subprocess.Popen([str(runner), str(project / 'scripts/live_backend_fixture.ts')], cwd=backend, env=environment, stdout=log, stderr=subprocess.STDOUT)
        ran_flutter = False
        restore_result = 0
        try:
            for _ in range(400):
                if metadata.exists():
                    break
                if fixture.poll() is not None:
                    log.seek(0)
                    sys.exit(log.read())
                time.sleep(.1)
            else:
                sys.exit('The isolated backend did not become ready.')
            connection = json.loads(metadata.read_text())
            command = [str(project / 'scripts/ios.sh'), 'test', 'integration_test/live_backend_test.dart', '--dart-define=MUKAI_TEST_BASE_URL=' + connection['baseUrl'], '--dart-define=MUKAI_TEST_USERNAME=' + connection['username'], '--dart-define=MUKAI_TEST_PASSWORD=' + connection['password'], '--dart-define=MUKAI_TEST_CAPTURE_URL=' + connection['captureUrl'], *sys.argv[1:]]
            ran_flutter = True
            result = subprocess.run(command, cwd=project)
            log.seek(0)
            backend_output = log.read()
            if result.returncode:
                print(backend_output, file=sys.stderr)
            else:
                for line in backend_output.splitlines():
                    if line.startswith('MUKAI_VISUAL_CAPTURE:'):
                        print(line)
        finally:
            if fixture.poll() is None:
                fixture.send_signal(signal.SIGINT)
                try:
                    fixture.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    fixture.kill()
                    fixture.wait()
            if ran_flutter:
                # Native tests replace Xcode's entry point with a temporary listener.
                print('Restoring Xcode settings for lib/main.dart.', flush=True)
                restore_result = subprocess.run([
                    str(project / 'scripts/ios.sh'), 'build', 'ios',
                    '--config-only', '--debug', '--no-codesign', '--no-pub',
                    '--target', 'lib/main.dart',
                ], cwd=project).returncode
        sys.exit(result.returncode or restore_result)
