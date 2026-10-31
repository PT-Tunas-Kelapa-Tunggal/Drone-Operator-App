"""OpenSfM community 1.x adapter. Invoked by the Mac app, never through a shell.

All OpenSfM stages run inside this process so cancellation terminates the session,
including its multiprocessing children. Inputs are original sRGB JPEGs or prepared
by Core Image, with optional gray-card normalization. No per-image equalization
or cosmetic color enhancement is requested.
"""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
from contextlib import contextmanager
import faulthandler
import json
import math
import os
from pathlib import Path
import runpy
import resource
import signal
import sys
import traceback
import threading
import tempfile
import time


def emit(event, **values):
    print("DRONEMAP_EVENT " + json.dumps(dict(event=event, **values), allow_nan=False), flush=True)


def write_json(path, value):
    temporary = path.with_suffix(".pending")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False))
    temporary.replace(path)


def native_feature_threads():
    # M5 measurements: two native threads match four within 1%, using fewer cores.
    # Keep one image in flight; joblib producer queues can deadlock in App Sandbox.
    return min(2, os.cpu_count() or 1)


@contextmanager
def measured_stage(report, name, path):
    started, cpu = time.monotonic(), time.process_time()
    record = dict(stage=name, status="running")
    report["stages"].append(record)
    write_json(path, report)
    try:
        yield
        record["status"] = "completed"
    except BaseException:
        record["status"] = "failed"
        raise
    finally:
        record["wallSeconds"] = time.monotonic() - started
        record["workerCPUSeconds"] = time.process_time() - cpu
        # This is the cumulative worker high-water mark, not total system or GPU memory.
        rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        record["workerPeakRSSBytes"] = rss if sys.platform == "darwin" else rss * 1024
        write_json(path, report)


def require_gpu():
    library = ctypes.util.find_library("OpenCL")
    if not library:
        raise RuntimeError("OpenCL tidak tersedia. Engine dense membutuhkan GPU yang mendukung OpenCL.")
    cl = ctypes.CDLL(library)
    count = ctypes.c_uint()
    cl.clGetPlatformIDs.argtypes = [ctypes.c_uint, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_uint)]
    cl.clGetDeviceIDs.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_uint,
                               ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_uint)]
    if cl.clGetPlatformIDs(0, None, ctypes.byref(count)) != 0 or not count.value:
        raise RuntimeError("Platform OpenCL tidak ditemukan.")
    platforms = (ctypes.c_void_p * count.value)()
    cl.clGetPlatformIDs(count.value, platforms, None)
    for platform in platforms:
        devices = ctypes.c_uint()
        if cl.clGetDeviceIDs(platform, 1 << 2, 0, None, ctypes.byref(devices)) == 0 and devices.value:
            return
    if os.environ.get("DRONEMAP_ALLOW_NO_GPU") == "1":
        return
    raise RuntimeError("GPU OpenCL tidak ditemukan. Rekonstruksi belum dapat dijalankan.")


def prepare_runtime(runtime):
    source = runtime / "OpenSfM"
    entrypoint = source / "bin" / "opensfm_main.py"
    if not entrypoint.is_file():
        raise RuntimeError("Folder engine tidak lengkap: OpenSfM/bin/opensfm_main.py tidak ditemukan.")
    sys.path.insert(0, str(source))
    import numpy  # noqa: F401
    import cv2  # noqa: F401
    import rasterio  # noqa: F401
    import yaml  # noqa: F401
    from PIL import Image  # noqa: F401
    from opensfm import commands, config, dataset, exif, pygeometry  # noqa: F401
    defaults = config.default_config()
    required = {"dsm_enabled", "ortho_bake_n_final_views", "equalize_apply_in_bake",
                "ortho_detail_injection", "ortho_median_threshold", "dsm_merge_feather"}
    if not required.issubset(defaults):
        raise RuntimeError("Versi OpenSfM belum mendukung pipeline ini. Gunakan engine komunitas 1.x sesuai panduan.")
    command_names = {module.__name__.rsplit(".", 1)[-1] for module in commands.opensfm_commands}
    if not {"dense_clustering", "compute_depthmaps", "fuse_depthmaps", "dense_merging"}.issubset(command_names):
        raise RuntimeError("Engine tidak menyediakan tahap rekonstruksi permukaan yang dibutuhkan.")
    require_gpu()
    return entrypoint


