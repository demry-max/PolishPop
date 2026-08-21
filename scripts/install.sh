#!/bin/zsh
# Build PolishPop from a fresh checkout and install it.
#
# This is the counterpart to package_app.sh, which is a *release* script: that one runs live Codex
# smoke tests and so requires an account that is already signed in — impossible for someone who has
# not installed the app yet. This one runs only the checks that work offline.
#
# Building locally also sidesteps Gatekeeper entirely. macOS applies the quarantine flag to
# downloads, not to software you compiled yourself, so an app installed this way never produces the
# "Apple could not verify..." dialog.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DEST_DIR="${POLISHPOP_DEST:-/Applications}"
APP_PATH="${DEST_DIR}/PolishPop.app"
SIGN_IDENTITY="PolishPop Self-Signed"

say() { print -r -- "$@" }
fail() { print -r -- "error: $@" >&2; exit 1 }

# --- Prerequisites -----------------------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || fail "PolishPop is a macOS app."
[[ "$(uname -m)" == "arm64" ]] || fail "PolishPop requires an Apple Silicon Mac."

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
(( macos_major >= 13 )) || fail "macOS 13 or later is required (found $(sw_vers -productVersion))."

if ! command -v swift >/dev/null 2>&1; then
    fail "The Swift toolchain is missing. Install Xcode, or the Command Line Tools with:
    xcode-select --install"
fi

say "==> Building PolishPop"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi
SDKROOT="$SDK_PATH" swift build --disable-sandbox --sdk "$SDK_PATH" -c release --package-path "$PROJECT_ROOT"

BINARY="${PROJECT_ROOT}/.build/release/PolishPop"
[[ -x "$BINARY" ]] || fail "The build did not produce an executable."

# --- Checks that need no account ---------------------------------------------------------------

say "==> Verifying"
"$BINARY" --self-test
"$BINARY" --activation-probe >/dev/null && say "window activation guard: passed"

# --- Assemble ----------------------------------------------------------------------------------

say "==> Assembling the app bundle"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="${STAGING}/PolishPop.app"
mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources"
cp "$BINARY" "${STAGED_APP}/Contents/MacOS/PolishPop"
cp "${PROJECT_ROOT}/Support/Info.plist" "${STAGED_APP}/Contents/Info.plist"
cp "${PROJECT_ROOT}/Support/PolishPop.icns" "${STAGED_APP}/Contents/Resources/PolishPop.icns"

# A certificate-based signature keeps its designated requirement stable across rebuilds, so macOS
# keeps honouring the Accessibility permission. An ad-hoc signature is keyed to the code hash and
# is therefore invalidated by every single build.
if /usr/bin/security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGED_APP"
    say "signed with: ${SIGN_IDENTITY}"
else
    /usr/bin/codesign --force --deep --sign - "$STAGED_APP"
    say "signed ad-hoc (no '${SIGN_IDENTITY}' certificate on this Mac)."
    say "  Accessibility permission will need re-granting after each rebuild."
    say "  See 'Stable code signing' in README.md to avoid that."
fi

# --- Install -----------------------------------------------------------------------------------

if pgrep -f "${APP_PATH}/Contents/MacOS/PolishPop" >/dev/null 2>&1; then
    say "==> Quitting the running copy"
    pkill -f "${APP_PATH}/Contents/MacOS/PolishPop" || true
    sleep 2
fi

say "==> Installing to ${DEST_DIR}"
mkdir -p "$DEST_DIR"
rm -rf "$APP_PATH"
cp -R "$STAGED_APP" "$APP_PATH"

say ""
say "Installed: ${APP_PATH}"
say ""
say "Next:"
say "  1. Install the Codex CLI if you have not already:  npm install -g @openai/codex"
say "  2. Open PolishPop and grant Accessibility permission when asked."
say "  3. In PolishPop's settings, choose 'Sign in with ChatGPT'."
say ""
say "Nothing was downloaded, so macOS will not ask you to bypass Gatekeeper."
