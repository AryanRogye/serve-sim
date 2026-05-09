#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-booted}"

xcrun simctl spawn "$DEVICE" log stream \
  --style compact \
  --level debug \
  --predicate 'eventMessage CONTAINS "[RuntimeInspector]"'
