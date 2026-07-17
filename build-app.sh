#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="VoiceInputLocal"
APP="${APP_NAME}.app"
ICON="Resources/AppIcon.icns"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-VoiceInputLocal Dev}"
SIGN_KEYCHAIN="${HOME}/Library/Keychains/voiceinput-signing.keychain-db"

if [[ ! -f "${ICON}" ]]; then
    echo "missing app icon: ${ICON}" >&2
    exit 1
fi

swift build -c "${CONFIG}"
BIN_DIR="$(swift build -c "${CONFIG}" --show-bin-path)"

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP}/Contents/Info.plist"
cp "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${APP}/Contents/PkgInfo"
if [[ -f "${SIGN_KEYCHAIN}" ]]; then
    security unlock-keychain -p "voiceinput-local" "${SIGN_KEYCHAIN}" 2>/dev/null || true
fi

if [[ -f "${SIGN_KEYCHAIN}" ]] && codesign --force --deep --options runtime --sign "${SIGN_IDENTITY}" --keychain "${SIGN_KEYCHAIN}" "${APP}" 2>/dev/null; then
    echo "signed with stable identity: ${SIGN_IDENTITY}"
elif [[ "${ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
    echo "warning: explicit ad-hoc signing; privacy permissions will not survive rebuilds" >&2
    codesign --force --deep --sign - "${APP}"
else
    echo "missing stable signing identity. Run ./tools/setup-signing.sh first." >&2
    exit 1
fi

echo "built: $(pwd)/${APP}"
