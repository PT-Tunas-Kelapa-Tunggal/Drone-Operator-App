#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ ! -d ".build/OrthomosaicEngine" || ! -f ".build/OrthomosaicPython" ]]; then
    runtime="${ORTHOMOSAIC_RUNTIME:-$HOME/Developer/OrthomosaicEngine-v1}"
    if [[ -d "$runtime" ]]; then
        echo "=== Packaging Orthomosaic Engine from $runtime ==="
        identity="$(security find-identity -v -p codesigning | grep 'Apple Development' | head -n 1 | sed 's/.*"\(.*\)".*/\1/')"
        python3 Scripts/package-orthomosaic-engine.py --runtime "$runtime" --identity "$identity"
    fi
fi

echo "=== Building ControlDroneMapping (Release) ==="
xcodebuild -scheme ControlDroneMapping \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .build/DerivedData \
    build

app_path=".build/DerivedData/Build/Products/Release/ControlDroneMapping.app"
if [[ ! -d "$app_path" ]]; then
    echo "Error: Application not found at $app_path" >&2
    exit 1
fi

echo "=== Ensuring QGroundControl Engine is Embedded ==="
TARGET_BUILD_DIR=".build/DerivedData/Build/Products/Release" CONTENTS_FOLDER_PATH="ControlDroneMapping.app/Contents" "$repo_root/Scripts/ensure-qgc-engine.sh"

echo "=== Verifying Embedded Orthomosaic Engine ==="
"$app_path/Contents/MacOS/ControlDroneMapping" --check-orthomosaic-engine

echo "=== Verifying Embedded QGC Engine ==="
"$app_path/Contents/MacOS/ControlDroneMapping" --check-qgc-engine

echo "=== Preparing DMG Staging Directory ==="
staging=".build/dmg-staging"
rm -rf "$staging"
mkdir -p "$staging"

# Copy the app bundle into staging
cp -R "$app_path" "$staging/"

# Create standard Applications symlink for drag-and-drop install
ln -s /Applications "$staging/Applications"

echo "=== Creating DMG ==="
output_dmg=".build/ControlDroneMapping.dmg"
rm -f "$output_dmg"

if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from \
        --volumeName "ControlDroneMapping" \
        --format UDZO \
        "$staging" \
        "$output_dmg"
else
    hdiutil create \
        -volname "ControlDroneMapping" \
        -srcfolder "$staging" \
        -ov \
        -format UDZO \
        "$output_dmg"
fi

echo ""
echo "=== DMG created successfully! ==="
ls -lh "$output_dmg"
echo ""
echo "To test the DMG, run:"
echo "  diskutil image attach $output_dmg"
echo "  /Volumes/ControlDroneMapping/ControlDroneMapping.app/Contents/MacOS/ControlDroneMapping --check-orthomosaic-engine"
echo "  /Volumes/ControlDroneMapping/ControlDroneMapping.app/Contents/MacOS/ControlDroneMapping --check-qgc-engine"
echo "  diskutil eject /Volumes/ControlDroneMapping"
