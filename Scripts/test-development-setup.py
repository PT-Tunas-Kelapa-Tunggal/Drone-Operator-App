#!/usr/bin/env python3
"""Offline regression checks for developer bootstrap; native compilation is not simulated."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
LOCKS = REPO / 'Config/Engine'
COMMIT = (LOCKS / 'opensfm-commit.txt').read_text().strip()
RECIPE = hashlib.sha256(b''.join((LOCKS / name).read_bytes() for name in (
    'opensfm-commit.txt', 'conda-osx-arm64.lock',
    'requirements-runtime.lock', 'requirements-build.lock',
))).hexdigest()


class DevelopmentSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='drone-development-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.engine = self.root / 'engine'
        self.log = self.root / 'commands.jsonl'
        self.environment = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                                TEST_LOG=str(self.log), TEST_COMMIT=COMMIT)
        self.tool('uname', '#!/bin/sh\ncase "$1" in -m) echo arm64;; -s) echo Darwin;; esac\n')
        # These stand-ins record operations instead of contacting GitHub/conda/PyPI.
        self.tool('git', '''#!/usr/bin/python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ['TEST_LOG'], 'a') as f: f.write(json.dumps(['git'] + args) + '\\n')
if args[0] == 'clone': pathlib.Path(args[-1]).mkdir()
elif 'rev-parse' in args: print(os.environ.get('TEST_SOURCE_COMMIT', os.environ['TEST_COMMIT']))
elif 'status' in args: print(os.environ.get('TEST_SOURCE_DIRTY', ''), end='')
''')
        self.tool('micromamba', '''#!/usr/bin/python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ['TEST_LOG'], 'a') as f: f.write(json.dumps(['manager'] + args) + '\\n')
if args[0] == 'create':
    executable = pathlib.Path(args[args.index('--prefix') + 1]) / 'bin/python3'
    executable.parent.mkdir(parents=True)
    executable.write_text('#!/bin/sh\\nif [ "$1" = "-c" ]; then exec /usr/bin/python3 "$@"; fi\\nexit 0\\n')
    executable.chmod(0o755)
''')

    def tool(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_setup(self, *args, success=True):
        result = subprocess.run(['bash', str(REPO / 'Scripts/setup-orthomosaic-engine.sh'),
                                 *map(str, args)], env=self.environment,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_fresh_install_pins_source_native_packages_and_wheels(self):
        self.run_setup(self.engine)
        commands = self.commands()
        self.assertIn(['git', '-C', str(self.engine / 'OpenSfM'), 'checkout', '--detach', COMMIT], commands)
        create = next(c for c in commands if c[:2] == ['manager', 'create'])
        self.assertEqual(create[create.index('--file') + 1], str(LOCKS / 'conda-osx-arm64.lock'))
        wheel_install = next(c for c in commands if '--require-hashes' in c)
        self.assertIn('--no-deps', wheel_install)
        self.assertIn('--only-binary=:all:', wheel_install)
        source_install = next(c for c in commands if '-e' in c)
        self.assertIn('--no-deps', source_install)
        self.assertIn('--no-build-isolation', source_install)
        metadata = json.loads((self.engine / 'engine.json').read_text())
        self.assertEqual(metadata['commit'], COMMIT)
        self.assertEqual(metadata['developmentLockSHA256'], RECIPE)
        self.assertIn('embedded package', self.run_setup(self.engine).stdout)
        self.assertTrue(any(c[:2] == ['manager', 'install'] for c in self.commands()))

    def test_rejects_unmanaged_environment_without_modifying_it(self):
        (self.engine / 'environment').mkdir(parents=True)
        sentinel = self.engine / 'environment/keep-me'
        sentinel.write_text('existing work')
        self.assertIn('Choose a new destination', self.run_setup(self.engine, success=False).stderr)
        self.assertEqual(sentinel.read_text(), 'existing work')
        self.assertEqual(self.commands(), [])

    def test_rejects_changed_locks_without_network_or_mutation(self):
        self.engine.mkdir()
        marker = self.engine / '.development-lock.sha256'
        marker.write_text('old-recipe\n')
        self.assertIn('Dependency locks changed', self.run_setup(self.engine, success=False).stderr)
        self.assertEqual(marker.read_text(), 'old-recipe\n')
        self.assertEqual(self.commands(), [])

    def test_preserves_source_with_another_commit(self):
        (self.engine / 'OpenSfM').mkdir(parents=True)
        self.environment['TEST_SOURCE_COMMIT'] = '0' * 40
        self.assertIn('differs from the pinned commit', self.run_setup(self.engine, success=False).stderr)
        self.assertFalse(any(c[0] == 'manager' or 'checkout' in c for c in self.commands()))

    def test_preserves_local_source_edits(self):
        (self.engine / 'OpenSfM').mkdir(parents=True)
        self.environment['TEST_SOURCE_DIRTY'] = ' M opensfm/local.py\n'
        self.assertIn('local source changes', self.run_setup(self.engine, success=False).stderr)
        self.assertFalse(any(c[0] == 'manager' or 'checkout' in c for c in self.commands()))

    def test_rejects_invalid_paths_and_arguments(self):
        self.run_setup(success=False)
        self.run_setup('relative/path', success=False)
        self.run_setup(self.root / 'has spaces', success=False)
        self.run_setup('--help')
        self.assertEqual(self.commands(), [])

    def test_conda_artifacts_have_checksums_and_scipy_is_native(self):
        lines = (LOCKS / 'conda-osx-arm64.lock').read_text().splitlines()
        urls = [line for line in lines if line.startswith('https://')]
        self.assertIn('@EXPLICIT', lines)
        self.assertGreater(len(urls), 100)
        for url in urls:
            self.assertRegex(url, r'^https://conda\.anaconda\.org/[^/]+/(osx-arm64|noarch)/[^#]+#[0-9a-f]{32}$')
        self.assertTrue(any('/scipy-1.15.2-' in url for url in urls))
        for name in ('runtime', 'build'):
            lock = (LOCKS / f'requirements-{name}.lock').read_text()
            requirements = [line for line in lock.splitlines() if line and not line.startswith(('#', ' '))]
            self.assertTrue(requirements)
            for line in requirements:
                self.assertRegex(line, r'^[A-Za-z0-9_-]+==[^ ]+ \\$')
            self.assertEqual(len(requirements), len(re.findall(r'^    --hash=sha256:', lock, re.M))
                             - len(re.findall(r'^    --hash=sha256:.* \\$', lock, re.M)))


if __name__ == '__main__':
    unittest.main(verbosity=2)
