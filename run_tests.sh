#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPTHALO_TEST_DIR="$(mktemp -d /tmp/prompthalo-self-tests.XXXXXX)"
PROMPTHALO_TEST_BINARY="$PROMPTHALO_TEST_DIR/PromptHaloSelfTests"

cleanup() {
    rm -rf "$PROMPTHALO_TEST_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"

swiftc \
    -parse-as-library \
    Sources/PromptHalo/Localization.swift \
    Sources/PromptHalo/PromptItem.swift \
    Sources/PromptHalo/PromptTemplates.swift \
    Sources/PromptHalo/PromptStore.swift \
    Sources/PromptHalo/TriggerHotKey.swift \
    Tests/PromptHaloSelfTests.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework Carbon \
    -o "$PROMPTHALO_TEST_BINARY"

"$PROMPTHALO_TEST_BINARY"
