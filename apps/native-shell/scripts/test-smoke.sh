#!/usr/bin/env bash
# Exercise the governed workspace test path in deterministic pass and fail modes.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"

native build -Dautomation=true

run_case() (
  local mode="$1"
  local fail=0
  if test "$mode" = "failure"; then fail=1; fi
  rm -rf .zig-cache/native-sdk-automation
  VELOCITY_FIXTURE_TEST_FAIL="$fail" ./zig-out/bin/velocity-ide >"/tmp/velocity-test-smoke-${mode}.out" 2>&1 &
  local app_pid=$!
  cleanup() {
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  }
  trap cleanup EXIT
  sleep 3
  kill -0 "$app_pid"

  local open_id
  open_id="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | head -1)"
  test -n "$open_id"
  native automate widget-click main-canvas "$open_id"
  sleep 1

  local run_id
  run_id="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Run workspace tests using the test or first test colon task".*/\1/p' | head -1)"
  if test -z "$run_id"; then
    local terminal_id
    terminal_id="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Toggle integrated terminal".*/\1/p' | head -1)"
    test -n "$terminal_id"
    native automate widget-click main-canvas "$terminal_id"
    sleep 0.5
    run_id="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=button name="Run workspace tests using the test or first test colon task".*/\1/p' | head -1)"
  fi
  test -n "$run_id"
  native automate widget-click main-canvas "$run_id"

  if test "$mode" = "success"; then
    native automate assert --timeout-ms 15000 'velocity-test-smoke-pass'
    native automate assert --timeout-ms 5000 'Tests: passed'
  else
    native automate assert --timeout-ms 15000 'controlled fixture failure'
    native automate assert --timeout-ms 5000 'Tests: failed'
    native automate assert --timeout-ms 5000 'TEST'
  fi
)

run_case success
run_case failure
echo "test-smoke: ok"
