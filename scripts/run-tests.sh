#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATS_VENDOR_DIR="$ROOT_DIR/tests/.deps/bats-core"
BATS_BIN=""

if command -v bats >/dev/null 2>&1; then
    BATS_BIN="$(command -v bats)"
elif [[ -x "$BATS_VENDOR_DIR/bin/bats" ]]; then
    BATS_BIN="$BATS_VENDOR_DIR/bin/bats"
else
    echo "bats-core not found; installing to tests/.deps/bats-core ..."
    rm -rf "$BATS_VENDOR_DIR"
    git clone --depth 1 --branch v1.11.0 https://github.com/bats-core/bats-core.git "$BATS_VENDOR_DIR"
    BATS_BIN="$BATS_VENDOR_DIR/bin/bats"
fi

echo "Running bats with: $BATS_BIN"
exec "$BATS_BIN" "$ROOT_DIR/tests"
