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

# High-contrast shell. Deterministic from the boot dark theme: the cycle is
# dark -> light -> high_contrast, so two switches land on high contrast; a
# third returns to dark for the rest of the tour.
native automate native-command switch_theme main-canvas || true
native automate native-command switch_theme main-canvas || true
native automate wait || true
capture 17-shell-high-contrast
native automate native-command switch_theme main-canvas || true
native automate wait || true

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

# Back to dark for the remaining panel captures.
native automate native-command switch_theme main-canvas || true
native automate wait
native automate native-command switch_theme main-canvas || true
native automate wait

# Best-effort: click an activity-rail button by its accessible label, then
# capture. Failures never abort the tour (the earlier captures are the
# guaranteed set; these are bonus coverage).
capture_activity() {
  local label="$1" name="$2"
  local id
  id="$(find_widget "$label")" || true
  if test -n "$id"; then
    native automate widget-click main-canvas "$id" || true
    native automate wait || true
    capture "$name"
  else
    echo "screenshot-tour: activity '$label' not found; skipped $name"
  fi
}

# 9. Search & replace panel.
capture_activity "Search and replace across workspace" 09-search-dark

# 10. Source Control panel.
capture_activity "Source Control: Git changes" 10-scm-dark

# 11. Document outline panel.
capture_activity "Document outline" 11-outline-dark

# 12. Problems panel.
capture_activity "Problems and diagnostics" 12-problems-dark

# Reopen the explorer/editor before the overlays.
EXP2="$(find_widget "Explorer: workspace files")" || true
test -n "$EXP2" && native automate widget-click main-canvas "$EXP2" || true
native automate wait || true

# 13. Agent panel.
native automate shortcut toggle_agent || true
native automate wait || true
capture 13-agent-dark
native automate shortcut toggle_agent || true
native automate wait || true

# 14. Quick Open overlay.
native automate shortcut quick_open || true
native automate wait || true
capture 14-quick-open-dark
native automate shortcut escape || true
native automate wait || true

# 15. Notifications overlay.
native automate native-command toggle_notifications_panel main-canvas || true
native automate wait || true
capture 15-notifications-dark
native automate native-command toggle_notifications_panel main-canvas || true
native automate wait || true

# 16. Keyboard shortcuts overlay.
native automate native-command toggle_shortcuts_help main-canvas || true
native automate wait || true
capture 16-shortcuts-dark
native automate shortcut escape || true
native automate wait || true

# ---- Overflow contract: declared minimum window 960x640 ----
native automate resize 960 640 || true
native automate wait || true
capture 20-min-shell-960x640

# Bottom panel open at min size (dense stress).
native automate shortcut toggle_terminal || true
native automate wait || true
capture 21-min-terminal-960x640
native automate shortcut toggle_terminal || true
native automate wait || true

# Settings at min size (full-page + Back header).
SET_MIN="$(find_widget "Application settings")" || true
test -n "$SET_MIN" && native automate widget-click main-canvas "$SET_MIN" || true
native automate wait || true
capture 22-min-settings-960x640
EXP_MIN="$(find_widget "Explorer: workspace files")" || true
test -n "$EXP_MIN" && native automate widget-click main-canvas "$EXP_MIN" || true
native automate wait || true

# Command palette at min size (must fit, top-anchored).
native automate shortcut command_palette || true
native automate wait || true
capture 23-min-palette-960x640
native automate shortcut escape || true
native automate wait || true

# Diff review at min size (the modal that used to overflow).
native automate native-command open_scm_diff main-canvas || true
native automate wait || true
capture 24-min-diff-960x640
native automate shortcut escape || true
native automate wait || true

# Wide desktop window.
native automate resize 1680 1050 || true
native automate wait || true
capture 25-wide-1680x1050

# Restore default size.
native automate resize 1280 800 || true
native automate wait || true

echo "screenshot-tour: ok ($OUT_DIR)"
