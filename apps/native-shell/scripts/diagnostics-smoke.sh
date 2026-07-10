#!/usr/bin/env bash
# Boot Velocity, run a compiler-like command, and verify clickable Problems output.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"

native build -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
./zig-out/bin/velocity-ide >/tmp/velocity-diagnostics-smoke.out 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 3
kill -0 "$APP_PID"

OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | head -1)"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
sleep 1

TERM_BOX="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=textbox name="Terminal command".*/\1/p' | head -1)"
if test -z "$TERM_BOX"; then
  TE_BTN="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Toggle integrated terminal".*/\1/p' | head -1)"
  test -n "$TE_BTN"
  native automate widget-click main-canvas "$TE_BTN"
  sleep 0.5
  TERM_BOX="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=textbox name="Terminal command".*/\1/p' | head -1)"
fi
RUN_BTN="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Run".*/\1/p' | head -1)"
test -n "$TERM_BOX" && test -n "$RUN_BTN"

native automate widget-action main-canvas "$TERM_BOX" set_text "echo 'src/server/auth.ts(1,1): error TS9999: smoke failure'"
native automate widget-click main-canvas "$RUN_BTN"
native automate assert --timeout-ms 15000 'TS9999'
native automate assert --timeout-ms 15000 'smoke failure'
native automate assert --timeout-ms 15000 '1 errors'
echo "diagnostics-smoke: ok"
