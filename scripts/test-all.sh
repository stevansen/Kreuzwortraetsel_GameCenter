#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== build =="
swift build -q
echo "== test =="
swift test
