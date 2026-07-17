#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CN="VoiceInputLocal Dev"
KC="$HOME/Library/Keychains/voiceinput-signing.keychain-db"
KC_PW="voiceinput-local"
P12_PW="voiceinput"

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
trap 'rm -rf "${TMP}"' EXIT

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

EXISTING="$(security list-keychains -d user | sed 's/[" ]//g' | grep -v "^${KC}$" || true)"
security list-keychains -d user -s "${KC}" ${EXISTING}

echo "created signing identity: ${CN}"
