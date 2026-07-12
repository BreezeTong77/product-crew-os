#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PYTHON_BIN=${PCO_PYTHON_BIN:-python3}
ITERATIONS=${1:-4}

index=1
while [ "$index" -le "$ITERATIONS" ]; do
  "$PYTHON_BIN" "$SCRIPT_DIR/run-release-gate.py"
  index=$((index + 1))
done
