#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BENCH_BUILD=$(mktemp -d /tmp/drone-preparation-benchmark.XXXXXX)
trap 'rm -rf "$BENCH_BUILD"' EXIT
xcrun swiftc -O -module-cache-path "$BENCH_BUILD/cache" \
    Shared/Domain/*.swift Shared/Domain/Ports/*.swift Shared/Data/ImageAssessment.swift Shared/Data/DatasetStore.swift \
    ControlDroneMapping/Domain/WebODMExport*.swift ControlDroneMapping/Domain/Orthomosaic*.swift \
    ControlDroneMapping/Data/Export/*.swift ControlDroneMapping/Data/Orthomosaic/*.swift \
    Tests/OrthomosaicPreparationBenchmark.swift -o "$BENCH_BUILD/preparation-benchmark"
"$BENCH_BUILD/preparation-benchmark" "$@"
