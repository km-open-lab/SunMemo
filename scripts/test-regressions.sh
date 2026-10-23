#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/regression
sources=()
for source in Sources/SunMemo/*.swift; do
  if [ "$source" != "Sources/SunMemo/main.swift" ]; then sources+=("$source"); fi
done
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" scripts/regression/main.swift -o build/regression/SunMemoRegression
build/regression/SunMemoRegression --demo
