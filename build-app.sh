#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="VoiceInputLocal"
APP="${APP_OUTPUT_DIR:-$(pwd)/${APP_NAME}.app}"
ICON="Resources/AppIcon.icns"
ENTITLEMENTS="$(pwd)/VoiceInputLocal.entitlements"
LOCAL_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-VoiceInputLocal Dev}"
SIGN_KEYCHAIN="${HOME}/Library/Keychains/voiceinput-signing.keychain-db"
SIGN_KEYCHAIN_PASSWORD_FILE="${HOME}/Library/Application Support/VoiceInputLocal/signing-keychain-password"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)"
LOCAL_KEYCHAIN_UNLOCKED=0

cleanup_signing_keychain() {
    if [[ "${LOCAL_KEYCHAIN_UNLOCKED}" == "1" ]]; then
        security lock-keychain "${SIGN_KEYCHAIN}" 2>/dev/null || true
    fi
}
trap cleanup_signing_keychain EXIT

if [[ ! -f "${ICON}" ]]; then
    echo "missing app icon: ${ICON}" >&2
    exit 1
fi
if [[ ! -f "${ENTITLEMENTS}" ]]; then
    echo "missing entitlements: ${ENTITLEMENTS}" >&2
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
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
        codesign \
            --force \
            --deep \
            --options runtime \
            --entitlements "${ENTITLEMENTS}" \
            --sign - \
            --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
            "${APP}"
        echo "signed for development distribution: ad-hoc"
    else
        codesign \
            --force \
            --deep \
            --options runtime \
            --entitlements "${ENTITLEMENTS}" \
            --timestamp \
            --sign "${SIGNING_IDENTITY}" \
            "${APP}"
        echo "signed for public distribution: ${SIGNING_IDENTITY}"
    fi
elif [[ -f "${SIGN_KEYCHAIN}" && -f "${SIGN_KEYCHAIN_PASSWORD_FILE}" ]]; then
    SIGN_KEYCHAIN_PASSWORD="$(<"${SIGN_KEYCHAIN_PASSWORD_FILE}")"
    security unlock-keychain -p "${SIGN_KEYCHAIN_PASSWORD}" "${SIGN_KEYCHAIN}"
    LOCAL_KEYCHAIN_UNLOCKED=1
    if codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${LOCAL_SIGN_IDENTITY}" \
        --keychain "${SIGN_KEYCHAIN}" \
        "${APP}" 2>/dev/null; then
        echo "signed with stable identity: ${LOCAL_SIGN_IDENTITY}"
    elif [[ "${ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
        echo "warning: explicit ad-hoc signing; privacy permissions will not survive rebuilds" >&2
        codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS}" --sign - "${APP}"
    else
        echo "stable signing failed. Run ./tools/setup-signing.sh again." >&2
        exit 1
    fi
elif [[ "${ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
    echo "warning: explicit ad-hoc signing; privacy permissions will not survive rebuilds" >&2
    codesign --force --deep --options runtime --entitlements "${ENTITLEMENTS}" --sign - "${APP}"
else
    echo "missing stable signing identity. Run ./tools/setup-signing.sh first." >&2
    exit 1
fi

echo "built: ${APP}"
