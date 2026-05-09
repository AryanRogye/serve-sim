#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <bundle-id> [simulator-udid|booted] [app-args...]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="$1"
DEVICE="${2:-booted}"
shift || true
if [ "$#" -gt 0 ]; then shift || true; fi

DYLIB="$("$ROOT_DIR/Scripts/build_runtime_inspector.sh")"

echo "Launching $BUNDLE_ID on $DEVICE with:"
echo "  DYLD_INSERT_LIBRARIES=$DYLIB"

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl spawn "$DEVICE" launchctl setenv DYLD_INSERT_LIBRARIES "$DYLIB"
trap 'xcrun simctl spawn "$DEVICE" launchctl unsetenv DYLD_INSERT_LIBRARIES >/dev/null 2>&1 || true' EXIT

xcrun simctl launch \
  --console-pty \
  "$DEVICE" \
  "$BUNDLE_ID" \
  "$@"
