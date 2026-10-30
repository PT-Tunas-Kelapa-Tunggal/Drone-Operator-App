#!/bin/bash
#
# release.sh
#
# Unified release, verification, notarization, and DMG packaging script for ControlDroneMapping.
#
# Subcommands:
#   dmg                        Build (if APP_PATH unset), verify, and package ControlDroneMapping.dmg
#   version [TAG]              Derive marketing_version, build_number, prerelease, app_environment, dmg_name
#   select-xcode [VER]         Select Xcode version on CI runner and export DEVELOPER_DIR
#   build-check                Run static config/schema audit, unsigned macOS + iOS builds, and engine smoke checks
#   export-cloudkit-schema     Export live CloudKit container schema to Config/CloudKit/schema.ckdb
#   sync-cloudkit-schema       Import Config/CloudKit/schema.ckdb to Development & verify Production schema
#   setup-signing              Create temp keychain, import Developer ID .p12 & provisioning profile
#   cleanup-signing            Remove temp keychain, provisioning profile, and CI xcconfig
#   archive                    Build Developer ID signed .xcarchive and extract .app to dist/
#   verify-app <APP> [--allow-development]
#                              Audit all Mach-O signatures, entitlements, manifests, and engine self-checks
#   sign-dmg <DMG>             Sign DMG with Developer ID Application and secure timestamp
#   notarize <APP_OR_DMG>      Submit to Apple notarytool, dump log on failure, staple & validate
#   verify-dmg <DMG>           Quarantine-simulate download, Gatekeeper spctl, stapler, and self-checks
#
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

STATE_FILE="$repo_root/.build/.ci-signing-state"

usage() {
    sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'
}

read_xcconfig_var() {
    local key="$1"
    local file="${2:-$repo_root/Config/Developer.xcconfig}"
    [[ -f "$file" ]] || return 0
    awk -F'=[[:space:]]*' -v k="$key" '
        $0 !~ /^[[:space:]]*\/\// && $1 ~ "^[[:space:]]*" k "[[:space:]]*$" {
            gsub(/[[:space:]]+$/, "", $2)
            print $2
        }
    ' "$file" | tail -n 1 | tr -d '\r'
}

cmd_version() {
    local tag="${1:-${GITHUB_REF_NAME:-v0.0.0-local}}"
    local build_number="${GITHUB_RUN_NUMBER:-1}"
    local marketing_version="0.0.0"
    local prerelease="true"
    local app_environment="staging"
    local version_label=""

    local strict_prod_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    local prerelease_semver_re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-([0-9A-Za-z.-]+)$'

    if [[ "$tag" =~ $strict_prod_re ]]; then
        marketing_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
        prerelease="false"
        app_environment="production"
        version_label="${marketing_version}"
    elif [[ "$tag" =~ $prerelease_semver_re ]]; then
        marketing_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
        local suffix="${BASH_REMATCH[4]}"
        prerelease="true"
        app_environment="staging"
        version_label="${marketing_version}-${suffix}"
    else
        local clean_tag="${tag#v}"
        clean_tag="$(echo "$clean_tag" | sed -E 's/[^0-9A-Za-z._-]+/-/g; s/^-+//; s/-+$//')"
        [[ -z "$clean_tag" ]] && clean_tag="0.0.0"
        marketing_version="0.0.0"
        prerelease="true"
        app_environment="staging"
        version_label="$clean_tag"
    fi

    local dmg_name="ControlDroneMapping-${version_label}-arm64.dmg"

    echo "tag_name=$tag"
    echo "marketing_version=$marketing_version"
    echo "build_number=$build_number"
    echo "prerelease=$prerelease"
    echo "app_environment=$app_environment"
    echo "dmg_name=$dmg_name"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "tag_name=$tag"
            echo "marketing_version=$marketing_version"
            echo "build_number=$build_number"
            echo "prerelease=$prerelease"
            echo "app_environment=$app_environment"
            echo "dmg_name=$dmg_name"
        } >> "$GITHUB_OUTPUT"
    fi
}

cmd_select_xcode() {
    local desired="${1:-${XCODE_VERSION:-27.1}}"
    echo "=== Selecting Xcode (desired prefix: $desired) ==="

    local current_ver
    current_ver="$(xcodebuild -version 2>/dev/null | awk '/^Xcode /{print $2}' || true)"
    if [[ "$current_ver" == "$desired"* ]]; then
        local dev_dir
        dev_dir="$(xcode-select -p)"
        echo "Current Xcode $current_ver at $dev_dir already matches."
        [[ -n "${GITHUB_ENV:-}" ]] && echo "DEVELOPER_DIR=$dev_dir" >> "$GITHUB_ENV"
        xcodebuild -version
        return 0
    fi

    local selected_app=""
    local major_prefix="${desired%%.*}"

    # 1. Exact prefix match in /Applications
    for app in /Applications/Xcode*.app; do
        [[ -d "$app" ]] || continue
        local ver
        ver="$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
        if [[ "$ver" == "$desired"* ]]; then
            selected_app="$app"
            break
        fi
    done

    # 2. Fallback to same major version (e.g. 27.x)
    if [[ -z "$selected_app" ]]; then
        for app in /Applications/Xcode*.app; do
            [[ -d "$app" ]] || continue
            local ver
            ver="$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
            if [[ "$ver" == "${major_prefix}."* || "$ver" == "$major_prefix" ]]; then
                selected_app="$app"
            fi
        done
    fi

    if [[ -z "$selected_app" ]]; then
        echo "error: Could not find Xcode matching '$desired' (or ${major_prefix}.x). Installed Xcode bundles:" >&2
        for app in /Applications/Xcode*.app; do
            [[ -d "$app" ]] || continue
            echo "  $app -> $(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unknown)" >&2
        done
        exit 1
    fi

    local dev_dir="$selected_app/Contents/Developer"
    export DEVELOPER_DIR="$dev_dir"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "DEVELOPER_DIR=$dev_dir" >> "$GITHUB_ENV"
    fi
    echo "Selected DEVELOPER_DIR=$dev_dir"
    xcodebuild -version
}

