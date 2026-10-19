# Apple Silicon optimization — 18 October 2026

Test machine: Apple M5 MacBook Pro, 10 CPU cores, 10 GPU cores, 24 GB unified memory. Engine: OpenSfM community commit `c1fbfcec947e0e4fa4d39eb02a66cddac10934ad`, OpenCV 4.13.0. Measurements below use the first 12 sorted JPEGs in the supplied Caliterra sample, not the user's private mission. They are stage measurements, not a promise of equivalent speedups for an entire flight.

## Implemented changes

- Without a gray card, a single-image, 8-bit RGB JPEG recognized by ImageIO as sRGB is copied without recompression. APFS `clonefile` shares unchanged storage blocks; ordinary file copying is the fallback. The imported source is never edited or hard-linked. Source and prepared-copy checksums must match. Wide-gamut/other formats still use Core Image to create sRGB PNGs. Gray-card inputs always follow the existing linear-RGB correction path.
- Feature extraction still processes one image at a time to avoid the sandbox joblib queue deadlock, but permits two native OpenCV threads. The previous thread setting is restored even on failure. Feature resolution, thresholds, descriptors, matching, depth resolution and output quality settings are unchanged.
- New successful runs discard the heavy `dataset` folder after final validation and publication. Camera metadata, reconstruction, configuration and OpenSfM reports are copied into `diagnostics` first. A per-project **Simpan data kerja setelah selesai** switch retains the full dataset. Failed/cancelled runs, original inputs and historical runs are retained. A cleanup error becomes a warning on an otherwise valid output.
- Preparation and engine timings are saved per run. The engine report tracks stage status, wall time, Python-process CPU time and its cumulative peak RSS. These measurements exclude GPU memory and do not aggregate subprocess memory; they must not be presented as total unified-memory usage. Force-termination can leave the last stage marked `running`.
- JPEG EXIF is merged by OpenSfM, so rejected/missing GPS is explicitly overridden with an empty dictionary. Keeping original JPEGs cannot revive stale GPS that the application has rejected.

## Measured results

SIFT extraction plus decoding, same original JPEGs, two repetitions in reversed thread order:

| Native threads | Mean time for 12 photos | Feature output |
|---|---:|---|
| 1 | 18.709 s | Baseline |
| 2 | 14.893 s | Identical point and descriptor hashes for every photo |
| 4 | 14.821 s | Identical point and descriptor hashes for every photo |

Two threads reduce this stage's wall time by 20.4%. Four threads improve on two by only about 0.5% in this sample; that does not justify doubling the native thread setting. This is not a measurement of energy consumption or all OpenSfM stages.

Native image preparation, including source and prepared-file hashing, no gray card:

| Path | Time | Prepared input size (logical bytes) |
|---|---:|---:|
| Existing Core Image → PNG | 4.982 s | 145,368,236 |
| Original sRGB JPEG via APFS clone | 0.050 s | 44,290,166 |

This sample uses 69.5% fewer logical prepared-image bytes. The timing is one warm-filesystem comparison on this APFS volume. Clones may consume much less additional physical storage; logical file sizes cannot measure that saving. Other filesystems, HEIC/wide-gamut inputs and gray-card correction will not obtain this same gain. JPEG and PNG decoding can differ in pixel rounding, so the whole reconstruction must be checked separately from thread-output identity.

Both prepared datasets were then processed through the real pinned OpenSfM worker, including OpenCL depth/fusion on the Apple M5 and raster export:

| Check | Previous PNG / 1-thread path | Original JPEG / 2-thread path |
|---|---:|---:|
| Worker wall time | 104.34 s | 102.26 s |
| Preparation + worker, excluding runtime startup/readiness | 109.32 s | 102.31 s |
| Actual feature stage | 19.45 s | 14.86 s |
| Depth calculation + fusion | 71.88 s | 75.67 s |
| Registered photos / connected components | 12 / 1 | 12 / 1 |
| Reconstructed points | 15,922 | 15,957 |
| OpenSfM mean reprojection error | 0.5773 px | 0.5760 px |
| GeoTIFF CRS | EPSG:32614 | EPSG:32614 |
| Working dataset logical size | 874.8 MB | 770.5 MB |
| Diagnostics retained by cleanup policy | 5.29 MB | 5.30 MB |

