#!/usr/bin/env bash
# Build, boot, exercise frame-timed UI paths, and inspect the honest HUD.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"
# shellcheck source=apps/native-shell/scripts/smoke-common.sh
. "$SHELL_ROOT/scripts/smoke-common.sh"

native build --yes -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
LOG_FILE=/tmp/velocity-perf-smoke.out
./zig-out/bin/velocity-ide >"$LOG_FILE" 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
smoke_wait_for_app "$APP_PID" "$LOG_FILE"

OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | sed -n '1p')"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
native automate wait

native automate shortcut command_palette
native automate assert --timeout-ms 5000 'Refresh Performance Metrics'
native automate wait
native automate shortcut escape

CURRENT_SNAPSHOT="$(native automate snapshot)"
if printf '%s\n' "$CURRENT_SNAPSHOT" | rg -q 'role=textbox name="Terminal command"'; then
  native automate shortcut toggle_terminal
  native automate assert --absent --timeout-ms 5000 'Terminal command'
fi
native automate shortcut toggle_terminal
native automate assert --timeout-ms 5000 'Terminal command'
native automate wait

native automate native-command run_perf main-canvas
native automate assert --timeout-ms 5000 \
  'Performance HUD' \
  'Boot to first observed nonblank paint' \
  'SDK first frame latency' \
  'First chrome callback' \
  'Command palette request to present' \
  'Terminal panel request to present' \
  'Resident memory' \
  'Plugins loaded' \
  'Features registered' \
  'Features enabled' \
  'Features loaded' \
  'Governor live processes' \
  'Governor terminal-owned processes' \
  'Governor task-owned processes' \
  'Plugin processes'

SNAPSHOT="$(native automate snapshot)"
if printf '%s\n' "$SNAPSHOT" | rg -i 'MOCK|fabricated|48 MB'; then
  echo "perf-smoke: dishonest placeholder text found" >&2
  exit 1
fi
printf '%s\n' "$SNAPSHOT" | rg -q 'Command palette request to present'
printf '%s\n' "$SNAPSHOT" | rg -q 'Terminal panel request to present'
# Values are human-readable (ns/ms/s, bytes/KB/MB, plain counts) or an honest n/a.
printf '%s\n' "$SNAPSHOT" | rg -q 'name="([0-9]+ ns|[0-9.]+ ms|[0-9.]+ s)"|name="n/a"'
printf '%s\n' "$SNAPSHOT" | rg -q 'Resident memory'
printf '%s\n' "$SNAPSHOT" | rg -q 'name="n/a"'
printf '%s\n' "$SNAPSHOT" | rg -q 'Plugins loaded'
printf '%s\n' "$SNAPSHOT" | rg -q 'name="0"'
# Every HUD row exposes its measurement state as a measured/unavailable badge.
LABELED_VALUES="$(printf '%s\n' "$SNAPSHOT" | rg -c 'name="(measured|unavailable)"')"
if test "$LABELED_VALUES" -lt 18; then
  echo "perf-smoke: expected every HUD row to expose measured or unavailable state" >&2
  exit 1
fi

echo "perf-smoke: ok"
