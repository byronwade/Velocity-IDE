#!/usr/bin/env bash
# Exercise a bounded .velocity/launch.json command profile end to end.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"
# shellcheck source=apps/native-shell/scripts/smoke-common.sh
. "$SHELL_ROOT/scripts/smoke-common.sh"

native build --yes -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
LOG_FILE=/tmp/velocity-launch-smoke.out
./zig-out/bin/velocity-ide >"$LOG_FILE" 2>&1 &
APP_PID=$!
cleanup() {
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
}
trap cleanup EXIT
smoke_wait_for_app "$APP_PID" "$LOG_FILE"

OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | head -1)"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
sleep 1

PROFILE_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="printf.*velocity-launch-smoke.*".*/\1/p' | head -1)"
if test -z "$PROFILE_ID"; then
  TERMINAL_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Toggle integrated terminal".*/\1/p' | head -1)"
  test -n "$TERMINAL_ID"
  native automate widget-click main-canvas "$TERMINAL_ID"
  sleep 0.5
  PROFILE_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="printf.*velocity-launch-smoke.*".*/\1/p' | head -1)"
fi
test -n "$PROFILE_ID"
native automate widget-click main-canvas "$PROFILE_ID"

RUN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Run selected command profile".*/\1/p' | head -1)"
test -n "$RUN_ID"
native automate widget-click main-canvas "$RUN_ID"
native automate assert --timeout-ms 15000 'velocity-launch-smoke:profile'
native automate assert --timeout-ms 5000 'Launch exited with code 0'
echo "launch-smoke: ok"
