#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/PromptHalo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ARM64_BUILD_DIR="$PROJECT_DIR/.build/release-arm64"
X86_64_BUILD_DIR="$PROJECT_DIR/.build/release-x86_64"
SIGNING_IDENTITY="${PROMPTHALO_SIGNING_IDENTITY:-PromptHalo Local Signing}"

cd "$PROJECT_DIR"

echo "Building PromptHalo for Apple silicon…"
swift build \
    -c release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$ARM64_BUILD_DIR"
ARM64_BIN_DIR="$(swift build \
    -c release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$ARM64_BUILD_DIR" \
    --show-bin-path)"

echo "Building PromptHalo for Intel…"
swift build \
    -c release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$X86_64_BUILD_DIR"
X86_64_BIN_DIR="$(swift build \
    -c release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$X86_64_BUILD_DIR" \
    --show-bin-path)"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
lipo -create \
    "$ARM64_BIN_DIR/PromptHalo" \
    "$X86_64_BIN_DIR/PromptHalo" \
    -output "$MACOS_DIR/PromptHalo"
chmod 755 "$MACOS_DIR/PromptHalo"
install -m 644 "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
find "$APP_DIR" -name '._*' -delete

if ! security find-identity -v -p codesigning \
    | grep -F "\"${SIGNING_IDENTITY}\"" >/dev/null; then
    echo "Missing stable signing identity: ${SIGNING_IDENTITY}" >&2
    echo "Run ./setup_local_signing.sh once, then build again." >&2
    exit 1
fi

codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --timestamp=none \
    "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"
lipo -archs "$MACOS_DIR/PromptHalo"

echo
echo "Built:"
echo "$APP_DIR"
