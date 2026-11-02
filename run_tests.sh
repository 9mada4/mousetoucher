#!/bin/bash

# Test runner script for Mouse Toucher. This intentionally uses only the Swift
# compiler so it also works with Apple's Command Line Tools (without Xcode).

set -euo pipefail

TEST_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT

swiftc \
    Sources/MouseToucherLib/CompoundTapDetector.swift \
    MouseToucherSettings.swift \
    DragEventMonitor.swift \
    NativeMagnificationEmitter.swift \
    Tests/CompoundTapDetectorTests.swift \
    -o "$TEST_BUILD_DIR/MouseToucherLogicTests"

"$TEST_BUILD_DIR/MouseToucherLogicTests"

# Link the private framework for the manager's production implementation, but
# use fake device access in every test: no devices are enumerated or started.
swiftc \
    -import-objc-header MultitouchBridge.h \
    -F /System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks \
    Sources/MouseToucherLib/CompoundTapDetector.swift \
    MultitouchManager.swift \
    Tests/MultitouchManagerTests.swift \
    -o "$TEST_BUILD_DIR/MultitouchManagerTests"

"$TEST_BUILD_DIR/MultitouchManagerTests"
