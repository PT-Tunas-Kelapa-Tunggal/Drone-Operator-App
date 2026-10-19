#!/bin/sh
set -eu

# Optional generated release assets. A source checkout still builds without them;
# the app then explains that its engine package has not been prepared yet.
task_helper="$SRCROOT/.build/OrthomosaicPython"
task_runtime="$SRCROOT/.build/OrthomosaicEngine"
task_helper_destination="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/OrthomosaicPython"
task_runtime_destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/OrthomosaicEngine"
if [ -f "$task_helper" ] && [ -d "$task_runtime" ]; then
    /usr/bin/ditto "$task_runtime" "$task_runtime_destination"
    /bin/cp "$task_helper" "$task_helper_destination"
    if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
        /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime \
            --timestamp=none --preserve-metadata=identifier,entitlements,flags \
            "$task_helper_destination"
    fi
fi
