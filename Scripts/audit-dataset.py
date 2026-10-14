#!/usr/bin/env python3
"""Read-only audit of one exported mission. Never modifies original photos."""
import hashlib
import json
import sys
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def audit(folder):
    errors = []
    manifest = json.loads((folder / 'mission.json').read_text())
    mapping = 0
    calibration = 0
    tests = 0
    indexes = list((folder / 'Metadata').glob('*.json'))
    indexes += [entry / 'capture.json' for entry in folder.iterdir()
                if entry.is_dir() and not entry.name.startswith('.') and (entry / 'capture.json').is_file()]
    seen = set()
    for index in sorted(indexes):
        capture_folder = index.parent
        try:
            capture = json.loads(index.read_text())
            flat = capture.get('layoutVersion') == 2
            capture_id = index.stem if flat else capture_folder.name
            if capture['id'].lower() in seen:
                errors.append(f'{capture_id}: duplicate capture index')
                continue
            seen.add(capture['id'].lower())
            if capture['missionID'].lower() != manifest['id'].lower():
                errors.append(f'{capture_folder.name}: mission ID mismatch')
            if capture['id'].lower() != capture_id.lower():
                errors.append(f'{capture_folder.name}: capture ID mismatch')
            if capture['kind'] == 'mapping':
                mapping += 1
            elif capture['kind'] == 'quality-test':
                tests += 1
            elif capture['kind'] in ('calibration-before', 'calibration-after'):
                calibration += 1
            else:
                errors.append(f'{capture_folder.name}: unknown capture kind')
            expected = {'.jpg', '.dng'} if capture['settings']['raw'] else {'.jpg'}
            if {Path(name).suffix for name in capture['files']} != expected or len(capture['files']) != len(expected):
                errors.append(f'{capture_id}: incomplete format set')
            for name in capture['files']:
                relative = Path(name)
                if relative.is_absolute() or '..' in relative.parts or len(relative.parts) > 2:
                    errors.append(f'{capture_id}: invalid path')
                    continue
                path = (folder if flat else capture_folder) / name
                if digest(path) != capture['sha256'].get(name):
                    errors.append(f'{name}: checksum mismatch')
                sidecar = folder / 'Metadata' / (relative.name + '.metadata.plist') if flat else capture_folder / (name + '.metadata.plist')
                if not sidecar.is_file():
                    errors.append(f'{name}: missing original metadata sidecar')
                if flat and path.suffix == '.jpg':
                    expected_parent = folder if capture['kind'] == 'mapping' else folder / 'Calibration'
                    if path.parent != expected_parent:
                        errors.append(f'{name}: image in wrong import group')
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(f'{capture_folder.name}: {error}')
    if mapping != manifest['saved']:
        errors.append(f'Manifest says {manifest["saved"]} mapping captures, found {mapping}')
    if not mapping and not calibration and not tests:
        errors.append('No committed captures found')
    print(f'Mapping: {mapping}; calibration references: {calibration}; test photos: {tests}; phase: {manifest["phase"]}')
    print('Image hashes and available captures checked. This does not certify survey accuracy or radiometric quality.')
    for error in errors:
        print('FAIL:', error)
    return 1 if errors else 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: audit-dataset.py /path/to/mission-uuid')
    try:
        sys.exit(audit(Path(sys.argv[1])))
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(f'FAIL: {error}')
