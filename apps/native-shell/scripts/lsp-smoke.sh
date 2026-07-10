#!/usr/bin/env bash
# Boot Velocity, enable the LSP toggle, open a TypeScript file with a
# deliberate type error, and assert a language-server diagnostic lands in
# the Problems panel (governed sidecar broker + typescript-language-server).
#
# Exits 0 with a SKIP message when typescript-language-server is not
# available (the app's honest "unavailable" state is covered by unit tests).
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"
# shellcheck source=apps/native-shell/scripts/smoke-common.sh
. "$SHELL_ROOT/scripts/smoke-common.sh"

# 1. The broker binary is not part of the app build yet — build it.
bash "$SHELL_ROOT/scripts/build-lsp-broker.sh"

# 2. Find typescript-language-server: PATH first, then a local install
#    (LSP_SMOKE_TLS_DIR or the CI scratch install), else SKIP honestly.
TLS_DIR="${LSP_SMOKE_TLS_DIR:-/tmp/claude-0/-home-user-Velocity-IDE/a858a959-b8df-5899-b5f0-7370bd2e5f48/scratchpad/tls}"
if ! command -v typescript-language-server >/dev/null 2>&1; then
  if test -x "$TLS_DIR/node_modules/.bin/typescript-language-server"; then
    export PATH="$TLS_DIR/node_modules/.bin:$PATH"
  fi
fi
if ! typescript-language-server --version >/dev/null 2>&1; then
  echo "lsp-smoke: SKIP — typescript-language-server not available (install it on PATH or set LSP_SMOKE_TLS_DIR)"
  exit 0
fi
echo "lsp-smoke: typescript-language-server $(typescript-language-server --version)"

# 3. Temporary fixture with a deliberate type error; prefs are restored so
#    the persisted LSP toggle does not leak into other runs.
FIXTURE="$SHELL_ROOT/fixtures/acme-dashboard/lsp-smoke.ts"
PREFS="$SHELL_ROOT/.velocity/prefs.txt"
PREFS_BACKUP=""
if test -f "$PREFS"; then
  PREFS_BACKUP="$(mktemp)"
  cp "$PREFS" "$PREFS_BACKUP"
fi
# Boot from default prefs so the persisted LSP toggle from any earlier run
# cannot invert the smoke's own toggle step.
rm -f "$PREFS"
cat >"$FIXTURE" <<'EOF'
// lsp-smoke fixture: the assignment below is a deliberate type error.
const answer: number = "forty-two";
export default answer;
EOF

LOG_FILE=/tmp/velocity-lsp-smoke.out
APP_PID=""
cleanup() {
  if test -n "$APP_PID"; then kill "$APP_PID" 2>/dev/null || true; fi
  pkill -f 'zig-out/bin/velocity-ide' 2>/dev/null || true
  rm -f "$FIXTURE"
  if test -n "$PREFS_BACKUP"; then
    cp "$PREFS_BACKUP" "$PREFS" 2>/dev/null || true
    rm -f "$PREFS_BACKUP"
  else
    rm -f "$PREFS"
  fi
}
trap cleanup EXIT

native build --yes -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
if test -z "${DISPLAY:-}" && command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a ./zig-out/bin/velocity-ide >"$LOG_FILE" 2>&1 &
else
  ./zig-out/bin/velocity-ide >"$LOG_FILE" 2>&1 &
fi
APP_PID=$!
smoke_wait_for_app "$APP_PID" "$LOG_FILE"

widget_id_by() { # role name
  native automate snapshot | sed -n "s/.*widget @w1\/main-canvas#\([0-9]*\) role=$1 name=\"$2\".*/\1/p" | head -1
}

# Click widget (role, name), retrying until a marker text appears in the
# snapshot — a click can race a frame that is still settling.
click_until() { # role name marker
  local role="$1" name="$2" marker="$3" attempt=0 id
  while test "$attempt" -lt 10; do
    id="$(widget_id_by "$role" "$name")"
    if test -n "$id"; then
      native automate widget-click main-canvas "$id" >/dev/null 2>&1 || true
    fi
    sleep 1
    if native automate snapshot | grep -qF "$marker"; then
      return 0
    fi
    attempt=$((attempt + 1))
  done
  echo "lsp-smoke: never reached '$marker' after clicking $role \"$name\"" >&2
  native automate snapshot | tail -40 >&2 || true
  return 1
}

# Open the fixture workspace, enable the LSP toggle in Settings (default
# OFF — activation is explicit), return to the workbench, open the broken
# TypeScript file (the activation trigger: toggle ON + supported file
# open -> governed broker spawn), and show the Problems panel (its header
# carries the LSP status line).
click_until listitem "acme-dashboard" 'name="Application settings"'
click_until button "Application settings" 'name="Settings search"'
LSP_SWITCH="$(widget_id_by switch "Toggle language server (LSP)")"
test -n "$LSP_SWITCH"
# Switches expose actions=[focus,toggle] - widget-click (press) is a no-op.
native automate widget-action main-canvas "$LSP_SWITCH" toggle
sleep 1
click_until button "Back to workbench" 'name="Explorer filter"'
click_until listitem "lsp-smoke.ts" 'deliberate type error'
click_until button "Problems and diagnostics" 'LSP:'

# The broker handshake + tsserver warm-up can take a while on first run.
native automate assert --timeout-ms 120000 'LSP: running'
native automate assert --timeout-ms 120000 'not assignable'
native automate assert --timeout-ms 15000 'lsp-smoke.ts'
echo "lsp-smoke: ok"
