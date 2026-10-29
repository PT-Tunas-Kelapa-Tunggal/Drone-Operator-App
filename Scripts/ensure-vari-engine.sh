#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
SRCROOT="${SRCROOT:-$repo_root}"
CACHE_DIR="$SRCROOT/.build"

# 1. Check if UI Preview Mode (Skip Vari Engine) is active
if [[ "${SKIP_VARI_ENGINE:-0}" == "1" || "${SKIP_ALL_ENGINES:-0}" == "1" || -f "$CACHE_DIR/.skip_vari_engine" ]]; then
    echo "note: [Vari Engine] Download and embedding skipped (UI Preview mode active)."
    exit 0
fi

CONFIG_FILE="$SRCROOT/Config/Engine/vari-engine.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "error: [Vari Engine] Config file not found at $CONFIG_FILE" >&2
    exit 1
fi

VERSION="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['version'])")"
DOWNLOAD_URL="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['url'])")"
EXPECTED_SHA="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['sha256'])")"

ENGINE_DIR="$CACHE_DIR/VariEngine"
HELPER_BIN="$CACHE_DIR/VariPython"
TAG_FILE="$CACHE_DIR/.vari_version"

# 2. Check cache validity
if [[ -d "$ENGINE_DIR" && -f "$HELPER_BIN" && -f "$TAG_FILE" && "$(cat "$TAG_FILE")" == "$VERSION" ]]; then
    echo "[Vari Engine] Cache is up to date (Version: $VERSION)."
else
    # Check if local packaging artifact already exists in .build or ../machine-learning/.build
    LOCAL_ARCHIVE=""
    if [[ -f "$CACHE_DIR/VariEngine-macOS-arm64.tar.gz" ]]; then
        LOCAL_ARCHIVE="$CACHE_DIR/VariEngine-macOS-arm64.tar.gz"
    elif [[ -f "$SRCROOT/../machine-learning/VariEngine-macOS-arm64.tar.gz" ]]; then
        LOCAL_ARCHIVE="$SRCROOT/../machine-learning/VariEngine-macOS-arm64.tar.gz"
    fi

    if [[ -n "$LOCAL_ARCHIVE" && -f "$LOCAL_ARCHIVE" ]]; then
        echo "=== [Vari Engine] Using locally built archive: $LOCAL_ARCHIVE ==="
        mkdir -p "$CACHE_DIR"
        rm -rf "$ENGINE_DIR" "$HELPER_BIN"
        tar -xzf "$LOCAL_ARCHIVE" -C "$CACHE_DIR"
        echo "$VERSION" > "$TAG_FILE"
        echo "[Vari Engine] Local extraction complete."
    else
        echo "=== [Vari Engine] Downloading pre-compiled engine ($VERSION) ==="
        mkdir -p "$CACHE_DIR"
        ARCHIVE="$CACHE_DIR/vari-$VERSION.tar.gz"

        if ! curl -fL --progress-bar "$DOWNLOAD_URL" -o "$ARCHIVE"; then
            echo "error: [Vari Engine] Failed to download from $DOWNLOAD_URL" >&2
            exit 1
        fi

        ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
        if [[ "$EXPECTED_SHA" != "placeholder" && "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
            echo "error: [Vari Engine] Checksum mismatch! Expected: $EXPECTED_SHA, got: $ACTUAL_SHA" >&2
            rm -f "$ARCHIVE"
            exit 1
        fi

        echo "[Vari Engine] Extracting engine archive..."
        rm -rf "$ENGINE_DIR" "$HELPER_BIN"
        tar -xzf "$ARCHIVE" -C "$CACHE_DIR"
        rm -f "$ARCHIVE"
        echo "$VERSION" > "$TAG_FILE"
        echo "[Vari Engine] Extraction complete."
    fi
fi

# 3. Determine target bundle directory inside destination .app bundle
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    APP_BUNDLE="$TARGET_BUILD_DIR/${CONTENTS_FOLDER_PATH:-ControlDroneMapping.app/Contents}"
elif [[ -n "${1:-}" ]]; then
    APP_BUNDLE="$1"
else
    APP_BUNDLE="$SRCROOT/.build/DerivedData/Build/Products/Debug/ControlDroneMapping.app/Contents"
fi

DEST_RESOURCES="$APP_BUNDLE/Resources"
DEST_MACOS="$APP_BUNDLE/MacOS"

echo "[Vari Engine] Staging engine into $APP_BUNDLE..."
mkdir -p "$DEST_RESOURCES" "$DEST_MACOS"

rm -rf "$DEST_RESOURCES/VariEngine"
cp -R "$ENGINE_DIR" "$DEST_RESOURCES/"
cp -f "$HELPER_BIN" "$DEST_MACOS/"
chmod +x "$DEST_MACOS/VariPython"

# 4. Inside-out codesigning & Team ID stamping
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep 'Apple Development' | head -n 1 | sed 's/.*"\(.*\)".*/\1/' || true)}"

if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    echo "=== [Vari Engine] Signing with identity: $IDENTITY ==="
    
    # 1. Sign dylibs and so extensions inside the engine
    find "$DEST_RESOURCES/VariEngine" -type f \( -name "*.dylib" -o -name "*.so" \) -exec \
        codesign --force --sign "$IDENTITY" --timestamp=none --options runtime {} \; 2>/dev/null || true

    # 2. Sign VariPython helper binary with strict 2-entitlement helper plist
    ENTITLEMENTS="$SRCROOT/Config/orthomosaic-helper.entitlements"
    codesign --force --sign "$IDENTITY" \
        --options runtime \
        --identifier "com.hata.ControlDroneMapping.engine.vari" \
        --entitlements "$ENTITLEMENTS" \
        --timestamp=none \
        "$DEST_MACOS/VariPython"

    # 3. Stamp developer Team ID into runtime manifest
    TEAM_ID="$(codesign -dvv "$DEST_MACOS/VariPython" 2>&1 | grep '^TeamIdentifier=' | cut -d= -f2 || true)"
    if [[ -n "$TEAM_ID" && "$TEAM_ID" != "not set" ]]; then
        python3 -c "
import json, pathlib
p = pathlib.Path('$DEST_RESOURCES/vari-engine.json')
data = {
    'formatVersion': 1,
    'sha256': '$EXPECTED_SHA',
    'folder': 'VariEngine',
    'teamIdentifier': '$TEAM_ID',
    'pythonIdentifier': 'com.hata.ControlDroneMapping.engine.vari',
    'architecture': 'arm64',
    'version': '$VERSION'
}
p.write_text(json.dumps(data, indent=2) + '\n')
"
    fi
fi

echo "[Vari Engine] Embedded and signed successfully into $APP_BUNDLE"
