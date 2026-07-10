#!/usr/bin/env bash
# Build, boot, exercise frame-timed UI paths, and inspect the honest HUD.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"

native build -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
./zig-out/bin/velocity-ide >/tmp/velocity-perf-smoke.out 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 3
kill -0 "$APP_PID"

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
printf '%s\n' "$SNAPSHOT" | rg -q 'ns \(measured\)|n/a \(unavailable\)'
printf '%s\n' "$SNAPSHOT" | rg -q 'Resident memory'
printf '%s\n' "$SNAPSHOT" | rg -q 'n/a \(unavailable\)'
printf '%s\n' "$SNAPSHOT" | rg -q 'Plugins loaded'
printf '%s\n' "$SNAPSHOT" | rg -q '0 \(measured\)'
LABELED_VALUES="$(printf '%s\n' "$SNAPSHOT" | rg -c 'role=text name="([0-9]+ (ns|bytes) \(measured\)|[0-9]+ \(measured\)|n/a \(unavailable\))"')"
if test "$LABELED_VALUES" -lt 18; then
  echo "perf-smoke: expected every HUD row to expose measured or unavailable state" >&2
  exit 1
fi

echo "perf-smoke: ok"
