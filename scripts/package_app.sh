#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
OUTPUT_DIR="${1:-${PROJECT_ROOT:h:h}/outputs}"
APP_PATH="${OUTPUT_DIR}/PolishPop.app"
ZIP_PATH="${OUTPUT_DIR}/PolishPop-0.4.1.zip"
CACHE_DIR="${PROJECT_ROOT}/.cache"

if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

/bin/mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/swiftpm"
SDKROOT="$SDK_PATH" \
CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/swiftpm" \
swift build --disable-sandbox --sdk "$SDK_PATH" -c release --package-path "$PROJECT_ROOT"

"$PROJECT_ROOT/.build/release/PolishPop" --self-test
"$PROJECT_ROOT/.build/release/PolishPop" --codex-smoke-test
"$PROJECT_ROOT/.build/release/PolishPop" --polish-smoke-test

/bin/rm -rf "$APP_PATH"
/bin/rm -f "$ZIP_PATH"
/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$OUTPUT_DIR"
/bin/cp "$PROJECT_ROOT/.build/release/PolishPop" "$APP_PATH/Contents/MacOS/PolishPop"
/bin/cp "$PROJECT_ROOT/Support/Info.plist" "$APP_PATH/Contents/Info.plist"
/bin/cp "$PROJECT_ROOT/Support/PolishPop.icns" "$APP_PATH/Contents/Resources/PolishPop.icns"
/usr/bin/codesign --force --deep --sign - "$APP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
