#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gaoyoujian-oauth-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Uses ephemeral in-memory RSA keys and local loopback TCP only. No real account login or email.
# Run outside a restrictive process sandbox that prevents Security.framework or local listeners.
swiftc -module-cache-path "$TEST_TMP/ModuleCache" \
  -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  "$PROJECT_ROOT/Sources/Vault.swift" \
  "$PROJECT_ROOT/Sources/OAuth.swift" \
  "$PROJECT_ROOT/Tests/OAuthTests.swift" \
  -o "$TEST_TMP/OAuthTests"
"$TEST_TMP/OAuthTests"