run_cached_engine_smoke_checks() {
    local cache_dir="$repo_root/.build"
    local ortho_py="$cache_dir/OrthomosaicPython"
    local ortho_dir="$cache_dir/OrthomosaicEngine"
    local qgc_bin="$cache_dir/QGroundControl.app/Contents/MacOS/QGroundControl"
    local vari_py="$cache_dir/VariPython"
    local vari_dir="$cache_dir/VariEngine"

    if [[ ! -x "$ortho_py" || ! -d "$ortho_dir" || ! -x "$qgc_bin" || ! -x "$vari_py" || ! -d "$vari_dir" ]]; then
        echo "note: Cached engines not fully present in .build/; skipping standalone engine smoke checks."
        return 0
    fi

    echo "=== Running Standalone Smoke Checks on Cached Engines (.build/) ==="
    echo "--- [1/3] Orthomosaic Engine Smoke Check ---"
    PYTHONHOME="$ortho_dir/environment" \
    CONDA_PREFIX="$ortho_dir/environment" \
    PYTHONNOUSERSITE=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PROJ_NETWORK=OFF \
        "$ortho_py" -u "$repo_root/ControlDroneMapping/Resources/orthomosaic_worker.py" \
        --runtime "$ortho_dir" --check

    echo "--- [2/3] QGroundControl Headless Health Check ---"
    python3 - "$qgc_bin" <<'PY'
import json, subprocess, sys, time, urllib.request

qgc_bin = sys.argv[1]
proc = subprocess.Popen(
    [qgc_bin],
    env={"QGC_HEADLESS": "1", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
try:
    deadline = time.time() + 12.0
    healthy = False
    while time.time() < deadline:
        if proc.poll() is not None:
            sys.exit(f"error: QGroundControl exited prematurely with code {proc.returncode}")
        try:
            with urllib.request.urlopen("http://127.0.0.1:18080/healthz", timeout=1.0) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("status") == "ok":
                    healthy = True
                    break
        except Exception:
            pass
        time.sleep(0.25)
    if not healthy:
        sys.exit("error: QGroundControl headless healthz check timed out")
    print("QGC cached engine healthy (127.0.0.1:18080/healthz).")
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            proc.kill()
PY

    echo "--- [3/3] VARI Engine Smoke Check ---"
    PYTHONHOME="$vari_dir/environment" \
    CONDA_PREFIX="$vari_dir/environment" \
    PYTHONNOUSERSITE=1 \
    PYTHONDONTWRITEBYTECODE=1 \
        "$vari_py" -m krops_vari.main --check

    echo "=== All 3 Cached Engine Smoke Checks Passed ==="
}

cmd_build_check() {
    echo "=== [1/4] Auditing Entitlements, Version Routing & CloudKit Schema ==="
    python3 - "$repo_root" <<'PY'
import pathlib, plistlib, re, subprocess, sys

repo = pathlib.Path(sys.argv[1])

# 1. Verify Config/App.entitlements enforces Development environment
dev_ent = plistlib.loads((repo / "Config/App.entitlements").read_bytes())
if dev_ent.get("com.apple.developer.icloud-container-environment") != "Development":
    sys.exit("error: Config/App.entitlements must set com.apple.developer.icloud-container-environment=Development")

# 2. Verify Config/App-DeveloperID.entitlements enforces Production environment
prod_ent = plistlib.loads((repo / "Config/App-DeveloperID.entitlements").read_bytes())
if prod_ent.get("com.apple.developer.icloud-container-environment") != "Production":
    sys.exit("error: Config/App-DeveloperID.entitlements must set com.apple.developer.icloud-container-environment=Production")

# 3. Verify Config/App-Info.plist declares AppEnvironment and ICloudContainerIdentifier
info_plist = plistlib.loads((repo / "Config/App-Info.plist").read_bytes())
if info_plist.get("AppEnvironment") != "$(APP_ENVIRONMENT)":
    sys.exit("error: Config/App-Info.plist must map AppEnvironment to $(APP_ENVIRONMENT)")
if info_plist.get("ICloudContainerIdentifier") != "$(ICLOUD_CONTAINER_NAME)":
    sys.exit("error: Config/App-Info.plist must map ICloudContainerIdentifier to $(ICLOUD_CONTAINER_NAME)")

# 4. Verify CloudKit schema file Config/CloudKit/schema.ckdb
schema_path = repo / "Config/CloudKit/schema.ckdb"
if not schema_path.is_file():
    sys.exit("error: Config/CloudKit/schema.ckdb is missing")
schema_text = schema_path.read_text()
for required_token in (
    'CREATE ROLE "Drone Operator"',
    "RECORD TYPE PlantationScanRequest",
    "RECORD TYPE Users",
    '"___createTime"',
    '"___recordID"',
    "agronomicJSON",
    "areaHectares",
    "boundaryJSON",
    "completedAt",
    "farmerAddress",
    "farmerName",
    "farmerPhone",
    "gardenID",
    "gardenName",
    "locationName",
    "orthomosaicAsset",
    "resultJSON",
    "statusCode",
    "submittedAt",
):
    if required_token not in schema_text:
        sys.exit(f"error: Config/CloudKit/schema.ckdb is missing required definition: {required_token}")

# 5. Self-test version & environment routing in release.sh
cases = [
    ("v1.0.0", "1.0.0", "false", "production"),
    ("v0.2.15", "0.2.15", "false", "production"),
    ("v1.0.0-rc1", "1.0.0", "true", "staging"),
    ("v1.0.0-beta.2", "1.0.0", "true", "staging"),
    ("v1.0", "0.0.0", "true", "staging"),
    ("dev", "0.0.0", "true", "staging"),
]
for tag, exp_ver, exp_pre, exp_env in cases:
    out = subprocess.check_output([str(repo / "Scripts/release.sh"), "version", tag], text=True)
    kv = dict(line.split("=", 1) for line in out.strip().splitlines() if "=" in line)
    if kv.get("marketing_version") != exp_ver or kv.get("prerelease") != exp_pre or kv.get("app_environment") != exp_env:
        sys.exit(
            f"error: release.sh version {tag} failed routing check: got {kv}, "
            f"expected marketing_version={exp_ver}, prerelease={exp_pre}, app_environment={exp_env}"
        )

print("Static entitlements, CloudKit schema.ckdb, and SemVer environment routing checks passed.")
PY

    if [[ ! -f "$repo_root/Config/Developer.xcconfig" ]]; then
        if [[ -n "${CI:-}" && -f "$repo_root/Config/Developer.xcconfig.example" ]]; then
            echo "CI environment detected: seeding Config/Developer.xcconfig from template"
            cp "$repo_root/Config/Developer.xcconfig.example" "$repo_root/Config/Developer.xcconfig"
        else
            echo "error: Config/Developer.xcconfig not found! Please run: cp Config/Developer.xcconfig.example Config/Developer.xcconfig" >&2
            exit 1
        fi
    fi

    local check_dd="$repo_root/.build/DerivedDataCheck"
    rm -rf "$check_dd"

    echo "=== [2/4] Running Unsigned Release Build Check: ControlDroneMapping (macOS) ==="
    SKIP_ALL_ENGINES=1 xcodebuild build \
        -project DroneMapping.xcodeproj \
        -scheme ControlDroneMapping \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$check_dd" \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY=""

    echo "=== [3/4] Running Unsigned Release Build Check: DroneMapping (iOS) ==="
    xcodebuild build \
        -project DroneMapping.xcodeproj \
        -scheme DroneMapping \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$check_dd" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY=""

    rm -rf "$check_dd"

    echo "=== [4/4] Running Engine Smoke Checks ==="
    if [[ "${SKIP_ENGINE_SELF_CHECKS:-0}" != "1" ]]; then
        run_cached_engine_smoke_checks
    else
        echo "Engine smoke checks skipped (SKIP_ENGINE_SELF_CHECKS=1)."
    fi

    echo "=== All Build & Validation Checks Passed ==="
}

cmd_export_cloudkit_schema() {
    local ck_env="${1:-development}"
    local team_id="${APPLE_TEAM_ID:-$(read_xcconfig_var DEVELOPMENT_TEAM)}"
    local container_id="${ICLOUD_CONTAINER_NAME:-$(read_xcconfig_var ICLOUD_CONTAINER_NAME)}"
    local schema_file="$repo_root/Config/CloudKit/schema.ckdb"

    if [[ -z "$team_id" ]]; then
        echo "error: APPLE_TEAM_ID (or DEVELOPMENT_TEAM in Config/Developer.xcconfig) is required" >&2
        exit 1
    fi
    if [[ -z "$container_id" ]]; then
        echo "error: ICLOUD_CONTAINER_NAME (in env or Config/Developer.xcconfig) is required" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$schema_file")"
    local token_args=()
    if [[ -n "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]]; then
        token_args=(--token "$CLOUDKIT_MANAGEMENT_TOKEN")
    fi

    echo "=== Exporting CloudKit Schema ($container_id [$ck_env]) -> $schema_file ==="
    xcrun cktool export-schema \
        "${token_args[@]}" \
        --team-id "$team_id" \
        --container-id "$container_id" \
        --environment "$ck_env" \
        --output-file "$schema_file"
    echo "=== Schema exported successfully to $schema_file ==="
}

cmd_sync_cloudkit_schema() {
    local team_id="${APPLE_TEAM_ID:-$(read_xcconfig_var DEVELOPMENT_TEAM)}"
    local container_id="${ICLOUD_CONTAINER_NAME:-$(read_xcconfig_var ICLOUD_CONTAINER_NAME)}"
    local schema_file="$repo_root/Config/CloudKit/schema.ckdb"

    if [[ -z "$team_id" ]]; then
        echo "error: APPLE_TEAM_ID (or DEVELOPMENT_TEAM in Config/Developer.xcconfig) is required" >&2
        exit 1
    fi
    if [[ -z "$container_id" ]]; then
        echo "error: ICLOUD_CONTAINER_NAME (in env or Config/Developer.xcconfig) is required" >&2
        exit 1
    fi
    if [[ ! -f "$schema_file" ]]; then
        echo "error: Schema file not found at $schema_file" >&2
        exit 1
    fi

    local token_args=()
    if [[ -n "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]]; then
        token_args=(--token "$CLOUDKIT_MANAGEMENT_TOKEN")
    fi

    echo "=== [1/2] Importing & Validating CloudKit Schema into $container_id (development) ==="
    xcrun cktool import-schema \
        "${token_args[@]}" \
        --team-id "$team_id" \
        --container-id "$container_id" \
        --environment development \
        --validate \
        --file "$schema_file"

    echo "=== [2/2] Verifying CloudKit Production Schema for $container_id ==="
    local prod_schema_tmp="${RUNNER_TEMP:-/tmp}/ck-prod-schema-$$.ckdb"
    trap 'rm -f "$prod_schema_tmp"' RETURN

    if ! xcrun cktool export-schema \
        "${token_args[@]}" \
        --team-id "$team_id" \
        --container-id "$container_id" \
        --environment production \
        --output-file "$prod_schema_tmp"; then
        echo "error: Unable to export Production schema for container '$container_id'." >&2
        echo "Note: The latest schema has been imported into '$container_id' (Development)." >&2
        echo "Please open CloudKit Console (https://icloud.developer.apple.com/dashboard), select '$container_id', click 'Deploy Schema Changes…' to Production, and re-run." >&2
        exit 1
    fi

    python3 - "$schema_file" "$prod_schema_tmp" "$container_id" <<'PY'
import pathlib, re, sys

expected_path = pathlib.Path(sys.argv[1])
prod_path = pathlib.Path(sys.argv[2])
container_id = sys.argv[3]

def parse_ckdb(text: str):
    roles = set(re.findall(r'CREATE\s+ROLE\s+"([^"]+)"', text))
    records = {}
    for m in re.finditer(r'RECORD\s+TYPE\s+([A-Za-z0-9_]+)\s*\((.*?)\)\s*;', text, re.DOTALL):
        rec_name = m.group(1)
        body = m.group(2)
        items = set()
        for raw_line in body.splitlines():
            line = re.sub(r'\s+', ' ', raw_line.strip().rstrip(','))
            if line:
                items.add(line)
        records[rec_name] = items
    return roles, records

exp_roles, exp_records = parse_ckdb(expected_path.read_text())
prod_roles, prod_records = parse_ckdb(prod_path.read_text())

missing = []
for role in sorted(exp_roles - prod_roles):
    missing.append(f'Missing ROLE: "{role}"')

for rec_name, exp_items in sorted(exp_records.items()):
    if rec_name not in prod_records:
        missing.append(f"Missing RECORD TYPE: {rec_name}")
        continue
    prod_items = prod_records[rec_name]
    for item in sorted(exp_items - prod_items):
        missing.append(f"In RECORD TYPE {rec_name}, missing or mismatched definition: '{item}'")

if missing:
    print(f"error: CloudKit Production schema for '{container_id}' is out of sync with Config/CloudKit/schema.ckdb:", file=sys.stderr)
    for m in missing:
        print(f"  - {m}", file=sys.stderr)
    print(
        f"\nACTION REQUIRED: Config/CloudKit/schema.ckdb has already been automatically staged into '{container_id}' (Development).\n"
        f"Open CloudKit Console (https://icloud.developer.apple.com/dashboard), select '{container_id}',\n"
        f"click 'Deploy Schema Changes…' to promote Development -> Production, and re-run this job.",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"Verified CloudKit Production schema for '{container_id}' matches Config/CloudKit/schema.ckdb.")
PY
}

cmd_setup_signing() {
    echo "=== Setting up Developer ID Signing Environment ==="
    : "${DEVELOPER_ID_P12_BASE64:?Missing DEVELOPER_ID_P12_BASE64}"
    : "${DEVELOPER_ID_P12_PASSWORD:?Missing DEVELOPER_ID_P12_PASSWORD}"
    : "${DEVELOPER_ID_PROFILE_BASE64:?Missing DEVELOPER_ID_PROFILE_BASE64}"
    : "${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"
    : "${APP_BUNDLE_PREFIX:?Missing APP_BUNDLE_PREFIX}"
    : "${ICLOUD_CONTAINER_NAME:?Missing ICLOUD_CONTAINER_NAME}"
    : "${APP_ENVIRONMENT:?Missing APP_ENVIRONMENT}"

    local bundle_prefix="$APP_BUNDLE_PREFIX"
    local icloud_container="$ICLOUD_CONTAINER_NAME"
    local app_env="$APP_ENVIRONMENT"

    if [[ "$app_env" != "staging" && "$app_env" != "production" ]]; then
        echo "error: APP_ENVIRONMENT for CI Developer ID signing must be 'staging' or 'production' (got: '$app_env')" >&2
        exit 1
    fi

    local temp_dir="${RUNNER_TEMP:-/tmp}"
    local keychain_path="$temp_dir/cdm-release-signing.keychain-db"
    local keychain_pass
    keychain_pass="$(openssl rand -hex 24)"
    local p12_file="$temp_dir/cdm-dev-id.p12"
    local profile_temp="$temp_dir/cdm-dev-id.provisionprofile"

    mkdir -p "$repo_root/.build"
    rm -f "$keychain_path" "$p12_file" "$profile_temp"

    echo "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$p12_file"
    echo "$DEVELOPER_ID_PROFILE_BASE64" | base64 --decode > "$profile_temp"

    security create-keychain -p "$keychain_pass" "$keychain_path"
    security set-keychain-settings -lut 21600 "$keychain_path"
    security unlock-keychain -p "$keychain_pass" "$keychain_path"

    # Prepend temporary keychain to user search list while preserving existing keychains
    local existing_keychains=()
    while IFS= read -r line; do
        local cleaned
        cleaned="$(echo "$line" | sed -E 's/^[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')"
        [[ -n "$cleaned" ]] && existing_keychains+=("$cleaned")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s "$keychain_path" "${existing_keychains[@]}"

    security import "$p12_file" \
        -k "$keychain_path" \
        -P "$DEVELOPER_ID_P12_PASSWORD" \
        -T /usr/bin/codesign \
        -T /usr/bin/security \
        -T /usr/bin/productbuild \
        -A
    rm -f "$p12_file"

    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_pass" "$keychain_path" >/dev/null

    # Verify Developer ID Application identity for APPLE_TEAM_ID is present
    local found_identity
    found_identity="$(security find-identity -v -p codesigning "$keychain_path" | grep "Developer ID Application" | grep "(${APPLE_TEAM_ID})" | head -n 1 || true)"
    if [[ -z "$found_identity" ]]; then
        echo "error: No valid 'Developer ID Application' identity for team $APPLE_TEAM_ID found in imported certificate." >&2
        security find-identity -v -p codesigning "$keychain_path" >&2 || true
        exit 1
    fi
    echo "Verified signing identity: $found_identity"

    # Parse and validate provisioning profile (including CloudKit container authorization)
    local profile_info
    profile_info="$(security cms -D -i "$profile_temp" | python3 - "$APPLE_TEAM_ID" "$icloud_container" <<'PY'
import plistlib, sys
expected_team, expected_container = sys.argv[1:3]
plist = plistlib.loads(sys.stdin.buffer.read())
uuid = plist.get("UUID", "")
name = plist.get("Name", "")
teams = plist.get("TeamIdentifier", [])
provisions_all = plist.get("ProvisionsAllDevices", False)
ent = plist.get("Entitlements", {})
allowed_containers = ent.get("com.apple.developer.icloud-container-identifiers", [])

if not uuid:
    sys.exit("error: Provisioning profile is missing UUID")
if expected_team not in teams:
    sys.exit(f"error: Profile TeamIdentifier {teams} does not match APPLE_TEAM_ID={expected_team}")
if not provisions_all:
    sys.exit("error: Provisioning profile is not a Developer ID profile (ProvisionsAllDevices is not true)")
if expected_container not in allowed_containers:
    sys.exit(
        f"error: Provisioning profile '{name}' ({uuid}) authorizes CloudKit containers {allowed_containers}, "
        f"which does not include ICLOUD_CONTAINER_NAME='{expected_container}'."
    )

print(uuid)
print(name)
PY
)"
    local profile_uuid profile_name
    {
        IFS= read -r profile_uuid
        IFS= read -r profile_name || true
    } <<< "$profile_info"

    local profile_dir1="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    local profile_dir2="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$profile_dir1" "$profile_dir2"
    cp -f "$profile_temp" "$profile_dir1/${profile_uuid}.provisionprofile"
    cp -f "$profile_temp" "$profile_dir2/${profile_uuid}.provisionprofile"
    rm -f "$profile_temp"

    local had_config="0"
    if [[ -f "$repo_root/Config/Developer.xcconfig" ]]; then
        had_config="1"
    fi
    cat > "$repo_root/Config/Developer.xcconfig" <<EOF
// Generated by Scripts/release.sh setup-signing
DEVELOPMENT_TEAM = $APPLE_TEAM_ID
APP_BUNDLE_PREFIX = $bundle_prefix
ICLOUD_CONTAINER_NAME = $icloud_container
APP_ENVIRONMENT = $app_env
EOF

    cat > "$STATE_FILE" <<EOF
KEYCHAIN_PATH=$keychain_path
PROFILE_FILE_1=$profile_dir1/${profile_uuid}.provisionprofile
PROFILE_FILE_2=$profile_dir2/${profile_uuid}.provisionprofile
HAD_CONFIG=$had_config
EOF

    echo "Installed Developer ID provisioning profile: $profile_name ($profile_uuid) for container $icloud_container ($app_env)"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "profile_uuid=$profile_uuid"
            echo "profile_name=$profile_name"
        } >> "$GITHUB_OUTPUT"
    fi
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "PROFILE_UUID=$profile_uuid" >> "$GITHUB_ENV"
    fi
}

cmd_cleanup_signing() {
    echo "=== Cleaning up Signing Environment ==="
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        if [[ -n "${KEYCHAIN_PATH:-}" && -f "$KEYCHAIN_PATH" ]]; then
            security delete-keychain "$KEYCHAIN_PATH" || rm -f "$KEYCHAIN_PATH"
            echo "Deleted temporary keychain $KEYCHAIN_PATH"
        fi
        [[ -n "${PROFILE_FILE_1:-}" ]] && rm -f "$PROFILE_FILE_1"
        [[ -n "${PROFILE_FILE_2:-}" ]] && rm -f "$PROFILE_FILE_2"
        if [[ "${HAD_CONFIG:-0}" == "0" ]]; then
            rm -f "$repo_root/Config/Developer.xcconfig"
        fi
        rm -f "$STATE_FILE"
    fi
}

cmd_archive() {
    : "${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"
    : "${PROFILE_UUID:?Missing PROFILE_UUID}"
    : "${MARKETING_VERSION:?Missing MARKETING_VERSION}"
    : "${BUILD_NUMBER:?Missing BUILD_NUMBER}"

    local marketing_version="$MARKETING_VERSION"
    local build_number="$BUILD_NUMBER"
    local bundle_prefix="${APP_BUNDLE_PREFIX:-$(read_xcconfig_var APP_BUNDLE_PREFIX)}"
    local icloud_container="${ICLOUD_CONTAINER_NAME:-$(read_xcconfig_var ICLOUD_CONTAINER_NAME)}"
    local app_env="${APP_ENVIRONMENT:-$(read_xcconfig_var APP_ENVIRONMENT)}"

    if [[ -z "$bundle_prefix" ]]; then
        echo "error: APP_BUNDLE_PREFIX not set in env or Config/Developer.xcconfig" >&2
        exit 1
    fi
    if [[ -z "$icloud_container" ]]; then
        echo "error: ICLOUD_CONTAINER_NAME not set in env or Config/Developer.xcconfig" >&2
        exit 1
    fi
    if [[ -z "$app_env" ]]; then
        echo "error: APP_ENVIRONMENT not set in env or Config/Developer.xcconfig" >&2
        exit 1
    fi

    local archive_path="$repo_root/.build/ControlDroneMapping.xcarchive"
    local archive_dd="$repo_root/.build/DerivedDataArchive"
    local dist_app="$repo_root/dist/ControlDroneMapping.app"

    echo "=== Archiving ControlDroneMapping ($marketing_version build $build_number, env=$app_env, container=$icloud_container) ==="
    rm -rf "$archive_path" "$archive_dd" "$dist_app"
    mkdir -p "$repo_root/dist"

    ENGINES_STRICT=1 ENGINE_SIGN_TIMESTAMP=1 xcodebuild archive \
        -project DroneMapping.xcodeproj \
        -scheme ControlDroneMapping \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$archive_path" \
        -derivedDataPath "$archive_dd" \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="Developer ID Application" \
        DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
        PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" \
        PRODUCT_BUNDLE_IDENTIFIER="${bundle_prefix}.ControlDroneMapping" \
        ICLOUD_CONTAINER_NAME="$icloud_container" \
        APP_ENVIRONMENT="$app_env" \
        CODE_SIGN_ENTITLEMENTS="Config/App-DeveloperID.entitlements" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        MARKETING_VERSION="$marketing_version" \
        CURRENT_PROJECT_VERSION="$build_number"

    local archived_app="$archive_path/Products/Applications/ControlDroneMapping.app"
    if [[ ! -d "$archived_app" ]]; then
        echo "error: Archived application not found at $archived_app" >&2
        exit 1
    fi

    ditto "$archived_app" "$dist_app"
    # Reclaim disk space on runner immediately
    rm -rf "$archive_path" "$archive_dd"
    echo "=== Archive extracted to $dist_app ==="
}

run_engine_self_checks() {
    local app_path="$1"
    local app_bin="$app_path/Contents/MacOS/ControlDroneMapping"

    echo "=== Running Embedded Engine Self-Checks on $app_path ==="
    echo "--- [1/3] --check-orthomosaic-engine ---"
    "$app_bin" --check-orthomosaic-engine
    echo "--- [2/3] --check-qgc-engine ---"
    "$app_bin" --check-qgc-engine
    echo "--- [3/3] --check-vari-engine ---"
    "$app_bin" --check-vari-engine
    echo "=== All 3 Engine Self-Checks Passed ==="
}

cmd_verify_app() {
    local app_path="${1:-}"
    local allow_dev="0"
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --allow-development)
                allow_dev="1"
                shift
                ;;
            *)
                echo "error: Unknown option to verify-app: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "$app_path" || ! -d "$app_path" ]]; then
        echo "error: Usage: release.sh verify-app <path/to/ControlDroneMapping.app> [--allow-development]" >&2
        exit 1
    fi

    echo "=== [1/4] Verifying Deep Bundle Seal: $app_path ==="
    codesign --verify --deep --strict --verbose=2 "$app_path"

    echo "=== [2/4] Verifying Embedded Engine Manifests & Structure ==="
    "$repo_root/Scripts/ensure-all-deps-valid.sh" --verify-only "$app_path/Contents"

    echo "=== [3/4] Auditing All Mach-O Signatures, Timestamps, Runtime Flags & Entitlements ==="
    local expected_team="${APPLE_TEAM_ID:-}"
    if [[ -z "$expected_team" ]]; then
        expected_team="$(codesign -dvv "$app_path" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}' || true)"
    fi
    local expected_env="${APP_ENVIRONMENT:-}"
    local expected_container="${ICLOUD_CONTAINER_NAME:-}"

    python3 - "$app_path" "$expected_team" "$allow_dev" "${MARKETING_VERSION:-}" "$repo_root/Config/engines.json" "$expected_env" "$expected_container" <<'PY'
import concurrent.futures
import json
import os
import plistlib
import struct
import subprocess
import sys

app_path, expected_team, allow_dev_str, expected_version, engines_json_path, expected_env, expected_container = sys.argv[1:8]
allow_dev = allow_dev_str == "1"

if not expected_team or expected_team == "not set":
    sys.exit("error: Expected TeamIdentifier could not be determined")

# 1. Check required app-side resources and ensure no stray __pycache__ / .pyc in Resources root
resources_dir = os.path.join(app_path, "Contents", "Resources")
for req in ("orthomosaic_worker.py", "ORTHOMOSAIC_ENGINE.md", "orthomosaic-engine.json", "vari-engine.json"):
    if not os.path.isfile(os.path.join(resources_dir, req)):
        sys.exit(f"error: Required resource missing from bundle: Contents/Resources/{req}")

if os.path.exists(os.path.join(resources_dir, "__pycache__")):
    sys.exit("error: Stray Contents/Resources/__pycache__ found in app bundle")
stray_pyc = [f for f in os.listdir(resources_dir) if f.endswith((".pyc", ".pyo"))]
if stray_pyc:
    sys.exit(f"error: Stray compiled Python files in Contents/Resources: {stray_pyc}")

# 2. Check Info.plist version, bundle identifier, CloudKit container, and AppEnvironment
info_plist_path = os.path.join(app_path, "Contents", "Info.plist")
with open(info_plist_path, "rb") as f:
    info_plist = plistlib.load(f)

bundle_id = info_plist.get("CFBundleIdentifier", "")
if not bundle_id or "$(" in bundle_id:
    sys.exit(f"error: CFBundleIdentifier is invalid or unexpanded: '{bundle_id}'")

if expected_version:
    actual_ver = info_plist.get("CFBundleShortVersionString")
    if actual_ver != expected_version:
        sys.exit(f"error: CFBundleShortVersionString='{actual_ver}' does not match MARKETING_VERSION='{expected_version}'")

icloud_container_id = info_plist.get("ICloudContainerIdentifier", "")
if not icloud_container_id or "$(" in icloud_container_id:
    sys.exit(f"error: ICloudContainerIdentifier in Info.plist is invalid or unexpanded: '{icloud_container_id}'")
if expected_container and icloud_container_id != expected_container:
    sys.exit(f"error: Info.plist ICloudContainerIdentifier='{icloud_container_id}' does not match expected '{expected_container}'")

app_env = info_plist.get("AppEnvironment", "")
if app_env not in ("development", "staging", "production"):
    sys.exit(f"error: AppEnvironment in Info.plist is invalid or unexpanded: '{app_env}'")
if expected_env and app_env != expected_env:
    sys.exit(f"error: Info.plist AppEnvironment='{app_env}' does not match expected '{expected_env}'")

# 3. Check main app and helper entitlements
def read_entitlements(target: str) -> dict:
    res = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", "--xml", target],
        capture_output=True,
    )
    if res.returncode != 0 or not res.stdout:
        return {}
    try:
        return plistlib.loads(res.stdout)
    except Exception:
        return {}

main_ent = read_entitlements(app_path)
if main_ent.get("com.apple.security.app-sandbox") is not True:
    sys.exit("error: Main app is missing com.apple.security.app-sandbox=true")

if allow_dev:
    if main_ent.get("com.apple.developer.icloud-container-environment") != "Development":
        sys.exit("error: Local development build must have com.apple.developer.icloud-container-environment=Development")
    if app_env != "development":
        sys.exit(f"error: Local development build must have AppEnvironment=development (got '{app_env}')")
else:
    if main_ent.get("com.apple.security.get-task-allow") is True:
        sys.exit("error: Main app has com.apple.security.get-task-allow=true (rejected by notarization)")
    if main_ent.get("com.apple.developer.icloud-container-environment") != "Production":
        sys.exit("error: Main app must have com.apple.developer.icloud-container-environment=Production for Developer ID")
    if app_env not in ("staging", "production"):
        sys.exit(f"error: Developer ID release build must have AppEnvironment in ('staging', 'production'), got '{app_env}'")
    profile_path = os.path.join(app_path, "Contents", "embedded.provisionprofile")
    if not os.path.isfile(profile_path):
        sys.exit("error: Contents/embedded.provisionprofile is missing (required for CloudKit with Developer ID)")
    cms = subprocess.run(["security", "cms", "-D", "-i", profile_path], capture_output=True, check=True)
    prof = plistlib.loads(cms.stdout)
    if expected_team not in prof.get("TeamIdentifier", []):
        sys.exit(f"error: Embedded profile TeamIdentifier {prof.get('TeamIdentifier')} != {expected_team}")
    prof_containers = prof.get("Entitlements", {}).get("com.apple.developer.icloud-container-identifiers", [])
    if icloud_container_id not in prof_containers:
        sys.exit(f"error: Embedded profile containers {prof_containers} do not authorize '{icloud_container_id}'")

# Validate CloudKit container in entitlements
containers = main_ent.get("com.apple.developer.icloud-container-identifiers", [])
if containers:
    if icloud_container_id not in containers:
        sys.exit(f"error: Info.plist ICloudContainerIdentifier '{icloud_container_id}' not found in entitlements {containers}")

# Validate helpers dynamically from engines.json
with open(engines_json_path, "r") as f:
    engines_cfg = json.load(f)

for eng_key, eng_data in engines_cfg.get("engines", {}).items():
    if not isinstance(eng_data, dict) or eng_data.get("layout") != "python-runtime":
        continue
    helper_name = eng_data.get("helper")
    suffix = eng_data.get("helperIdentifierSuffix")
    expected_id = f"{bundle_id}.{suffix}"
    hpath = os.path.join(app_path, "Contents", "MacOS", helper_name)
    hent = read_entitlements(hpath)
    if hent.get("com.apple.security.app-sandbox") is not True or hent.get("com.apple.security.inherit") is not True:
        sys.exit(f"error: {helper_name} is missing app-sandbox + inherit entitlements: {hent}")
    dv = subprocess.run(["codesign", "-dvv", hpath], capture_output=True, text=True).stderr
    if f"Identifier={expected_id}" not in dv:
        sys.exit(f"error: {helper_name} does not have Identifier={expected_id}")

qgc_app = os.path.join(app_path, "Contents", "Helpers", "QGroundControl.app")
qgc_ent = read_entitlements(qgc_app)
for req_key in (
    "com.apple.security.app-sandbox",
    "com.apple.security.inherit",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
):
    if qgc_ent.get(req_key) is not True:
        sys.exit(f"error: QGroundControl.app is missing required entitlement {req_key} (got: {qgc_ent})")
for forbidden_key in ("com.apple.security.network.client", "com.apple.security.network.server"):
    if forbidden_key in qgc_ent:
        sys.exit(f"error: QGroundControl.app must not declare {forbidden_key} alongside com.apple.security.inherit")

# 4. Audit every Mach-O binary in the bundle
SKIP_EXTS = {
    ".py", ".pyc", ".pyo", ".pyd", ".txt", ".md", ".rst", ".json", ".yaml", ".yml",
    ".xml", ".plist", ".html", ".htm", ".css", ".js", ".ts", ".qml", ".qmldir",
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".icns", ".ico", ".tif", ".tiff",
    ".h", ".hpp", ".hxx", ".c", ".cc", ".cpp", ".cxx", ".m", ".mm", ".swift",
    ".cmake", ".pc", ".la", ".a", ".o", ".lo", ".al", ".nib", ".strings",
    ".ttf", ".otf", ".woff", ".woff2", ".eot", ".wav", ".mp3", ".ogg",
    ".sql", ".csv", ".tsv", ".lock", ".sh", ".bash", ".zsh", ".fish", ".bat",
}
MACHO_MAGICS = {0xFEEDFACE, 0xCEFAEDFE, 0xFEEDFACF, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA}

macho_list = []
for dirpath, _, filenames in os.walk(app_path):
    for fn in filenames:
        p = os.path.join(dirpath, fn)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        _, ext = os.path.splitext(p)
        if ext.lower() in SKIP_EXTS:
            continue
        try:
            with open(p, "rb") as f:
                hdr = f.read(16)
            if len(hdr) < 16:
                continue
            magic = struct.unpack(">I", hdr[:4])[0]
            if magic not in MACHO_MAGICS:
                continue
            is_exec = False
            if magic in (0xCAFEBABE, 0xBEBAFECA):
                narch = struct.unpack(">I" if magic == 0xCAFEBABE else "<I", hdr[4:8])[0]
                if not (1 <= narch <= 20):
                    continue
            else:
                le = magic in (0xCEFAEDFE, 0xCFFAEDFE)
                ftype = struct.unpack("<I" if le else ">I", hdr[12:16])[0]
                if ftype not in (2, 6, 8):
                    continue
                is_exec = (ftype == 2)
            macho_list.append((p, is_exec))
        except OSError:
            pass

def check_one(item):
    p, is_exec = item
    rel = os.path.relpath(p, app_path)
    res = subprocess.run(["codesign", "-dvvv", p], capture_output=True, text=True)
    out = res.stderr
    if res.returncode != 0 or "code object is not signed at all" in out:
        return f"{rel}: unsigned"
    if "Signature=adhoc" in out:
        return f"{rel}: ad-hoc signed"
    if f"TeamIdentifier={expected_team}" not in out:
        return f"{rel}: TeamIdentifier != {expected_team}"
    if is_exec and "(runtime)" not in out:
        return f"{rel}: executable missing hardened runtime flag"
    if not allow_dev:
        if "Authority=Developer ID Application:" not in out:
            return f"{rel}: not signed with Developer ID Application"
        if "Timestamp=" not in out:
            return f"{rel}: missing secure timestamp"
    return None

failures = []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for err in pool.map(check_one, macho_list):
        if err:
            failures.append(err)

if failures:
    print(f"error: {len(failures)} Mach-O signature violation(s) found:", file=sys.stderr)
    for msg in failures[:25]:
        print(f"  - {msg}", file=sys.stderr)
    sys.exit(1)

print(
    f"Verified all {len(macho_list)} Mach-O binaries "
    f"(TeamIdentifier={expected_team}, AppEnvironment={app_env}, Container={icloud_container_id}, allow_dev={allow_dev})."
)
PY

    if [[ "${SKIP_ENGINE_SELF_CHECKS:-0}" != "1" ]]; then
        echo "=== [4/4] Running Functional Engine Self-Checks ==="
        run_engine_self_checks "$app_path"
    else
        echo "=== [4/4] Functional Engine Self-Checks skipped (SKIP_ENGINE_SELF_CHECKS=1) ==="
    fi
}

cmd_dmg() {
    local app_path="${APP_PATH:-}"
    local dmg_path="${DMG_PATH:-$repo_root/.build/ControlDroneMapping.dmg}"
    local volume_name="${VOLUME_NAME:-ControlDroneMapping}"
    local dmg_format="${DMG_FORMAT:-ULFO}"

    if [[ -z "$app_path" ]]; then
        echo "=== Ensuring Engine Dependencies are Cached & Valid ==="
        "$repo_root/Scripts/ensure-all-deps-valid.sh" --download-only

        echo "=== Building ControlDroneMapping (Release, arm64) ==="
        xcodebuild -project DroneMapping.xcodeproj \
            -scheme ControlDroneMapping \
            -configuration Release \
            -destination 'platform=macOS,arch=arm64' \
            -derivedDataPath .build/DerivedData \
            ARCHS=arm64 \
            ONLY_ACTIVE_ARCH=NO \
            build

        app_path="$repo_root/.build/DerivedData/Build/Products/Release/ControlDroneMapping.app"
    fi

    if [[ ! -d "$app_path" ]]; then
        echo "error: Application bundle not found at $app_path" >&2
        exit 1
    fi

    echo "=== Verifying Application Bundle Signature Integrity Before Packaging ==="
    codesign --verify --deep --strict --verbose=2 "$app_path"

    if [[ "${SKIP_ENGINE_SELF_CHECKS:-0}" != "1" ]]; then
        run_engine_self_checks "$app_path"
    fi

    echo "=== Preparing DMG Staging Directory ==="
    local staging="$repo_root/.build/dmg-staging"
    rm -rf "$staging"
    mkdir -p "$staging"

    ditto "$app_path" "$staging/ControlDroneMapping.app"
    ln -s /Applications "$staging/Applications"

    echo "=== Creating DMG ($dmg_format) at $dmg_path ==="
    mkdir -p "$(dirname "$dmg_path")"
    rm -f "$dmg_path"

    hdiutil create \
        -volname "$volume_name" \
        -srcfolder "$staging" \
        -ov \
        -fs APFS \
        -format "$dmg_format" \
        "$dmg_path"

    rm -rf "$staging"
    echo "=== DMG created successfully ==="
    ls -lh "$dmg_path"
}

cmd_sign_dmg() {
    local dmg_path="${1:-}"
    if [[ -z "$dmg_path" || ! -f "$dmg_path" ]]; then
        echo "error: Usage: release.sh sign-dmg <path/to/file.dmg>" >&2
        exit 1
    fi
    local identity="${DMG_SIGN_IDENTITY:-Developer ID Application}"
    echo "=== Signing DMG: $dmg_path ==="
    codesign --force --sign "$identity" --timestamp "$dmg_path"
    codesign --verify --strict --verbose=2 "$dmg_path"
}

cmd_notarize() {
    local target="${1:-}"
    if [[ -z "$target" || ! -e "$target" ]]; then
        echo "error: Usage: release.sh notarize <path/to/ControlDroneMapping.app | file.dmg>" >&2
        exit 1
    fi
    : "${NOTARY_KEY_P8_BASE64:?Missing NOTARY_KEY_P8_BASE64}"
    : "${NOTARY_KEY_ID:?Missing NOTARY_KEY_ID}"
    : "${NOTARY_ISSUER_ID:?Missing NOTARY_ISSUER_ID}"

    local temp_dir="${RUNNER_TEMP:-/tmp}"
    local key_file="$temp_dir/AuthKey_${NOTARY_KEY_ID}.p8"
    local submit_path="$target"
    local cleanup_zip=""

    echo "$NOTARY_KEY_P8_BASE64" | base64 --decode > "$key_file"
    trap 'rm -f "$key_file" ${cleanup_zip:+"$cleanup_zip"}' RETURN

    if [[ -d "$target" && "$target" == *.app ]]; then
        cleanup_zip="$temp_dir/$(basename "$target").notarize.zip"
        rm -f "$cleanup_zip"
        echo "=== Creating temporary archive for app notarization: $cleanup_zip ==="
        ditto -c -k --keepParent "$target" "$cleanup_zip"
        submit_path="$cleanup_zip"
    fi

    echo "=== Submitting $(basename "$submit_path") to Apple Notary Service ==="
    local result_json="$temp_dir/notary-result-$$.json"
    xcrun notarytool submit "$submit_path" \
        --key "$key_file" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER_ID" \
        --wait \
        --timeout 60m \
        --output-format json | tee "$result_json"

    local sub_id status
    sub_id="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('id',''))" "$result_json")"
    status="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" "$result_json")"
    rm -f "$result_json"

    if [[ "$status" != "Accepted" ]]; then
        echo "error: Notarization failed with status '$status' (submission ID: $sub_id)" >&2
        if [[ -n "$sub_id" ]]; then
            echo "=== Fetching Detailed Apple Notarization Log ===" >&2
            xcrun notarytool log "$sub_id" \
                --key "$key_file" \
                --key-id "$NOTARY_KEY_ID" \
                --issuer "$NOTARY_ISSUER_ID" >&2 || true
        fi
        exit 1
    fi

    echo "=== Stapling & Validating Notarization Ticket on $target ==="
    xcrun stapler staple "$target"
    xcrun stapler validate "$target"
}