def has_georeference(overrides):
    """Require distributed GPS observations; EXIF alone does not prove alignment."""
    points = []
    for item in overrides.values():
        gps = item.get("gps", {})
        lat, lon = gps.get("latitude"), gps.get("longitude")
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
            if math.isfinite(lat) and math.isfinite(lon) and -80 <= lat <= 84 and -180 <= lon <= 180:
                points.append([lon, lat])
    if len(points) < 3:
        return False
    mean_x = sum(p[0] for p in points) / len(points)
    mean_y = sum(p[1] for p in points) / len(points)
    longitude_scale = math.cos(math.radians(mean_y))
    centered = [((x - mean_x) * 111_000 * longitude_scale, (y - mean_y) * 111_000) for x, y in points]
    xx = sum(x * x for x, y in centered)
    yy = sum(y * y for x, y in centered)
    xy = sum(x * y for x, y in centered)
    # Smallest singular value > 1 m: repeated or effectively collinear fixes do not qualify.
    return (xx + yy - math.hypot(xx - yy, 2 * xy)) / 2 > 1.0


def validate_reconstruction(path, expected):
    reconstructions = json.loads(path.read_text())
    if not isinstance(reconstructions, list) or len(reconstructions) != 1:
        raise RuntimeError("Foto terpisah menjadi beberapa blok atau gagal direkonstruksi. Tambahkan foto penghubung dengan overlap yang cukup.")
    shots = set(reconstructions[0].get("shots", {}))
    if shots != set(expected):
        raise RuntimeError(f"Hanya {len(shots)}/{len(expected)} foto masuk satu rekonstruksi. Hasil parsial tidak dinyatakan selesai.")
    if not reconstructions[0].get("points"):
        raise RuntimeError("Rekonstruksi tidak memiliki titik permukaan.")
    return len(shots)


def run_stage(entrypoint, command, dataset, *options):
    saved = sys.argv
    try:
        sys.argv = [str(entrypoint), command, *options, str(dataset)]
        try:
            runpy.run_path(str(entrypoint), run_name="__main__")
        except SystemExit as error:
            if error.code not in (0, None):
                raise RuntimeError(f"Tahap {command} gagal (kode {error.code}).") from error
    finally:
        sys.argv = saved


@contextmanager
def stage_activity(message, fraction):
    """Show elapsed time even while native code is busy; dump stacks for diagnostics."""
    stopped = threading.Event()
    start = time.monotonic()

    def heartbeat():
        while not stopped.wait(5):
            emit("progress", message=f"{message} · {int(time.monotonic() - start)} detik", fraction=fraction)

    emit("progress", message=message, fraction=fraction)
    thread = threading.Thread(target=heartbeat, daemon=True)
    thread.start()
    faulthandler.dump_traceback_later(120, repeat=True)
    try:
        yield
    finally:
        stopped.set()
        thread.join()
        faulthandler.cancel_dump_traceback_later()


def detect_features(dataset_path):
    """Avoid producer/consumer queues: errors propagate and each image has progress.

    This also avoids OpenSfM's Linux `free` subprocess when planning its queue on
    macOS. Only the adapter changes; upstream detection and report formats remain.
    """
    import cv2
    from opensfm import dataset, features_processing
    from opensfm.actions import detect_features as action
    data = dataset.DataSet(str(dataset_path))
    names = data.images()
    started = time.monotonic()
    old_threads = cv2.getNumThreads()
    cv2.setNumThreads(native_feature_threads())
    try:
        for index, name in enumerate(names):
            message = f"Mencari titik foto · {index + 1}/{len(names)} · {name}"
            fraction = 0.06 + 0.09 * index / max(1, len(names))
            with stage_activity(message, fraction):
                pixels = data.load_image(name)
                segmentation = data.load_segmentation(name) if data.config["features_bake_segmentation"] else None
                instances = data.load_instances(name) if data.config["features_bake_segmentation"] else None
                features_processing.detect(name, pixels, segmentation, instances, data, False)
                del pixels, segmentation, instances
                found = data.load_features(name)
                if found is None or len(found.points) == 0:
                    raise RuntimeError(f"Tidak ditemukan titik visual pada {name}. Gunakan foto yang tajam dan memiliki tekstur.")
            emit("progress", message=f"Titik foto selesai · {index + 1}/{len(names)}",
                 fraction=0.06 + 0.09 * (index + 1) / max(1, len(names)))
        action.write_report(data, time.monotonic() - started)
    finally:
        cv2.setNumThreads(old_threads)


