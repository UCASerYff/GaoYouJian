#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gaoyoujian-floating-geometry.XXXXXX")"
cleanup() {
  if [[ -s "$TEST_TMP/native-suite.txt" ]]; then
    local native_test_suite
    IFS= read -r native_test_suite < "$TEST_TMP/native-suite.txt"
    if [[ "$native_test_suite" =~ ^GaoYouJian\.HiddenNativeTest\.[A-Fa-f0-9-]{36}$ ]]; then
      # A failed assertion bypasses Swift defer cleanup. Remove the exact test domain from cfprefsd as well.
      /usr/bin/defaults delete "$native_test_suite" >/dev/null 2>&1 || true
      # CFPreferences may flush an empty plist several seconds after the test process exits.
      # Keep removing only this run's UUID domain through that deferred flush window.
      for _ in {1..12}; do
        sleep 0.5
        rm -f -- "$HOME/Library/Preferences/$native_test_suite.plist"
      done
    fi
  fi
  rm -rf -- "$TEST_TMP"
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Concatenation gives the test extension access to private setup methods; no production API is exposed for testing.
cat "$PROJECT_ROOT/Sources/MailFloatingController.swift" "$PROJECT_ROOT/Tests/FloatingGeometryTests.swift" \
  > "$TEST_TMP/ControllerAndTests.swift"

# Real hidden NSPanel objects receive directly constructed NSEvents; no windows are shown and no OS input is injected.
swiftc -module-cache-path "$TEST_TMP/ModuleCache" \
  -swift-version 5 -D DEBUG_TESTING -target "$(uname -m)-apple-macos14.0" \
  "$TEST_TMP/ControllerAndTests.swift" \
  "$PROJECT_ROOT/Sources/MailFloatingRail.swift" \
  -framework AppKit -framework SwiftUI \
  -o "$TEST_TMP/FloatingGeometryTests"
GAOYOUJIAN_TEST_SUITE_METADATA="$TEST_TMP/native-suite.txt" "$TEST_TMP/FloatingGeometryTests"
