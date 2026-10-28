#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/regression
swift package resolve
sparkle_framework=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
sources=()
for source in Sources/SunMemo/*.swift; do
  if [ "$source" != "Sources/SunMemo/main.swift" ]; then sources+=("$source"); fi
done
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  -F "$sparkle_framework" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$(pwd)/$sparkle_framework" \
  "${sources[@]}" scripts/regression/main.swift -o build/regression/SunMemoRegression
build/regression/SunMemoRegression --demo
