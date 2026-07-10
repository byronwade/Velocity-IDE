#!/usr/bin/env bash
# Boot Velocity and exercise the terminal panel via native automate.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"

native build --yes -Dautomation=true
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

native automate widget-action main-canvas "$TERM_BOX" set_text 'echo velocity-smoke'
native automate widget-click main-canvas "$RUN_BTN"
native automate assert --timeout-ms 15000 'velocity-smoke'
native automate assert --timeout-ms 5000 'exit 0'

# A running command owns the sole terminal/task effect. A second Run must be
# refused without replacing it, and only the explicit Stop action cancels it.
native automate widget-action main-canvas "$TERM_BOX" set_text 'while :; do :; done'
native automate widget-click main-canvas "$RUN_BTN"
native automate assert --timeout-ms 5000 'running'
native automate widget-action main-canvas "$TERM_BOX" set_text 'echo must-not-interleave'
native automate widget-click main-canvas "$RUN_BTN"
native automate assert --timeout-ms 5000 'use Stop Terminal/Task before starting another'
STOP_BTN="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Stop Terminal\/Task".*/\1/p' | head -1)"
test -n "$STOP_BTN"
native automate widget-click main-canvas "$STOP_BTN"
native automate assert --timeout-ms 10000 'Command cancelled'
echo "terminal-smoke: ok"