cmd_verify_dmg() {
    local dmg_path="${1:-}"
    if [[ -z "$dmg_path" || ! -f "$dmg_path" ]]; then
        echo "error: Usage: release.sh verify-dmg <path/to/file.dmg>" >&2
        exit 1
    fi

    echo "=== [1/4] Verifying DMG Signature, Notarization Ticket & Gatekeeper ==="
    codesign --verify --strict --verbose=2 "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl -a -t open --context context:primary-signature -vvv "$dmg_path"

    echo "=== [2/4] Simulating Browser Download (Quarantine) & Mounting DMG ==="
    local work_dir
    work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/cdm-dmg-verify.XXXXXX")"
    local mnt="$work_dir/mnt"
    local q_dmg="$work_dir/$(basename "$dmg_path")"
    local installed_app="$work_dir/Applications/ControlDroneMapping.app"
    mkdir -p "$mnt" "$work_dir/Applications"

    cleanup_verify_dmg() {
        hdiutil detach "$mnt" -force >/dev/null 2>&1 || true
        rm -rf "$work_dir"
    }
    trap cleanup_verify_dmg RETURN

    cp -f "$dmg_path" "$q_dmg"
    xattr -w com.apple.quarantine "0083;67200000;Safari;00000000-0000-0000-0000-000000000000" "$q_dmg"

    hdiutil attach "$q_dmg" -nobrowse -readonly -mountpoint "$mnt"
    ditto "$mnt/ControlDroneMapping.app" "$installed_app"
    hdiutil detach "$mnt"

    echo "=== [3/4] Verifying Quarantined Installed App Against Gatekeeper & Stapler ==="
    xcrun stapler validate "$installed_app"
    spctl -a -t exec -vvv "$installed_app"
    if command -v syspolicy_check >/dev/null 2>&1; then
        syspolicy_check distribution "$installed_app" || echo "note: syspolicy_check reported non-fatal advisory above"
    fi

    echo "=== [4/4] Running Engine Self-Checks from Quarantined Installed Copy ==="
    run_engine_self_checks "$installed_app"

    local sha_file="${dmg_path}.sha256"
    (cd "$(dirname "$dmg_path")" && shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$sha_file")")
    echo "=== Generated Checksum: $sha_file ==="
    cat "$sha_file"
}

subcmd="${1:-}"
shift || true

case "$subcmd" in
    dmg)                    cmd_dmg "$@" ;;
    version)                cmd_version "$@" ;;
    select-xcode)           cmd_select_xcode "$@" ;;
    build-check)            cmd_build_check "$@" ;;
    export-cloudkit-schema) cmd_export_cloudkit_schema "$@" ;;
    sync-cloudkit-schema)   cmd_sync_cloudkit_schema "$@" ;;
    setup-signing)          cmd_setup_signing "$@" ;;
    cleanup-signing)        cmd_cleanup_signing "$@" ;;
    archive)                cmd_archive "$@" ;;
    verify-app)             cmd_verify_app "$@" ;;
    sign-dmg)               cmd_sign_dmg "$@" ;;
    notarize)               cmd_notarize "$@" ;;
    verify-dmg)             cmd_verify_dmg "$@" ;;
    -h|--help|help)         usage ;;
    *)
        echo "error: Unknown subcommand '$subcmd'" >&2
        usage >&2
        exit 1
        ;;
esac

