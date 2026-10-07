#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gaoyoujian-model-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

swiftc -module-cache-path "$TEST_TMP/ModuleCache" \
  -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  "$PROJECT_ROOT/Sources/Models.swift" \
  "$PROJECT_ROOT/Sources/Storage.swift" \
  "$PROJECT_ROOT/Tests/ModelTests.swift" \
  -o "$TEST_TMP/ModelTests"
"$TEST_TMP/ModelTests"
