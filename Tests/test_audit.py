import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

spec = importlib.util.spec_from_file_location('audit', Path(__file__).resolve().parents[1] / 'Scripts/audit-dataset.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

class DatasetAuditTests(unittest.TestCase):
    def test_complete_and_corrupted_transfer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mission, capture_id = str(uuid4()), str(uuid4())
            folder = root / capture_id
            folder.mkdir()
            (root / 'mission.json').write_text(json.dumps({'id': mission, 'saved': 1, 'phase': 'completed'}))
            image = folder / 'image.jpg'
            image.write_bytes(b'synthetic-image-bytes-not-a-real-photograph')
            (folder / 'image.jpg.metadata.plist').write_text('<plist/>')
            capture = {'id': capture_id, 'missionID': mission, 'kind': 'mapping', 'settings': {'raw': False}, 'files': ['image.jpg'], 'sha256': {'image.jpg': audit.digest(image)}}
            (folder / 'capture.json').write_text(json.dumps(capture))
            self.assertEqual(audit.audit(root), 0)
            image.write_bytes(b'corrupted')
            self.assertEqual(audit.audit(root), 1)
            image.unlink()
            self.assertEqual(audit.audit(root), 1)

    def test_flat_mapping_and_calibration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Metadata').mkdir()
            (root / 'Calibration').mkdir()
            mission = str(uuid4())
            (root / 'mission.json').write_text(json.dumps({'id': mission, 'saved': 1, 'phase': 'completed'}))
            for kind in ['mapping', 'quality-test', 'calibration-before']:
                capture_id = str(uuid4())
                name = f'IMG_000001_{capture_id}.jpg'
                if kind != 'mapping':
                    name = 'Calibration/' + name
                image = root / name
                image.write_bytes(kind.encode())
                (root / 'Metadata' / (image.name + '.metadata.plist')).write_text('<plist/>')
                capture = {'layoutVersion': 2, 'id': capture_id, 'missionID': mission, 'kind': kind,
                           'settings': {'raw': False}, 'files': [name], 'sha256': {name: audit.digest(image)}}
                (root / 'Metadata' / (capture_id + '.json')).write_text(json.dumps(capture))
            self.assertEqual(audit.audit(root), 0)
            image.unlink()
            self.assertEqual(audit.audit(root), 1)

    def test_partial_transfer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'mission.json').write_text(json.dumps({'id': str(uuid4()), 'saved': 10, 'phase': 'completed'}))
            self.assertEqual(audit.audit(root), 1)

if __name__ == '__main__':
    unittest.main()
