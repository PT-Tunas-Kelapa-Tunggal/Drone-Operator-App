#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=$(mktemp -d /tmp/drone-architecture-tests.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" \
    Shared/Domain/*.swift Shared/Domain/Ports/*.swift Shared/Data/*.swift \
    ControlDroneMapping/Domain/*.swift ControlDroneMapping/Domain/FlightPlanning/*.swift \
    ControlDroneMapping/Data/FileMissionDraftRepository.swift ControlDroneMapping/Data/FileMissionLibraryRepository.swift ControlDroneMapping/Data/DemoCameraSimulator.swift \
    ControlDroneMapping/Data/FlightPlanning/*.swift ControlDroneMapping/Data/QGroundControlLauncher.swift ControlDroneMapping/Data/Export/*.swift ControlDroneMapping/Data/Orthomosaic/*.swift \
    ControlDroneMapping/Presentation/ControlNavigation.swift ControlDroneMapping/Presentation/ViewModels/*.swift \
    DroneMapping/Domain/*.swift Tests/ArchitectureBoundaryTests.swift -o "$BUILD_DIR/architecture-tests"
"$BUILD_DIR/architecture-tests"