def publish_raster(source, destination, georeferenced):
    import numpy as np
    import rasterio
    from rasterio.enums import Resampling
    from PIL import Image
    with rasterio.open(source) as src:
        if src.count not in (3, 4) or src.width <= 0 or src.height <= 0:
            raise RuntimeError("Orthophoto engine bukan raster RGB/RGBA yang valid.")
        if not all(math.isfinite(x) for x in src.transform) or abs(src.transform.determinant) < 1e-20:
            raise RuntimeError("Transformasi raster tidak valid.")
        if georeferenced and (src.crs is None or not src.crs.is_projected):
            raise RuntimeError("Georeferencing tidak menghasilkan CRS proyeksi. GeoTIFF tidak dipublikasikan.")
        profile = src.profile.copy()
        profile.update(driver="GTiff", compress="deflate", tiled=True, blockxsize=256,
                       blockysize=256, BIGTIFF="IF_SAFER")
        if not georeferenced:
            # A local SfM grid is not an Earth coordinate reference system.
            profile["crs"] = None
        covered = False
        with rasterio.Env(GDAL_TIFF_INTERNAL_MASK=True), rasterio.open(destination, "w", **profile) as dst:
            dst.colorinterp = src.colorinterp
            for _, window in src.block_windows(1):
                pixels = src.read(window=window)
                mask = src.dataset_mask(window=window)
                covered |= bool(np.any(mask))
                dst.write(pixels, window=window)
                dst.write_mask(mask, window=window)
        if not covered:
            raise RuntimeError("Orthomosaic tidak memiliki piksel permukaan yang valid.")
        scale = min(1, 1200 / max(src.width, src.height))
        size = (max(1, round(src.width * scale)), max(1, round(src.height * scale)))
        preview = src.read(indexes=[1, 2, 3], out_shape=(3, size[1], size[0]), resampling=Resampling.nearest)
        if preview.dtype != np.uint8:
            raise RuntimeError("Engine menghasilkan tipe piksel yang tidak didukung; diharapkan RGB 8-bit.")
        alpha = src.dataset_mask(out_shape=(size[1], size[0]), resampling=Resampling.nearest)
        rgba = np.concatenate([preview.transpose(1, 2, 0), alpha[..., None]], axis=2)
        Image.fromarray(rgba).save(destination.with_name("preview.png"))
        return src.width, src.height


def process(run_folder, entrypoint):
    import yaml
    from opensfm import exif
    request = json.loads((run_folder / "request.json").read_text())
    dataset = run_folder / "dataset"
    overrides = json.loads((dataset / "exif_overrides.json").read_text())
    names = [item["image"] for item in request["images"]]
    if len(names) < 3 or len(set(names)) != len(names):
        raise RuntimeError("Input pemetaan minimal 3 foto berbeda.")
    if set(overrides) != set(names):
        raise RuntimeError("Metadata kamera tidak cocok dengan daftar foto.")
    for name in names:
        if Path(name).name != name or not (dataset / "images" / name).is_file():
            raise RuntimeError("Daftar foto pemetaan tidak valid.")
    geo = has_georeference(overrides)
    warnings = list(request.get("warnings", []))
    if not geo:
        warnings.append("Koordinat GPS tersebar yang memadai belum tersedia. TIFF memakai grid lokal; posisi dan skala absolut belum tervalidasi.")
        # Do not partially anchor a scene with repeated/collinear coordinates.
        for item in overrides.values():
            item["gps"] = {}
        write_json(dataset / "exif_overrides.json", overrides)
    else:
        warnings.append("GeoTIFF memakai referensi GPS perkiraan; akurasi absolut belum diukur dengan checkpoint.")
    missing_focal = sum("focal_ratio" not in item for item in overrides.values())
    if missing_focal:
        warnings.append(f"{missing_focal} foto tidak memiliki focal length ekuivalen; engine mengestimasi kalibrasi kamera.")
    for item in overrides.values():
        # Overrides merge into embedded JPEG EXIF. Explicitly clear rejected or
        # stale positions so the original tags cannot silently restore them.
        item.setdefault("gps", {})
        item.setdefault("projection_type", "perspective")
        item.setdefault("focal_ratio", 0.0)
        # Prepared PNGs do not retain camera EXIF. Override the camera identifier
        # as well as its fields so different source lenses/resolutions cannot collapse
        # into the same unknown-PNG camera model during metadata extraction.
        item["camera"] = exif.camera_id(item)
    write_json(dataset / "exif_overrides.json", overrides)
    settings = {
        "feature_type": "SIFT", "feature_process_size": 2048,
        "matcher_type": "FLANN", "matching_gps_distance": 0,
        "processes": 2, "io_processes": 2, "proj_cdn_enabled": False,
        "bundle_use_gps": geo, "bundle_use_gcp": False,
        "undistorted_image_format": "png", "undistorted_image_max_size": 4096,
        "depthmap_max_image_size": 1600, "depthmap_fusion_mesh_enabled": False,
        "dense_pointcloud_export_las": False, "dense_pointcloud_export_laz": False,
        "dsm_enabled": True, "dsm_merge_max_ram_mb": 512,
        "equalize_apply_in_bake": False,
        "ortho_bake_n_final_views": 1, "ortho_detail_injection": False,
        "ortho_median_threshold": 1e9, "dsm_merge_feather": False,
    }
    (dataset / "config.yaml").write_text(yaml.safe_dump(settings, sort_keys=True))
    stages = [
        ("extract_metadata", "Membaca kamera dan lokasi", 0.01),
        ("detect_features", "Mencari titik foto", 0.06),
        ("match_features", "Mencocokkan foto", 0.15),
        ("create_tracks", "Menyusun titik penghubung", 0.25),
        ("reconstruct", "Menghitung posisi kamera", 0.30),
        ("undistort", "Mengoreksi distorsi lensa", 0.44),
        ("dense_clustering", "Menyiapkan rekonstruksi permukaan", 0.50),
        ("compute_depthmaps", "Menghitung kedalaman permukaan", 0.55),
        ("fuse_depthmaps", "Membangun permukaan dan orthomosaic", 0.75),
        ("dense_merging", "Menyusun TIFF dan koordinat", 0.90),
    ]
    registered = 0
    performance = dict(version=1, featureNativeThreads=native_feature_threads(), stages=[])
    performance_path = run_folder / "engine-performance.json"
    for command, message, fraction in stages:
        emit("progress", message=message, fraction=fraction)
        options = ["--georeferenced"] if command == "dense_merging" and geo else []
        with measured_stage(performance, command, performance_path):
            if command == "detect_features":
                detect_features(dataset)
            else:
                with stage_activity(message, fraction):
                    run_stage(entrypoint, command, dataset, *options)
            if command == "reconstruct":
                registered = validate_reconstruction(dataset / "reconstruction.json", names)
    emit("progress", message="Memeriksa TIFF hasil", fraction=0.97)
    with measured_stage(performance, "publish_raster", performance_path):
        width, height = publish_raster(dataset / "undistorted/depthmaps/ortho.tif",
                                       run_folder / "orthomosaic.tif", geo)
    result = dict(georeferenced=geo, width=width, height=height, registered=registered, warnings=warnings)
    write_json(run_folder / "result.json", result)
    engine_file = entrypoint.parent.parent.parent / "engine.json"
    engine = json.loads(engine_file.read_text()) if engine_file.is_file() else {"version": "unrecorded"}
    write_json(run_folder / "processing-report.json", dict(request=request, engine=engine, settings=settings,
                                                          performance=performance, result=result))
    emit("progress", message="Orthomosaic selesai", fraction=1.0)


