#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CN="VoiceInputLocal Dev"
KC="$HOME/Library/Keychains/voiceinput-signing.keychain-db"
STATE_DIR="$HOME/Library/Application Support/VoiceInputLocal"
KC_PW_FILE="$STATE_DIR/signing-keychain-password"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

if [[ -f "$KC" && ! -f "$KC_PW_FILE" ]]; then
    security delete-keychain "$KC" 2>/dev/null || rm -f "$KC"
fi

if [[ ! -f "$KC_PW_FILE" ]]; then
    umask 077
    openssl rand -base64 48 | tr -d '\n' > "$KC_PW_FILE"
fi
chmod 600 "$KC_PW_FILE"

KC_PW="$(<"$KC_PW_FILE")"
P12_PW="$(openssl rand -base64 48 | tr -d '\n')"

cleanup() {
    security lock-keychain "${KC}" 2>/dev/null || true
    if [[ -n "${TMP:-}" ]]; then
        rm -rf "${TMP}"
    fi
}
trap cleanup EXIT

if [[ -f "${KC}" ]]; then
    security unlock-keychain -p "${KC_PW}" "${KC}"
else
    security create-keychain -p "${KC_PW}" "${KC}"
    security unlock-keychain -p "${KC_PW}" "${KC}"
fi
security set-keychain-settings "${KC}" 2>/dev/null || true

if security find-certificate -c "${CN}" "${KC}" >/dev/null 2>&1; then
    echo "signing identity already exists: ${CN}"
    exit 0
fi

TMP="$(mktemp -d)"

cat > "${TMP}/codesign.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ${CN}
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -keyout "${TMP}/codesign.key" -out "${TMP}/codesign.crt" \
    -days 3650 -nodes -config "${TMP}/codesign.cnf" 2>/dev/null

if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    openssl pkcs12 -export -legacy -inkey "${TMP}/codesign.key" -in "${TMP}/codesign.crt" \
        -out "${TMP}/codesign.p12" -passout "pass:${P12_PW}" -name "${CN}" 2>/dev/null
else
    openssl pkcs12 -export -inkey "${TMP}/codesign.key" -in "${TMP}/codesign.crt" \
        -out "${TMP}/codesign.p12" -passout "pass:${P12_PW}" -name "${CN}" 2>/dev/null
fi

security import "${TMP}/codesign.p12" -k "${KC}" -P "${P12_PW}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KC_PW}" "${KC}" >/dev/null
security lock-keychain "${KC}"

echo "created signing identity: ${CN}"
