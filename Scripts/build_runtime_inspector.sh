#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT_DIR/RuntimeInspector/RuntimeInspector.m"
OUT_DIR="$ROOT_DIR/.build/runtime-inspector"
OUT="$OUT_DIR/libRuntimeInspector.dylib"

ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) TARGET="arm64-apple-ios15.0-simulator" ;;
  x86_64) TARGET="x86_64-apple-ios15.0-simulator" ;;
  *)
    echo "Unsupported ARCH '$ARCH'. Use ARCH=arm64 or ARCH=x86_64." >&2
    exit 1
    ;;
esac

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
mkdir -p "$OUT_DIR"

xcrun clang \
  -target "$TARGET" \
  -isysroot "$SDK" \
  -mios-simulator-version-min=15.0 \
  -dynamiclib \
  -fobjc-arc \
  "$SRC" \
  -framework Foundation \
  -framework UIKit \
  -o "$OUT"

codesign -s - -f "$OUT" >/dev/null 2>&1 || true

echo "$OUT"
