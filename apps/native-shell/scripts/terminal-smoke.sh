#!/usr/bin/env bash
# Boot Velocity and exercise the terminal panel via native automate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="/workspace/.tools/node_modules/.bin:/home/ubuntu/.native/toolchains/zig-0.16.0:${PATH:-}"

native build -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
./zig-out/bin/velocity-ide >/tmp/velocity-terminal-smoke.out 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 3
kill -0 "$APP_PID"

# Open fixture from launch recent list (first listitem)
OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | head -1)"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
sleep 1

# Terminal is closed by default — open via activity rail
TE_BTN="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Toggle integrated terminal".*/\1/p' | head -1)"
test -n "$TE_BTN"
native automate widget-click main-canvas "$TE_BTN"
sleep 0.5

TERM_BOX="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=textbox name="Terminal command".*/\1/p' | head -1)"
RUN_BTN="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Run".*/\1/p' | head -1)"
test -n "$TERM_BOX" && test -n "$RUN_BTN"

native automate widget-action main-canvas "$TERM_BOX" set_text 'echo velocity-smoke'
native automate widget-click main-canvas "$RUN_BTN"
native automate assert --timeout-ms 15000 'velocity-smoke'
native automate assert --timeout-ms 5000 'exit 0'
echo "terminal-smoke: ok"
