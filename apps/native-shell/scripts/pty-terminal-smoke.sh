#!/usr/bin/env bash
# Boot Velocity, activate the terminal panel's interactive shell (PTY
# sidecar broker), and prove REAL shell-state persistence across commands
# — `export V=42` in one submit, `echo "pty_$V"` in the next — something
# the one-shot pipe runner cannot do. Then deactivate and assert the
# broker/shell tree is gone (clean teardown, no leaked processes).
#
# Exits 0 with a SKIP message when the PTY broker cannot be built (no zig
# toolchain) or the platform has no PTY support; the app's honest
# "unavailable" states are covered by unit tests.
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"
# shellcheck source=apps/native-shell/scripts/smoke-common.sh
. "$SHELL_ROOT/scripts/smoke-common.sh"

if [ "$(uname -s)" != "Linux" ]; then
  echo "pty-terminal-smoke: SKIP — PTY broker is Linux-only for now (sidecar README platform gates)"
  exit 0
fi

# Boot from default prefs so persisted panel state from earlier runs
# cannot invert this smoke's own steps; restore afterwards.
PREFS="$SHELL_ROOT/.velocity/prefs.txt"
PREFS_BACKUP=""
if test -f "$PREFS"; then
  PREFS_BACKUP="$(mktemp)"
  cp "$PREFS" "$PREFS_BACKUP"
fi
rm -f "$PREFS"

LOG_FILE=/tmp/velocity-pty-terminal-smoke.out
APP_PID=""
cleanup() {
  if test -n "$APP_PID"; then kill "$APP_PID" 2>/dev/null || true; fi
  pkill -f 'zig-out/bin/velocity-ide' 2>/dev/null || true
  pkill -f 'zig-out/bin/velocity-pty-broker' 2>/dev/null || true
  if test -n "$PREFS_BACKUP"; then
    cp "$PREFS_BACKUP" "$PREFS" 2>/dev/null || true
    rm -f "$PREFS_BACKUP"
  else
    rm -f "$PREFS"
  fi
}
trap cleanup EXIT

native build --yes -Dautomation=true
# The app build above installed the managed Zig toolchain; now the broker
# (its build script resolves zig from that toolchain on fresh runners).
if ! bash "$SHELL_ROOT/scripts/build-pty-broker.sh"; then
  echo "pty-terminal-smoke: SKIP — PTY broker could not be built (zig toolchain unavailable)"
  exit 0
fi
rm -rf .zig-cache/native-sdk-automation
if test -z "${DISPLAY:-}" && command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a ./zig-out/bin/velocity-ide >"$LOG_FILE" 2>&1 &
else
  ./zig-out/bin/velocity-ide >"$LOG_FILE" 2>&1 &
fi
APP_PID=$!
smoke_wait_for_app "$APP_PID" "$LOG_FILE"

# Snapshot reads can race the app rewriting the file on slow runners
# (torn read -> transient automate failure); retry instead of dying.
snap() {
  local attempt=0
  while test "$attempt" -lt 10; do
    if native automate snapshot 2>/dev/null; then return 0; fi
    attempt=$((attempt + 1))
    sleep 1
  done
  echo "pty-terminal-smoke: snapshot unavailable after retries" >&2
  return 1
}

widget_id_by() { # role name
  snap | sed -n "s/.*widget @w1\/main-canvas#\([0-9]*\) role=$1 name=\"$2\".*/\1/p" | head -1
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
    if snap | grep -qF "$marker"; then
      return 0
    fi
    attempt=$((attempt + 1))
  done
  echo "pty-terminal-smoke: never reached '$marker' after clicking $role \"$name\"" >&2
  snap | tail -40 >&2 || true
  return 1
}

# Submit one command line into the terminal input.
run_terminal() { # command
  local box run_btn
  box="$(widget_id_by textbox "Terminal command")"
  run_btn="$(widget_id_by button "Run")"
  test -n "$box" && test -n "$run_btn"
  native automate widget-action main-canvas "$box" set_text "$1"
  native automate widget-click main-canvas "$run_btn"
}

# 1. Open the fixture workspace and the terminal panel.
click_until listitem "acme-dashboard" 'name="Explorer filter"'
click_until button "Toggle integrated terminal" 'name="Terminal command"'

# 2. Activate the interactive shell. Switches expose actions=[focus,toggle]
#    — widget-click (press) is a no-op; use widget-action toggle.
PTY_SWITCH="$(widget_id_by switch "Toggle interactive shell (PTY)")"
test -n "$PTY_SWITCH"
native automate widget-action main-canvas "$PTY_SWITCH" toggle
native automate assert --timeout-ms 30000 'PTY: running'

# 3. State persistence across submits: an exported variable set by one
#    command is expanded by a later one — impossible in the one-shot
#    pipe runner (`sh -c` per command).
run_terminal 'export V=42'
sleep 1
run_terminal 'echo "pty_$V"'
# The PTY echoes the typed line as `pty_$V` (unexpanded); the shell's
# OUTPUT is the expanded `pty_42` — assert the expansion, proving the
# export survived into the second command.
native automate assert --timeout-ms 20000 'pty_42'

# 4. The broker and its shell exist while the session is active.
pgrep -f 'zig-out/bin/velocity-pty-broker' >/dev/null || {
  echo "pty-terminal-smoke: broker process not found while session active" >&2
  exit 1
}

# 5. Deactivate: the switch tears the session down; broker + shell tree
#    must be gone (broker escalates over the whole shell session).
native automate widget-action main-canvas "$PTY_SWITCH" toggle
sleep 1
native automate assert --timeout-ms 10000 'PTY: off'
DEADLINE=$((SECONDS + 15))
while pgrep -f 'zig-out/bin/velocity-pty-broker' >/dev/null; do
  if [ $SECONDS -ge $DEADLINE ]; then
    echo "pty-terminal-smoke: broker still alive after deactivation" >&2
    pgrep -af 'zig-out/bin/velocity-pty-broker' >&2 || true
    exit 1
  fi
  sleep 0.5
done

# 6. The pipe runner remains the default path after deactivation.
run_terminal 'echo pipe-fallback-ok'
native automate assert --timeout-ms 15000 'pipe-fallback-ok'
native automate assert --timeout-ms 5000 'exit 0'

echo "pty-terminal-smoke: ok"