The observed preparation-plus-worker reduction is about 6.4%, **not** the 20% feature-stage gain applied to the whole job. There was only one complete run per path, optimized first; GPU warm-up, geometry variation and thermal state can affect these timings. The depth/fusion stage was slightly slower in the optimized run and remains roughly three quarters of its worker time. Both rasters were validated, with nonempty surface coverage. Similar reprojection errors are a regression check, not proof of survey accuracy: there are no independent checkpoints here. Output rasters are not expected to be bit-identical.

These full reconstructions used the native development runtime outside App Sandbox. Native Swift image preparation, lifecycle tests and the final signed-app feature smoke test are separate checks; this does not claim that the user's entire private mission has been rerun in the app.

The production Swift cleanup routine was also run against both completed benchmark runs. Each retained its GeoTIFF with an unchanged SHA-256 checksum, along with the reports and coordinate reference; each resulting run folder occupies about 7.8 MB. The large benchmark intermediates have been removed. All 12 original photo checksums still match their pre-processing values.

An additional test compared cached-descriptor FLANN with OpenCL symmetric brute-force matching on seven actual photo pairs. After warm-up, FLANN took 0.360 s and OpenCL took 1.150 s. Index construction was excluded; GPU transfers were included. The brute-force matcher found more matches/inliers on overlapping pairs, so these are different algorithmic results, not identical work on different processors. There is no measured performance reason to switch the default: matching already takes only about 2.8 s in this 12-photo pipeline.

## Reproduction

Measured stage results, feature hashes and geometry checks are preserved in [the benchmark record](benchmarks/apple-m5-2026-10-18.json).

Preparation benchmark uses the actual Swift preparation code. Supply an output directory that does not exist; the benchmark preserves both prepared datasets for inspection:

```sh
zsh Scripts/benchmark-orthomosaic-preparation.sh odm_data_caliterra-master/images .build/preparation-benchmark 12
```

For the SIFT benchmark, use the development Python environment containing the pinned OpenSfM, not the signed sandbox-inheriting helper directly:

```sh
OPENBLAS_NUM_THREADS=2 OMP_NUM_THREADS=2 /path/to/development/environment/bin/python3 \
  Scripts/benchmark-orthomosaic-sift.py odm_data_caliterra-master/images .build/sift-benchmark.json 12
```

`Scripts/test-orthomosaic.sh` verifies real native image handling plus lifecycle contracts and pure Python orchestration. Its fixture worker is not evidence of reconstruction quality. The signed app's `--check-orthomosaic-features` mode separately exercises the real detector within App Sandbox.

Validation: 72 Swift assertions and 9 Python tests passed. The Apple Development build succeeded; deep/strict signature verification passed with access to macOS trust services. The signed app's detector check completed all 12 synthetic images with `joblib workers: 1, native threads: 2`. Gray-card gain, wide-gamut conversion, copied-file independence, orientation metadata, missing GPS overrides, retention settings and failed-run preservation are covered by the regression tests.

## Remaining limits

Depth reconstruction still uses upstream OpenCL, not a new Metal implementation. Core Image is used for color-managed image preparation; it does not accelerate the entire SfM pipeline. There is no Core ML or Neural Engine inference in this path. Larger runs can still require multiple GB of temporary storage, even when completed working files are removed. Runs are recomputed; there is no cross-run feature cache or automatic resume.

Keep the existing FLANN matcher and exhaustive pair selection until a representative accuracy/performance comparison justifies changing them. A Metal depth implementation would be a separate numerical kernel project, requiring depth-map, camera and final-raster validation. Reducing image/depth resolution simply to obtain a faster benchmark is not part of this optimization.
