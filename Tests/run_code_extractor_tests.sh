#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gaoyoujian-code-extractor-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

swiftc -module-cache-path "$TEST_TMP/ModuleCache" \
  -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  "$PROJECT_ROOT/Sources/CodeExtractor.swift" \
  "$PROJECT_ROOT/Tests/CodeExtractorTests.swift" \
  -o "$TEST_TMP/CodeExtractorTests"
"$TEST_TMP/CodeExtractorTests"
