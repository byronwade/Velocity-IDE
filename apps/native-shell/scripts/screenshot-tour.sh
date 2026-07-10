#!/usr/bin/env bash
# Boot the app and capture deterministic reference-renderer screenshots of
# the key surfaces (launch, shell, terminal, perf HUD, palette, light theme).
# Output PNGs land in the directory given as $1 (default: ./screenshots).
set -euo pipefail
SHELL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$SHELL_ROOT/../.." && pwd)"
cd "$SHELL_ROOT"
export PATH="$REPO_ROOT/.tools/node_modules/.bin:${PATH:-}"
# shellcheck source=apps/native-shell/scripts/smoke-common.sh
. "$SHELL_ROOT/scripts/smoke-common.sh"

OUT_DIR="${1:-$SHELL_ROOT/screenshots}"
mkdir -p "$OUT_DIR"
CAPTURE_SRC=".zig-cache/native-sdk-automation/screenshot-main-canvas.png"

native build --yes -Dautomation=true
rm -rf .zig-cache/native-sdk-automation
LOG_FILE=/tmp/velocity-screenshot-tour.out
./zig-out/bin/velocity-ide >"$LOG_FILE" 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT
smoke_wait_for_app "$APP_PID" "$LOG_FILE"

capture() {
  local name="$1"
  native automate wait
  native automate screenshot main-canvas
  cp "$CAPTURE_SRC" "$OUT_DIR/$name.png"
  echo "screenshot-tour: captured $name"
}

# Resolve a widget id on main-canvas by its accessible name.
find_widget() {
  local name="$1"
  native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=[a-z]* name="'"$name"'".*/\1/p' | sed -n '1p'
}

# 1. Launch screen (dark).
capture 01-launch-dark

# 2. IDE shell with the fixture workspace open.
OPEN_ID="$(native automate snapshot | sed -n 's/.*widget @w1\/main-canvas#\([0-9]*\) role=listitem name="acme-dashboard".*/\1/p' | sed -n '1p')"
test -n "$OPEN_ID"
native automate widget-click main-canvas "$OPEN_ID"
native automate wait
capture 02-shell-explorer-dark

# 3. Integrated terminal panel.
native automate shortcut toggle_terminal
native automate assert --timeout-ms 5000 'Terminal command'
capture 03-terminal-dark
native automate shortcut toggle_terminal

# 4. Performance HUD.
native automate native-command run_perf main-canvas
native automate assert --timeout-ms 5000 'Performance HUD'
capture 04-perf-hud-dark

# 5. Command palette overlay.
native automate shortcut command_palette
native automate assert --timeout-ms 5000 'Command search'
capture 05-command-palette-dark
native automate shortcut escape

# 6. Settings page, then flip to the light theme through the real toggle.
SETTINGS_ID="$(find_widget "Application settings")"
test -n "$SETTINGS_ID"
native automate widget-click main-canvas "$SETTINGS_ID"
native automate assert --timeout-ms 5000 'Settings search'
capture 06-settings-dark

THEME_ID="$(find_widget "Change color theme")"
test -n "$THEME_ID"
native automate widget-click main-canvas "$THEME_ID"
native automate wait
capture 07-settings-light

# 7. Shell in the light theme.
EXPLORER_ID="$(find_widget "Explorer: workspace files")"
test -n "$EXPLORER_ID"
native automate widget-click main-canvas "$EXPLORER_ID"
native automate wait
capture 08-shell-light

echo "screenshot-tour: ok ($OUT_DIR)"
