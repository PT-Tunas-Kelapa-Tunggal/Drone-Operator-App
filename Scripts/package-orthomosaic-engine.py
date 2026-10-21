#!/usr/bin/env python3
"""Developer/release step: package an already-built engine for the sandboxed Mac app.

This runs outside the app. The installed runtime never invokes a compiler, pip,
conda, or xcrun. Keep the resulting archive with its generated manifest.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.STDOUT, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--identity', required=True, help='Apple signing identity used for the Mac app')
    parser.add_argument('--timestamp', action='store_true', help='Use secure timestamps for Developer ID releases')
    parser.add_argument('--output', type=Path, default=Path('.build/engine-package'))
    parser.add_argument('--manifest-output', type=Path, default=Path('ControlDroneMapping/Resources/orthomosaic-engine.json'))
    parser.add_argument('--helper-output', type=Path, default=Path('.build/OrthomosaicPython'))
    parser.add_argument('--runtime-output', type=Path, default=Path('.build/OrthomosaicEngine'))
    args = parser.parse_args()
    original = args.runtime.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    build = Path('.build/engine-packaging')
    build.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=build) as temporary:
        parent = Path(temporary).resolve()
        runtime = parent / 'OpenSfM-engine'
        runtime.mkdir()
        print('Menyalin runtime untuk paket distribusi…', flush=True)
        run('/bin/cp', '-cR', str(original/'environment'), str(runtime/'environment'))
        shutil.copytree(original/'OpenSfM', runtime/'OpenSfM', symlinks=True,
                        ignore=shutil.ignore_patterns('build', 'cmake_build', '__pycache__', '.git', '*.egg-info'))
        site = runtime/'environment/lib/python3.10/site-packages'
        for entry in (runtime/'environment/bin').iterdir():
            if entry.name not in {'python', 'python3', 'python3.10'}:
                if entry.is_dir() and not entry.is_symlink():
                    shutil.rmtree(entry)
                else:
                    entry.unlink()
        for name in ('include', 'libexec', 'compiler_compat', 'lib/clang', 'lib/cmake'):
            path = runtime/'environment'/name
            if path.is_dir():
                shutil.rmtree(path)
        # Install compiled extensions alongside the normal Python package, with no
        # editable-import hook pointing back to the developer's source directory.
        if (site/'opensfm').is_dir():
            for extension in (site/'opensfm').glob('*.so'):
                shutil.copy2(extension, runtime/'OpenSfM/opensfm'/extension.name)
            shutil.rmtree(site/'opensfm')
        for pattern in ('*editable*opensfm*', '*opensfm*editable*', 'opensfm*.dist-info'):
            for item in site.glob(pattern):
                if item.is_dir():
                    shutil.rmtree(item)
                else:
                    item.unlink()
        for cache in runtime.rglob('__pycache__'):
            shutil.rmtree(cache)
        for link in runtime.rglob('*'):
            if link.is_symlink() and os.readlink(link).startswith(str(original)+'/'):
                destination = runtime/Path(os.readlink(link)).relative_to(original)
                link.unlink()
                link.symlink_to(os.path.relpath(destination, link.parent))
        magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}
        binaries = []
        for path in runtime.rglob('*'):
            if not path.is_file() or path.is_symlink():
                continue
            with path.open('rb') as handle:
                if handle.read(4) not in magic:
                    continue
            binaries.append(path)
        print('Menyiapkan jalur library relatif dan tanda tangan (%d berkas)…' % len(binaries), flush=True)
        entitlements = parent/'Python.entitlements'
        entitlements.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.inherit</key><true/>
</dict></plist>''')
        python = runtime/'environment/bin/python3.10'
        for index, path in enumerate(binaries):
            identifiers = [line for line in run('/usr/bin/otool', '-D', str(path)).splitlines()
                           if line and not line.endswith(':') and '(architecture ' not in line]
            identifier = identifiers[-1] if identifiers else None
            if identifier and identifier.startswith('/'):
                run('/usr/bin/install_name_tool', '-id', '@rpath/'+path.name, str(path))
            commands = run('/usr/bin/otool', '-l', str(path))
            rpaths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', commands)
            for old in dict.fromkeys(rpaths):
                if old.startswith(str(original)+'/'):
                    mapped = runtime/Path(old).relative_to(original)
                    new = '@loader_path/'+os.path.relpath(mapped, path.parent)
                    run('/usr/bin/install_name_tool', '-rpath', old, new, str(path))
            for line in run('/usr/bin/otool', '-L', str(path)).splitlines()[1:]:
                if not line.startswith('\t'):
                    continue
                dependency = line.strip().split(' (compatibility')[0]
                if dependency.startswith(str(original)+'/'):
                    mapped = runtime/Path(dependency).relative_to(original)
                    new = '@loader_path/'+os.path.relpath(mapped, path.parent)
                    run('/usr/bin/install_name_tool', '-change', dependency, new, str(path))
                elif dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/', '/Library/Apple/')):
                    raise RuntimeError('Library di luar paket: %s: %s' % (path, dependency))
            signing = ['/usr/bin/codesign', '--force', '--sign', args.identity,
                       '--timestamp' if args.timestamp else '--timestamp=none']
            if path == python:
                signing += ['--options', 'runtime', '--identifier', 'com.hata.ControlDroneMapping.engine.python',
                            '--entitlements', str(entitlements)]
            run(*(signing+[str(path)]))
            if (index+1) % 100 == 0:
                print('Ditandatangani: %d/%d' % (index+1, len(binaries)), flush=True)
        details = run('/usr/bin/codesign', '-dvv', str(python))
        team = re.search(r'^TeamIdentifier=(.+)$', details, re.M).group(1)
        if team == 'not set':
            raise RuntimeError('Paket memerlukan identitas Apple, bukan tanda tangan ad-hoc.')
        run('/usr/bin/codesign', '--verify', '--strict', str(python))
        args.helper_output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(python, args.helper_output)
        metadata = json.loads((original/'engine.json').read_text())
        metadata.update({'packaged': True, 'teamIdentifier': team})
        (runtime/'engine.json').write_text(json.dumps(metadata, indent=2))
        if args.runtime_output.exists():
            shutil.rmtree(args.runtime_output)
        run('/bin/cp', '-cR', str(runtime), str(args.runtime_output.resolve()))
        archive = output/'orthomosaic-engine.zip'
        print('Mengarsipkan engine…', flush=True)
        run('/usr/bin/ditto', '-c', '-k', '--keepParent', str(runtime), str(archive))
        digest = hashlib.sha256()
        with archive.open('rb') as handle:
            for chunk in iter(lambda: handle.read(1024*1024), b''):
                digest.update(chunk)
        manifest = dict(formatVersion=1, sha256=digest.hexdigest(), folder='OpenSfM-engine',
                        teamIdentifier=team, pythonIdentifier='com.hata.ControlDroneMapping.engine.python',
                        architecture='arm64', opensfmCommit=metadata['commit'])
        manifest_path = output/'orthomosaic-engine.json'
        manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')
        args.manifest_output.parent.mkdir(parents=True, exist_ok=True)
        if manifest_path.resolve() != args.manifest_output.resolve():
            shutil.copy2(manifest_path, args.manifest_output)
        print('Paket siap: %s (%.0f MB)' % (archive, archive.stat().st_size/1_000_000), flush=True)


if __name__ == '__main__':
    main()
