#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=$(mktemp -d /tmp/drone-orthomosaic-tests.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" \
    Shared/Domain/*.swift Shared/Domain/Ports/*.swift Shared/Data/ImageAssessment.swift Shared/Data/DatasetStore.swift \
    ControlDroneMapping/Domain/WebODMExport*.swift ControlDroneMapping/Domain/Orthomosaic*.swift \
    ControlDroneMapping/Data/Export/*.swift ControlDroneMapping/Data/Orthomosaic/*.swift \
    ControlDroneMapping/Presentation/ViewModels/OrthomosaicViewModel.swift \
    Tests/OrthomosaicTests.swift -o "$BUILD_DIR/orthomosaic-tests"
"$BUILD_DIR/orthomosaic-tests"
python3 -m unittest discover -s Tests -p 'test_orthomosaic_worker.py' -v
