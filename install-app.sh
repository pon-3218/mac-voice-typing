#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="VoiceInputLocal"
SOURCE_APP="${APP_NAME}.app"
INSTALL_APP="/Applications/${APP_NAME}.app"
BUNDLE_ID="jp.co.ntc.voice-input-local"
SIGN_KEYCHAIN="${HOME}/Library/Keychains/voiceinput-signing.keychain-db"

if [[ ! -f "${SIGN_KEYCHAIN}" ]]; then
    ./tools/setup-signing.sh
fi

./build-app.sh release
pkill -x "${APP_NAME}" 2>/dev/null || true

rm -rf "${INSTALL_APP}"
ditto "${SOURCE_APP}" "${INSTALL_APP}"
codesign --verify --deep --strict "${INSTALL_APP}"
rm -rf "${SOURCE_APP}"

if codesign -d --verbose=2 "${INSTALL_APP}" 2>&1 | grep -q 'Signature=adhoc'; then
    echo "installation refused: app is ad-hoc signed" >&2
    exit 1
fi

open "${INSTALL_APP}"
echo "installed: ${INSTALL_APP}"
