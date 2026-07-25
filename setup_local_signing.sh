#!/bin/bash

set -euo pipefail

SIGNING_IDENTITY="${PROMPTHALO_SIGNING_IDENTITY:-PromptHalo Local Signing}"
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning \
    | grep -F "\"${SIGNING_IDENTITY}\"" >/dev/null; then
    echo "Stable signing identity already exists: ${SIGNING_IDENTITY}"
    exit 0
fi

TEMP_DIR="$(mktemp -d /tmp/prompthalo-signing.XXXXXX)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

P12_PASSWORD="$(openssl rand -hex 24)"

echo "Creating a local code-signing identity for PromptHalo…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=${SIGNING_IDENTITY}/" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "${TEMP_DIR}/key.pem" \
    -out "${TEMP_DIR}/cert.pem" \
    >/dev/null 2>&1

openssl pkcs12 -export \
    -out "${TEMP_DIR}/identity.p12" \
    -inkey "${TEMP_DIR}/key.pem" \
    -in "${TEMP_DIR}/cert.pem" \
    -passout "pass:${P12_PASSWORD}" \
    >/dev/null 2>&1

security import "${TEMP_DIR}/identity.p12" \
    -k "${LOGIN_KEYCHAIN}" \
    -P "${P12_PASSWORD}" \
    -T /usr/bin/codesign \
    >/dev/null

# Trust is limited to code signing. It does not change browser/TLS trust.
security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k "${LOGIN_KEYCHAIN}" \
    "${TEMP_DIR}/cert.pem"

security find-identity -v -p codesigning \
    | grep -F "\"${SIGNING_IDENTITY}\"" >/dev/null

echo "Created stable signing identity: ${SIGNING_IDENTITY}"
