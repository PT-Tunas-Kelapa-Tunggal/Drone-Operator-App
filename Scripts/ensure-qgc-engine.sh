#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
SRCROOT="${SRCROOT:-$repo_root}"
CACHE_DIR="$SRCROOT/.build"

# 1. Check if UI Preview Mode (Skip Engine) is active
if [[ "${SKIP_QGC_ENGINE:-0}" == "1" || -f "$CACHE_DIR/.skip_qgc_engine" ]]; then
    echo "note: [QGC Engine] Download and embedding skipped (UI Preview mode active)."
    exit 0
fi

CONFIG_FILE="$SRCROOT/Config/Engine/qgc-engine.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "error: [QGC Engine] Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi

VERSION="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['version'])")"
DOWNLOAD_URL="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['url'])")"
EXPECTED_SHA="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['sha256'])")"
QGC_APP="$CACHE_DIR/QGroundControl.app"
TAG_FILE="$CACHE_DIR/.qgc_version"

# 2. Check cache validity
if [[ -d "$QGC_APP" && -f "$TAG_FILE" && "$(cat "$TAG_FILE")" == "$VERSION" ]]; then
    echo "[QGC Engine] Cache is up to date (Version: $VERSION)."
else
    echo "=== [QGC Engine] Downloading pre-compiled engine ($VERSION) ==="
    mkdir -p "$CACHE_DIR"
    ARCHIVE="$CACHE_DIR/qgc-$VERSION.tar.gz"

    curl -fL --progress-bar "$DOWNLOAD_URL" -o "$ARCHIVE"

    ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
        echo "error: [QGC Engine] Checksum mismatch! Expected: $EXPECTED_SHA, got: $ACTUAL_SHA" >&2
        rm -f "$ARCHIVE"
        exit 1
    fi

    echo "[QGC Engine] Extracting engine archive..."
    rm -rf "$QGC_APP"
    tar -xzf "$ARCHIVE" -C "$CACHE_DIR"
    rm -f "$ARCHIVE"
    echo "$VERSION" > "$TAG_FILE"
    echo "[QGC Engine] Extraction complete."
fi

# 3. Determine target helper folder inside destination .app bundle
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    TARGET_HELPERS="$TARGET_BUILD_DIR/${CONTENTS_FOLDER_PATH:-ControlDroneMapping.app/Contents}/Helpers"
elif [[ -n "${1:-}" ]]; then
    TARGET_HELPERS="$1"
else
    TARGET_HELPERS="$SRCROOT/.build/DerivedData/Build/Products/Debug/ControlDroneMapping.app/Contents/Helpers"
fi

echo "[QGC Engine] Staging into $TARGET_HELPERS/QGroundControl.app..."
mkdir -p "$TARGET_HELPERS"
rm -rf "$TARGET_HELPERS/QGroundControl.app"
cp -R "$QGC_APP" "$TARGET_HELPERS/"

# 4. Inside-out codesigning
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep 'Apple Development' | head -n 1 | sed 's/.*"\(.*\)".*/\1/' || true)}"

if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    echo "=== [QGC Engine] Signing with identity: $IDENTITY ==="
    DEST_APP="$TARGET_HELPERS/QGroundControl.app"
    ENTITLEMENTS="$SRCROOT/Config/qgc-helper.entitlements"

    # 1. Sign dylibs and frameworks
    if [[ -d "$DEST_APP/Contents/Frameworks" ]]; then
        find "$DEST_APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -perm +111 \) -exec \
            codesign --force --sign "$IDENTITY" --timestamp=none --options runtime {} \; 2>/dev/null || true
    fi

    # 2. Sign main binary with helper entitlements
    codesign --force --sign "$IDENTITY" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp=none \
        "$DEST_APP/Contents/MacOS/QGroundControl"

    # 3. Sign bundle envelope
    codesign --force --sign "$IDENTITY" \
        --timestamp=none \
        "$DEST_APP"
fi

echo "[QGC Engine] Embedded and signed successfully into $TARGET_HELPERS"
