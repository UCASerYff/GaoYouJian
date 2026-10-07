#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gaoyoujian-floating-geometry.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Compile the real native controller/rail; the test supplies inert UI/store types and never opens a window.
swiftc -module-cache-path "$TEST_TMP/ModuleCache" \
  -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  "$PROJECT_ROOT/Sources/MailFloatingController.swift" \
  "$PROJECT_ROOT/Sources/MailFloatingRail.swift" \
  "$PROJECT_ROOT/Tests/FloatingGeometryTests.swift" \
  -framework AppKit -framework SwiftUI \
  -o "$TEST_TMP/FloatingGeometryTests"
"$TEST_TMP/FloatingGeometryTests"
