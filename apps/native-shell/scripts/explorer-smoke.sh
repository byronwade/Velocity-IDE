#!/usr/bin/env bash
# Exercise compact 1280px Explorer collapse, filter, reveal controls, and labels.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"

native build --yes -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
./zig-out/bin/velocity-ide >/tmp/velocity-explorer-smoke.out 2>&1 &
APP_PID=$!
cleanup() {
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
}
trap cleanup EXIT
sleep 3
kill -0 "$APP_PID"

OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | head -1)"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
native automate assert --timeout-ms 5000 \
  'Collapse all Explorer folders' \
  'Expand all Explorer folders' \
  'Collapse src' \
  'auth.ts'

SRC_CHEVRON="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Collapse src".*/\1/p' | head -1)"
test -n "$SRC_CHEVRON"
native automate widget-click main-canvas "$SRC_CHEVRON"
native automate assert --absent --timeout-ms 5000 'auth.ts'
native automate assert --timeout-ms 5000 'Expand src'

FILTER_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=textbox name="Explorer filter".*/\1/p' | head -1)"
test -n "$FILTER_ID"
native automate widget-action main-canvas "$FILTER_ID" set_text "auth"
native automate assert --timeout-ms 5000 'auth.ts' 'src' 'server'

native automate widget-action main-canvas "$FILTER_ID" set_text ""
native automate assert --absent --timeout-ms 5000 'auth.ts'

EXPAND_ALL="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Expand all Explorer folders".*/\1/p' | head -1)"
test -n "$EXPAND_ALL"
native automate widget-click main-canvas "$EXPAND_ALL"
native automate assert --timeout-ms 5000 'auth.ts' 'Collapse src'

echo "explorer-smoke: ok"
