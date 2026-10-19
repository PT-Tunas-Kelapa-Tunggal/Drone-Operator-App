"""Pure adapter checks. These tests do not replace a real OpenSfM reconstruction."""
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / "ControlDroneMapping/Resources/orthomosaic_worker.py"
spec = importlib.util.spec_from_file_location("orthomosaic_worker", path)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerTests(unittest.TestCase):
    def test_native_threads_are_bounded(self):
        for cores, expected in ((None, 1), (1, 1), (2, 2), (10, 2)):
            with patch.object(worker.os, "cpu_count", return_value=cores):
                self.assertEqual(worker.native_feature_threads(), expected)

    def test_stage_metrics_survive_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "performance.json"
            report = {"stages": []}
            with self.assertRaisesRegex(RuntimeError, "stage failed"):
                with worker.measured_stage(report, "reconstruct", path):
                    self.assertEqual(json.loads(path.read_text())["stages"][0]["status"], "running")
                    raise RuntimeError("stage failed")
            record = json.loads(path.read_text())["stages"][0]
            self.assertEqual(record["status"], "failed")
            self.assertGreaterEqual(record["wallSeconds"], 0)
            self.assertGreater(record["workerPeakRSSBytes"], 0)

    def gps(self, points):
        return {str(i): {"gps": {"latitude": lat, "longitude": lon}} for i, (lat, lon) in enumerate(points)}

    def test_gps_requires_distributed_positions(self):
        self.assertFalse(worker.has_georeference({}))
        self.assertFalse(worker.has_georeference(self.gps([(-6, 106)] * 4)))
        self.assertFalse(worker.has_georeference(self.gps([(-6, 106), (-6, 106.001), (-6, 106.002)])))
        self.assertFalse(worker.has_georeference(self.gps([(float("nan"), 106), (0, 0), (1, 1)])))
        self.assertTrue(worker.has_georeference(self.gps([(-6, 106), (-6.001, 106), (-6, 106.001)])))

    def test_reconstruction_rejects_partial_or_disconnected_blocks(self):
        with tempfile.TemporaryDirectory() as folder:
            reconstruction = Path(folder) / "reconstruction.json"
            def save(blocks):
                reconstruction.write_text(json.dumps(blocks))
            full = {"shots": {"a": {}, "b": {}, "c": {}}, "points": {"p": {}}}
            save([full])
            self.assertEqual(worker.validate_reconstruction(reconstruction, ["a", "b", "c"]), 3)
            save([dict(full, shots={"a": {}, "b": {}})])
            with self.assertRaisesRegex(RuntimeError, "Hanya 2/3"):
                worker.validate_reconstruction(reconstruction, ["a", "b", "c"])
            save([full, full])
            with self.assertRaisesRegex(RuntimeError, "beberapa blok"):
                worker.validate_reconstruction(reconstruction, ["a", "b", "c"])
            save([dict(full, points={})])
            with self.assertRaisesRegex(RuntimeError, "titik permukaan"):
                worker.validate_reconstruction(reconstruction, ["a", "b", "c"])

    def test_cli_arguments_are_not_shell_interpolated(self):
        before = sys.argv
        with patch.object(worker.runpy, "run_path", side_effect=lambda *a, **k: self.assertEqual(
            sys.argv, ["/engine/opensfm_main.py", "dense_merging", "--georeferenced", "/misi/foto $name; test"]
        )):
            worker.run_stage(Path("/engine/opensfm_main.py"), "dense_merging", Path("/misi/foto $name; test"), "--georeferenced")
        self.assertIs(sys.argv, before)

    def test_failed_cli_exit_is_a_processing_error(self):
        before = sys.argv
        with patch.object(worker.runpy, "run_path", side_effect=SystemExit(2)):
            with self.assertRaisesRegex(RuntimeError, "reconstruct gagal"):
                worker.run_stage(Path("/engine/main.py"), "reconstruct", Path("/dataset"))
        self.assertIs(sys.argv, before)

    def test_pool_child_termination_does_not_kill_the_worker(self):
        program = '''
import importlib.util, os, signal, sys, time
spec = importlib.util.spec_from_file_location("adapter", sys.argv[1])
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
adapter.isolate_process_group()
reader, writer = os.pipe()
child = os.fork()
if child == 0:
    os.close(reader)
    os.write(writer, b"ready")
    time.sleep(10)
    os._exit(0)
os.close(writer)
os.read(reader, 5)
os.kill(child, signal.SIGTERM)
os.waitpid(child, 0)
print("parent survived")
'''
        result = subprocess.run([sys.executable, "-c", program, str(path)], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("parent survived", result.stdout)

    def test_feature_errors_propagate_without_queue_deadlock(self):
        from unittest.mock import Mock
        data = Mock()
        data.images.return_value = ["a.png", "b.png", "c.png"]
        data.config = {"features_bake_segmentation": False}
        data.load_features.return_value = types.SimpleNamespace(points=[1, 2])
        detector = Mock()
        action = types.SimpleNamespace(write_report=Mock())
        cv2 = types.SimpleNamespace(getNumThreads=lambda: 4, setNumThreads=Mock())
        opensfm = types.ModuleType("opensfm")
        opensfm.dataset = types.SimpleNamespace(DataSet=lambda path: data)
        opensfm.features_processing = types.SimpleNamespace(detect=detector)
        actions = types.ModuleType("opensfm.actions")
        actions.detect_features = action
        with patch.dict(sys.modules, {"cv2": cv2, "opensfm": opensfm, "opensfm.actions": actions}), \
             patch.object(worker, "emit") as events:
            worker.detect_features(Path("/dataset"))
            self.assertEqual(detector.call_count, 3)
            self.assertIn("3/3", events.call_args.kwargs["message"])
            detector.side_effect = RuntimeError("bad input")
            with self.assertRaisesRegex(RuntimeError, "bad input"):
                worker.detect_features(Path("/dataset"))
            cv2.setNumThreads.assert_called_with(4)
            detector.side_effect = None
            data.load_features.return_value = types.SimpleNamespace(points=[])
            with self.assertRaisesRegex(RuntimeError, "Tidak ditemukan titik"):
                worker.detect_features(Path("/dataset"))

    def test_pipeline_keeps_camera_groups_and_gates_geotiff_export(self):
        # Test orchestration against documented command boundaries; not a reconstruction benchmark.
        for georeferenced in (False, True):
            with self.subTest(georeferenced=georeferenced), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                dataset = folder / "dataset"
                (dataset / "images").mkdir(parents=True)
                names = ["a.png", "b.png", "c.png"] + (["d.jpg"] if georeferenced else [])
                for name in names:
                    (dataset / "images" / name).touch()
                request = {"images": [{"image": name} for name in names], "warnings": []}
                metadata = {name: {"make": "Apple", "model": "Test Camera", "width": 256, "height": 192,
                                   "focal_ratio": focal} for name, focal in zip(names, (0.5, 0.5, 0.8, 0.5))}
                if georeferenced:
                    for name, point in zip(names, ((-6, 106), (-6.001, 106), (-6, 106.001))):
                        metadata[name]["gps"] = dict(latitude=point[0], longitude=point[1])
                worker.write_json(folder / "request.json", request)
                worker.write_json(dataset / "exif_overrides.json", metadata)
                commands = []
                def stage(entrypoint, command, path, *options):
                    commands.append((command, options))
                    if command == "reconstruct":
                        worker.write_json(path / "reconstruction.json", [{"shots": dict.fromkeys(names, {}), "points": {"p": {}}}])
                def camera_id(item):
                    return f"camera-{item['focal_ratio']}"
                opensfm = types.ModuleType("opensfm")
                opensfm.exif = types.SimpleNamespace(camera_id=camera_id)
                yaml = types.SimpleNamespace(safe_dump=lambda value, **kwargs: json.dumps(value))
                with patch.dict(sys.modules, {"opensfm": opensfm, "yaml": yaml}), \
                     patch.object(worker, "run_stage", side_effect=stage), \
                     patch.object(worker, "detect_features") as detect, \
                     patch.object(worker, "publish_raster", return_value=(256, 192)) as publish, \
                     patch.object(worker, "emit"):
                    worker.process(folder, folder / "engine/OpenSfM/bin/opensfm_main.py")
                detect.assert_called_once_with(dataset)
                result = json.loads((folder / "result.json").read_text())
                self.assertEqual(result["georeferenced"], georeferenced)
                self.assertEqual(result["registered"], len(names))
                metrics = json.loads((folder / "engine-performance.json").read_text())
                self.assertEqual(len(metrics["stages"]), 11)
                self.assertTrue(all(s["status"] == "completed" for s in metrics["stages"]))
                self.assertEqual(commands[-1], ("dense_merging", ("--georeferenced",) if georeferenced else ()))
                corrected = json.loads((dataset / "exif_overrides.json").read_text())
                if not georeferenced:
                    self.assertTrue(all(item["gps"] == {} for item in corrected.values()))
                else:
                    self.assertEqual(corrected["d.jpg"]["gps"], {})
                self.assertEqual(corrected["a.png"]["camera"], corrected["b.png"]["camera"])
                self.assertNotEqual(corrected["a.png"]["camera"], corrected["c.png"]["camera"])
                settings = json.loads((dataset / "config.yaml").read_text())
                self.assertFalse(settings["equalize_apply_in_bake"])
                self.assertEqual(settings["ortho_bake_n_final_views"], 1)
                self.assertFalse(settings["dsm_merge_feather"])
                self.assertFalse(settings["ortho_detail_injection"])
                self.assertEqual(publish.call_args.args[-1], georeferenced)


if __name__ == "__main__":
    unittest.main()
