#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=$(mktemp -d /tmp/krops-flight-planner-tests.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" \
    Shared/Domain/*.swift Shared/Domain/Ports/*.swift Shared/Data/DatasetStore.swift \
    ControlDroneMapping/Domain/FlightPlanning/*.swift ControlDroneMapping/Domain/FarmArea*.swift ControlDroneMapping/Domain/OperatorLocation.swift \
    ControlDroneMapping/Data/FlightPlanning/*.swift ControlDroneMapping/Data/BundledQGCEngine.swift ControlDroneMapping/Data/QGroundControlLauncher.swift \
    ControlDroneMapping/Presentation/ViewModels/FlightPlannerViewModel.swift ControlDroneMapping/Presentation/ViewModels/OperatorLocationViewModel.swift ControlDroneMapping/Presentation/ViewModels/FarmAreaViewModel.swift \
    Tests/FlightPlannerTests.swift -o "$BUILD_DIR/planner-tests"
"$BUILD_DIR/planner-tests"
