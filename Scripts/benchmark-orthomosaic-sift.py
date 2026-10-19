"""Opt-in SIFT thread benchmark. Run with the development OpenSfM Python runtime.

Usage: python benchmark-orthomosaic-sift.py INPUT_IMAGES NEW_REPORT_JSON [COUNT]
Uses unchanged image resolution and extraction settings; verifies exact feature
and descriptor hashes across thread counts. No source files are modified.
"""
import hashlib
import json
from pathlib import Path
import sys
import time

import cv2
from opensfm import config, features, io


def main():
    folder, report = Path(sys.argv[1]), Path(sys.argv[2])
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    if report.exists():
        raise ValueError("Report must not already exist")
    paths = sorted(folder.glob("*.jpg"))[:count]
    if count <= 0 or len(paths) != count:
        raise ValueError("Insufficient JPEG inputs")
    cfg = config.default_config()
    cfg.update(feature_type="SIFT", feature_process_size=2048)
    results = []
    expected = None
    for repetition, order in enumerate(((1, 2, 4), (4, 2, 1))):
        for threads in order:
            cv2.setNumThreads(threads)
            started = time.monotonic()
            counts, digests = [], []
            for path in paths:
                points, descriptors, _ = features.extract_features(io.imread(str(path)), cfg, False)
                counts.append(len(points))
                digests.append(hashlib.sha256(points.tobytes() + descriptors.tobytes()).hexdigest())
            record = dict(repetition=repetition, threads=threads, seconds=time.monotonic() - started,
                          counts=counts, digests=digests)
            results.append(record)
            report.write_text(json.dumps(dict(opencv=cv2.__version__, images=[p.name for p in paths],
                                             results=results), indent=2))
            print(json.dumps(record), flush=True)
            if expected is None:
                expected = digests
            if digests != expected:
                raise RuntimeError("Feature output differs between thread settings; inspect the report")


if __name__ == "__main__":
    main()
