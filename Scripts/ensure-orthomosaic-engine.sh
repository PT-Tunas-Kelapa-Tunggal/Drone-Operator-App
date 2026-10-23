#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
SRCROOT="${SRCROOT:-$repo_root}"
CACHE_DIR="$SRCROOT/.build"

# 1. Check if UI Preview Mode (Skip Orthomosaic Engine) is active
if [[ "${SKIP_ORTHOMOSAIC_ENGINE:-0}" == "1" || -f "$CACHE_DIR/.skip_orthomosaic_engine" ]]; then
    echo "note: [Orthomosaic Engine] Download and embedding skipped (UI Preview mode active)."
    exit 0
fi

CONFIG_FILE="$SRCROOT/Config/Engine/orthomosaic-engine.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "error: [Orthomosaic Engine] Config file not found at $CONFIG_FILE" >&2
    exit 1
fi

VERSION="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['version'])")"
DOWNLOAD_URL="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['url'])")"
EXPECTED_SHA="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['sha256'])")"
COMMIT="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('opensfmCommit', ''))")"

ENGINE_DIR="$CACHE_DIR/OrthomosaicEngine"
HELPER_BIN="$CACHE_DIR/OrthomosaicPython"
TAG_FILE="$CACHE_DIR/.orthomosaic_version"

# 2. Check cache validity
if [[ -d "$ENGINE_DIR" && -f "$HELPER_BIN" && -f "$TAG_FILE" && "$(cat "$TAG_FILE")" == "$VERSION" ]]; then
    echo "[Orthomosaic Engine] Cache is up to date (Version: $VERSION)."
else
    echo "=== [Orthomosaic Engine] Downloading pre-compiled engine ($VERSION) ==="
    mkdir -p "$CACHE_DIR"
    ARCHIVE="$CACHE_DIR/orthomosaic-$VERSION.tar.gz"

    curl -fL --progress-bar "$DOWNLOAD_URL" -o "$ARCHIVE"

    ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
        echo "error: [Orthomosaic Engine] Checksum mismatch! Expected: $EXPECTED_SHA, got: $ACTUAL_SHA" >&2
        rm -f "$ARCHIVE"
        exit 1
    fi

    echo "[Orthomosaic Engine] Extracting engine archive..."
    rm -rf "$ENGINE_DIR" "$HELPER_BIN"
    tar -xzf "$ARCHIVE" -C "$CACHE_DIR"
    rm -f "$ARCHIVE"
    echo "$VERSION" > "$TAG_FILE"
    echo "[Orthomosaic Engine] Extraction complete."
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

echo "[Orthomosaic Engine] Staging engine into $APP_BUNDLE..."
mkdir -p "$DEST_RESOURCES" "$DEST_MACOS"

rm -rf "$DEST_RESOURCES/OrthomosaicEngine"
cp -R "$ENGINE_DIR" "$DEST_RESOURCES/"
cp -f "$HELPER_BIN" "$DEST_MACOS/"
chmod +x "$DEST_MACOS/OrthomosaicPython"

# 4. Inside-out codesigning & Team ID stamping
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep 'Apple Development' | head -n 1 | sed 's/.*"\(.*\)".*/\1/' || true)}"

if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    echo "=== [Orthomosaic Engine] Signing with identity: $IDENTITY ==="
    
    # 1. Sign dylibs and so extensions inside the engine
    find "$DEST_RESOURCES/OrthomosaicEngine" -type f \( -name "*.dylib" -o -name "*.so" \) -exec \
        codesign --force --sign "$IDENTITY" --timestamp=none --options runtime {} \; 2>/dev/null || true

    # 2. Sign Python helper binary with strict 2-entitlement helper plist
    ENTITLEMENTS="$SRCROOT/Config/orthomosaic-helper.entitlements"
    codesign --force --sign "$IDENTITY" \
        --options runtime \
        --identifier "com.hata.ControlDroneMapping.engine.python" \
        --entitlements "$ENTITLEMENTS" \
        --timestamp=none \
        "$DEST_MACOS/OrthomosaicPython"

    # 3. Stamp developer Team ID into runtime manifest
    TEAM_ID="$(codesign -dvv "$DEST_MACOS/OrthomosaicPython" 2>&1 | grep '^TeamIdentifier=' | cut -d= -f2 || true)"
    if [[ -n "$TEAM_ID" && "$TEAM_ID" != "not set" ]]; then
        python3 -c "
import json, pathlib
p = pathlib.Path('$DEST_RESOURCES/orthomosaic-engine.json')
data = {
    'formatVersion': 1,
    'sha256': '$EXPECTED_SHA',
    'folder': 'OrthomosaicEngine',
    'teamIdentifier': '$TEAM_ID',
    'pythonIdentifier': 'com.hata.ControlDroneMapping.engine.python',
    'architecture': 'arm64',
    'opensfmCommit': '$COMMIT',
    'version': '$VERSION'
}
p.write_text(json.dumps(data, indent=2) + '\n')
"
    fi
fi

echo "[Orthomosaic Engine] Embedded and signed successfully into $APP_BUNDLE"
