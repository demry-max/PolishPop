#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
OUTPUT_DIR="${1:-${PROJECT_ROOT:h:h}/outputs}"
APP_PATH="${OUTPUT_DIR}/PolishPop.app"
ZIP_PATH="${OUTPUT_DIR}/PolishPop-0.5.0.zip"
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
"$PROJECT_ROOT/.build/release/PolishPop" --render-ui "${OUTPUT_DIR}/ui-render"
"$PROJECT_ROOT/.build/release/PolishPop" --activation-probe
"$PROJECT_ROOT/.build/release/PolishPop" --codex-smoke-test
"$PROJECT_ROOT/.build/release/PolishPop" --polish-smoke-test

/bin/rm -rf "$APP_PATH"
/bin/rm -f "$ZIP_PATH"
/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$OUTPUT_DIR"
/bin/cp "$PROJECT_ROOT/.build/release/PolishPop" "$APP_PATH/Contents/MacOS/PolishPop"
/bin/cp "$PROJECT_ROOT/Support/Info.plist" "$APP_PATH/Contents/Info.plist"
/bin/cp "$PROJECT_ROOT/Support/PolishPop.icns" "$APP_PATH/Contents/Resources/PolishPop.icns"
# Prefer a stable signing identity over ad-hoc.
#
# An ad-hoc signature's designated requirement is the code hash, so it changes on every build and
# macOS discards the app's Accessibility permission each time. Signing with a certificate makes the
# requirement `identifier ... and certificate leaf = H"..."`, which survives rebuilds — the user
# grants Accessibility once instead of after every packaging run.
#
# This self-issued certificate is for LOCAL DEVELOPMENT ONLY. It does nothing for Gatekeeper: a
# copy downloaded through a browser is still blocked on first launch, because Gatekeeper wants a
# notarization ticket rather than merely a signature. Apple's notary service also rejects
# self-signed certificates outright, so shipping properly means replacing this identity with a
# Developer ID Application certificate, adding --options runtime --timestamp, and submitting to
# `xcrun notarytool` then `xcrun stapler staple`. Run `syspolicy_check distribution "$APP_PATH"`
# to see what Apple thinks is missing.
SIGN_IDENTITY="PolishPop Self-Signed"
if /usr/bin/security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
    echo "signed with: $SIGN_IDENTITY"
else
    /usr/bin/codesign --force --deep --sign - "$APP_PATH"
    echo "WARNING: '$SIGN_IDENTITY' not found; fell back to ad-hoc signing."
    echo "         Accessibility permission will need re-granting after every build."
    echo "         See 'Stable code signing' in README.md."
fi
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
