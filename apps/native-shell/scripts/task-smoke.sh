#!/usr/bin/env bash
# Boot Velocity, detect the fixture npm scripts, and run the safe smoke task.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="/workspace/.tools/node_modules/.bin:/home/ubuntu/.native/toolchains/zig-0.16.0:${PATH:-}"

native build -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
./zig-out/bin/velocity-ide >/tmp/velocity-task-smoke.out 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 3
kill -0 "$APP_PID"

OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | head -1)"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
sleep 1

TERMINAL_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Toggle integrated terminal".*/\1/p' | head -1)"
test -n "$TERMINAL_ID"
native automate widget-click main-canvas "$TERMINAL_ID"
sleep 0.5

TASK_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="echo velocity-task-smoke".*/\1/p' | head -1)"
test -n "$TASK_ID"
native automate widget-click main-canvas "$TASK_ID"

RUN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Run Selected Task".*/\1/p' | head -1)"
test -n "$RUN_ID"
native automate widget-click main-canvas "$RUN_ID"
native automate assert --timeout-ms 15000 'velocity-task-smoke'
native automate assert --timeout-ms 5000 'Task exited with code 0'
echo "task-smoke: ok"
