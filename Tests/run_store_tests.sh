#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
store_test_temp="$(mktemp -d /private/tmp/GaoMailStoreTestBuild.XXXXXX)"
trap 'rm -rf "$store_test_temp"' EXIT
clang -c Sources/MailNative.c -o "$store_test_temp/MailNative.o"
swiftc -swift-version 5 -module-cache-path "$store_test_temp/modules" -import-objc-header Sources/MailNative.h -lcurl "$store_test_temp/MailNative.o" Sources/Models.swift Sources/Storage.swift Sources/Vault.swift Sources/OAuth.swift Sources/MailTransport.swift Sources/MailStore.swift Tests/StoreTests.swift -o "$store_test_temp/store-tests"
"$store_test_temp/store-tests"
