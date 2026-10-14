#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR=$(mktemp -d /tmp/drone-mapping-tests.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" Shared/Domain/*.swift Shared/Domain/Ports/*.swift Shared/Data/ImageAssessment.swift Shared/Data/DatasetStore.swift Shared/Data/PeerIdentityStore.swift Tests/CoreTests.swift Tests/WorkflowPressureTests.swift Tests/DatasetLayoutTests.swift -o "$BUILD_DIR/core-tests"
"$BUILD_DIR/core-tests"
