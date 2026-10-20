#!/bin/bash
# Build the pinned development runtime outside the app sandbox, then package it for Xcode.
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    echo 'Usage: bash Scripts/setup-orthomosaic-engine.sh /absolute/path/OrthomosaicEngine'
    echo 'Requires Apple Silicon, Xcode, Git, internet, and conda or micromamba.'
    echo 'Uses the source commit and dependency locks in Config/Engine.'
    exit 0
fi
if [[ $# -ne 1 ]]; then
    echo 'Usage: bash Scripts/setup-orthomosaic-engine.sh /absolute/path/OrthomosaicEngine' >&2
    exit 1
fi
if [[ "$(uname -m)" != arm64 || "$(uname -s)" != Darwin ]]; then
    echo 'The supported OpenSfM environment requires an Apple Silicon Mac.' >&2
    exit 1
fi
engine_root="$1"
if [[ "$engine_root" != /* || "$engine_root" == *[[:space:]]* ]]; then
    echo 'Choose an absolute destination without spaces.' >&2
    exit 1
fi
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
lock_root="$repo_root/Config/Engine"
engine_commit="$(cat "$lock_root/opensfm-commit.txt")"
if [[ ! "$engine_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo 'Invalid pinned OpenSfM commit in Config/Engine.' >&2
    exit 1
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
    echo 'Install Xcode or set DEVELOPER_DIR to your Xcode installation.' >&2
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
# A recipe marker prevents silently changing or moving an unrelated conda environment.
lock_hash="$(cat "$lock_root/opensfm-commit.txt" "$lock_root/conda-osx-arm64.lock" \
    "$lock_root/requirements-runtime.lock" "$lock_root/requirements-build.lock" | shasum -a 256 | cut -d ' ' -f 1)"
marker="$engine_root/.development-lock.sha256"
if [[ -d "$engine_root/environment" && ! -f "$marker" ]]; then
    echo 'Existing environment was not created with this recipe. Choose a new destination; keep the old runtime.' >&2
    exit 1
fi
if [[ -f "$marker" && "$(cat "$marker")" != "$lock_hash" ]]; then
    echo 'Dependency locks changed. Choose a new destination to build the updated engine.' >&2
    exit 1
fi
mkdir -p "$engine_root"
engine_root="$(cd "$engine_root" && pwd -P)"
marker="$engine_root/.development-lock.sha256"
if [[ "$engine_root" == *[[:space:]]* ]]; then
    echo 'The resolved destination contains spaces. Choose another location.' >&2
    exit 1
fi
if [[ ! -e "$engine_root/OpenSfM" ]]; then
    git clone --no-checkout https://github.com/OpenSfM/OpenSfM.git "$engine_root/OpenSfM"
    git -C "$engine_root/OpenSfM" checkout --detach "$engine_commit"
fi
if [[ "$(git -C "$engine_root/OpenSfM" rev-parse HEAD)" != "$engine_commit" ]]; then
    echo 'Existing OpenSfM source differs from the pinned commit. Choose a new destination.' >&2
    exit 1
fi
if [[ -n "$(git -C "$engine_root/OpenSfM" status --porcelain --untracked-files=no)" ]]; then
    echo 'OpenSfM has local source changes. Preserve them and choose a new destination.' >&2
    exit 1
fi
git -C "$engine_root/OpenSfM" submodule update --init --recursive
printf '%s\n' "$lock_hash" > "$marker"
engine_prefix="$engine_root/environment"
engine_action=create
if [[ -x "$engine_prefix/bin/python3" ]]; then
    engine_action=install
fi
"$engine_manager" "$engine_action" --prefix "$engine_prefix" \
    --file "$lock_root/conda-osx-arm64.lock" --yes
export PYTHONNOUSERSITE=1
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
# No dependency solving: conda supplies exact native artifacts (including SciPy),
# pip supplies hashed wheels, and OpenSfM builds against those installed versions.
"$engine_manager" run --prefix "$engine_prefix" python -m pip --isolated install \
    --index-url https://pypi.org/simple --no-deps --only-binary=:all: --require-hashes \
    -r "$lock_root/requirements-runtime.lock" -r "$lock_root/requirements-build.lock"
"$engine_manager" run --prefix "$engine_prefix" /usr/bin/env \
    CC=/usr/bin/clang CXX=/usr/bin/clang++ LD=/usr/bin/ld \
    "CFLAGS=-O2 -fPIC -I$engine_prefix/include" \
    "CXXFLAGS=-O2 -fPIC -stdlib=libc++ -I$engine_prefix/include" \
    "LDFLAGS=-L$engine_prefix/lib -Wl,-rpath,$engine_prefix/lib -fuse-ld=/usr/bin/ld" \
    "CMAKE_ARGS=-DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_LINKER=/usr/bin/ld -DCMAKE_AR=/usr/bin/ar -DCMAKE_RANLIB=/usr/bin/ranlib -DCMAKE_PREFIX_PATH=$engine_prefix -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0" \
    python -m pip --isolated install --no-deps --no-build-isolation -e "$engine_root/OpenSfM"
"$engine_manager" run --prefix "$engine_prefix" python -m pip --isolated check
"$engine_prefix/bin/python3" -c \
    'import json, pathlib, sys; pathlib.Path(sys.argv[1], "engine.json").write_text(json.dumps({"repository":"https://github.com/OpenSfM/OpenSfM", "commit":sys.argv[2], "developmentLockSHA256":sys.argv[3]}, indent=2))' \
    "$engine_root" "$engine_commit" "$lock_hash"
"$engine_prefix/bin/python3" "$repo_root/ControlDroneMapping/Resources/orthomosaic_worker.py" \
    --runtime "$engine_root" --check
printf '\nDevelopment runtime ready: %s\n' "$engine_root"
echo 'Next: run Scripts/package-orthomosaic-engine.py with this --runtime and your Apple signing --identity.'
echo 'Then build ControlDroneMapping in Xcode. The sandboxed app uses the embedded package, not this external folder.'
