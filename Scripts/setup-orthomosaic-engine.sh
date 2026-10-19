#!/bin/bash
# Installs a self-contained folder selected later through the Mac app's file panel.
set -euo pipefail

if [[ "${1:-}" == "--help" || $# -ne 1 ]]; then
    echo 'Usage: bash Scripts/setup-orthomosaic-engine.sh /absolute/path/OrthomosaicEngine'
    echo 'Requires Apple Silicon, Git, internet, and conda or micromamba.'
    exit 0
fi
if [[ "$(uname -m)" != arm64 || "$(uname -s)" != Darwin ]]; then
    echo 'The supported OpenSfM environment requires an Apple Silicon Mac.' >&2
    exit 1
fi
engine_root="$1"
if [[ "$engine_root" != /* ]]; then
    echo 'Choose an absolute destination path.' >&2
    exit 1
fi
if [[ "$engine_root" == *[[:space:]]* ]]; then
    echo 'Choose a destination without spaces; the conda compiler flags do not support spaced prefixes.' >&2
    exit 1
fi
if ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
    echo 'Install Apple Command Line Tools or Xcode before building the engine.' >&2
    exit 1
fi
if command -v micromamba >/dev/null 2>&1; then
    engine_manager="$(command -v micromamba)"
elif command -v conda >/dev/null 2>&1; then
    engine_manager="$(command -v conda)"
else
    echo 'Install Miniforge/conda or micromamba first, then rerun this script.' >&2
    exit 1
fi
mkdir -p "$engine_root"
if [[ ! -d "$engine_root/OpenSfM" ]]; then
    git clone --recursive https://github.com/OpenSfM/OpenSfM.git "$engine_root/OpenSfM"
fi
if [[ ! -f "$engine_root/OpenSfM/conda-osx-arm64.lock" ]]; then
    echo 'The selected source does not include the supported Apple Silicon environment.' >&2
    exit 1
fi
if [[ ! -x "$engine_root/environment/bin/python3" ]]; then
    "$engine_manager" create --prefix "$engine_root/environment" \
        --file "$engine_root/OpenSfM/conda-osx-arm64.lock" --yes
fi
git -C "$engine_root/OpenSfM" submodule update --init --recursive
engine_prefix="$engine_root/environment"
if ! compgen -G "$engine_prefix/conda-meta/scipy-*.json" >/dev/null; then
    "$engine_manager" run --prefix "$engine_prefix" python -m pip uninstall --yes scipy
fi
"$engine_manager" install --prefix "$engine_prefix" --channel conda-forge \
    --freeze-installed 'scipy=1.15.2' --yes
"$engine_manager" run --prefix "$engine_prefix" /usr/bin/env \
    CC=/usr/bin/clang CXX=/usr/bin/clang++ LD=/usr/bin/ld \
    "CFLAGS=-O2 -fPIC -I$engine_prefix/include" \
    "CXXFLAGS=-O2 -fPIC -stdlib=libc++ -I$engine_prefix/include" \
    "LDFLAGS=-L$engine_prefix/lib -Wl,-rpath,$engine_prefix/lib -fuse-ld=/usr/bin/ld" \
    "CMAKE_ARGS=-DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_LINKER=/usr/bin/ld -DCMAKE_AR=/usr/bin/ar -DCMAKE_RANLIB=/usr/bin/ranlib -DCMAKE_PREFIX_PATH=$engine_prefix -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0" \
    python -m pip install -e "$engine_root/OpenSfM" 'scipy==1.15.2'
"$engine_manager" run --prefix "$engine_root/environment" python -m pip install rasterio Pillow
engine_commit="$(git -C "$engine_root/OpenSfM" rev-parse HEAD)"
"$engine_root/environment/bin/python3" -c \
    'import json, pathlib, sys; pathlib.Path(sys.argv[1], "engine.json").write_text(json.dumps({"repository":"https://github.com/OpenSfM/OpenSfM", "commit":sys.argv[2]}, indent=2))' \
    "$engine_root" "$engine_commit"
engine_worker="$(dirname "$0")/../ControlDroneMapping/Resources/orthomosaic_worker.py"
"$engine_root/environment/bin/python3" "$engine_worker" --runtime "$engine_root" --check
echo 'Engine installed. In Hasil → Olah foto → Persiapan engine lokal, select this folder:'
echo "$engine_root"
echo 'The app checks the compiled modules, supported pipeline, and OpenCL GPU before enabling processing.'
