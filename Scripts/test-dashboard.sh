#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=$(mktemp -d /tmp/krops-dashboard-tests.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" Shared/Domain/*.swift Shared/Domain/Ports/*.swift Shared/Data/ImageAssessment.swift ControlDroneMapping/Domain/FarmArea*.swift ControlDroneMapping/Domain/FlightPlanning/FlightRoute.swift ControlDroneMapping/Data/FarmAreaStore.swift ControlDroneMapping/Presentation/ViewModels/FarmAreaViewModel.swift Tests/DashboardAreaTests.swift -o "$BUILD_DIR/area-tests"
"$BUILD_DIR/area-tests"
