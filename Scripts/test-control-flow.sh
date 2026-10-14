#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=$(mktemp -d /tmp/drone-control-tests.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" Shared/Domain/*.swift Shared/Domain/Ports/*.swift Shared/Data/ImageAssessment.swift Shared/Data/DatasetStore.swift Shared/Data/PeerIdentityStore.swift Shared/Data/LocalLink.swift ControlDroneMapping/Presentation/ViewModels/ControlViewModel*.swift ControlDroneMapping/Presentation/ControlNavigation.swift ControlDroneMapping/Domain/MissionDraftRepository.swift ControlDroneMapping/Domain/SavedMission.swift ControlDroneMapping/Domain/FarmArea.swift ControlDroneMapping/Data/FileMissionDraftRepository.swift ControlDroneMapping/Data/FileMissionLibraryRepository.swift ControlDroneMapping/Data/DemoCameraSimulator.swift ControlDroneMapping/Data/QGroundControlLauncher.swift Tests/DevicePanelFlowTests.swift Tests/MissionLibraryTests.swift Tests/OperatorFlowTests.swift Tests/ControlFlowTests.swift -o "$BUILD_DIR/controller-tests"
"$BUILD_DIR/controller-tests"