def check_features(entrypoint):
    """Small synthetic smoke test of the real native detector inside the app sandbox."""
    import numpy as np
    import yaml
    from PIL import Image
    with tempfile.TemporaryDirectory(prefix="orthomosaic-feature-check-") as temporary:
        folder = Path(temporary)
        (folder / "images").mkdir()
        rng = np.random.default_rng(42)
        for i in range(12):
            pixels = rng.integers(0, 256, (512, 512, 3), dtype=np.uint8)
            Image.fromarray(pixels).save(folder / "images" / f"diagnostic_{i}.png")
        (folder / "config.yaml").write_text(yaml.safe_dump({
            "feature_type": "SIFT", "feature_process_size": 512,
            "processes": 1, "io_processes": 1, "matcher_type": "FLANN",
        }))
        run_stage(entrypoint, "extract_metadata", folder)
        detect_features(folder)
    from joblib._parallel_backends import ThreadingBackend
    workers = ThreadingBackend().effective_n_jobs(2)
    emit("ready", message=f"Deteksi titik foto nyata selesai: 12/12 foto uji sintetis "
                         f"(joblib workers: {workers}, native threads: {native_feature_threads()})")


def isolate_process_group():
    try:
        os.setsid()
    except OSError:
        return

    owner = os.getpid()

    def terminate_session(signum, frame):
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        if os.getpid() == owner:
            os.killpg(os.getpgrp(), signal.SIGTERM)
        else:
            # A fork-based Pool may inherit this handler; terminating one pool
            # child during normal teardown must not kill the entire pipeline.
            os.kill(os.getpid(), signal.SIGTERM)

    signal.signal(signal.SIGTERM, terminate_session)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--check-features", action="store_true")
    mode.add_argument("--run", type=Path)
    args = parser.parse_args()
    isolate_process_group()
    try:
        entrypoint = prepare_runtime(args.runtime.resolve())
        if args.check:
            emit("ready", message="OpenSfM dan GPU lokal siap")
        elif args.check_features:
            check_features(entrypoint)
        else:
            process(args.run.resolve(), entrypoint)
    except Exception as error:
        traceback.print_exc()
        emit("error", message=str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
