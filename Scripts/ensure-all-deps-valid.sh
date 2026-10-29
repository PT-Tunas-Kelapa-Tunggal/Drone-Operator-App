#!/bin/bash
#
# ensure-all-deps-valid.sh
#
# Unified dependency provisioning, validation, embedding, and inside-out code signing
# for ControlDroneMapping engines (Orthomosaic, QGroundControl, VARI).
#
# Usage:
#   Scripts/ensure-all-deps-valid.sh [--download-only | --verify-only] [--engine NAME]... [APP_CONTENTS_DIR]
#
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
SRCROOT="${SRCROOT:-$repo_root}"
CACHE_DIR="$SRCROOT/.build"
CONFIG_DIR="$SRCROOT/Config/Engine"
STRICT="${ENGINES_STRICT:-0}"

MODE="embed"
ENGINES=()
POSITIONAL_APP=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [--download-only | --verify-only] [--engine NAME]... [APP_CONTENTS_DIR]

Modes:
  (default)        Validate config -> fetch/verify cache -> embed -> inside-out sign -> stamp -> verify
  --download-only  Validate config -> fetch/verify cache -> verify archive layout & arm64 binaries
  --verify-only    Verify an already-embedded .app bundle (files, manifests, strict codesign, team ID)

Options:
  --engine NAME    Limit to a specific engine (orthomosaic | qgc | vari). Repeatable.
  -h, --help       Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --download-only)
            MODE="download-only"
            shift
            ;;
        --verify-only)
            MODE="verify-only"
            shift
            ;;
        --engine)
            if [[ -z "${2:-}" ]]; then
                echo "error: [Engines] --engine requires an argument (orthomosaic | qgc | vari)" >&2
                exit 1
            fi
            ENGINES+=("$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "error: [Engines] Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            POSITIONAL_APP="$1"
            shift
            ;;
    esac
done

if [[ ${#ENGINES[@]} -eq 0 ]]; then
    ENGINES=("orthomosaic" "qgc" "vari")
fi

# Global UI Preview / skip check (applies to default embed mode during Xcode builds)
if [[ "$MODE" == "embed" ]]; then
    if [[ "${SKIP_ALL_ENGINES:-0}" == "1" || -f "$CACHE_DIR/.skip_engines" ]]; then
        echo "note: [Engines] Download and embedding skipped (UI Preview / skip mode active)."
        exit 0
    fi
fi

resolve_app_contents() {
    local target=""
    if [[ -n "$POSITIONAL_APP" ]]; then
        target="$POSITIONAL_APP"
    elif [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
        target="$TARGET_BUILD_DIR/${CONTENTS_FOLDER_PATH:-ControlDroneMapping.app/Contents}"
    else
        target="$SRCROOT/.build/DerivedData/Build/Products/Debug/ControlDroneMapping.app/Contents"
    fi
    # Normalize if caller passed .../ControlDroneMapping.app instead of .../Contents
    if [[ "$target" == *.app ]]; then
        target="$target/Contents"
    fi
    echo "$target"
}

resolve_signing_identity() {
    if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
        echo ""
        return 0
    fi
    if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]]; then
        echo "${EXPANDED_CODE_SIGN_IDENTITY}"
        return 0
    fi
    if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
        # Try resolving to an exact SHA-1 from the keychain first
        local matched
        matched="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "${CODE_SIGN_IDENTITY}" | head -n 1 | awk '{print $2}' || true)"
        if [[ -n "$matched" ]]; then
            echo "$matched"
            return 0
        fi
        echo "${CODE_SIGN_IDENTITY}"
        return 0
    fi
    # Fallback: prefer Developer ID Application, then Apple Development
    local dev_id
    dev_id="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -n 1 | awk '{print $2}' || true)"
    if [[ -n "$dev_id" ]]; then
        echo "$dev_id"
        return 0
    fi
    local apple_dev
    apple_dev="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | head -n 1 | awk '{print $2}' || true)"
    echo "$apple_dev"
}

resolve_timestamp_flag() {
    local identity="$1"
    if [[ "${ENGINE_SIGN_TIMESTAMP:-}" == "1" ]]; then
        echo "--timestamp"
        return 0
    elif [[ "${ENGINE_SIGN_TIMESTAMP:-}" == "0" ]]; then
        echo "--timestamp=none"
        return 0
    fi
    if [[ "$identity" == *"Developer ID"* ]]; then
        echo "--timestamp"
        return 0
    fi
    if security find-identity -v -p codesigning 2>/dev/null | grep -F "$identity" | grep -q 'Developer ID Application'; then
        echo "--timestamp"
        return 0
    fi
    echo "--timestamp=none"
}

# Inside-out signing of all Mach-O files and nested bundles under a directory.
# Finds Mach-O binaries by 4-byte header magic (not just file extension) so executables
# without extensions (bin/python3.11, openssl, sbin/*, Qt helpers) are never missed.
sign_nested_code() {
    local target_root="$1"
    local identity="$2"
    local ts_flag="$3"
    local skip_main="${4:-}"

    python3 - "$target_root" "$identity" "$ts_flag" "$skip_main" <<'PY'
import concurrent.futures
import os
import struct
import subprocess
import sys

target_root, identity, ts_flag, skip_main = sys.argv[1:5]
skip_main = os.path.realpath(skip_main) if skip_main else ""

SKIP_EXTS = {
    ".py", ".pyc", ".pyo", ".pyd", ".txt", ".md", ".rst", ".json", ".yaml", ".yml",
    ".xml", ".plist", ".html", ".htm", ".css", ".js", ".ts", ".qml", ".qmldir",
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".icns", ".ico", ".tif", ".tiff",
    ".h", ".hpp", ".hxx", ".c", ".cc", ".cpp", ".cxx", ".m", ".mm", ".swift",
    ".cmake", ".pc", ".la", ".a", ".o", ".lo", ".al", ". nib", ".strings",
    ".ttf", ".otf", ".woff", ".woff2", ".eot", ".wav", ".mp3", ".ogg",
    ".sql", ".csv", ".tsv", ".lock", ".sh", ".bash", ".zsh", ".fish", ".bat",
}

MACHO_MAGICS = {
    0xFEEDFACE, 0xCEFAEDFE,
    0xFEEDFACF, 0xCFFAEDFE,
    0xCAFEBABE, 0xBEBAFECA,
}

def is_signable_macho(path: str) -> bool:
    try:
        if os.path.islink(path) or not os.path.isfile(path):
            return False
        _, ext = os.path.splitext(path)
        if ext.lower() in SKIP_EXTS:
            return False
        with open(path, "rb") as f:
            hdr = f.read(16)
        if len(hdr) < 16:
            return False
        magic = struct.unpack(">I", hdr[:4])[0]
        if magic not in MACHO_MAGICS:
            return False
        if magic in (0xCAFEBABE, 0xBEBAFECA):
            narch = struct.unpack(">I" if magic == 0xCAFEBABE else "<I", hdr[4:8])[0]
            return 1 <= narch <= 20
        le = magic in (0xCEFAEDFE, 0xCFFAEDFE)
        filetype = struct.unpack("<I" if le else ">I", hdr[12:16])[0]
        # MH_EXECUTE (2), MH_DYLIB (6), MH_BUNDLE (8)
        return filetype in (2, 6, 8)
    except OSError:
        return False

BUNDLE_SUFFIXES = (".framework", ".bundle", ".plugin", ".xpc", ".app")

macho_files = []
nested_bundles = []
target_real = os.path.realpath(target_root)

for dirpath, dirnames, filenames in os.walk(target_root):
    for d in dirnames:
        if d.endswith(BUNDLE_SUFFIXES):
            bpath = os.path.join(dirpath, d)
            if os.path.realpath(bpath) != target_real and not os.path.islink(bpath):
                nested_bundles.append(bpath)
    for fn in filenames:
        fpath = os.path.join(dirpath, fn)
        if skip_main and os.path.realpath(fpath) == skip_main:
            continue
        if is_signable_macho(fpath):
            #Ensure writable so codesign can update the signature
            try:
                mode = os.stat(fpath).st_mode
                if not (mode & 0o200):
                    os.chmod(fpath, mode | 0o200)
            except OSError:
                pass
            macho_files.append(fpath)

def sign_one(path: str) -> None:
    cmd = [
        "codesign", "--force", "--sign", identity,
        "--options", "runtime", ts_flag, path,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"codesign failed on {path}:\n{res.stderr.strip()}")

# 1. Sign all inner Mach-O binaries in parallel (deepest paths first)
macho_files.sort(key=lambda p: (-p.count(os.sep), p))
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    futures = [pool.submit(sign_one, p) for p in macho_files]
    for fut in concurrent.futures.as_completed(futures):
        fut.result()

# 2. Sign nested bundles (.framework, .bundle, .plugin, .xpc, .app) inside-out
nested_bundles.sort(key=lambda p: (-p.count(os.sep), p))
for bpath in nested_bundles:
    sign_one(bpath)

print(f"Signed {len(macho_files)} Mach-O binaries and {len(nested_bundles)} nested bundles in {os.path.basename(target_root)}.")
PY
}

is_engine_skipped() {
    local name="$1"
    local upper
    upper="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
    local var_name="SKIP_${upper}_ENGINE"
    if [[ "${!var_name:-0}" == "1" || -f "$CACHE_DIR/.skip_${name}_engine" ]]; then
        return 0
    fi
    return 1
}

validate_and_process_engine() {
    local name="$1"
    local config_file="$CONFIG_DIR/${name}-engine.json"

    if [[ "$MODE" == "embed" ]] && is_engine_skipped "$name"; then
        echo "note: [$name Engine] Download and embedding skipped (UI Preview mode active)."
        return 0
    fi

    if [[ ! -f "$config_file" ]]; then
        echo "error: [$name Engine] Config file not found at $config_file" >&2
        exit 1
    fi

    # 1. Parse and validate configuration
    local parsed
    parsed="$(python3 - "$config_file" "$STRICT" "$SRCROOT/Config" <<'PY'
import json, pathlib, re, sys

cfg_path = pathlib.Path(sys.argv[1])
strict = sys.argv[2] == "1"
config_dir = pathlib.Path(sys.argv[3])

data = json.loads(cfg_path.read_text())
required = ["version", "url", "sha256", "layout", "folder", "helper", "entitlements"]
missing = [k for k in required if not data.get(k)]
if missing:
    sys.exit(f"error: [{cfg_path.name}] Missing required keys: {', '.join(missing)}")

sha = data["sha256"]
if sha == "placeholder":
    if strict:
        sys.exit(f"error: [{cfg_path.name}] Placeholder sha256 is not allowed when ENGINES_STRICT=1")
elif not re.fullmatch(r"[0-9a-fA-F]{64}", sha):
    sys.exit(f"error: [{cfg_path.name}] Invalid sha256 '{sha}' (expected 64 hex characters)")

layout = data["layout"]
if layout not in ("python-runtime", "helper-app"):
    sys.exit(f"error: [{cfg_path.name}] Unsupported layout '{layout}'")

if layout == "python-runtime" and not data.get("pythonIdentifier"):
    sys.exit(f"error: [{cfg_path.name}] python-runtime requires 'pythonIdentifier'")

ent_file = config_dir / data["entitlements"]
if not ent_file.is_file():
    sys.exit(f"error: [{cfg_path.name}] Entitlements file not found: {ent_file}")

print(data["version"])
print(data["url"])
print(data["sha256"].lower())
print(data["layout"])
print(data["folder"])
print(data["helper"])
print(data["entitlements"])
print(data.get("pythonIdentifier", ""))
print(data.get("opensfmCommit", ""))
PY
)"

    local version download_url expected_sha layout folder helper entitlements_rel python_id commit
    {
        IFS= read -r version
        IFS= read -r download_url
        IFS= read -r expected_sha
        IFS= read -r layout
        IFS= read -r folder
        IFS= read -r helper
        IFS= read -r entitlements_rel
        IFS= read -r python_id || true
        IFS= read -r commit || true
    } <<< "$parsed"

    local entitlements="$SRCROOT/Config/$entitlements_rel"
    local engine_cache_dir="$CACHE_DIR/$folder"
    local tag_file="$CACHE_DIR/.${name}_version"
    local cached_helper=""
    if [[ "$layout" == "python-runtime" ]]; then
        cached_helper="$CACHE_DIR/$helper"
    else
        cached_helper="$engine_cache_dir/$helper"
    fi

    # 2. If --verify-only, verify the embedded copy inside the app bundle and return
    if [[ "$MODE" == "verify-only" ]]; then
        local app_contents
        app_contents="$(resolve_app_contents)"
        echo "=== [$name Engine] Verifying embedded engine in $app_contents ==="
        if [[ "$layout" == "python-runtime" ]]; then
            local emb_dir="$app_contents/Resources/$folder"
            local emb_helper="$app_contents/MacOS/$helper"
            local emb_manifest="$app_contents/Resources/${name}-engine.json"
            [[ -d "$emb_dir" ]] || { echo "error: [$name Engine] Missing embedded directory $emb_dir" >&2; exit 1; }
            [[ -x "$emb_helper" ]] || { echo "error: [$name Engine] Missing or non-executable helper $emb_helper" >&2; exit 1; }
            [[ -f "$emb_manifest" ]] || { echo "error: [$name Engine] Missing runtime manifest $emb_manifest" >&2; exit 1; }
            codesign --verify --strict "$emb_helper"
            local helper_team
            helper_team="$(codesign -dvv "$emb_helper" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
            python3 - "$emb_manifest" "$expected_sha" "$folder" "$python_id" "$helper_team" <<'PY'
import json, pathlib, sys
manifest_path, expected_sha, folder, python_id, helper_team = sys.argv[1:6]
m = json.loads(pathlib.Path(manifest_path).read_text())
assert m.get("formatVersion") == 1, f"Unexpected formatVersion in {manifest_path}"
assert m.get("sha256") == expected_sha, f"SHA mismatch in {manifest_path}: {m.get('sha256')} != {expected_sha}"
assert m.get("folder") == folder, f"Folder mismatch in {manifest_path}"
assert m.get("pythonIdentifier") == python_id, f"pythonIdentifier mismatch in {manifest_path}"
if helper_team and helper_team != "not set":
    assert m.get("teamIdentifier") == helper_team, (
        f"teamIdentifier mismatch in {manifest_path}: manifest={m.get('teamIdentifier')} vs binary={helper_team}"
    )
PY
        else
            local emb_app="$app_contents/Helpers/$folder"
            [[ -d "$emb_app" ]] || { echo "error: [$name Engine] Missing helper bundle $emb_app" >&2; exit 1; }
            [[ -x "$emb_app/$helper" ]] || { echo "error: [$name Engine] Missing helper executable $emb_app/$helper" >&2; exit 1; }
            codesign --verify --deep --strict "$emb_app"
        fi
        echo "[$name Engine] Embedded verification passed."
        return 0
    fi

    # 3. Check cache validity or download & extract
    if [[ -d "$engine_cache_dir" && -f "$cached_helper" && -f "$tag_file" && "$(cat "$tag_file")" == "$version" ]]; then
        echo "[$name Engine] Cache is up to date (Version: $version)."
    else
        mkdir -p "$CACHE_DIR"
        local upper_name
        upper_name="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
        local override_var="${upper_name}_ENGINE_ARCHIVE"
        local source_archive="${!override_var:-}"

        # Optional local VariEngine archive fallback when not in strict CI mode
        if [[ -z "$source_archive" && "$name" == "vari" && "$STRICT" != "1" ]]; then
            for candidate in "$CACHE_DIR/VariEngine-macOS-arm64.tar.gz" "$SRCROOT/../machine-learning/VariEngine-macOS-arm64.tar.gz"; do
                if [[ -f "$candidate" ]]; then
                    local cand_sha
                    cand_sha="$(shasum -a 256 "$candidate" | awk '{print $1}')"
                    if [[ "$expected_sha" == "placeholder" || "$cand_sha" == "$expected_sha" ]]; then
                        source_archive="$candidate"
                        break
                    fi
                fi
            done
        fi

        local archive="$CACHE_DIR/${name}-${version}.tar.gz"
        local cleanup_archive=0
        if [[ -n "$source_archive" && -f "$source_archive" ]]; then
            echo "=== [$name Engine] Using local archive: $source_archive ==="
            archive="$source_archive"
        else
            echo "=== [$name Engine] Downloading pre-compiled engine ($version) ==="
            cleanup_archive=1
            curl -fL --retry 3 --retry-delay 2 --progress-bar "$download_url" -o "$archive"
        fi

        local actual_sha
        actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
        if [[ "$expected_sha" != "placeholder" && "$actual_sha" != "$expected_sha" ]]; then
            echo "error: [$name Engine] Checksum mismatch! Expected: $expected_sha, got: $actual_sha" >&2
            [[ "$cleanup_archive" == "1" ]] && rm -f "$archive"
            exit 1
        fi

        echo "[$name Engine] Extracting engine archive..."
        rm -rf "$engine_cache_dir"
        [[ "$layout" == "python-runtime" ]] && rm -f "$cached_helper"
        tar -xzf "$archive" -C "$CACHE_DIR"
        [[ "$cleanup_archive" == "1" ]] && rm -f "$archive"
        echo "$version" > "$tag_file"
        echo "[$name Engine] Extraction complete."
    fi

    # 4. Validate extracted layout & arm64 Mach-O architecture
    if [[ ! -d "$engine_cache_dir" ]]; then
        echo "error: [$name Engine] Extracted directory missing: $engine_cache_dir" >&2
        exit 1
    fi
    if [[ ! -f "$cached_helper" ]]; then
        echo "error: [$name Engine] Extracted helper binary missing: $cached_helper" >&2
        exit 1
    fi
    chmod +x "$cached_helper"
    if ! lipo -archs "$cached_helper" 2>/dev/null | grep -qw "arm64"; then
        echo "error: [$name Engine] Helper binary $cached_helper is not an arm64 Mach-O executable" >&2
        exit 1
    fi

    if [[ "$MODE" == "download-only" ]]; then
        echo "[$name Engine] Download, SHA-256, and layout validation passed ($version)."
        return 0
    fi

    # 5. Stage into destination .app bundle
    local app_contents
    app_contents="$(resolve_app_contents)"
    local identity
    identity="$(resolve_signing_identity)"
    local ts_flag="--timestamp=none"
    if [[ -n "$identity" ]]; then
        ts_flag="$(resolve_timestamp_flag "$identity")"
    fi

    if [[ "$layout" == "python-runtime" ]]; then
        local dest_resources="$app_contents/Resources"
        local dest_macos="$app_contents/MacOS"
        echo "[$name Engine] Staging into $app_contents..."
        mkdir -p "$dest_resources" "$dest_macos"
        rm -rf "$dest_resources/$folder"
        ditto "$engine_cache_dir" "$dest_resources/$folder"
        cp -f "$cached_helper" "$dest_macos/$helper"
        chmod +x "$dest_macos/$helper"

        if [[ -n "$identity" ]]; then
            echo "=== [$name Engine] Signing inside-out with identity: $identity ($ts_flag) ==="
            sign_nested_code "$dest_resources/$folder" "$identity" "$ts_flag"
            codesign --force --sign "$identity" \
                --options runtime \
                --identifier "$python_id" \
                --entitlements "$entitlements" \
                "$ts_flag" \
                "$dest_macos/$helper"
            codesign --verify --strict "$dest_macos/$helper"

            local team_id
            team_id="$(codesign -dvv "$dest_macos/$helper" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}' || true)"
            if [[ -n "$team_id" && "$team_id" != "not set" ]]; then
                python3 - "$dest_resources/${name}-engine.json" "$expected_sha" "$folder" "$team_id" "$python_id" "$version" "$commit" <<'PY'
import json, pathlib, sys
out_path, sha, folder, team_id, python_id, version, commit = sys.argv[1:8]
data = {
    "formatVersion": 1,
    "sha256": sha,
    "folder": folder,
    "teamIdentifier": team_id,
    "pythonIdentifier": python_id,
    "architecture": "arm64",
    "version": version,
}
if commit:
    data["opensfmCommit"] = commit
pathlib.Path(out_path).write_text(json.dumps(data, indent=2) + "\n")
PY
            fi
        fi
        echo "[$name Engine] Embedded and signed successfully into $app_contents"
    else
        local target_helpers="$app_contents/Helpers"
        local dest_app="$target_helpers/$folder"
        echo "[$name Engine] Staging into $dest_app..."
        mkdir -p "$target_helpers"
        rm -rf "$dest_app"
        ditto "$engine_cache_dir" "$dest_app"

        if [[ -n "$identity" ]]; then
            echo "=== [$name Engine] Signing inside-out with identity: $identity ($ts_flag) ==="
            sign_nested_code "$dest_app" "$identity" "$ts_flag" "$dest_app/$helper"
            # Sign the helper .app bundle once with its entitlements so the main executable
            # retains its sandbox-inheritance + JIT entitlements and the bundle envelope is sealed.
            codesign --force --sign "$identity" \
                --options runtime \
                --entitlements "$entitlements" \
                "$ts_flag" \
                "$dest_app"
            codesign --verify --deep --strict "$dest_app"
        fi
        echo "[$name Engine] Embedded and signed successfully into $target_helpers"
    fi
}

# Remove any stray top-level __pycache__ / .pyc in Resources before sealing
if [[ "$MODE" == "embed" ]]; then
    app_contents_cleanup="$(resolve_app_contents)"
    if [[ -d "$app_contents_cleanup/Resources" ]]; then
        rm -rf "$app_contents_cleanup/Resources/__pycache__"
        find "$app_contents_cleanup/Resources" -maxdepth 1 -name "*.pyc" -delete 2>/dev/null || true
    fi
fi

for engine in "${ENGINES[@]}"; do
    validate_and_process_engine "$engine"
done
