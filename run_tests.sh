#!/bin/bash

# Test runner script for Mouse Toucher. This intentionally uses only the Swift
# compiler so it also works with Apple's Command Line Tools (without Xcode).

set -euo pipefail

TEST_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT

swiftc \
    Sources/MouseToucherLib/CompoundTapDetector.swift \
    Tests/CompoundTapDetectorTests.swift \
    -o "$TEST_BUILD_DIR/MouseToucherLogicTests"

"$TEST_BUILD_DIR/MouseToucherLogicTests"
